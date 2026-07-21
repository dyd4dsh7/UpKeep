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
