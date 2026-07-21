import Foundation
import Testing
@testable import Upkeep

private let app = InstalledApp(
    name: "Example",
    bundleIdentifier: "com.example.app",
    installedVersion: "1.0",
    buildVersion: "100",
    url: URL(fileURLWithPath: "/Applications/Example.app"),
    sparkleFeedURL: URL(string: "https://example.com/appcast.xml"),
    githubRepository: "example/app",
    hasAppStoreReceipt: false
)

private func update(
    _ source: UpdateSource,
    version: String,
    requiresHomebrewAdoption: Bool = false
) -> AvailableUpdate {
    AvailableUpdate(
        app: app,
        availableVersion: version,
        source: source,
        releaseNotes: nil,
        actionURL: nil,
        homebrewToken: source == .homebrew ? "example" : nil,
        requiresHomebrewAdoption: requiresHomebrewAdoption
    )
}

@Test func mergesEveryUpdateSourceAndUsesExplicitPreference() {
    let merged = AvailableUpdate.merging([
        update(.github, version: "4.0"),
        update(.sparkle, version: "3.0"),
        update(.homebrew, version: "2.0")
    ])

    #expect(merged?.source == .homebrew)
    #expect(merged?.candidates.map(\.source) == [.homebrew, .sparkle, .github])
}

@Test func appStoreIsPreferredAndHomebrewAdoptionIsLast() {
    let merged = AvailableUpdate.merging([
        update(.homebrew, version: "5.0", requiresHomebrewAdoption: true),
        update(.github, version: "4.0"),
        update(.appStore, version: "2.0")
    ])

    #expect(merged?.source == .appStore)
    #expect(merged?.candidates.map(\.source) == [.appStore, .github, .homebrew])
    #expect(merged?.candidates.last?.requiresHomebrewAdoption == true)
}

@Test func duplicateSourcesKeepNewestCandidate() {
    let merged = AvailableUpdate.merging([
        update(.github, version: "2.0"),
        update(.github, version: "2.1")
    ])

    #expect(merged?.candidates.count == 1)
    #expect(merged?.availableVersion == "2.1")
}
