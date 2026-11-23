import Foundation
import Testing
@testable import Upkeep

// MARK: - GitHub API access

private final class TokenReads: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func read() { lock.withLock { count += 1 } }
}

private func request(_ url: String, authorization: String? = nil) -> URLRequest {
    var request = URLRequest(url: URL(string: url)!)
    if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
    return request
}

private func response(_ url: String, status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: url)!, statusCode: status, httpVersion: nil, headerFields: headers)!
}

private let token = "gho_" + String(repeating: "a", count: 36)

@Test func gitHubSignInIsSentOnlyToTheGitHubAPI() async throws {
    let reads = TokenReads()
    let access = GitHubAPIAccess(readToken: { reads.read(); return token + "\n" })
    let api = try await access.prepare(request("https://api.github.com/repos/cli/cli/releases"))
    #expect(api.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
    let web = try await access.prepare(request("https://github.com/nvm-sh/nvm/releases/latest"))
    #expect(web.value(forHTTPHeaderField: "Authorization") == nil)
    let other = try await access.prepare(request("https://registry.npmjs.org/npm"))
    #expect(other.value(forHTTPHeaderField: "Authorization") == nil)
    let plain = try await access.prepare(request("http://api.github.com/repos/cli/cli"))
    #expect(plain.value(forHTTPHeaderField: "Authorization") == nil)
    _ = try await access.prepare(request("https://api.github.com/repos/cli/cli"))
    #expect(reads.value == 1)

    await access.setUsesGitHubCLI(false)
    let signedOut = try await access.prepare(request("https://api.github.com/repos/cli/cli"))
    #expect(signedOut.value(forHTTPHeaderField: "Authorization") == nil)
}

@Test func anExhaustedGitHubLimitPausesRequestsUntilItResets() async throws {
    nonisolated(unsafe) var now = Date(timeIntervalSince1970: 1_000)
    let access = GitHubAPIAccess(readToken: { nil }, now: { now })
    let sent = try await access.prepare(request("https://api.github.com/repos/a/b"))
    await access.record(response("https://api.github.com/repos/a/b", status: 403,
                                 headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "2000"]), for: sent)
    await #expect(throws: GitHubAPIAccess.RateLimited(resetsAt: Date(timeIntervalSince1970: 2_000), isSignedIn: false)) {
        try await access.prepare(request("https://api.github.com/repos/c/d"))
    }
    // Other hosts are unaffected.
    _ = try await access.prepare(request("https://github.com/a/b/releases/latest"))
    now = Date(timeIntervalSince1970: 2_001)
    _ = try await access.prepare(request("https://api.github.com/repos/c/d"))
    #expect(await access.isRateLimited == false)
}

@Test func aRejectedGitHubTokenIsDroppedAndAForbiddenPageIsNotALimit() async throws {
    let access = GitHubAPIAccess(readToken: { token })
    let signed = try await access.prepare(request("https://api.github.com/repos/a/b"))
    await access.record(response("https://api.github.com/repos/a/b", status: 401), for: signed)
    let next = try await access.prepare(request("https://api.github.com/repos/a/b"))
    #expect(next.value(forHTTPHeaderField: "Authorization") == nil)

    await access.record(response("https://api.github.com/repos/a/b", status: 403), for: next)
    #expect(await access.isRateLimited == false)
}

@Test func gitHubTokensAndReleaseTagsAreValidated() {
    #expect(GitHubAPIAccess.validToken("  \(token)\n") == token)
    #expect(GitHubAPIAccess.validToken("not a token") == nil)
    #expect(GitHubAPIAccess.validToken("short") == nil)
    #expect(githubReleaseTag(fromPath: "/nvm-sh/nvm/releases/tag/v0.41.0") == "v0.41.0")
    #expect(githubReleaseTag(fromPath: "/oven-sh/bun/releases/tag/bun-v1.4.5/") == "bun-v1.4.5")
    #expect(githubReleaseTag(fromPath: "/nvm-sh/nvm/releases") == nil)
}

// MARK: - App data

