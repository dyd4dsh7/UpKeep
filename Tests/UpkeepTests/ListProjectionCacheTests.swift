import Foundation
import Testing
@testable import Upkeep

@Test func listProjectionCacheReusesOnlyLatestKeyAndRefusesExpiredEntries() {
    var cache = ListProjectionCache<Int, String>()
    let now = Date(timeIntervalSince1970: 100)
    var builds = 0
    func build() -> [Int] { builds += 1; return [builds] }
    #expect(cache.values(for: "one", expiresAt: now.addingTimeInterval(1), now: now, build: build) == [1])
    #expect(cache.values(for: "one", now: now, build: build) == [1])
    #expect(builds == 1)
    #expect(cache.values(for: "one", now: now.addingTimeInterval(2), build: build) == [2])
    #expect(cache.values(for: "two", now: now, build: build) == [3])
    #expect(cache.values(for: "one", now: now, build: build) == [4])
}

@MainActor
@Test func developerListProjectionTracksQueryPolicyManagerAndInventory() {
    let suite = "ListProjection.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.showCurrentDeveloperPackages = false
    let store = UpkeepStore(settings: settings)
    let outdated = DeveloperPackage(name: "old", currentVersion: "1", latestVersion: "2", manager: .npm, executablePath: "/fixture/npm")
    let current = DeveloperPackage(name: "current", currentVersion: "1", latestVersion: "1", manager: .npm, executablePath: "/fixture/npm")
    store.developerPackages = [outdated, current]
    #expect(store.filteredDeveloperPackages.map(\.name) == ["old"])
    #expect(store.filteredDeveloperPackages.map(\.name) == ["old"])
    settings.showCurrentDeveloperPackages = true
    #expect(store.filteredDeveloperPackages.count == 2)
    store.developerManagerFilter = .manager(.pipx)
    #expect(store.filteredDeveloperPackages.isEmpty)
    store.developerManagerFilter = .all
    store.searchText = "CURRENT"
    #expect(store.filteredDeveloperPackages.map(\.name) == ["current"])
    store.developerPackages = [outdated]
    #expect(store.filteredDeveloperPackages.isEmpty)
    store.searchText = "old"
    #expect(store.filteredDeveloperPackages.count == 1)
}

@MainActor
@Test func homebrewListProjectionTracksAppMappingExclusionsAndPackageInventory() {
    let suite = "HomebrewProjection.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    let store = UpkeepStore(settings: settings)
    let package = HomebrewPackage(token: "fixture", displayName: "Fixture", description: nil,
        homepage: nil, license: nil, installedVersion: "1", currentVersion: "2", kind: .cask,
        isOutdated: true, isDependency: false, dependencies: [])
    store.homebrewPackages = [package]
    store.homebrewFilter = .unmapped
    #expect(store.filteredHomebrewPackages.count == 1)
    #expect(store.filteredHomebrewPackages.count == 1)
    store.apps = [InstalledApp(name: "Fixture", bundleIdentifier: "test.mapping-cache",
        installedVersion: "1", buildVersion: nil, url: URL(fileURLWithPath: "/fixture.app"),
        sparkleFeedURL: nil, githubRepository: nil, hasAppStoreReceipt: false)]
    #expect(store.filteredHomebrewPackages.isEmpty)
    store.homebrewFilter = .updates
    #expect(store.filteredHomebrewPackages.count == 1)
    settings.ignore(key: "homebrew|\(package.id)", name: package.displayName, category: "Package", duration: nil)
    #expect(store.filteredHomebrewPackages.isEmpty)
    settings.restoreAllExclusions()
    #expect(store.filteredHomebrewPackages.count == 1)
    store.homebrewPackages = []
    #expect(store.filteredHomebrewPackages.isEmpty)
}
