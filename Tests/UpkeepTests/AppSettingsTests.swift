import Foundation
import Testing
@testable import Upkeep

@MainActor
@Test func listDensityPersistsAcrossSettingsInstances() throws {
    let suiteName = "UpkeepTests.ListDensity.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.removePersistentDomain(forName: suiteName)

    let settings = AppSettings(defaults: defaults)
    #expect(settings.listDensity == .comfortable)

    settings.listDensity = .compact
    let restored = AppSettings(defaults: defaults)
    #expect(restored.listDensity == .compact)
}

@MainActor
@Test func completedScanDatePersistsAcrossSettingsInstances() throws {
    let suiteName = "UpkeepTests.LastScan.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.removePersistentDomain(forName: suiteName)

    let date = Date(timeIntervalSince1970: 1_753_132_800)
    let settings = AppSettings(defaults: defaults)
    settings.lastCompletedScanDate = date

    let restored = AppSettings(defaults: defaults)
    #expect(restored.lastCompletedScanDate == date)

    let store = UpkeepStore(settings: restored)
    #expect(store.lastChecked == date)
}
