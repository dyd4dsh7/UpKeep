import Foundation
import Observation
import Testing
@testable import Upkeep

@MainActor
@Test func cachedPrimaryCountTracksInventoryExclusionsAndSkippedTargetVersion() {
    let suite = "PrimaryCount.\(UUID())"
    let defaults = UserDefaults(testSuiteName: suite)!
    defer { defaults.removeTestDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    let store = UpkeepStore(settings: settings)
    let app = InstalledApp(name: "Fixture", bundleIdentifier: "test.count", installedVersion: "1",
        buildVersion: nil, url: URL(fileURLWithPath: "/not-executed/count.app"),
        sparkleFeedURL: nil, githubRepository: nil, hasAppStoreReceipt: false)
    func update(_ version: String) -> AvailableUpdate {
        AvailableUpdate(app: app, availableVersion: version, source: .github,
            releaseNotes: nil, actionURL: nil, homebrewToken: nil)
    }
    store.updates = [update("2")]
    #expect(store.totalUpdateCount == 1)
    #expect(store.totalUpdateCount == 1)
    settings.skip(key: app.updateExclusionKey, name: app.name, category: "App", version: "2", duration: nil)
    #expect(store.totalUpdateCount == 0)
    store.updates = [update("3")]
    #expect(store.totalUpdateCount == 1)
    settings.ignore(key: app.updateExclusionKey, name: app.name, category: "App", duration: nil)
    #expect(store.totalUpdateCount == 0)
    settings.restoreAllExclusions()
    #expect(store.totalUpdateCount == 1)
    store.updates = []
    #expect(store.totalUpdateCount == 0)
}
