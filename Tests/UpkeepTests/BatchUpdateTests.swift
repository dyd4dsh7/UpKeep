import Foundation
import Testing
@testable import Upkeep

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
