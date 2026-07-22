import Foundation
import Testing
@testable import Upkeep

@Test func appPermissionInspectionCombinesPrivacyKeysAndEntitlementsWithoutDuplicates() {
    let permissions = AppSecurityInspector.declaredPermissions(
        info: [
            "NSCameraUsageDescription": "Camera access",
            "NSPhotoLibraryUsageDescription": "Photo access"
        ],
        entitlements: [
            "com.apple.security.device.camera": true,
            "com.apple.security.files.user-selected.read-write": true
        ]
    )

    #expect(permissions.map(\.title) == ["Camera", "Photos", "User Selected Files"])
}

@MainActor
@Test func perItemLastCheckedDatesPersistAcrossSettingsInstances() {
    let suiteName = "UpkeepTests.ItemLastChecked.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let checkedAt = Date(timeIntervalSince1970: 1_725_000_000)

    AppSettings(defaults: defaults).recordChecks(
        for: ["app|bundle|com.example.app", "homebrew|Formula:ripgrep"],
        at: checkedAt
    )
    let restored = AppSettings(defaults: defaults)

    #expect(restored.lastChecked(for: "app|bundle|com.example.app") == checkedAt)
    #expect(restored.lastChecked(for: "homebrew|Formula:ripgrep") == checkedAt)
}

@Test func networkErrorsHaveActionableMessages() {
    #expect(UpdateSourceError(URLError(.notConnectedToInternet)).errorDescription == "No network connection.")
    #expect(UpdateSourceError(URLError(.timedOut)).errorDescription == "The request timed out.")
    #expect(UpdateSourceError(URLError(.cannotFindHost)).errorDescription == "The update server could not be reached.")
}

@Test func homebrewRetriesOnlyLockContention() {
    #expect(HomebrewClient.BrewError.isConcurrentCommandFailure("Another active Homebrew update process is already in progress"))
    #expect(HomebrewClient.BrewError.isConcurrentCommandFailure("Could not acquire a lock on /opt/homebrew"))
    #expect(!HomebrewClient.BrewError.isConcurrentCommandFailure("No available formula with the name foo"))
}

@Test func warningSummariesStayCompact() {
    let warning = ScanWarning(
        source: .sparkle,
        itemNames: ["Zed", "Arc", "Example", "Arc"],
        message: "The request timed out."
    )

    #expect(warning.itemNames == ["Arc", "Example", "Zed"])
    #expect(warning.title == "Sparkle · 3 items")
    #expect(warning.detail == "The request timed out. Affected: Arc, Example, Zed.")
}

@Test func warningMessagesAreBounded() {
    let warning = ScanWarning(source: .github, message: String(repeating: "x", count: 1_000))
    #expect(warning.message.count == 601)
    #expect(warning.message.hasSuffix("…"))
}

@Test func externallyManagedAppsRejectHomebrewCandidates() {
    for management in [AppUpdateManagement.testFlight, .setapp, .microsoftAutoUpdate] {
        let app = InstalledApp(
            name: "Managed App",
            bundleIdentifier: "com.example.managed",
            installedVersion: "1.0",
            buildVersion: nil,
            url: URL(fileURLWithPath: "/Applications/Managed App.app"),
            sparkleFeedURL: nil,
            githubRepository: nil,
            hasAppStoreReceipt: management == .testFlight,
            updateManagement: management
        )
        #expect(!UpdateScanner.allowsHomebrewCandidate(for: app))
    }
}

@Test func directAppsAllowHomebrewCandidates() {
    let app = InstalledApp(
        name: "Direct App",
        bundleIdentifier: "com.example.direct",
        installedVersion: "1.0",
        buildVersion: nil,
        url: URL(fileURLWithPath: "/Applications/Direct App.app"),
        sparkleFeedURL: nil,
        githubRepository: nil,
        hasAppStoreReceipt: false
    )
    #expect(UpdateScanner.allowsHomebrewCandidate(for: app))
}

@MainActor
@Test func homebrewAdoptionIgnoreIsPersistedSeparately() {
    let suiteName = "UpkeepTests.HomebrewAdoptionIgnore.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let first = AppSettings(defaults: defaults)
    first.setHomebrewAdoptionIgnored(true, key: "app:com.example.direct")

    let restored = AppSettings(defaults: defaults)
    #expect(restored.isHomebrewAdoptionIgnored(key: "app:com.example.direct"))
    #expect(restored.updateExclusions.isEmpty)

    restored.setHomebrewAdoptionIgnored(false, key: "app:com.example.direct")
    #expect(!AppSettings(defaults: defaults).isHomebrewAdoptionIgnored(key: "app:com.example.direct"))
}

@MainActor
@Test func ignoringHomebrewAdoptionKeepsOtherUpdateSources() {
    let suiteName = "UpkeepTests.HomebrewAdoptionCandidate.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let app = InstalledApp(
        name: "Direct App",
        bundleIdentifier: "com.example.direct",
        installedVersion: "1.0",
        buildVersion: nil,
        url: URL(fileURLWithPath: "/Applications/Direct App.app"),
        sparkleFeedURL: nil,
        githubRepository: "example/direct",
        hasAppStoreReceipt: false
    )
    let store = UpkeepStore(settings: AppSettings(defaults: defaults))
    store.updates = [AvailableUpdate(app: app, candidates: [
        UpdateCandidate(
            availableVersion: "1.1", source: .github, releaseNotes: nil,
            actionURL: URL(string: "https://github.com/example/direct/releases/tag/1.1"),
            homebrewToken: nil, sourcePrereleaseChannel: nil, requiresHomebrewAdoption: false
        ),
        UpdateCandidate(
            availableVersion: "1.2", source: .homebrew, releaseNotes: nil,
            actionURL: nil, homebrewToken: "direct-app", sourcePrereleaseChannel: nil,
            requiresHomebrewAdoption: true
        )
    ])]

    store.ignoreHomebrewAdoption(app)

    #expect(store.updates.first?.candidates.map(\.source) == [.github])
    #expect(!store.isExcluded(store.updates[0]))
}