private func makeLibrary(_ paths: [String]) throws -> URL {
    let library = FileManager.default.temporaryDirectory.appendingPathComponent("UpkeepLibrary-\(UUID().uuidString)")
    for path in paths {
        let url = library.appendingPathComponent(path)
        if path.hasSuffix(".plist") || path.hasSuffix(".binarycookies") {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        } else {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
    return library
}

private func testApp(_ name: String, _ bundleID: String?, path: String? = nil) -> InstalledApp {
    InstalledApp(name: name, bundleIdentifier: bundleID, installedVersion: "1.0", buildVersion: nil,
                 url: URL(fileURLWithPath: path ?? "/Applications/\(name).app"), sparkleFeedURL: nil,
                 githubRepository: nil, hasAppStoreReceipt: false)
}

@Test func appDataIsFoundByBundleIdentifierAndUnsharedName() throws {
    let library = try makeLibrary([
        "Application Support/com.example.editor", "Caches/com.example.editor",
        "Preferences/com.example.editor.plist", "Preferences/ByHost/com.example.editor.ABC123.plist",
        "Saved Application State/com.example.editor.savedState", "Application Support/Editor",
        "Application Support/com.example.editorhelper", "Caches/com.other.app", "Preferences/com.example.editor.other.plist"
    ])
    defer { try? FileManager.default.removeItem(at: library) }
    let editor = testApp("Editor", "com.example.editor")
    let items = AppDataLocator.items(for: editor, otherApps: [editor], library: library)
    let paths = Set(items.map { $0.url.path.replacingOccurrences(of: library.path + "/", with: "") })
    #expect(paths == [
        "Application Support/com.example.editor", "Caches/com.example.editor",
        "Preferences/com.example.editor.plist", "Preferences/ByHost/com.example.editor.ABC123.plist",
        "Saved Application State/com.example.editor.savedState", "Application Support/Editor"
    ])
    #expect(AppDataLocator.locationSummary(items) == "Application Support, Caches, Preferences, and Saved Application State"
            || AppDataLocator.locationSummary(items) == "Application Support, Caches, Preferences and Saved Application State")

    // A second app named Editor keeps the shared name folder.
    let otherEditor = testApp("Editor", "com.example.other-editor", path: "/Applications/Other/Editor.app")
    let named = AppDataLocator.items(for: editor, otherApps: [editor, otherEditor], library: library)
    #expect(!named.contains { $0.url.lastPathComponent == "Editor" })
}

@Test func appDataIsKeptForCopiesAppleAppsAndAppsWithoutIdentifiers() throws {
    let library = try makeLibrary(["Caches/com.example.editor", "Caches/com.apple.Pages", "Caches/NoID"])
    defer { try? FileManager.default.removeItem(at: library) }
    let editor = testApp("Editor", "com.example.editor")
    let copy = testApp("Editor", "com.example.editor", path: "/Users/test/Applications/Editor.app")
    #expect(AppDataLocator.items(for: editor, otherApps: [editor, copy], library: library).isEmpty)
    #expect(AppDataLocator.items(for: testApp("Pages", "com.apple.Pages"), otherApps: [], library: library).isEmpty)
    #expect(AppDataLocator.items(for: testApp("NoID", nil), otherApps: [], library: library).isEmpty)
}

private actor RecordingAppUninstaller: AppUninstalling {
    var trashedApps: [URL] = []
    var trashedData: [URL] = []
    let protected: Set<String>
    init(protected: Set<String> = []) { self.protected = protected }
    func moveToTrash(_ url: URL) async throws -> URL? { trashedApps.append(url); return nil }
    func moveDataToTrash(_ urls: [URL]) async -> AppDataTrashResult {
        // Protected by the Library folder they are in, such as Containers.
        let isProtected = { (url: URL) in self.protected.contains(url.deletingLastPathComponent().lastPathComponent) }
        let moved = urls.filter { !isProtected($0) }
        trashedData += moved
        return AppDataTrashResult(moved: moved.map { TrashedItem(originalPath: $0.path, trashPath: "/fixture/.Trash/" + $0.lastPathComponent) },
                                  failed: urls.filter(isProtected))
    }
}

@MainActor
@Test func uninstallingWithDataMovesTheAppsLibraryFoldersToTheTrash() async throws {
    let bundleID = CVEStoreFixture.app.bundleIdentifier!
    let library = try makeLibrary(["Caches/\(bundleID)", "Containers/\(bundleID)", "Caches/com.other.app"])
    defer { try? FileManager.default.removeItem(at: library) }
    let suite = "Upkeep.AppDataTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removeTestDomain(forName: suite) }
    let uninstaller = RecordingAppUninstaller(protected: ["Containers"])
    let store = CVEStoreFixture.makeStore(settings: AppSettings(defaults: UserDefaults(testSuiteName: suite)!),
                                          appUninstaller: uninstaller, appDataLibrary: library)
    let app = CVEStoreFixture.app
    #expect(store.appData(for: app).count == 2)

    await store.uninstallApp(app, removingData: true)
    #expect(await uninstaller.trashedApps == [app.url])
    #expect(await uninstaller.trashedData.map(\.path) == [library.appendingPathComponent("Caches/\(bundleID)").path])
    // The protected container is reported, and the app is still gone from the list.
    #expect(store.errorMessage?.contains("Containers") == true)
    #expect(!store.apps.contains { $0.id == app.id })
}

