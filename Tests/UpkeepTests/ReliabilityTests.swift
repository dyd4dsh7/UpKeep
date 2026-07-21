import Foundation
import Testing
@testable import Upkeep

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
