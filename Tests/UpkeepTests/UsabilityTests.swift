import Foundation
import Testing
@testable import Upkeep

@MainActor
private func usabilityStore() throws -> (UpkeepStore, AppSettings, () -> Void) {
    let suite = "UpkeepTests.Usability.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(testSuiteName: suite))
    let settings = AppSettings(defaults: defaults)
    return (UpkeepStore(settings: settings), settings, { defaults.removeTestDomain(forName: suite) })
}

private func storeApp(_ name: String) -> InstalledApp {
    InstalledApp(
        name: name, bundleIdentifier: "test.usability.\(name)", installedVersion: "1.0",
        buildVersion: nil, url: URL(fileURLWithPath: "/Applications/\(name).app"),
        sparkleFeedURL: nil, githubRepository: nil, hasAppStoreReceipt: true
    )
}

private func formula(_ token: String, outdated: Bool = true) -> HomebrewPackage {
    HomebrewPackage(
        token: token, displayName: token, description: nil, homepage: nil, license: nil,
        installedVersion: "1.0", currentVersion: outdated ? "1.1" : "1.0", kind: .formula,
        isOutdated: outdated, isDependency: false, dependencies: []
    )
}

@MainActor
@Test func sidebarBadgesCountPendingUpdatesNotInventory() throws {
    let (store, _, cleanUp) = try usabilityStore()
    defer { cleanUp() }
    let kept = storeApp("Kept")
    let ignored = storeApp("Ignored")
    store.apps = [kept, ignored, storeApp("Current")]
    store.updates = [kept, ignored].map {
        AvailableUpdate(app: $0, availableVersion: "2.0", source: .appStore, releaseNotes: nil,
                        actionURL: URL(string: "macappstore://apps.apple.com/app/id1"), homebrewToken: nil)
    }
    store.homebrewPackages = [formula("pending"), formula("skipped"), formula("current", outdated: false)]
    store.macOSUpdates = [false, true].map { installer in
        MacOSUpdate(label: "macOS-\(installer)", title: "macOS", version: "27.0", size: nil,
                    requiresRestart: true, isBeta: false, isFullInstaller: installer)
    }
    store.ignore(ignored)
    store.skip(try #require(store.homebrewPackages.first { $0.token == "skipped" }))

    #expect(store.count(for: .allApps) == 1)
    #expect(store.count(for: .appStore) == 1)
    #expect(store.count(for: .homebrewPackages) == 1)
    // Full installers are not counted, matching the Updates total.
    #expect(store.count(for: .macOSUpdates) == 1)
    #expect(store.count(for: .history) == 0)
    #expect(store.count(for: .cveChecker) == 0)
    #expect(store.count(for: .updates) == store.totalUpdateCount)
    // Row visibility still follows inventory, including apps without updates.
    #expect(store.applicationSourceCounts()[.appStore] == 3)
}

@MainActor
@Test func menuBarPendingListMatchesTheUpdateCount() throws {
    let (store, _, cleanUp) = try usabilityStore()
    defer { cleanUp() }
    let app = storeApp("Widget")
    store.apps = [app]
    store.updates = [AvailableUpdate(app: app, availableVersion: "1.1", source: .homebrew,
                                     releaseNotes: nil, actionURL: nil, homebrewToken: "widget")]
    let cask = HomebrewPackage(
        token: "widget", displayName: "Widget", description: nil, homepage: nil, license: nil,
        installedVersion: "1.0", currentVersion: "1.1", kind: .cask, isOutdated: true,
        isDependency: false, dependencies: []
    )
    store.homebrewPackages = [cask, formula("tool"), formula("skipped")]
    store.skip(store.homebrewPackages[2])
    store.macOSUpdates = [MacOSUpdate(label: "full", title: "macOS Installer", version: "27.0", size: nil,
                                      requiresRestart: true, isBeta: false, isFullInstaller: true)]
    store.developerPackages = [DeveloperPackage(name: "manual", currentVersion: "1.0", latestVersion: "1.1",
        manager: .npm, executablePath: "/not-executed/npm", canUpdateAutomatically: false)]

    let pending = store.pendingUpdateSummaries
    #expect(pending.count == store.totalUpdateCount)
    #expect(pending.map(\.target) == [.application(app.id), .homebrew(store.homebrewPackages[1].id),
                                      .developer(store.developerPackages[0].id)])
    #expect(pending[0].versionText == "1.0 → 1.1")
    #expect(MenuBarController.buttonTitle(count: 0, showCount: true) == "")
    #expect(MenuBarController.buttonTitle(count: 3, showCount: true) == " 3")
    #expect(MenuBarController.buttonTitle(count: 3, showCount: false) == "")
}

@MainActor
@Test func pendingRevealSurvivesTheDestinationChangeThatClearsSelection() throws {
    let (store, _, cleanUp) = try usabilityStore()
    defer { cleanUp() }
    store.homebrewPackages = [formula("tool")]
    let id = store.homebrewPackages[0].id
    store.selection = .updates
    store.navigation.pendingUpdateReveal = .homebrew(id)
    // ContentView clears the inspector on a destination change, then completes.
    store.clearInspectorSelection()
    store.completePendingUpdateReveal()
    #expect(store.updateInspectorSelection == .homebrew(id))
    #expect(store.selectedPackageID == id)
    #expect(store.navigation.pendingUpdateReveal == nil)

    store.navigation.pendingUpdateReveal = .homebrew(id)
    store.clearInspectorSelection()
    store.selection = .history
    store.completePendingUpdateReveal()
    #expect(store.updateInspectorSelection == nil)
    #expect(store.navigation.pendingUpdateReveal == nil)
}

@Test func previousSessionCheckDateIsNotPresentedAsCurrentResults() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(UpdateCheckState.notChecked.title(lastChecked: date) == "Not checked this session")
    #expect(UpdateCheckState.notChecked.detail(lastChecked: date).contains("aren’t kept"))
    #expect(UpdateCheckState.notChecked.title(lastChecked: nil) == UpdateCheckState.notChecked.title)
    #expect(UpdateCheckState.complete.title(lastChecked: date) == UpdateCheckState.complete.title)
    let health = MenuBarHealth(count: 0, state: .notChecked, lastChecked: date)
    #expect(health.summary == "Not checked this session")
}

@Test func batchSummaryCountsItemsThatDidNotStart() {
    let app = storeApp("Example")
    let item = BatchUpdateItem.application(AvailableUpdate(
        app: app, availableVersion: "2.0", source: .appStore, releaseNotes: nil,
        actionURL: URL(string: "macappstore://apps.apple.com/app/id1"), homebrewToken: nil
    ))
    let summary = BatchUpdateSummary(results: [
        BatchUpdateResult(item: item, outcome: .updated, detail: "Updated"),
        BatchUpdateResult(item: item, outcome: .notStarted, detail: "Stopped")
    ])
    #expect(summary.updatedCount == 1)
    #expect(summary.notStartedCount == 1)
    #expect(summary.failedCount == 0)
}