@MainActor
@Test func uninstallingWithoutDataLeavesTheLibraryAlone() async throws {
    let bundleID = CVEStoreFixture.app.bundleIdentifier!
    let library = try makeLibrary(["Caches/\(bundleID)"])
    defer { try? FileManager.default.removeItem(at: library) }
    let suite = "Upkeep.AppDataTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removeTestDomain(forName: suite) }
    let uninstaller = RecordingAppUninstaller()
    let store = CVEStoreFixture.makeStore(settings: AppSettings(defaults: UserDefaults(testSuiteName: suite)!),
                                          appUninstaller: uninstaller, appDataLibrary: library)
    await store.uninstallApp(CVEStoreFixture.app)
    #expect(await uninstaller.trashedApps.count == 1)
    #expect(await uninstaller.trashedData.isEmpty)
}

// MARK: - Automatic updates

@MainActor
@Test func automaticUpdatesOnlyIncludeWhatTheSettingAllows() {
    let suite = "Upkeep.AutomaticUpdateTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removeTestDomain(forName: suite) }
    let settings = AppSettings(defaults: UserDefaults(testSuiteName: suite)!)
    let store = CVEStoreFixture.makeStore(settings: settings)
    func package(_ token: String, _ kind: HomebrewPackageKind, dependency: Bool = false, to latest: String = "1.0.1") -> HomebrewPackage {
        HomebrewPackage(token: token, displayName: token, description: nil, homepage: nil, license: nil,
                        installedVersion: "1.0.0", currentVersion: latest, kind: kind, isOutdated: true,
                        isDependency: dependency, dependencies: [])
    }
    store.updates = []
    store.homebrewPackages = [package("jq", .formula), package("libpng", .formula, dependency: true),
                              package("node", .formula, to: "2.0.0"), package("raycast", .cask)]

    #expect(settings.automaticUpdates == .off)
    #expect(store.automaticUpdateItems.isEmpty)

    settings.automaticUpdates = .homebrewFormulae
    #expect(store.automaticUpdateItems.map(\.name) == ["jq"])

    // Casks may ask for a password in Terminal, so they wait even here.
    settings.automaticUpdates = .recommended
    #expect(store.automaticUpdateItems.map(\.name) == ["jq"])
}

// MARK: - Links

@Test func upkeepLinksOpenViewsAndStartChecksOnly() {
    #expect(UpkeepLink(URL(string: "upkeep://updates")!) == .show(.updates))
    #expect(UpkeepLink(URL(string: "upkeep://")!) == .show(.updates))
    #expect(UpkeepLink(URL(string: "upkeep://Homebrew")!) == .show(.homebrewPackages))
    #expect(UpkeepLink(URL(string: "upkeep://ai-models")!) == .show(.localModels))
    #expect(UpkeepLink(URL(string: "upkeep:check")!) == .check)
    #expect(UpkeepLink(URL(string: "upkeep://review")!) == .review)
    #expect(UpkeepLink(URL(string: "upkeep://search?q=fire%20fox")!) == .search("fire fox"))
    #expect(UpkeepLink(URL(string: "upkeep://search")!) == nil)
    #expect(UpkeepLink(URL(string: "upkeep://install-everything")!) == nil)
    #expect(UpkeepLink(URL(string: "https://updates")!) == nil)
}

// MARK: - More descriptions

