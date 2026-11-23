import Foundation
import Testing
@testable import Upkeep

@MainActor private func settings(_ suite: String) -> AppSettings {
    AppSettings(defaults: UserDefaults(testSuiteName: suite)!)
}

// MARK: - App Store updates with mas

@Test func appStoreListingsGiveTheAppID() {
    #expect(MacAppStoreCLI.appID(from: URL(string: "https://apps.apple.com/us/app/xcode/id497799835?mt=12")) == "497799835")
    #expect(MacAppStoreCLI.appID(from: URL(string: "https://apps.apple.com/app/id1234567")) == "1234567")
    #expect(MacAppStoreCLI.appID(from: URL(string: "https://apps.apple.com/us/app/xcode")) == nil)
    #expect(MacAppStoreCLI.appID(from: nil) == nil)
}

private actor RecordingAppStoreUpdater: AppStoreUpdating {
    nonisolated var isAvailable: Bool { true }
    var updated: [String] = []
    func update(appID: String) async throws { updated.append(appID) }
}

@MainActor
@Test func appStoreUpdatesRunMasWhenItIsInstalled() async {
    let suite = "Upkeep.MasTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removeTestDomain(forName: suite) }
    let updater = RecordingAppStoreUpdater()
    let store = CVEStoreFixture.makeStore(settings: settings(suite), appStoreUpdater: updater)
    let app = InstalledApp(name: "Pages", bundleIdentifier: "com.apple.iWork.Pages", installedVersion: "14.0",
                           buildVersion: nil, url: URL(fileURLWithPath: "/fixture/Pages.app"), sparkleFeedURL: nil,
                           githubRepository: nil, hasAppStoreReceipt: true)
    let update = AvailableUpdate(app: app, availableVersion: "14.1", source: .appStore, releaseNotes: nil,
                                 actionURL: URL(string: "https://apps.apple.com/us/app/pages/id409201541?mt=12"),
                                 homebrewToken: nil)
    store.apps = [app]; store.updates = [update]
    await store.performUpdate(update)
    #expect(await updater.updated == ["409201541"])
}

// MARK: - Homebrew pinning

private actor PinningBrew: HomebrewManaging {
    var calls: [String] = []
    var refreshed: HomebrewPackage?
    init(refreshed: HomebrewPackage?) { self.refreshed = refreshed }
    func package(token: String, kind: HomebrewPackageKind, includePrereleases: Bool) async throws -> HomebrewPackage? { refreshed }
    func upgrade(_ package: HomebrewPackage) async throws {}
    func adopt(_ item: AdoptableApp) async throws {}
    func installOrReplace(_ item: AdoptableApp) async throws {}
    func upgradeCask(token: String) async throws {}
    func setPinned(_ package: HomebrewPackage, _ pinned: Bool) async throws {
        calls.append("\(pinned ? "pin" : "unpin") \(package.token)")
    }
}

private func formula(_ token: String, outdated: Bool = true, pinned: Bool = false) -> HomebrewPackage {
    HomebrewPackage(token: token, displayName: token, description: nil, homepage: nil, license: nil,
                    installedVersion: "1.0.0", currentVersion: "1.0.1", kind: .formula, isOutdated: outdated,
                    isDependency: false, dependencies: [], isPinned: pinned)
}

@MainActor
@Test func pinningAFormulaHoldsItAndUnpinningRestoresItsUpdate() async {
    let suite = "Upkeep.PinTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removeTestDomain(forName: suite) }
    let brew = PinningBrew(refreshed: formula("jq"))
    let appSettings = settings(suite)
    appSettings.automaticUpdates = .homebrewFormulae
    let store = CVEStoreFixture.makeStore(settings: appSettings, homebrew: brew)
    store.updates = []
    store.homebrewPackages = [formula("jq")]
    #expect(store.automaticUpdateItems.count == 1)

    await store.setPinned(store.homebrewPackages[0], true)
    #expect(await brew.calls == ["pin jq"])
    #expect(store.homebrewPackages[0].isPinned && !store.homebrewPackages[0].isOutdated)
    #expect(store.homebrewPackages[0].currentVersion == "1.0.1")
    #expect(store.automaticUpdateItems.isEmpty)

    await store.setPinned(store.homebrewPackages[0], false)
    #expect(await brew.calls == ["pin jq", "unpin jq"])
    #expect(!store.homebrewPackages[0].isPinned && store.homebrewPackages[0].isOutdated)
}

