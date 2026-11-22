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
    let defaults = try #require(UserDefaults(testSuiteName: suite))
    defer { defaults.removeTestDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)

    settings.setGitHubRepository("owner/project", for: "COM.Example.App")

    #expect(settings.githubRepository(for: "com.example.app") == "owner/project")
    #expect(AppSettings(defaults: defaults).githubRepository(
        for: "COM.EXAMPLE.APP"
    ) == "owner/project")
}

@Test func runtimeSparkleFeedDiscoveryReadsPublisherPreferences() throws {
    let bundleIdentifier = TestDefaults.domain("com.example.sparkle.\(UUID().uuidString)")
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

@Test func runtimeSparkleFeedDiscoveryRejectsPlainHTTPFeeds() {
    #expect(AppDiscovery.sparkleFeedURL(
        info: ["SUFeedURL": "http://127.0.0.1/appcast.xml"],
        bundleIdentifier: nil,
        defaults: .standard
    ) == nil)
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

@Test func trustedMappingsCoverVerifiedGitHubReleaseApps() {
    #expect(AppDiscovery.trustedGitHubRepository(bundleIdentifier: "com.utmapp.UTM") == "utmapp/UTM")
    #expect(AppDiscovery.trustedGitHubRepository(bundleIdentifier: "com.puremac.app") == "momenbasel/PureMac")
    #expect(AppDiscovery.trustedGitHubRepository(
        bundleIdentifier: "dev.ahmed.blitztree"
    ) == "ahmedkhaleel2004/blitztree")
    #expect(AppDiscovery.trustedGitHubRepository(
        bundleIdentifier: "rocks.spotifast.Spotifast"
    ) == "crmne/spotifast")
}

@Test func trustedSparkleFeedFillsInRuntimeFeedsOnly() {
    #expect(AppDiscovery.trustedSparkleFeedURL(
        bundleIdentifier: "com.openai.codex"
    )?.absoluteString == "https://persistent.oaistatic.com/codex-app-prod/appcast.xml")
    #expect(AppDiscovery.trustedSparkleFeedURL(bundleIdentifier: "com.example.app") == nil)

    // A feed the app declares itself still wins. Info.plist is read before
    // preferences, so this does not depend on the Mac's ChatGPT settings.
    let declared = AppDiscovery.sparkleFeedURL(
        info: ["SUFeedURL": "https://example.com/appcast.xml"],
        bundleIdentifier: "com.openai.codex",
        defaults: .standard
    )
    #expect(declared?.absoluteString == "https://example.com/appcast.xml")
}

@Test func trustedSparkleFeedIsUsedWhenNothingIsDeclared() throws {
    let bundleIdentifier = "com.openai.codex"
    let suite = TestDefaults.domain("com.example.empty.\(UUID().uuidString)")
    let defaults = try #require(UserDefaults(testSuiteName: suite))
    defer { defaults.removeTestDomain(forName: suite) }
    // Skip on a Mac where ChatGPT stores its own feed; that feed correctly wins.
    guard defaults.persistentDomain(forName: bundleIdentifier)?["SUFeedURL"] == nil else { return }
    #expect(AppDiscovery.sparkleFeedURL(info: [:], bundleIdentifier: bundleIdentifier, defaults: defaults)
        == AppDiscovery.trustedSparkleFeedURL(bundleIdentifier: bundleIdentifier))
}