@Test func steamGamesAndDotNetToolsHaveDescriptions() async {
    let client = ItemDescriptionClient(caskCatalog: { [] }, appStoreLookup: { _ in [:] }, fetch: { request in
        let url = request.url?.absoluteString ?? ""
        if url.hasPrefix("https://store.steampowered.com/api/appdetails?appids=3419430") {
            return .data(Data(#"{"3419430":{"success":true,"data":{"short_description":"Bongo cat needs your help."}}}"#.utf8))
        }
        if url.hasPrefix("https://azuresearch-usnc.nuget.org/query"), url.contains("dotnet-ef") {
            return .data(Data(#"{"data":[{"id":"dotnet-ef","description":"Entity Framework Core Tools for the .NET Command-Line Interface.\n\n  More."}]}"#.utf8))
        }
        return .notFound
    })
    let game = AppDescriptionInput(bundleIdentifier: "com.steam.3419430", name: "Bongo Cat",
                                   url: URL(fileURLWithPath: "/fixture/Bongo Cat.app"), isAppStore: false, steamAppID: "3419430")
    let tool = ItemDescriptionRequest.developerPackage(manager: .dotnet, identifier: "dotnet-ef")
    let results = await client.describe([.app(game), tool])
    #expect(results[game.key] == .found("Bongo cat needs your help."))
    #expect(results[tool.key] == .found("Entity Framework Core Tools for the .NET Command-Line Interface."))
}

@MainActor
@Test func automaticUpdatesWaitForPowerAndAnUnmeteredNetwork() async {
    let suite = "Upkeep.AutomaticUpdateTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removeTestDomain(forName: suite) }
    let settings = AppSettings(defaults: UserDefaults(testSuiteName: suite)!)
    settings.automaticUpdates = .homebrewFormulae
    let formula = HomebrewPackage(token: "jq", displayName: "jq", description: nil, homepage: nil, license: nil,
                                  installedVersion: "1.0.0", currentVersion: "1.0.1", kind: .formula, isOutdated: true,
                                  isDependency: false, dependencies: [])

    let waiting = CVEStoreFixture.makeStore(settings: settings,
        unattendedConditions: ReadyForUnattendedUpdates(reason: "the Mac is on battery power"))
    waiting.updates = []; waiting.homebrewPackages = [formula]
    #expect(await waiting.installAutomaticUpdates() == nil)

    let ready = CVEStoreFixture.makeStore(settings: settings)
    ready.updates = []; ready.homebrewPackages = [formula]
    // The fixture refuses real upgrades, so the attempt is reported as failed.
    let summary = await ready.installAutomaticUpdates()
    #expect(summary?.results.count == 1)
}

@Test func meteredAndOfflineNetworksDelayAutomaticUpdates() {
    #expect(LiveUnattendedConditions.reasonToWait(status: .satisfied, isExpensive: false, isConstrained: false) == nil)
    #expect(LiveUnattendedConditions.reasonToWait(status: .satisfied, isExpensive: true, isConstrained: false)?.contains("metered") == true)
    #expect(LiveUnattendedConditions.reasonToWait(status: .satisfied, isExpensive: false, isConstrained: true)?.contains("Low Data Mode") == true)
    #expect(LiveUnattendedConditions.reasonToWait(status: .unsatisfied, isExpensive: false, isConstrained: false) != nil)
}

@MainActor
@Test func putBackMovesUninstalledItemsBackFromTheTrash() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("UpkeepPutBack-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let original = root.appendingPathComponent("Models/model.gguf")
    let trash = root.appendingPathComponent("Trash/model.gguf")
    let dataOriginal = root.appendingPathComponent("Library/Caches/model")
    let dataTrash = root.appendingPathComponent("Trash/model-cache")
    try FileManager.default.createDirectory(at: trash.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("weights".utf8).write(to: trash)
    try FileManager.default.createDirectory(at: dataTrash, withIntermediateDirectories: true)
    let record = UpdateRecord(id: UUID(), date: Date(), name: "Model", fromVersion: "abc", toVersion: "",
        kind: .model, originalAppPath: nil, backupPath: nil, recoveryNote: nil, action: .uninstall,
        trashedItems: [TrashedItem(originalPath: original.path, trashPath: trash.path),
                       TrashedItem(originalPath: dataOriginal.path, trashPath: dataTrash.path)])
    #expect(record.canPutBack && !record.isBackInPlace)

    let suite = "Upkeep.PutBackTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removeTestDomain(forName: suite) }
    let store = CVEStoreFixture.makeStore(settings: AppSettings(defaults: UserDefaults(testSuiteName: suite)!))
    await store.putBack(record)
    #expect(FileManager.default.fileExists(atPath: original.path))
    #expect(FileManager.default.fileExists(atPath: dataOriginal.path))
    #expect(!FileManager.default.fileExists(atPath: trash.path))
    #expect(!record.canPutBack && record.isBackInPlace)
}

@Test func olderHistoryRecordsReadAsUpdates() throws {
    let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":0,"name":"Editor","fromVersion":"1","toVersion":"2","kind":"App"}"#
    let record = try JSONDecoder().decode(UpdateRecord.self, from: Data(json.utf8))
    #expect(!record.isUninstall && record.trashedItems == nil && !record.canPutBack)
}
