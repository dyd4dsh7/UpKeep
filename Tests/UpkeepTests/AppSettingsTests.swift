import Foundation
import Testing
@testable import Upkeep

@MainActor
@Test func freshSetupDefaultsToFocusedApplicationManagement() {
    let suiteName = "AppSettingsSetupTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)
    #expect(!settings.hasCompletedSetup)
    #expect(settings.enabledDeveloperManagers.isEmpty)
    #expect(settings.sidebarViewMode == .basic)

    settings.completeSetup(.applications, sidebarViewMode: .advanced)
    #expect(settings.hasCompletedSetup)
    #expect(settings.sidebarViewMode == .advanced)
    #expect(!settings.checkHomebrew)
    #expect(!settings.checkLocalModels)
    #expect(settings.enabledDeveloperManagers.isEmpty)
}

@MainActor
@Test func sidebarViewModePersistsAcrossSettingsInstances() throws {
    let suiteName = "UpkeepTests.SidebarViewMode.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.removePersistentDomain(forName: suiteName)

    let settings = AppSettings(defaults: defaults)
    #expect(settings.sidebarViewMode == .basic)

    settings.sidebarViewMode = .advanced
    let restored = AppSettings(defaults: defaults)
    #expect(restored.sidebarViewMode == .advanced)
}

@MainActor
@Test func basicModeScansOnlyBasicSources() throws {
    let suiteName = "UpkeepTests.BasicScanSettings.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.removePersistentDomain(forName: suiteName)

    let settings = AppSettings(defaults: defaults)
    settings.completeSetup(.advanced, sidebarViewMode: .advanced)
    settings.includePrereleaseUpdates = true
    settings.sidebarViewMode = .basic

    let basic = settings.scanSettings
    #expect(basic.checkAppStore)
    #expect(basic.checkSparkle)
    #expect(basic.checkHomebrew)
    #expect(basic.checkGitHub)
    #expect(basic.checkMacOS)
    #expect(!basic.checkLocalModels)
    #expect(!basic.includePrereleaseUpdates)
    #expect(basic.enabledDeveloperManagers.isEmpty)
    #expect(!basic.includeAdvancedSources)

    settings.sidebarViewMode = .advanced
    let advanced = settings.scanSettings
    #expect(advanced.checkLocalModels)
    #expect(advanced.includePrereleaseUpdates)
    #expect(advanced.enabledDeveloperManagers == Set(DeveloperPackageManager.allCases))
    #expect(advanced.includeAdvancedSources)
}

@Test func advancedOnlySettingsSectionsAreClassified() {
    #expect(SettingsSection.developer.requiresAdvancedView)
    #expect(SettingsSection.diagnostics.requiresAdvancedView)
    #expect(!SettingsSection.general.requiresAdvancedView)
    #expect(!SettingsSection.sources.requiresAdvancedView)
}

@Test func dependencyFilterIsAdvancedOnly() {
    #expect(HomebrewFilter.dependencies.requiresAdvancedView)
    #expect(!HomebrewFilter.all.requiresAdvancedView)
    #expect(!HomebrewFilter.updates.requiresAdvancedView)
}

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
