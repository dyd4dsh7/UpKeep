import Foundation
import Testing
@testable import Upkeep

private func cvePackage(_ manager: DeveloperPackageManager = .npm, name: String = "@example/tool",
                        version: String = "1.2.3", identifier: String? = nil) -> DeveloperPackage {
    DeveloperPackage(name: name, currentVersion: version, latestVersion: "9.0.0", manager: manager,
                     executablePath: "/private/local/bin/tool", registryIdentifier: identifier,
                     installationContext: "/private/local/context")
}

private actor CVETransportFixture {
    private var pages: [(Int, String)]
    private(set) var requests: [URLRequest] = []
    init(_ pages: [(Int, String)]) { self.pages = pages }
    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !pages.isEmpty else { throw URLError(.badServerResponse) }
        let (status, body) = pages.removeFirst()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status,
                                                httpVersion: nil, headerFields: nil)!)
    }
}

@Test func cveRegistryMapping() {
    let ecosystems: [(DeveloperPackageManager, String)] = [(.npm, "npm"), (.pnpm, "npm"), (.yarn, "npm"),
        (.python, "PyPI"), (.pipx, "PyPI"), (.uv, "PyPI"), (.rubyGems, "RubyGems"), (.cargo, "crates.io"),
        (.composer, "Packagist"), (.dotnet, "NuGet")]
    for (manager, expected) in ecosystems {
        #expect(CVEPackageQuery(cvePackage(manager))?.ecosystem == expected)
    }
    #expect(CVEPackageQuery(cvePackage(.go, identifier: "example.org/module"))?.name == "example.org/module")
    #expect(CVEPackageQuery(cvePackage(.yarn, name: "Yarn", version: "1.22.22"))?.name == "yarn")
    #expect(CVEPackageQuery(cvePackage(.yarn, name: "Yarn", version: "4.0.0")) == nil)
    #expect(CVEPackageQuery(cvePackage(.go)) == nil)
    #expect(CVEPackageQuery(cvePackage(.go, identifier: "go-runtime")) == nil)
    #expect(CVEPackageQuery(cvePackage(.uv, identifier: "python:3.13")) == nil)
    for manager in [DeveloperPackageManager.node, .bun, .deno, .vsCode, .rustup, .macPorts, .nix, .mise, .asdf, .volta, .fnm, .githubCLI] {
        #expect(CVEPackageQuery(cvePackage(manager)) == nil)
    }
    for version in ["", "unknown", "latest", "(devel)", "n/a"] {
        #expect(CVEPackageQuery(cvePackage(version: version)) == nil)
    }
}