@Test func electronGenericProviderResolvesChannelManifest() {
    #expect(ElectronUpdateFeed.manifestURL(fromConfig: """
        provider: generic
        url: https://downloads.example.com/app/mac
        updaterCacheDirName: example-updater
        """)?.absoluteString == "https://downloads.example.com/app/mac/latest-mac.yml")
    #expect(ElectronUpdateFeed.manifestURL(fromConfig: """
        provider: generic
        url: 'https://downloads.example.com/app/'
        channel: beta
        """)?.absoluteString == "https://downloads.example.com/app/beta-mac.yml")
    // Plain HTTP, templated URLs, and other providers are not checked.
    #expect(ElectronUpdateFeed.manifestURL(fromConfig: "provider: generic\nurl: http://example.com/app") == nil)
    #expect(ElectronUpdateFeed.manifestURL(fromConfig: "provider: generic\nurl: https://example.com/${arch}") == nil)
    #expect(ElectronUpdateFeed.manifestURL(fromConfig: "provider: s3\nbucket: example") == nil)
    #expect(ElectronUpdateFeed.manifestURL(fromConfig: "provider: generic\nurl: https://example.com\nchannel: ../x") == nil)
}

@Test func electronManifestVersionIgnoresNestedFileEntries() {
    let manifest = """
        version: 2.4.1
        files:
          - url: Example-2.4.1-arm64-mac.zip
            sha512: abc
            size: 100
        path: Example-2.4.1-arm64-mac.zip
        releaseDate: '2026-11-20T10:00:00.000Z'
        """
    #expect(ElectronUpdateFeed.version(fromManifest: manifest) == "2.4.1")
    #expect(ElectronUpdateFeed.version(fromManifest: "version: '3.0.0-beta.2'\n") == "3.0.0-beta.2")
    #expect(ElectronUpdateFeed.version(fromManifest: "files:\n  - version: 1.0\n") == nil)
    #expect(ElectronUpdateFeed.version(fromManifest: "version: 4.0.0\r\npath: a.zip # comment\r\n") == "4.0.0")
}

@Test func electronManifestWaitsForStagedRolloutsToFinish() {
    #expect(ElectronUpdateFeed.version(fromManifest: "version: 2.0.0\nstagingPercentage: 25\n") == nil)
    #expect(ElectronUpdateFeed.version(fromManifest: "version: 2.0.0\nstagingPercentage: 100\n") == "2.0.0")
    #expect(ElectronUpdateFeed.offeredVersion(nil, installedVersion: "1.0.0", includePrereleases: true) == nil)
}

@MainActor
@Test func appDetailsListDeveloperServicesForEveryPublisherChannel() throws {
    let suite = "UpkeepTests.DeveloperSources.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(testSuiteName: suite))
    defer { defaults.removeTestDomain(forName: suite) }
    let store = UpkeepStore(settings: AppSettings(defaults: defaults))
    let chrome = InstalledApp(
        name: "Google Chrome", bundleIdentifier: "com.google.Chrome", installedVersion: "140.0",
        buildVersion: nil, url: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
        sparkleFeedURL: nil, githubRepository: nil, hasAppStoreReceipt: false,
        chromiumUpdateChannel: .stable
    )
    let electron = InstalledApp(
        name: "Example", bundleIdentifier: "com.example.electron", installedVersion: "1.0.0",
        buildVersion: nil, url: URL(fileURLWithPath: "/Applications/Example.app"),
        sparkleFeedURL: nil, githubRepository: nil, hasAppStoreReceipt: false,
        electronUpdateFeedURL: URL(string: "https://example.com/latest-mac.yml")
    )
    store.apps = [chrome, electron]
    #expect(store.sources(for: chrome) == [.developer])
    #expect(store.sources(for: electron) == [.developer])
}

@Test func electronFeedHidesPrereleasesFromStableInstalls() {
    #expect(ElectronUpdateFeed.offeredVersion("2.0.0", installedVersion: "1.0.0", includePrereleases: false) == "2.0.0")
    #expect(ElectronUpdateFeed.offeredVersion("2.0.0-beta.1", installedVersion: "1.0.0", includePrereleases: false) == nil)
    #expect(ElectronUpdateFeed.offeredVersion(
        "2.0.0-beta.1", installedVersion: "1.0.0", includePrereleases: true
    ) == "2.0.0-beta.1")
    #expect(ElectronUpdateFeed.offeredVersion(
        "2.0.0-beta.2", installedVersion: "2.0.0-beta.1", includePrereleases: false
    ) == "2.0.0-beta.2")
}

@Test func electronManifestURLKeepsPercentEncoding() {
    #expect(ElectronUpdateFeed.manifestURL(fromConfig: """
        provider: generic
        url: https://example.com/My%20App/updates?token=abc
        """)?.absoluteString == "https://example.com/My%20App/updates/latest-mac.yml?token=abc")
}

@Test func developerUpdateServiceCoversEveryPublisherChannel() {
    func app(
        chromium: ChromiumUpdateChannel? = nil,
        brave: BraveUpdateChannel? = nil,
        electron: URL? = nil
    ) -> InstalledApp {
        InstalledApp(
            name: "Example", bundleIdentifier: "com.example.app", installedVersion: "1.0",
            buildVersion: nil, url: URL(fileURLWithPath: "/Applications/Example.app"),
            sparkleFeedURL: nil, githubRepository: nil, hasAppStoreReceipt: false,
            chromiumUpdateChannel: chromium, braveUpdateChannel: brave, electronUpdateFeedURL: electron
        )
    }
    #expect(!app().usesDeveloperUpdateService)
    #expect(app(chromium: .stable).usesDeveloperUpdateService)
    #expect(app(brave: .release).usesDeveloperUpdateService)
    #expect(app(electron: URL(string: "https://example.com/latest-mac.yml")).usesDeveloperUpdateService)
}

@Test func electronGenericFeedEnablesTheDeveloperSource() {
    let app = InstalledApp(
        name: "Example",
        bundleIdentifier: "com.example.electron",
        installedVersion: "2.0.0",
        buildVersion: nil,
        url: URL(fileURLWithPath: "/Applications/Example.app"),
        sparkleFeedURL: nil,
        githubRepository: nil,
        hasAppStoreReceipt: false,
        electronUpdateFeedURL: URL(string: "https://downloads.example.com/latest-mac.yml")
    )
    #expect(app.hasBuiltInUpdater)
    #expect(enabledAppUpdateSources(for: app, checkAppStore: true, checkSparkle: true, checkGitHub: true)
        .map(\.source) == [.developer])
}