@Test func pinnedFormulaeAreReadAsCurrent() throws {
    let data = Data(#"{"formulae":[{"name":"jq","versions":{"stable":"1.8"},"dependencies":[],"installed":[{"version":"1.7","installed_on_request":true}],"outdated":true,"pinned":true}],"casks":[]}"#.utf8)
    let package = try #require(decodeHomebrewInventory(data).first)
    #expect(package.isPinned && !package.isOutdated && package.currentVersion == "1.8")
}

// MARK: - Release notes

@Test func githubRepositoriesAreFoundInPackageMetadataURLs() {
    #expect(githubRepository(fromURL: "git+https://github.com/openai/codex.git") == "openai/codex")
    #expect(githubRepository(fromURL: "git://github.com/sindresorhus/is-number.git") == "sindresorhus/is-number")
    #expect(githubRepository(fromURL: "github:jqlang/jq") == "jqlang/jq")
    #expect(githubRepository(fromURL: "https://github.com/pnpm/pnpm/tree/main/pnpm#readme") == "pnpm/pnpm")
    #expect(githubRepository(fromURL: "https://github.com/sponsors/someone") == nil)
    #expect(githubRepository(fromURL: "https://gitlab.com/owner/repo") == nil)
}

@Test func releasesMatchTheVersionWhateverTheTagPrefix() {
    func release(_ tag: String, draft: Bool = false) -> PackageReleaseNotesClient.Release {
        .init(tagName: tag, name: nil, body: tag, htmlUrl: nil, draft: draft)
    }
    let list = [release("v2.0.0", draft: true), release("rust-v0.171.0"), release("bun-v1.4.5"),
                release("@scope/pkg@3.1.0"), release("v1.2.3"), release("11.2.3")]
    #expect(PackageReleaseNotesClient.release(matching: "1.2.3", in: list)?.tagName == "v1.2.3")
    #expect(PackageReleaseNotesClient.release(matching: "0.171.0", in: list)?.tagName == "rust-v0.171.0")
    #expect(PackageReleaseNotesClient.release(matching: "1.4.5", in: list)?.tagName == "bun-v1.4.5")
    #expect(PackageReleaseNotesClient.release(matching: "3.1.0", in: list)?.tagName == "@scope/pkg@3.1.0")
    #expect(PackageReleaseNotesClient.release(matching: "2.0.0", in: list) == nil)
}

@Test func packageReleaseNotesComeFromTheRegistrysGitHubRepository() async {
    let client = PackageReleaseNotesClient(fetch: { url in
        switch url.absoluteString {
        case "https://registry.npmjs.org/@openai/codex/latest":
            return Data(#"{"repository":{"type":"git","url":"git+https://github.com/openai/codex.git"}}"#.utf8)
        case "https://api.github.com/repos/openai/codex/tags?per_page=100":
            return Data(#"[{"name":"rust-v0.172.0-alpha.1"},{"name":"rust-v0.171.0"}]"#.utf8)
        case "https://api.github.com/repos/openai/codex/releases/tags/rust-v0.171.0":
            return Data(###"{"tag_name":"rust-v0.171.0","body":"## Fixes\n- Faster startup","html_url":"https://github.com/openai/codex/releases/tag/rust-v0.171.0"}"###.utf8)
        default:
            return nil
        }
    })
    let request = PackageReleaseNotesRequest(source: .npm("@openai/codex"), version: "0.171.0")
    let notes = await client.releaseNotes(for: request)
    #expect(notes?.notes == "## Fixes\n- Faster startup")
    #expect(notes?.url?.absoluteString == "https://github.com/openai/codex/releases/tag/rust-v0.171.0")
    #expect(await client.releaseNotes(for: PackageReleaseNotesRequest(source: .npm("@openai/codex"), version: "9.9.9")) == nil)
}

@Test func releaseNoteRequestsUseTheVersionBeingInstalled() {
    let outdated = DeveloperPackage(name: "@openai/codex", currentVersion: "0.147.0", latestVersion: "0.171.0",
                                    manager: .npm, executablePath: "/fixture/npm")
    #expect(PackageReleaseNotesRequest.make(for: outdated) == PackageReleaseNotesRequest(source: .npm("@openai/codex"), version: "0.171.0"))
    let node = DeveloperPackage(name: "Node.js", currentVersion: "22.1.0", latestVersion: "22.1.0", manager: .node, executablePath: "/fixture/node")
    #expect(PackageReleaseNotesRequest.make(for: node)?.source == .repository("nodejs/node"))
    let brew = HomebrewPackage(token: "ripgrep", displayName: "ripgrep", description: nil,
                               homepage: URL(string: "https://github.com/BurntSushi/ripgrep"), license: nil,
                               installedVersion: "15.2.0", currentVersion: "16.0.0_1", kind: .formula, isOutdated: true,
                               isDependency: false, dependencies: [])
    #expect(PackageReleaseNotesRequest.make(for: brew) == PackageReleaseNotesRequest(source: .repository("BurntSushi/ripgrep"), version: "16.0.0"))
    #expect(PackageReleaseNotesRequest.homebrewUpstreamVersion("1.2_3") == "1.2")
    #expect(PackageReleaseNotesRequest.homebrewUpstreamVersion("2024_06") == "2024")
}

// MARK: - Notification actions

@MainActor
@Test func updateRecommendedFromANotificationReviewsUpdatesThatNeedAPassword() async {
    let suite = "Upkeep.NotificationTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removeTestDomain(forName: suite) }
    let brew = PinningBrew(refreshed: nil)
    let store = CVEStoreFixture.makeStore(settings: settings(suite), homebrew: brew)
    store.updates = []
    let cask = HomebrewPackage(token: "raycast", displayName: "Raycast", description: nil, homepage: nil, license: nil,
                               installedVersion: "1.0.0", currentVersion: "1.0.1", kind: .cask, isOutdated: true,
                               isDependency: false, dependencies: [])
    store.homebrewPackages = [cask]
    await store.updateRecommendedFromNotification()
    #expect(store.navigation.isShowingBatchReview)
    #expect(store.selection == .updates)
}

@Test func updateNotificationsOfferReviewAndUpdateRecommended() {
    let category = UpdateNotificationAction.category
    #expect(category.identifier == UpdateNotificationAction.categoryIdentifier)
    #expect(category.actions.map(\.title) == ["Review", "Update Recommended"])
    #expect(category.actions.first?.options.contains(.foreground) == true)
}

@Test func olderReleasesAreFetchedByTheRepositorysTagPattern() async {
    let client = PackageReleaseNotesClient(fetch: { url in
        switch url.absoluteString {
        case "https://api.github.com/repos/openai/codex/tags?per_page=100":
            return Data(#"[{"name":"rust-v0.173.0-alpha.4"},{"name":"rust-v0.172.0"}]"#.utf8)
        case "https://api.github.com/repos/openai/codex/releases/tags/rust-v0.171.0":
            return Data(#"{"tag_name":"rust-v0.171.0","body":"The one we want"}"#.utf8)
        default:
            return nil
        }
    })
    let notes = await client.releaseNotes(for: PackageReleaseNotesRequest(source: .repository("openai/codex"), version: "0.171.0"))
    #expect(notes?.notes == "The one we want")
    #expect(PackageReleaseNotesClient.candidateTags(for: "1.0.0", from: []) == ["v1.0.0", "1.0.0"])
    // Other crates' tags in the same repository do not crowd out the plain tag.
    let crates = ["wincolor-0.1.6", "wincolor-0.1.5", "grep-0.3.2", "grep-0.3.1", "ignore-0.4.23"]
    #expect(PackageReleaseNotesClient.candidateTags(for: "16.0.0", from: crates) == ["grep-16.0.0", "wincolor-16.0.0", "v16.0.0", "16.0.0"])
}
