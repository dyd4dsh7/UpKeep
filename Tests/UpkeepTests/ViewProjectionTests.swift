import AppKit
import Foundation
import Testing
@testable import Upkeep

@MainActor
@Test func iconCacheReloadsWhenBundleChanges() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("IconCache.\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var loads = 0
    let cache = AppIconCache(loader: { _ in loads += 1; return NSImage(size: NSSize(width: 32, height: 32)) })
    let first = AppIconIdentity(url: root)
    let image = cache.image(for: first)
    #expect(cache.image(for: first) === image)
    #expect(loads == 1)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: root.path)
    #expect(cache.image(for: AppIconIdentity(url: root)) !== image)
    #expect(loads == 2)
}

@MainActor
@Test func cachedSearchTracksInventoryQueryAndSourceChanges() {
    let suite = "SearchProjection.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = UpkeepStore(settings: AppSettings(defaults: defaults))
    let app = InstalledApp(name: "Example", bundleIdentifier: "test.search", installedVersion: "1.0",
        buildVersion: nil, url: URL(fileURLWithPath: "/not-real/Example.app"), sparkleFeedURL: nil,
        githubRepository: nil, hasAppStoreReceipt: false)
    store.searchText = "github"
    store.apps = [app]
    #expect(store.globalSearchResults.isEmpty)
    store.updates = [AvailableUpdate(app: app, availableVersion: "2.0", source: .github,
        releaseNotes: nil, actionURL: nil, homebrewToken: nil)]
    #expect(store.globalSearchResults.apps.map(\.id) == [app.id])
    store.searchText = "missing"
    #expect(store.globalSearchResults.isEmpty)
    store.searchText = "example"
    #expect(store.globalSearchResults.apps.count == 1)
    store.apps = []
    #expect(store.globalSearchResults.apps.isEmpty)
}