@Test func cvePaginationAliasesAndRequestPrivacy() async throws {
    let fixture = CVETransportFixture([
        (200, #"{"vulns":[{"id":"GHSA-example","aliases":["CVE-2026-1234"],"summary":"Example advisory"},{"id":"withdrawn","withdrawn":"2026-01-01"}],"next_page_token":"second"}"#),
        (200, #"{"vulns":[{"id":"GHSA-example","aliases":["CVE-2026-1234"]},{"id":"CVE-2026-5678"}]}"#)
    ])
    let result = try await CVEClient(transport: { try await fixture.send($0) }).check(cvePackage())
    #expect(result.advisories.count == 2)
    #expect(result.advisories.flatMap(\.cveIDs).sorted() == ["CVE-2026-1234", "CVE-2026-5678"])
    let requests = await fixture.requests
    #expect(requests.count == 2)
    let first = try #require(requests.first)
    let body = try #require(first.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["version"] as? String == "1.2.3")
    #expect((json["package"] as? [String: String]) == ["name": "@example/tool", "ecosystem": "npm"])
    #expect(!String(decoding: body, as: UTF8.self).contains("/private"))
    #expect(first.url?.absoluteString == "https://api.osv.dev/v1/query")
    #expect(first.httpMethod == "POST")
    let secondBody = try #require(requests.last?.httpBody)
    let secondJSON = try #require(JSONSerialization.jsonObject(with: secondBody) as? [String: Any])
    #expect(secondJSON["page_token"] as? String == "second")
}

@Test func cveEmptyAndUnsupportedAreDistinct() async throws {
    let fixture = CVETransportFixture([(200, "{}")])
    let client = CVEClient(transport: { try await fixture.send($0) })
    let empty = try await client.check(cvePackage())
    #expect(empty.supported && empty.advisories.isEmpty && empty.failure == nil)
    let unsupported = try await client.check(cvePackage(.node))
    #expect(!unsupported.supported)
    #expect(await fixture.requests.count == 1)
}

@Test func cveFailuresNeverBecomeEmptySuccess() async {
    for pages in [[(429, "{}")], [(200, "invalid")], [(200, #"{"vulns":"wrong"}"#)],
                  [(200, #"{"next_page_token":"repeated"}"#), (200, #"{"next_page_token":"repeated"}"#)],
                  [(200, #"{"vulns":[{"id":"CVE-example"}],"next_page_token":"next"}"#), (503, "{}")]] {
        let fixture = CVETransportFixture(pages)
        do {
            _ = try await CVEClient(transport: { try await fixture.send($0) }).check(cvePackage())
            Issue.record("An incomplete or invalid response must throw")
        } catch { /* Expected; callers render an incomplete check. */ }
    }
}

@Test func cveCancellationStopsBeforeNetwork() async {
    let fixture = CVETransportFixture([])
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await CVEClient(transport: { try await fixture.send($0) }).check(cvePackage())
    }
    do { _ = try await task.value; Issue.record("Expected cancellation") } catch { }
    #expect(await fixture.requests.isEmpty)
}

private func cveApp(bundle: String? = "org.mozilla.firefox", version: String = "100.0", name: String = "Firefox") -> InstalledApp {
    InstalledApp(name: name, bundleIdentifier: bundle, installedVersion: version, buildVersion: nil,
        url: URL(fileURLWithPath: "/private/local/Firefox.app"), sparkleFeedURL: nil,
        githubRepository: nil, hasAppStoreReceipt: false)
}

private func cveBrew(_ token: String = "zip", version: String = "3.0_1", kind: HomebrewPackageKind = .formula,
                     tap: String? = "homebrew/core") -> HomebrewPackage {
    HomebrewPackage(token: token, displayName: token, description: nil, homepage: nil, license: nil,
        installedVersion: version, currentVersion: "9.0", kind: kind, isOutdated: false,
        isDependency: true, dependencies: [], tap: tap)
}

private let cveBrewFeed = #"{"advisories":{"zip":[{"id":"BREW-zip-example","upstream":["CVE-2026-1234"],"affected":[{"package":{"name":"zip","ecosystem":"Homebrew"},"ranges":[{"type":"ECOSYSTEM","events":[{"introduced":"0"},{"fixed":"3.0_2"},{"introduced":"4.0"},{"fixed":"4.1"}]}]}]},{"id":"withdrawn","withdrawn":"2026-01-01","affected":[]}]}}"#

@Test func cveAppAndCaskIdentityIsExplicit() throws {
    let app = CVEInventoryItem(cveApp())
    let target = try #require(app.target)
    guard case let .nvd(product) = target else { Issue.record("Expected NVD mapping"); return }
    #expect(product.vendor == "mozilla" && product.product == "firefox" && product.version == "100.0")
    #expect(product.cpeName == "cpe:2.3:a:mozilla:firefox:100.0:*:*:*:*:mac_os_x:*:*")
    #expect(CVEInventoryItem(cveApp(bundle: "unknown.app", name: "Firefox")).target == nil)
    #expect(CVEInventoryItem(cveApp(bundle: "org.mozilla.firefoxdeveloperedition")).target == nil)
    #expect(CVEInventoryItem(cveApp(version: "100.0:*")).target == nil)
    #expect(CVEInventoryItem(cveApp(version: "latest")).target == nil)
    let cask = CVEInventoryItem(cveBrew("firefox", version: "100.0,123", kind: .cask, tap: "homebrew/cask"))
    #expect(cask.target == target)
    #expect(CVEInventoryItem(cveBrew("firefox", kind: .cask, tap: "third/party")).target == nil)
    #expect(CVEInventoryItem(cveBrew("firefox", kind: .cask, tap: nil)).target == nil)
    #expect(CVEInventoryItem(cveBrew("unknown-app", kind: .cask, tap: "homebrew/cask")).target == nil)
}

@Test func cveHomebrewProvenanceAndRevisionBoundaries() throws {
    let index = try JSONDecoder().decode(HomebrewAdvisoryIndex.self, from: Data(cveBrewFeed.utf8))
    for version in ["2.0", "3.0", "3.0_1", "4.0", "4.0_1"] {
        let matches = try index.check(name: "zip", version: version)
        #expect(matches.count == 1)
        #expect(matches.first?.cveIDs == ["CVE-2026-1234"])
        #expect(matches.first?.url.host == "github.com")
    }
    for version in ["3.0_2", "3.0_3", "3.1", "4.1", "5.0"] {
        #expect(try index.check(name: "zip", version: version).isEmpty)
    }
    #expect(try HomebrewAdvisoryVersion.compare("3.0_10", "3.0_2") == .orderedDescending)
    #expect(try HomebrewAdvisoryVersion.compare("3.0_1", "3.0.0") == .orderedDescending)
    #expect(CVEInventoryItem(cveBrew()).target != nil)
    #expect(CVEInventoryItem(cveBrew(tap: "third/party")).target == nil)
    #expect(CVEInventoryItem(cveBrew(tap: nil)).target == nil)
    #expect(CVEInventoryItem(cveBrew(version: "HEAD-abc")).target == nil)
    var resetVersion = cveBrew(); resetVersion.versionScheme = 1
    #expect(CVEInventoryItem(resetVersion).target == nil)
}

@Test func cveHomebrewInclusiveBoundsAndInvalidRanges() throws {
    typealias Range = HomebrewAdvisoryIndex.Record.Range
    let inclusive = Range(type: "ECOSYSTEM", events: [["introduced": "1.0"], ["last_affected": "2.0"]])
    #expect(try inclusive.contains("2.0"))
    #expect(try !inclusive.contains("2.0_1"))
    let limited = Range(type: "ECOSYSTEM", events: [["introduced": "1.0"], ["limit": "2.0"]])
    #expect(try !limited.contains("2.0"))
    let invalid = [Range(type: "GIT", events: [["introduced": "0"]]),
        Range(type: "ECOSYSTEM", events: [["introduced": "0"], ["fixed": "HEAD"]]),
        Range(type: "ECOSYSTEM", events: [["fixed": "1.0"]]),
        Range(type: "ECOSYSTEM", events: [])]
    for range in invalid {
        #expect(throws: (any Error).self) { try range.contains("1.0") }
    }
}

@Test func cveHomebrewInventoryRetainsTap() throws {
    let data = Data(#"{"formulae":[{"name":"zip","tap":"homebrew/core","versions":{"stable":"3.0"},"revision":2,"dependencies":[],"installed":[{"version":"3.0_1","installed_on_request":false}],"outdated":true}],"casks":[{"token":"firefox","tap":"homebrew/cask","name":["Firefox"],"version":"101.0","installed":"100.0","outdated":true}]}"#.utf8)
    let packages = try decodeHomebrewInventory(data)
    #expect(packages.map(\.tap) == ["homebrew/core", "homebrew/cask"])
    #expect(packages.allSatisfy { CVEInventoryItem($0).target != nil })
    #expect(packages[1].reconciled(with: cveApp(version: "101.0")).tap == "homebrew/cask")
}

@Test func cveNVDPaginationPrivacyAndRejectedRecords() async throws {
    let fixture = CVETransportFixture([
        (200, #"{"startIndex":0,"resultsPerPage":1,"totalResults":2,"vulnerabilities":[{"cve":{"id":"CVE-2026-1234","descriptions":[{"lang":"en","value":"App advisory"}]}}]}"#),
        (200, #"{"startIndex":1,"resultsPerPage":1,"totalResults":2,"vulnerabilities":[{"cve":{"id":"CVE-rejected","vulnStatus":"Rejected","descriptions":[]}}]}"#)
    ])
    let product = try #require(CVEProduct(bundleID: "org.mozilla.firefox", version: "100.0"))
    let results = try await NVDCVEClient(transport: { try await fixture.send($0) }, pace: {}).check(product)
    #expect(results.count == 1)
    #expect(results.first?.url.absoluteString == "https://nvd.nist.gov/vuln/detail/CVE-2026-1234")
    let requests = await fixture.requests
    #expect(requests.count == 2)
    let firstURL = try #require(requests.first?.url)
    let query = try #require(URLComponents(url: firstURL, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(query.first { $0.name == "cpeName" }?.value == product.cpeName)
    #expect(query.contains { $0.name == "isVulnerable" })
    #expect(!firstURL.absoluteString.contains("/private"))
    #expect(!firstURL.absoluteString.contains("org.mozilla"))
    let next = URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)?.queryItems
    #expect(next?.first { $0.name == "startIndex" }?.value == "1")
}

@Test func cveInventoryFeedAndProductCacheArePerScan() async throws {
    let brewFixture = CVETransportFixture([(200, cveBrewFeed)])
    let nvdFixture = CVETransportFixture([(200, #"{"startIndex":0,"resultsPerPage":2000,"totalResults":0,"vulnerabilities":[]}"#)])
    let client = CVEInventoryClient(nvd: NVDCVEClient(transport: { try await nvdFixture.send($0) }, pace: {}),
        transport: { try await brewFixture.send($0) })
    let first = try await client.check(CVEInventoryItem(cveBrew()))
    #expect(first.advisories.count == 1 && first.failure == nil)
    let patched = try await client.check(CVEInventoryItem(cveBrew(version: "3.0_2")))
    #expect(patched.advisories.isEmpty && patched.failure == nil)
    #expect(await brewFixture.requests.count == 1)
    _ = try await client.check(CVEInventoryItem(cveApp()))
    _ = try await client.check(CVEInventoryItem(cveBrew("firefox", version: "100.0", kind: .cask, tap: "homebrew/cask")))
    #expect(await nvdFixture.requests.count == 1)
    let unknown = try await client.check(CVEInventoryItem(cveApp(bundle: "unknown.app")))
    #expect(!unknown.supported && unknown.status == "Not covered")
}

@Test func cveExpandedFailuresRemainIncomplete() async throws {
    let product = try #require(CVEProduct(bundleID: "org.mozilla.firefox", version: "100.0"))
    for response in [(429, "{}"), (200, "{}"), (200, #"{"startIndex":0,"resultsPerPage":1,"totalResults":3,"vulnerabilities":[]}"#)] {
        let fixture = CVETransportFixture([response])
        do {
            _ = try await NVDCVEClient(transport: { try await fixture.send($0) }, pace: {}).check(product)
            Issue.record("Expected failure for unavailable or incomplete NVD results")
        } catch { }
    }
    let fixture = CVETransportFixture([(503, "{}")])
    let client = CVEInventoryClient(transport: { try await fixture.send($0) })
    let result = try await client.check(CVEInventoryItem(cveBrew()))
    #expect(result.failure != nil && result.status == "Check incomplete")
    _ = try await client.check(CVEInventoryItem(cveBrew(version: "3.0_2")))
    #expect(await fixture.requests.count == 1)
}

@MainActor @Test func cveScanStatePublishesProgressAndRetainsResults() async throws {
    let fixture = CVETransportFixture([(200, cveBrewFeed)])
    let client = CVEInventoryClient(transport: { try await fixture.send($0) })
    let state = CVEScanState()
    let items = [CVEInventoryItem(cveBrew()), CVEInventoryItem(cveApp(bundle: "unknown.app"))]
    #expect(state.checkedAt == nil && !state.running && state.results.isEmpty)
    state.start(inventory: items, client: client)
    #expect(state.running && state.checkedAt != nil && state.inventory == items)
    // A second button action cannot replace a running check.
    state.start(inventory: [], client: client)
    #expect(state.inventory == items)
    await state.waitForCompletion()
    #expect(!state.running && state.currentItemID == nil)
    #expect(state.results.count == 2)
    #expect(state.results.first?.advisories.count == 1)
    #expect(state.results.last?.status == "Not covered")
    // Results belong to this window state, independent of any view task.
    await Task.yield()
    #expect(state.results.count == 2 && state.checkedAt != nil)
    #expect(await fixture.requests.count == 1)
}

@MainActor @Test func cveScanCancellationKeepsUncoveredDistinct() async {
    let fixture = CVETransportFixture([])
    let state = CVEScanState()
    state.start(inventory: [CVEInventoryItem(cveBrew()), CVEInventoryItem(cveApp(bundle: "unknown.app"))],
        client: CVEInventoryClient(transport: { try await fixture.send($0) }))
    state.cancel()
    await state.waitForCompletion()
    #expect(!state.running && state.results.count == 2)
    #expect(state.results.first?.status == "Check incomplete")
    #expect(state.results.last?.failure == nil && state.results.last?.status == "Not covered")
    #expect(await fixture.requests.isEmpty)
}

@Test func cveAdvisoryGroupsMergeAliasesAndKeepEverySource() {
    let records = [
        CVEAdvisory(id: "GHSA-first", aliases: ["CVE-2026-1111"], summary: "First issue"),
        CVEAdvisory(id: "CVE-2026-1111", summary: "First issue with details"),
        CVEAdvisory(id: "GHSA-second", aliases: ["CVE-2026-2222"], summary: "Second issue"),
        CVEAdvisory(id: "CVE-2026-2222")
    ]
    let groups = CVEAdvisoryGroup.grouped(records)
    #expect(groups.count == 2)
    #expect(groups.map(\.id) == ["CVE-2026-1111", "CVE-2026-2222"])
    #expect(groups.first?.summary == "First issue with details")
    #expect(Set(groups.flatMap(\.records).map(\.id)) == Set(records.map(\.id)))
    let result = CVEInventoryResult(item: CVEInventoryItem(cvePackage()), advisories: records, failure: nil)
    #expect(result.status == "2 advisories")
    #expect(CVEAdvisoryGroup.grouped(records.reversed()).map(\.id) == groups.map(\.id))
}

@Test func cveAdvisoryGroupsMergeTransitiveAliasesWithoutMergingUnrelatedIssues() {
    let records = [CVEAdvisory(id: "CVE-2026-1111"), CVEAdvisory(id: "OSV-other"),
        CVEAdvisory(id: "GHSA-a", aliases: ["CVE-2026-1111"]),
        CVEAdvisory(id: "GHSA-b", aliases: ["GHSA-a"], upstream: ["CVE-2026-2222"]),
        CVEAdvisory(id: "CVE-2026-2222")]
    let groups = CVEAdvisoryGroup.grouped(records)
    #expect(groups.count == 2)
    #expect(groups.first?.cveIDs == ["CVE-2026-1111", "CVE-2026-2222"])
    #expect(groups.flatMap(\.records).count == records.count)
    #expect(groups.last?.id == "OSV-other")
}

@Test func cveResultFiltersKeepFailuresAndCoverageDistinct() {
    let item = CVEInventoryItem(cvePackage())
    let unsupported = CVEInventoryItem(cveApp(bundle: "unknown"))
    let finding = CVEInventoryResult(item: item, advisories: [CVEAdvisory(id: "CVE-example")], failure: nil)
    let failure = CVEInventoryResult(item: item, advisories: [], failure: "Unavailable")
    let clear = CVEInventoryResult(item: item, advisories: [], failure: nil)
    #expect(CVEResultFilter.findings.includes(item, result: finding))
    #expect(!CVEResultFilter.findings.includes(item, result: clear))
    #expect(!CVEResultFilter.findings.includes(item, result: nil))
    #expect(CVEResultFilter.incomplete.includes(item, result: failure))
    #expect(!CVEResultFilter.incomplete.includes(unsupported, result: nil))
    #expect(CVEResultFilter.notCovered.includes(unsupported, result: nil))
    #expect(!CVEResultFilter.notCovered.includes(item, result: failure))
    #expect(CVEResultFilter.all.includes(item, result: nil))
}

@MainActor @Test func cveListBadgesRequireMatchingInstalledVersionAndFreshCheck() async throws {
    let fixture = CVETransportFixture([(200, cveBrewFeed)])
    let state = CVEScanState()
    let item = CVEInventoryItem(cveBrew())
    #expect(state.listStatus(for: item) == .pending)
    #expect(state.listStatus(for: CVEInventoryItem(cveApp(bundle: "unknown"))) == .notCovered)
    state.start(inventory: [item], client: CVEInventoryClient(transport: { try await fixture.send($0) }))
    await state.waitForCompletion()
    #expect(state.listStatus(for: item) == .advisories(1, potential: false))
    #expect(state.listStatus(for: CVEInventoryItem(cveBrew(version: "3.0_2"))) == .needsCheck)
    let checkedAt = try #require(state.checkedAt)
    #expect(state.listStatus(for: item, now: checkedAt.addingTimeInterval(86_400)) == .needsCheck)
    let old = cvePackage()
    #expect(CVEInventoryItem(old).hasSameCheckIdentity(as: CVEInventoryItem(old.replacingLatestVersion(with: "100.0"))))
}

@MainActor @Test func cveListBadgesDistinguishFailureAndNoAdvisories() async {
    let fixture = CVETransportFixture([(200, cveBrewFeed)])
    let state = CVEScanState()
    let patched = CVEInventoryItem(cveBrew(version: "3.0_2"))
    state.start(inventory: [patched], client: CVEInventoryClient(transport: { try await fixture.send($0) }))
    await state.waitForCompletion()
    #expect(state.listStatus(for: patched) == .noAdvisories)
    let failed = CVETransportFixture([(503, "{}")])
    state.start(inventory: [patched], client: CVEInventoryClient(transport: { try await failed.send($0) }))
    await state.waitForCompletion()
    #expect(state.listStatus(for: patched) == .incomplete)
    #expect(CVEListStatus.advisories(2, potential: false).title == "2 advisories")
    #expect(CVEListStatus.advisories(1, potential: true).title == "1 potential CVE")
}

@MainActor @Test func cveAutomaticChecksFollowInventoryScansAndCanBeDisabled() async throws {
    let suite = "CVEAuto.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.refreshInterval = .never
    settings.checkOnLaunch = false
    let store = CVEStoreFixture.makeStore(settings: settings, includeCVEInventory: true)
    #expect(settings.automaticallyCheckCVEs)
    await store.scan()
    await store.waitForAutomaticCVECheck()
    #expect(store.cveScanState.results.count == store.cveInventory.count)
    #expect(store.cveScanState.results.contains { !$0.advisories.isEmpty })
    let date = store.cveScanState.checkedAt
    store.setAutomaticCVEChecking(false)
    await store.scan()
    await store.waitForAutomaticCVECheck()
    #expect(store.cveScanState.checkedAt == date)
    #expect(!AppSettings(defaults: defaults).automaticallyCheckCVEs)
    store.setAutomaticCVEChecking(true)
    await store.waitForAutomaticCVECheck()
    #expect(store.cveScanState.checkedAt != date)
    let item = try #require(store.cveInventory.first)
    store.showCVEInfo(for: item)
    #expect(store.selection == .cveChecker)
    #expect(store.cveScanState.searchText == item.name && store.cveScanState.filter == .all)
    #expect(store.cveScanState.requestedItemID == item.id)
}

private actor CVEHeldFeed {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var count = 0
    func send(_ request: URLRequest) async -> (Data, HTTPURLResponse) {
        count += 1
        if count == 1 { await withCheckedContinuation { continuation = $0 } }
        return (Data(cveBrewFeed.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: nil)!)
    }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor private func waitForCVEFeed(_ fixture: CVEHeldFeed) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while await fixture.count == 0 {
        guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
        try await Task.sleep(for: .milliseconds(1))
    }
}

@MainActor @Test func cveAutomaticChecksCoalesceChangesDuringActiveCheck() async throws {
    let suite = "CVECoalesce.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.checkOnLaunch = false; settings.refreshInterval = .never
    let feed = CVEHeldFeed()
    let store = CVEStoreFixture.makeStore(settings: settings, makeCVEClient: {
        CVEInventoryClient(transport: { await feed.send($0) })
    })
    store.apps = []; store.developerPackages = []; store.homebrewPackages = [cveBrew()]
    store.refreshCVEsAutomatically()
    try await waitForCVEFeed(feed)
    store.homebrewPackages = [cveBrew(version: "3.0_2")]
    store.refreshCVEsAutomatically()
    store.refreshCVEsAutomatically()
    await feed.release()
    await store.waitForAutomaticCVECheck()
    #expect(await feed.count == 2)
    #expect(store.cveScanState.inventory == store.cveInventory)
    #expect(store.cveScanState.results.first?.advisories.isEmpty == true)
    #expect(store.cveScanState.listStatus(for: CVEInventoryItem(cveBrew(version: "3.0_2"))) == .noAdvisories)
}

@MainActor @Test func cveDisablingAutomaticChecksDoesNotCancelManualCheck() async throws {
    let suite = "CVEManual.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.checkOnLaunch = false; settings.refreshInterval = .never
    let feed = CVEHeldFeed()
    let store = CVEStoreFixture.makeStore(settings: settings, makeCVEClient: {
        CVEInventoryClient(transport: { await feed.send($0) })
    })
    store.apps = []; store.developerPackages = []; store.homebrewPackages = [cveBrew()]
    store.cveScanState.start(inventory: store.cveInventory, client: store.makeCVEClient())
    try await waitForCVEFeed(feed)
    store.refreshCVEsAutomatically()
    await Task.yield()
    store.setAutomaticCVEChecking(false)
    await feed.release()
    await store.cveScanState.waitForCompletion()
    #expect(store.cveScanState.results.first?.failure == nil)
    #expect(store.cveScanState.results.first?.advisories.count == 1)
    #expect(await feed.count == 1)
}

@Test func cveCVSSBaseScoresAndInvalidVectors() {
    #expect(CVSS3BaseScore.calculate("CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H") == 9.8)
    #expect(CVSS3BaseScore.calculate("CVSS:3.0/AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H") == 10)
    #expect(CVSS3BaseScore.calculate("CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:N") == 0)
    #expect(CVSS3BaseScore.calculate("CVSS:3.1/S:U/AV:N/AC:L/PR:H/UI:N/C:L/I:L/A:N/E:F/RL:X") == 3.8)
    #expect(CVSS3BaseScore.calculate("CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:C/C:L/I:L/A:N") == 6.1)
    for invalid in ["CVSS:4.0/AV:N", "CVSS:3.1/AV:N", "CVSS:3.1/AV:N/AV:L/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H",
                    "CVSS:3.1/AV:INVALID/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H"] {
        #expect(CVSS3BaseScore.calculate(invalid) == nil)
    }
    #expect(CVESeverityRating(score: 9.8, method: "CVSS 3.1").level == .critical)
    #expect(CVESeverityRating(score: 9.8, method: "CVSS 2.0").level == .high)
    #expect(CVESeverityRating(score: 11, method: "CVSS 3.1").level == .unknown)
    #expect(CVESeverityRating(score: nil, label: "MODERATE", method: "Publisher rating").level == .medium)
}

@Test func cveOSVMetadataIsScopedToPackageAndRetainsReleaseBranches() async throws {
    let fixture = CVETransportFixture([(200, #"{"vulns":[{"id":"GHSA-metadata","aliases":["CVE-2026-1234"],"database_specific":{"severity":"MODERATE"},"affected":[{"package":{"name":"other","ecosystem":"npm"},"severity":[{"type":"CVSS_V3","score":"CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H"}],"ranges":[{"type":"SEMVER","events":[{"introduced":"0"},{"fixed":"99.0.0"}]}]},{"package":{"name":"@example/tool","ecosystem":"npm"},"ranges":[{"type":"SEMVER","events":[{"introduced":"0"},{"fixed":"1.2.4"},{"introduced":"2.0.0"},{"fixed":"2.0.1"}]},{"type":"GIT","events":[{"introduced":"abc"},{"fixed":"deadbeef"}]},{"type":"ECOSYSTEM","events":[{"introduced":"0"},{"limit":"3.0.0"}]}]}]}]}"#)])
    let result = try await CVEClient(transport: { try await fixture.send($0) }).check(cvePackage())
    let advisory = try #require(result.advisories.first)
    #expect(advisory.fixedVersions == ["1.2.4", "2.0.1"])
    #expect(CVESeverityRating.highest(advisory.ratings)?.level == .medium)
    #expect(advisory.affected?.count == 1)
}

@Test func cveHomebrewRetainsRevisionFixAndMissingSeverity() throws {
    let feed = try JSONDecoder().decode(HomebrewAdvisoryIndex.self, from: Data(cveBrewFeed.utf8))
    let advisory = try #require(feed.check(name: "zip", version: "3.0_1").first)
    #expect(advisory.fixedVersions == ["3.0_2", "4.1"])
    #expect(CVESeverityRating.highest(advisory.ratings) == nil)
}

@Test func cveNVDUsesPublishedMetricsButDoesNotInventFixedReleases() async throws {
    let fixture = CVETransportFixture([(200, #"{"startIndex":0,"resultsPerPage":2000,"totalResults":2,"vulnerabilities":[{"cve":{"id":"CVE-metric","descriptions":[],"metrics":{"cvssMetricV31":[{"cvssData":{"baseScore":9.8,"baseSeverity":"CRITICAL"}}],"cvssMetricV40":[{"cvssData":{"baseScore":8.7,"baseSeverity":"HIGH"}}]}}},{"cve":{"id":"CVE-unknown","descriptions":[],"configurations":[{"nodes":[{"cpeMatch":[{"versionEndExcluding":"101.0"}]}]}]}}]}"#)])
    let product = try #require(CVEProduct(bundleID: "org.mozilla.firefox", version: "100.0"))
    let results = try await NVDCVEClient(transport: { try await fixture.send($0) }, pace: {}).check(product)
    let rated = try #require(results.first { $0.id == "CVE-metric" })
    #expect(CVESeverityRating.highest(rated.ratings)?.score == 8.7)
    #expect(CVESeverityRating.highest(rated.ratings)?.method == "CVSS 4.0")
    #expect(results.allSatisfy { $0.fixedVersions.isEmpty })
    #expect(results.first { $0.id == "CVE-unknown" }?.ratings.isEmpty == true)
}

@Test func cveGroupedMetadataPreservesSourcesAndPrioritizesHighestSeverity() {
    let critical = CVEAdvisory(id: "GHSA-z", aliases: ["CVE-z"], sourceRatings: [.init(score: 9.8, method: "CVSS 3.1")])
    let low = CVEAdvisory(id: "CVE-z", sourceRatings: [.init(score: 2.1, method: "CVSS 3.1")])
    let other = CVEAdvisory(id: "CVE-a", sourceRatings: [.init(score: 5.4, method: "CVSS 3.1")])
    let grouped = CVEAdvisoryGroup.grouped([low, other, critical])
    #expect(grouped.map(\.id) == ["CVE-z", "CVE-a"])
    #expect(grouped.first?.records.count == 2)
    #expect(grouped.first?.severity?.score == 9.8)
}

@MainActor @Test func cveShowSoftwareClearsFiltersThatCouldHideAffectedInstalledSoftware() async throws {
    let suite = "CVEActions.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.completeSetup(.advanced, sidebarViewMode: .advanced)
    settings.refreshInterval = .never
    settings.checkOnLaunch = false
    settings.automaticallyCheckCVEs = false
    let store = CVEStoreFixture.makeStore(settings: settings, includeCVEInventory: true)
    await store.scan()
    settings.showCurrentDeveloperPackages = false
    let current = try #require(store.developerPackages.first { !$0.isOutdated && CVEPackageQuery($0) != nil })
    store.showCVESoftware(CVEInventoryItem(current))
    store.completeCVESoftwareNavigation()
    #expect(store.selection == .developerPackages)
    #expect(store.filteredDeveloperPackages.contains { $0.id == current.id })
    #expect(store.selectedDeveloperPackageID == current.id)
    store.homebrewFilter = .casks
    let formula = try #require(store.homebrewPackages.first)
    store.showCVESoftware(CVEInventoryItem(formula))
    store.completeCVESoftwareNavigation()
    #expect(store.selection == .homebrewPackages)
    #expect(store.filteredHomebrewPackages.contains { $0.id == formula.id })
    #expect(store.selectedPackageID == formula.id)
    let app = try #require(store.apps.first)
    store.appListFilter = .updates
    store.showCVESoftware(CVEInventoryItem(app))
    store.selectedApp = nil
    store.completeCVESoftwareNavigation()
    #expect(store.selection == .allApps)
    #expect(store.selectedApp?.id == app.id)
    #expect(store.appListFilter == .all)

    settings.sidebarViewMode = .basic
    settings.showCurrentDeveloperPackages = false
    store.selection = .cveChecker
    store.showCVESoftware(CVEInventoryItem(current))
    #expect(store.selection == .cveChecker)
    #expect(store.searchText == current.name)
    #expect(store.navigation.requestedSearchResult == .developer(current.id))
    #expect(!settings.showCurrentDeveloperPackages)
}

@Test func cvePackageMetadataMatchesCanonicalPyPIAndNuGetNames() throws {
    let data = Data(#"{"id":"CVE-canonical","affected":[{"package":{"name":"Example_Tool","ecosystem":"PyPI"},"ranges":[{"type":"ECOSYSTEM","events":[{"introduced":"0"},{"fixed":"2.0"}]}]}]}"#.utf8)
    let advisory = try JSONDecoder().decode(CVEAdvisory.self, from: data)
    let query = try #require(CVEPackageQuery(cvePackage(.python, name: "example-tool")))
    #expect(advisory.scoped(to: query).fixedVersions == ["2.0"])
    let nuget = try JSONDecoder().decode(CVEAdvisory.self, from: Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "PyPI", with: "NuGet").utf8))
    let nugetQuery = try #require(CVEPackageQuery(cvePackage(.dotnet, name: "example_tool")))
    #expect(nuget.scoped(to: nugetQuery).fixedVersions == ["2.0"])
    let unknownShape = try JSONDecoder().decode(CVEAdvisory.self, from: Data(#"{"id":"CVE-shape","database_specific":{"severity":{"custom":"high"}}}"#.utf8))
    #expect(unknownShape.ratings.isEmpty)
}

@MainActor @Test func cveDirectUpdateActionsUseCurrentInventoryOffersAndRespectExclusions() async throws {
    let suite = "CVEUpdateActions.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.automaticallyCheckCVEs = false
    let store = CVEStoreFixture.makeStore(settings: settings, includeCVEInventory: true)
    store.cveScanState.start(inventory: store.cveInventory, client: CVEStoreFixture.cveInventoryClient)
    await store.cveScanState.waitForCompletion()
    let app = CVEInventoryItem(CVEStoreFixture.cveApp)
    let brew = CVEInventoryItem(CVEStoreFixture.cveFormula)
    let developer = CVEInventoryItem(CVEStoreFixture.cvePackages[0])
    #expect(store.cveUpdateAction(for: app)?.title == CVEStoreFixture.cveUpdate.actionTitle)
    #expect(store.cveUpdateAction(for: brew)?.title == "Update")
    #expect(store.cveUpdateAction(for: brew)?.version == "1.0_2")
    #expect(store.cveUpdateAction(for: developer)?.title == "Update")
    #expect(store.cveUpdateAction(for: developer)?.version == "2.0.0")
    #expect(store.cveUpdateAction(for: CVEInventoryItem(CVEStoreFixture.cvePackages[1])) == nil)
    store.skip(CVEStoreFixture.cveFormula)
    store.skip(CVEStoreFixture.cveUpdate)
    store.skip(CVEStoreFixture.cvePackages[0])
    #expect(store.cveUpdateAction(for: app) == nil)
    #expect(store.cveUpdateAction(for: brew) == nil)
    #expect(store.cveUpdateAction(for: developer) == nil)
    store.restoreAllExclusions()
    store.developerPackages = [CVEStoreFixture.cvePackages[0].replacingLatestVersion(with: "1.0.0")]
    #expect(store.cveUpdateAction(for: developer) == nil)
    store.homebrewPackages = []
    store.apps = []
    #expect(store.cveUpdateAction(for: app) == nil)
    #expect(store.cveUpdateAction(for: brew) == nil)
}

@MainActor @Test func cveDirectUpdatesRevalidateVersionAndUseExistingBusyAndErrorHandling() async throws {
    let suite = "CVEUpdateExecution.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.automaticallyCheckCVEs = false
    let store = CVEStoreFixture.makeStore(settings: settings, includeCVEInventory: true)
    store.cveScanState.start(inventory: store.cveInventory, client: CVEStoreFixture.cveInventoryClient)
    await store.cveScanState.waitForCompletion()
    let item = CVEInventoryItem(CVEStoreFixture.cvePackages[0])
    let action = try #require(store.cveUpdateAction(for: item))
    store.updateExecutionState.activeOperations.insert(action.operation)
    #expect(store.isUpdatingCVESoftware(action))
    await store.updateCVESoftware(item)
    #expect(store.errorMessage == nil)
    store.updateExecutionState.activeOperations.remove(action.operation)
    await store.updateCVESoftware(item)
    // The injected fixture rejects every mutation; reaching its error proves normal execution was used.
    #expect(store.errorMessage != nil)
    store.errorMessage = nil
    let changed = DeveloperPackage(name: CVEStoreFixture.cvePackages[0].name, currentVersion: "1.0.1", latestVersion: "2.0.0",
                                   manager: .npm, executablePath: "/fixture/npm")
    store.developerPackages = [changed]
    #expect(store.cveUpdateAction(for: item) == nil)
    await store.updateCVESoftware(item)
    #expect(store.errorMessage == nil)
}

@MainActor @Test func cveUpdateAllIncludesAllAffectedOffersIndependentOfFilters() async throws {
    let suite = "CVEUpdateAll.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.automaticallyCheckCVEs = false
    let store = CVEStoreFixture.makeStore(settings: settings, includeCVEInventory: true)
    store.cveScanState.start(inventory: store.cveInventory, client: CVEStoreFixture.cveInventoryClient)
    await store.cveScanState.waitForCompletion()
    store.cveScanState.searchText = "nothing matches"
    store.cveScanState.filter = .incomplete
    let items = store.cveBatchUpdateItems
    #expect(Set(items.map(\.name)) == ["Fixture Firefox", "zip", "fixture-vulnerable-tool"])
    #expect(!items.contains { $0.name == "Fixture Editor" })
    let developer = try #require(items.first { if case .developer = $0 { true } else { false } })
    store.updateExecutionState.activeOperations.insert(developer.updateOperationID)
    #expect(store.cveBatchUpdateItems.count == 2)
    store.updateExecutionState.activeOperations.remove(developer.updateOperationID)
    store.skip(CVEStoreFixture.cveFormula)
    #expect(!store.cveBatchUpdateItems.contains { $0.name == "zip" })
    store.restoreAllExclusions()
    // A reviewed offer must still match when execution begins; no stale mutation is attempted.
    store.developerPackages = [CVEStoreFixture.cvePackages[0].replacingLatestVersion(with: "3.0.0")]
    let summary = await store.performCVEBatchUpdates([developer, developer])
    #expect(summary.results.count == 1)
    #expect(summary.failedCount == 1)
    #expect(summary.results.first?.detail.contains("changed") == true)
    #expect(store.errorMessage == nil)
}

@MainActor @Test func cveUpdateAllDeduplicatesAnAppAndItsActualHomebrewCaskAction() async throws {
    let suite = "CVEUpdateAllCask.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.automaticallyCheckCVEs = false
    let store = CVEStoreFixture.makeStore(settings: settings, includeCVEInventory: true)
    let cask = HomebrewPackage(token: "firefox", displayName: "Firefox", description: nil, homepage: nil, license: nil,
        installedVersion: "100.0", currentVersion: "101.0", kind: .cask, isOutdated: true,
        isDependency: false, dependencies: [], tap: "homebrew/cask")
    store.homebrewPackages = [cask]
    let appUpdate = AvailableUpdate(app: CVEStoreFixture.cveApp, availableVersion: "101.0", source: .homebrew,
                                   releaseNotes: nil, actionURL: nil, homebrewToken: "firefox")
    store.updates = [appUpdate]
    store.cveScanState.start(inventory: store.cveInventory, client: CVEStoreFixture.cveInventoryClient)
    await store.cveScanState.waitForCompletion()
    #expect(store.cveBatchUpdateItems.filter { if case .application = $0 { true } else { false } }.count == 1)
    #expect(store.cveBatchUpdateItems.filter { if case .homebrew = $0 { true } else { false } }.isEmpty)
    // Without an app's Homebrew action, the affected cask remains independently updatable.
    store.updates = []
    #expect(store.cveBatchUpdateItems.filter { if case .homebrew = $0 { true } else { false } }.count == 1)
}

@MainActor @Test func cveUpdateAllUsesExistingBatchFailureReportingForValidOffers() async throws {
    let suite = "CVEUpdateAllExecution.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.automaticallyCheckCVEs = false
    let store = CVEStoreFixture.makeStore(settings: settings, includeCVEInventory: true)
    store.cveScanState.start(inventory: store.cveInventory, client: CVEStoreFixture.cveInventoryClient)
    await store.cveScanState.waitForCompletion()
    let developer = try #require(store.cveBatchUpdateItems.first { if case .developer = $0 { true } else { false } })
    let summary = await store.performCVEBatchUpdates([developer])
    #expect(summary.results.count == 1)
    #expect(summary.results.first?.item.id == developer.id)
    #expect(summary.failedCount == 1) // The offline fixture blocks installation.
    #expect(!store.isWorking(.unifiedBatch))
    #expect(store.batchUpdateProgress == nil)
}
