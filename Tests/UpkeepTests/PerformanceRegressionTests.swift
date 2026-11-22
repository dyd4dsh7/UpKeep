import AppKit
import Foundation
import Testing
@testable import Upkeep

private actor CountingCVETransport {
    private(set) var requests: [URL] = []
    func send(_ request: URLRequest) -> (Data, HTTPURLResponse) {
        requests.append(request.url!)
        let json: String
        if request.url?.host == "formulae.brew.sh" {
            json = #"{"advisories":{"zip":[{"id":"BREW-fixture","upstream":["CVE-2026-0001"],"affected":[{"package":{"name":"zip","ecosystem":"Homebrew"},"ranges":[{"type":"ECOSYSTEM","events":[{"introduced":"0"},{"fixed":"1.0_2"}]}]}]}]}}"#
        } else if request.url?.host == "api.osv.dev" {
            json = "{}"
        } else {
            json = #"{"startIndex":0,"resultsPerPage":2000,"totalResults":0,"vulnerabilities":[]}"#
        }
        return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private func countingClient(_ transport: CountingCVETransport) -> CVEInventoryClient {
    let send: CVEClient.Transport = { await transport.send($0) }
    return CVEInventoryClient(developer: CVEClient(transport: send),
                              nvd: NVDCVEClient(transport: send, pace: {}), transport: send)
}

@MainActor @Test func cveIncrementalCheckReusesFreshResultsAndKeepsThemVisible() async {
    let transport = CountingCVETransport()
    let state = CVEScanState()
    let formula = CVEInventoryItem(CVEStoreFixture.cveFormula)
    let packages = CVEStoreFixture.cvePackages.map(CVEInventoryItem.init)
    let inventory = [formula] + packages
    state.start(inventory: inventory, client: countingClient(transport))
    await state.waitForCompletion()
    let firstRequests = await transport.requests.count
    #expect(state.results.map(\.id) == inventory.map(\.id))
    #expect(state.listStatus(for: formula) == .advisories(1, potential: false))
    #expect(state.isCurrent(for: inventory))

    // Unchanged inventory: everything reused, no network.
    state.start(inventory: inventory, client: countingClient(transport), reuseFreshResults: true)
    // Previous results remain visible while the check runs.
    #expect(state.listStatus(for: formula) == .advisories(1, potential: false))
    await state.waitForCompletion()
    #expect(await transport.requests.count == firstRequests)
    #expect(state.results.map(\.id) == inventory.map(\.id))

    // One changed package: only it is re-checked.
    let changedPackage = DeveloperPackage(name: "fixture-current-tool", currentVersion: "2.0.1", latestVersion: "2.0.1",
                                          manager: .npm, executablePath: "/fixture/npm")
    let changed = [formula, packages[0], CVEInventoryItem(changedPackage), packages[2]]
    #expect(!state.isCurrent(for: changed))
    state.start(inventory: changed, client: countingClient(transport), reuseFreshResults: true)
    await state.waitForCompletion()
    let requests = await transport.requests
    #expect(requests.count == firstRequests + 1)
    #expect(requests.last?.host == "api.osv.dev")
    #expect(state.results.map(\.id) == changed.map(\.id))

    // Stale results are not reused.
    let later = Date().addingTimeInterval(CVEScanState.freshnessInterval + 1)
    #expect(!state.isCurrent(for: changed, now: later))
}

@MainActor @Test func cveResultIndexMatchesResults() async {
    let transport = CountingCVETransport()
    let state = CVEScanState()
    let inventory = [CVEInventoryItem(CVEStoreFixture.cveFormula)] + CVEStoreFixture.cvePackages.map(CVEInventoryItem.init)
    state.start(inventory: inventory, client: countingClient(transport))
    await state.waitForCompletion()
    for result in state.results {
        #expect(state.result(for: result.id)?.advisories.map(\.id) == result.advisories.map(\.id))
    }
    #expect(state.resultsByID.count == state.results.count)
}

@Test func appStoreBatchLookupMapsResultsByBundleID() throws {
    let body = #"{"resultCount":2,"results":[{"bundleId":"com.Example.One","version":"2.0","trackViewUrl":"https://apps.apple.com/app/id1"},{"bundleId":"com.example.two","version":"3.1"}]}"#
    let results = try AppStoreClient.decodeLookup(Data(body.utf8),
        requestedBundleIDs: ["com.example.one", "com.example.two", "com.example.missing"])
    #expect(results[AppStoreClient.lookupKey("com.example.one")]?.version == "2.0")
    #expect(results[AppStoreClient.lookupKey("COM.EXAMPLE.TWO")]?.version == "3.1")
    #expect(results[AppStoreClient.lookupKey("com.example.missing")] == nil)
    // A single-ID lookup keeps using the first result.
    let single = try AppStoreClient.decodeLookup(Data(#"{"results":[{"version":"1.5"}]}"#.utf8),
        requestedBundleIDs: ["com.example.one"])
    #expect(single[AppStoreClient.lookupKey("com.example.one")]?.version == "1.5")
}

@MainActor @Test func sortedInsertMatchesFullSort() {
    func update(_ name: String) -> AvailableUpdate {
        let app = InstalledApp(name: name, bundleIdentifier: "test.\(name)", installedVersion: "1.0", buildVersion: nil,
            url: URL(fileURLWithPath: "/fixture/\(name).app"), sparkleFeedURL: nil, githubRepository: nil,
            hasAppStoreReceipt: false)
        return AvailableUpdate(app: app, availableVersion: "2.0", source: .sparkle, releaseNotes: nil,
                               actionURL: nil, homebrewToken: nil)
    }
    let names = ["Zed", "app 10", "App 2", "Beta", "alpha", "Beta", "Ölfass", "app 1"]
    var incremental: [AvailableUpdate] = []
    var reference: [AvailableUpdate] = []
    for name in names {
        let item = update(name)
        UpkeepStore.insertSortedByName(item, into: &incremental)
        reference.append(item)
        reference.sort { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending }
        #expect(incremental.map(\.app.name) == reference.map(\.app.name))
    }
}

@MainActor @Test func cachedSourceCountsMatchApplicationFilters() throws {
    let suite = "SourceCounts.\(UUID())"
    let defaults = try #require(UserDefaults(testSuiteName: suite))
    defer { defaults.removeTestDomain(forName: suite) }
    let store = CVEStoreFixture.makeStore(settings: AppSettings(defaults: defaults), includeCVEInventory: true)
    for destination in UpkeepStore.applicationSourceDestinations {
        #expect(store.applicationSourceCounts()[destination] == store.applications(for: destination).count)
        #expect(store.count(for: destination)
            == store.visibleUpdates.count { store.application($0.app, belongsTo: destination) })
    }
    #expect(store.applicationSourceCounts()[.sparkle] == 1)
    #expect(store.count(for: .sparkle) == 1)
    // Caches invalidate with the inventory.
    store.updates = []
    #expect(store.count(for: .sparkle) == 0)
    #expect(store.applicationSourceCounts()[.sparkle] == 1)
    store.apps = []
    #expect(store.applicationSourceCounts()[.sparkle] == 0)
}

@Test func registryCacheEvictsExpiredAndOldestEntries() async {
    let cache = RegistryRequestCache(maximumEntries: 2, maximumBytes: 10)
    let start = Date(timeIntervalSince1970: 1_000)
    await cache.store(Data("aaaa".utf8), for: "a", now: start)
    await cache.store(Data("bbbb".utf8), for: "b", now: start.addingTimeInterval(1))
    await cache.store(Data("cccc".utf8), for: "c", now: start.addingTimeInterval(2))
    #expect(await cache.entryCount == 2)
    #expect(await cache.cachedData(for: "a", now: start.addingTimeInterval(2)) == nil)
    #expect(await cache.cachedData(for: "c", now: start.addingTimeInterval(2)) != nil)
    // Byte cap: an 8-byte entry evicts the older one.
    await cache.store(Data("dddddddd".utf8), for: "d", now: start.addingTimeInterval(3))
    #expect(await cache.entryCount == 1)
    // Expired entries are dropped on the next insert.
    await cache.store(Data("e".utf8), for: "e", now: start.addingTimeInterval(RegistryRequestCache.freshnessInterval + 10))
    #expect(await cache.entryCount == 1)
}

@MainActor @Test func appIconIdentityIsMemoizedBriefly() {
    var resolves = 0
    let cache = AppIconIdentityCache(maximumAge: .seconds(5)) { url in
        resolves += 1
        return AppIconIdentity(url: url)
    }
    let url = URL(fileURLWithPath: "/System/Applications/Calculator.app")
    let now = ContinuousClock.now
    _ = cache.identity(for: url, now: now)
    _ = cache.identity(for: url, now: now.advanced(by: .seconds(1)))
    #expect(resolves == 1)
    _ = cache.identity(for: url, now: now.advanced(by: .seconds(6)))
    #expect(resolves == 2)
}

@MainActor @Test func checkRecordsAreCoalescedAndPruned() throws {
    let suite = "CheckRecords.\(UUID())"
    let defaults = try #require(UserDefaults(testSuiteName: suite))
    defer { defaults.removeTestDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    let date = Date(timeIntervalSince1970: 1_000)
    settings.recordChecks(for: ["app|keep", "app|gone"], at: date)
    settings.recordSourceAttempts(["app|keep-id|Sparkle": "", "app|gone-id|Sparkle": "", "homebrew.catalog": ""], at: date)
    // Not written yet: the write is coalesced.
    #expect(defaults.data(forKey: "itemLastCheckedDates") == nil)
    settings.pruneCheckRecords(keepingItemKeys: ["app|keep"], appIDs: ["keep-id"])
    #expect(settings.lastChecked(for: "app|gone") == nil)
    #expect(settings.lastChecked(for: "app|keep") == date)
    #expect(Set(settings.sourceCheckFreshness.keys) == ["app|keep-id|Sparkle", "homebrew.catalog"])
    // A new instance on the same defaults sees the pending records.
    let restored = AppSettings(defaults: defaults)
    #expect(restored.lastChecked(for: "app|keep") == date)
    #expect(restored.lastChecked(for: "app|gone") == nil)
    #expect(Set(restored.sourceCheckFreshness.keys) == ["app|keep-id|Sparkle", "homebrew.catalog"])
}

@Test func marketplaceBatchResponseMapsEveryExtensionByIdentifier() {
    let json = """
    {"results":[{"extensions":[
      {"extensionName":"Python","publisher":{"publisherName":"ms-python"},"versions":[{"version":"2026.1.0"},{"version":"2026.2.0","targetPlatform":"win32-x64"}]},
      {"extensionName":"gitlens","publisher":{"publisherName":"eamodio"},"versions":[{"version":"17.0.0","targetPlatform":"universal"}]}
    ]}]}
    """
    let versions = parseVisualStudioMarketplaceBatch(Data(json.utf8))
    #expect(versions["ms-python.python"] == ["2026.1.0"], "Platform-specific builds for other systems are ignored")
    #expect(versions["eamodio.gitlens"] == ["17.0.0"])
    #expect(versions.count == 2)
}

@Test func systemVersionIsReadFromThePlistWithoutLaunchingSwVers() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("SystemVersion-\(UUID()).plist")
    defer { try? FileManager.default.removeItem(at: url) }
    let plist: [String: Any] = ["ProductBuildVersion": "26C5047e", "ProductVersion": "27.3", "ProductVersionExtra": "(a)"]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url)
    #expect(SystemVersionInfo.read(from: url) == SystemVersionInfo(build: "26C5047e", extra: "(a)"))
    #expect(SystemVersionInfo.current != nil)
}

@Test func installerListingCacheExpires() async {
    let cache = MacOSInstallerListingCache()
    let start = Date()
    await cache.store(Data("listing".utf8), at: start)
    #expect(await cache.recent(maximumAge: 60, now: start.addingTimeInterval(30)) == Data("listing".utf8))
    #expect(await cache.recent(maximumAge: 60, now: start.addingTimeInterval(61)) == nil)
}

@Test func installerListingSurvivesARelaunch() async {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Installers-\(UUID())/macos-installers.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let start = Date()
    await MacOSInstallerListingCache(fileURL: url).store(Data("listing".utf8), at: start)
    let relaunched = MacOSInstallerListingCache(fileURL: url)
    #expect(await relaunched.recent(maximumAge: 60, now: start.addingTimeInterval(30)) == Data("listing".utf8))
    #expect(await MacOSInstallerListingCache(fileURL: url).recent(maximumAge: 60, now: start.addingTimeInterval(61)) == nil)
    #expect(await MacOSInstallerListingCache(fileURL: url).recent(maximumAge: 60, now: start.addingTimeInterval(-3_600)) == nil)
}

@Test func slimCaskCatalogKeepsEveryFieldUpkeepUses() throws {
    let api = """
    [{"token":"firefox","name":["Mozilla Firefox"],"version":"140.0","auto_updates":true,
      "artifacts":[{"app":["Firefox.app"]},{"zap":["~/Library/Firefox"]}],"desc":"Web browser","url":"https://example.invalid"},
     {"token":"tool","name":["Tool"],"version":"1.0,42","artifacts":[{"binary":["tool"]}]}]
    """
    let catalog = try JSONDecoder().decode([CatalogCask].self, from: Data(api.utf8))
    let slim = try JSONEncoder().encode(SlimCaskCatalog(catalog))
    let restored = try #require(SlimCaskCatalog.decode(slim))
    #expect(restored.map(\.token) == ["firefox", "tool"])
    #expect(restored[0].name == ["Mozilla Firefox"] && restored[0].version == "140.0")
    #expect(restored[0].autoUpdates && restored[0].artifactAppNames == ["Firefox.app"])
    #expect(!restored[1].autoUpdates && restored[1].artifactAppNames.isEmpty && restored[1].version == "1.0,42")
    #expect(slim.count < Data(api.utf8).count)
    // The old full-response cache format is not mistaken for the slim one.
    #expect(SlimCaskCatalog.decode(Data(api.utf8)) == nil)
}
