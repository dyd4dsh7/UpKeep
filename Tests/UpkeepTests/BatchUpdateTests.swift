import Foundation
import Testing
@testable import Upkeep

@MainActor
@Test func focusedCountMatchesPlanAcrossExclusionsAndCollectionChanges() throws {
    let suite = "UpkeepTests.FocusedCount.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    let store = UpkeepStore(settings: settings)
    let app = InstalledApp(
        name: "Widget", bundleIdentifier: "test.widget", installedVersion: "1.0",
        buildVersion: nil, url: URL(fileURLWithPath: "/Applications/Widget.app"),
        sparkleFeedURL: nil, githubRepository: nil, hasAppStoreReceipt: false
    )
    store.updates = [AvailableUpdate(
        app: app, availableVersion: "1.1", source: .homebrew,
        releaseNotes: nil, actionURL: nil, homebrewToken: "widget"
    )]
    store.homebrewPackages = ["widget", "requested", "dependency"].map { token in
        HomebrewPackage(
            token: token, displayName: token, description: nil, homepage: nil, license: nil,
            installedVersion: "1.0", currentVersion: "1.1",
            kind: token == "widget" ? .cask : .formula, isOutdated: true,
            isDependency: token == "dependency", dependencies: []
        )
    }
    store.macOSUpdates = [false, true].map { installer in
        MacOSUpdate(
            label: "macOS-\(installer)", title: "macOS", version: "27.0", size: nil,
            requiresRestart: true, isBeta: false, isFullInstaller: installer
        )
    }
    store.developerPackages = [DeveloperPackage(
        name: "tool", currentVersion: "1.0", latestVersion: "1.1",
        manager: .npm, executablePath: "/usr/local/bin/npm"
    )]
    store.localModels = [LocalLLMModel(
        id: "ollama:widget", name: "Widget", variant: nil, runtime: .ollama,
        installedRevision: "old", latestRevision: "new", sizeBytes: nil,
        modifiedAt: nil, homepage: nil, executablePath: nil,
        updateReference: "widget:latest", isOutdated: true
    )]
    #expect(store.totalUpdateCount == 6)
    #expect(store.totalUpdateCount == store.updatePlan.primaryUpdateCount)
    #expect(store.availableBatchUpdateItems.count == 5)
    settings.ignore(key: app.updateExclusionKey, name: app.name, category: "App")
    // The cask becomes unrepresented when its app update is excluded.
    #expect(store.totalUpdateCount == 6)
    #expect(store.totalUpdateCount == store.updatePlan.primaryUpdateCount)
    store.homebrewPackages = []
    #expect(store.totalUpdateCount == 3)
    settings.restoreAllExclusions()
    #expect(store.totalUpdateCount == 4)
    store.macOSUpdates = []
    #expect(store.totalUpdateCount == 3)
    #expect(store.totalUpdateCount == store.updatePlan.primaryUpdateCount)

    // Refreshing just these inventories must invalidate the sidebar/dock count.
    store.developerPackages = []
    #expect(store.totalUpdateCount == 2)
    let model = store.localModels[0]
    store.ignore(model)
    #expect(store.totalUpdateCount == 1)
    settings.restoreAllExclusions()
    #expect(store.totalUpdateCount == 2)
    store.localModels = []
    #expect(store.totalUpdateCount == 1)

    // A manual developer update is visible even though batch install cannot run it.
    store.developerPackages = [DeveloperPackage(
        name: "manual-tool", currentVersion: "1.0", latestVersion: "1.1",
        manager: .npm, executablePath: "/not-executed/npm",
        canUpdateAutomatically: false
    )]
    #expect(store.totalUpdateCount == 2)
    #expect(store.availableBatchUpdateItems.count == 1)
    let package = store.developerPackages[0]
    store.ignore(package)
    #expect(store.totalUpdateCount == 1)
}

