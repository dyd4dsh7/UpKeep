import Foundation
import Testing
@testable import Upkeep

@Test func trustedMappingsCoverStatsAndUniGetUI() {
    #expect(AppDiscovery.trustedGitHubRepository(
        bundleIdentifier: "eu.exelban.Stats"
    ) == "exelban/stats")
    #expect(AppDiscovery.trustedGitHubRepository(
        bundleIdentifier: "io.github.marticliment.unigetui"
    ) == "Devolutions/UniGetUI")
}

@MainActor
@Test func customGitHubMappingsPersistByBundleIdentifier() throws {
    let suite = "AdditionalUpdaterCoverageTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)

    settings.setGitHubRepository("owner/project", for: "COM.Example.App")

    #expect(settings.githubRepository(for: "com.example.app") == "owner/project")
    #expect(AppSettings(defaults: defaults).githubRepository(
        for: "COM.EXAMPLE.APP"
    ) == "owner/project")
}

@Test func runtimeSparkleFeedDiscoveryReadsPublisherPreferences() throws {
    let bundleIdentifier = "com.example.sparkle.\(UUID().uuidString)"
    let defaults = UserDefaults.standard
    defaults.setPersistentDomain(
        ["SUFeedURL": "https://updates.example.com/appcast.xml"],
        forName: bundleIdentifier
    )
    defer { defaults.removePersistentDomain(forName: bundleIdentifier) }

    #expect(AppDiscovery.sparkleFeedURL(
        info: [:],
        bundleIdentifier: bundleIdentifier,
        defaults: defaults
    )?.absoluteString == "https://updates.example.com/appcast.xml")
}

@Test func safariIsClassifiedAsMacOSManaged() {
    #expect(AppDiscovery.updateManagement(
        bundleIdentifier: "com.apple.Safari",
        appPath: "/Applications/Safari.app",
        hasReceipt: false,
        receiptType: nil,
        hasEmbeddedProvisioningProfile: false,
        hasSetappFramework: false,
        microsoftRegisteredPaths: []
    ) == .macOS)
}

@Test func steamManifestReportsDownloadProgress() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Upkeep-Steam-Test-\(UUID().uuidString)", isDirectory: true)
    let steamApps = root.appendingPathComponent("Steam/steamapps", isDirectory: true)
    try FileManager.default.createDirectory(at: steamApps, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try """
    "AppState"
    {
        "appid" "123"
        "StateFlags" "4096"
        "BytesToDownload" "1000"
        "BytesDownloaded" "250"
    }
    """.write(
        to: steamApps.appendingPathComponent("appmanifest_123.acf"),
        atomically: true,
        encoding: .utf8
    )

    let status = try #require(AppDiscovery.steamUpdateStatus(
        appID: "123",
        applicationSupportURL: root
    ))
    #expect(status.state == .downloading)
    #expect(status.progress == 0.25)
}

@Test func githubRepositoryInputIsNormalizedAndConstrained() {
    #expect(GitHubClient.normalizedRepository(
        "https://github.com/Devolutions/UniGetUI.git"
    ) == "Devolutions/UniGetUI")
    #expect(GitHubClient.normalizedRepository("three/part/repository") == nil)
    #expect(GitHubClient.normalizedRepository("owner/project?tab=readme") == nil)
}

@Test func githubAtomFallbackParsesReleaseTagsAndNotes() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <entry>
        <link rel="alternate" type="text/html" href="https://github.com/owner/project/releases/tag/v2.0.0"/>
        <title>v2.0.0</title>
        <content type="html">&lt;p&gt;Important fixes&lt;/p&gt;</content>
      </entry>
    </feed>
    """
    let entries = try GitHubAtomClient.entries(
        data: try #require(xml.data(using: .utf8))
    )

    #expect(entries.first?.tagName == "v2.0.0")
    #expect(entries.first?.content == "Important fixes")
}

@Test func homebrewCatalogMatchesDeclaredApplicationArtifacts() {
    let app = InstalledApp(
        name: "Publisher Product",
        bundleIdentifier: "com.example.publisher-product",
        installedVersion: "1.0",
        buildVersion: nil,
        url: URL(fileURLWithPath: "/Applications/Publisher Product.app"),
        sparkleFeedURL: nil,
        githubRepository: nil,
        hasAppStoreReceipt: false
    )
    let cask = CatalogCask(
        token: "unexpected-token",
        name: ["Unrelated Marketing Name"],
        version: "2.0",
        artifactAppNames: ["Publisher Product.app"]
    )

    let match = HomebrewClient.adoptableApps(
        from: [app],
        catalog: [cask],
        excluding: []
    )

    #expect(match.first?.caskToken == "unexpected-token")
}

@Test func builtInUpdaterAppsRemainExplicitlyAdoptableButAutoUpdatingCasksDoNot() {
    let app = InstalledApp(
        name: "Built In Updater",
        bundleIdentifier: "com.example.builtin",
        installedVersion: "1.0",
        buildVersion: nil,
        url: URL(fileURLWithPath: "/Applications/Built In Updater.app"),
        sparkleFeedURL: nil,
        githubRepository: nil,
        hasAppStoreReceipt: false,
        hasBuiltInUpdater: true
    )
    let eligible = CatalogCask(
        token: "built-in-updater",
        name: ["Built In Updater"],
        version: "2.0"
    )
    let selfUpdating = CatalogCask(
        token: "built-in-updater",
        name: ["Built In Updater"],
        version: "2.0",
        autoUpdates: true
    )

    #expect(HomebrewClient.adoptableApps(
        from: [app],
        catalog: [eligible],
        excluding: []
    ).count == 1)
    #expect(HomebrewClient.adoptableApps(
        from: [app],
        catalog: [selfUpdating],
        excluding: []
    ).isEmpty)
}
