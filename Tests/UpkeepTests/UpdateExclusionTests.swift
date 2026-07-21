import Foundation
import Testing
@testable import Upkeep

@MainActor
@Test func skippedVersionReturnsWhenANewerVersionAppears() throws {
    let (settings, defaults, suiteName) = try makeSettings()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    settings.skip(key: "homebrew|Cask:example", name: "Example", category: "Homebrew", version: "2.0")

    #expect(settings.isExcluded(key: "homebrew|Cask:example", version: "2.0"))
    #expect(!settings.isExcluded(key: "homebrew|Cask:example", version: "2.1"))

    let restored = AppSettings(defaults: defaults)
    #expect(restored.isExcluded(key: "homebrew|Cask:example", version: "2.0"))
    #expect(!restored.isExcluded(key: "homebrew|Cask:example", version: "2.1"))
}

@MainActor
@Test func ignoredItemSuppressesEveryFutureVersionUntilRestored() throws {
    let (settings, defaults, suiteName) = try makeSettings()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    settings.ignore(key: "developer|npm:example", name: "example", category: "npm")

    #expect(settings.isExcluded(key: "developer|npm:example", version: "2.0"))
    #expect(settings.isExcluded(key: "developer|npm:example", version: "99.0"))

    settings.restoreAllExclusions()
    #expect(!settings.isExcluded(key: "developer|npm:example", version: "99.0"))
}

@MainActor
@Test func temporarySkipExpiresAndRemainsVersionSpecific() throws {
    let (settings, defaults, suiteName) = try makeSettings()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let key = "homebrew|Cask:temporary"

    settings.skip(
        key: key, name: "Temporary", category: "Homebrew", version: "2.0",
        duration: .oneDay
    )
    #expect(settings.isExcluded(key: key, version: "2.0"))
    #expect(!settings.isExcluded(key: key, version: "2.1"))
    #expect(settings.updateExclusions.first?.expiresAt != nil)

    settings.skip(
        key: key, name: "Temporary", category: "Homebrew", version: "2.0",
        duration: .oneDay, now: Date().addingTimeInterval(-172_800)
    )
    #expect(!settings.isExcluded(key: key, version: "2.0"))
    #expect(settings.updateExclusions.isEmpty)
}

@MainActor
@Test func temporaryIgnoreSuppressesNewVersionsUntilExpiry() throws {
    let (settings, defaults, suiteName) = try makeSettings()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let key = "developer|npm:temporary"

    settings.ignore(key: key, name: "temporary", category: "npm", duration: .oneWeek)

    #expect(settings.isExcluded(key: key, version: "1.0"))
    #expect(settings.isExcluded(key: key, version: "9.0"))
    #expect(settings.updateExclusions.first?.isTemporary == true)
}

@Test func exclusionDurationsUseCalendarBoundaries() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 12)))

    let month = UpdateExclusionDuration.oneMonth.expirationDate(from: start, calendar: calendar)
    let components = calendar.dateComponents([.year, .month, .day, .hour], from: month)
    #expect(components.year == 2026)
    #expect(components.month == 2)
    #expect(components.day == 28)
    #expect(components.hour == 12)

    let threeMonths = UpdateExclusionDuration.threeMonths.expirationDate(from: start, calendar: calendar)
    let threeMonthComponents = calendar.dateComponents([.year, .month, .day, .hour], from: threeMonths)
    #expect(threeMonthComponents.year == 2026)
    #expect(threeMonthComponents.month == 4)
    #expect(threeMonthComponents.day == 30)
    #expect(threeMonthComponents.hour == 12)

    let sixMonths = UpdateExclusionDuration.sixMonths.expirationDate(from: start, calendar: calendar)
    let sixMonthComponents = calendar.dateComponents([.year, .month, .day, .hour], from: sixMonths)
    #expect(sixMonthComponents.year == 2026)
    #expect(sixMonthComponents.month == 7)
    #expect(sixMonthComponents.day == 31)
    #expect(sixMonthComponents.hour == 12)
}

@Test func exclusionDurationMenuContainsEveryRequestedPreset() {
    #expect(UpdateExclusionDuration.allCases.map(\.title) == [
        "1 Day", "2 Days", "3 Days", "4 Days", "5 Days", "6 Days",
        "1 Week", "1 Month", "3 Months", "6 Months"
    ])
}

@MainActor
@Test func appExclusionIdentitySurvivesApplicationMoves() {
    let first = installedApp(at: "/Applications/Example.app", bundleIdentifier: "com.example.app")
    let moved = installedApp(at: "/Users/test/Applications/Example.app", bundleIdentifier: "com.example.app")

    #expect(first.id != moved.id)
    #expect(first.updateExclusionKey == moved.updateExclusionKey)
}

@MainActor
@Test func legacyAppExclusionsAreMigrated() throws {
    let (settings, defaults, suiteName) = try makeSettings()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let app = installedApp(at: "/Applications/Example.app", bundleIdentifier: "com.example.app")
    let legacyKey = "app|\(app.id)"

    settings.ignore(key: legacyKey, name: app.name, category: "App")
    settings.migrateExclusion(from: legacyKey, to: app.updateExclusionKey)

    #expect(settings.updateExclusions.count == 1)
    #expect(settings.isExcluded(key: app.updateExclusionKey, version: "3.0"))
    #expect(!settings.isExcluded(key: legacyKey, version: "3.0"))
}

@MainActor
private func makeSettings() throws -> (AppSettings, UserDefaults, String) {
    let suiteName = "UpkeepTests.UpdateExclusions.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return (AppSettings(defaults: defaults), defaults, suiteName)
}

private func installedApp(at path: String, bundleIdentifier: String?) -> InstalledApp {
    InstalledApp(
        name: "Example",
        bundleIdentifier: bundleIdentifier,
        installedVersion: "1.0",
        buildVersion: "1",
        url: URL(fileURLWithPath: path),
        sparkleFeedURL: nil,
        githubRepository: nil,
        hasAppStoreReceipt: false
    )
}