@MainActor
@Test func batchReviewDeduplicatesHomebrewCasksRepresentedByAnAppUpdate() {
    let suiteName = "BatchUpdateTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = UpkeepStore(settings: AppSettings(defaults: defaults))
    let app = InstalledApp(
        name: "Example",
        bundleIdentifier: "com.example.app",
        installedVersion: "1.0",
        buildVersion: nil,
        url: URL(fileURLWithPath: "/Applications/Example.app"),
        sparkleFeedURL: nil,
        githubRepository: nil,
        hasAppStoreReceipt: true
    )
    store.updates = [AvailableUpdate(app: app, candidates: [
        UpdateCandidate(
            availableVersion: "2.0", source: .appStore, releaseNotes: nil,
            actionURL: URL(string: "macappstore://apps.apple.com/app/id1"), homebrewToken: nil,
            sourcePrereleaseChannel: nil, requiresHomebrewAdoption: false
        ),
        UpdateCandidate(
            availableVersion: "2.0", source: .homebrew, releaseNotes: nil,
            actionURL: nil, homebrewToken: "example",
            sourcePrereleaseChannel: nil, requiresHomebrewAdoption: false
        )
    ])]
    store.homebrewPackages = [HomebrewPackage(
        token: "example", displayName: "Example", description: nil,
        homepage: nil, license: nil, installedVersion: "1.0", currentVersion: "2.0",
        kind: .cask, isOutdated: true, isDependency: false, dependencies: []
    )]

    #expect(store.availableBatchUpdateItems.count == 1)
    guard case let .application(update) = store.availableBatchUpdateItems[0] else {
        Issue.record("Expected the application update to represent the Homebrew cask")
        return
    }
    #expect(update.app.id == app.id)
}

@Test func batchSummarySeparatesUpdatedOpenedAndFailedResults() {
    let app = InstalledApp(
        name: "Example", bundleIdentifier: "com.example.app", installedVersion: "1.0",
        buildVersion: nil, url: URL(fileURLWithPath: "/Applications/Example.app"),
        sparkleFeedURL: nil, githubRepository: nil, hasAppStoreReceipt: true
    )
    let item = BatchUpdateItem.application(AvailableUpdate(
        app: app, availableVersion: "2.0", source: .appStore, releaseNotes: nil,
        actionURL: URL(string: "macappstore://apps.apple.com/app/id1"), homebrewToken: nil
    ))
    let summary = BatchUpdateSummary(results: [
        BatchUpdateResult(item: item, outcome: .updated, detail: "Updated"),
        BatchUpdateResult(item: item, outcome: .opened, detail: "Opened"),
        BatchUpdateResult(item: item, outcome: .failed, detail: "Failed")
    ])

    #expect(summary.updatedCount == 1)
    #expect(summary.openedCount == 1)
    #expect(summary.failedCount == 1)
}

@Test func batchPlanSelectsOnlyStableDirectUpdatesByDefault() {
    let app = InstalledApp(
        name: "Example", bundleIdentifier: "com.example.app", installedVersion: "1.0.0",
        buildVersion: nil, url: URL(fileURLWithPath: "/Applications/Example.app"),
        sparkleFeedURL: nil, githubRepository: nil, hasAppStoreReceipt: false
    )
    let automatic = BatchUpdateItem.application(AvailableUpdate(
        app: app, availableVersion: "1.1.0", source: .homebrew,
        releaseNotes: nil, actionURL: nil, homebrewToken: "example"
    ))
    let manual = BatchUpdateItem.application(AvailableUpdate(
        app: app, availableVersion: "1.1.0", source: .github,
        releaseNotes: nil, actionURL: URL(string: "https://example.com/release"), homebrewToken: nil
    ))
    let major = BatchUpdateItem.application(AvailableUpdate(
        app: app, availableVersion: "2.0.0", source: .homebrew,
        releaseNotes: nil, actionURL: nil, homebrewToken: "example"
    ))
    let prerelease = BatchUpdateItem.application(AvailableUpdate(
        app: app, availableVersion: "1.1.0-beta.1", source: .homebrew,
        releaseNotes: nil, actionURL: nil, homebrewToken: "example"
    ))

    #expect(automatic.riskGroup == .automatic)
    #expect(automatic.isRecommendedByDefault)
    #expect(manual.riskGroup == .manual)
    #expect(major.riskGroup == .major)
    #expect(prerelease.riskGroup == .prerelease)
    #expect(!manual.isRecommendedByDefault)
    #expect(!major.isRecommendedByDefault)
    #expect(!prerelease.isRecommendedByDefault)
}
