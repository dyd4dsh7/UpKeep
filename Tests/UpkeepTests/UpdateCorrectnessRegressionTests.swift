import Foundation
import Testing
@testable import Upkeep

// Regression coverage for the 2026-11 correctness review.

@Test func postReleaseLetterSuffixesAreNewerStableReleases() {
    #expect(VersionComparator.isNewer("3.5c", than: "3.5"))
    #expect(VersionComparator.isNewer("3.5d", than: "3.5c"))
    #expect(VersionComparator.isNewer("3.6", than: "3.5c"))
    #expect(VersionComparator.isNewer("9.9p1", than: "9.9"))
    #expect(VersionComparator.isNewer("9.9p2", than: "9.9p1"))
    #expect(VersionComparator.isNewer("10.0", than: "9.9p1"))
    #expect(VersionComparator.isNewer("1.1.1w", than: "1.1.1v"))
    #expect(VersionComparator.isNewer("9f", than: "9e"))
    #expect(VersionComparator.isNewer("1.1.1w_1", than: "1.1.1w"))
    for version in ["9.9p1", "1.1.1w", "9e", "9.9p1_1"] {
        #expect(!VersionComparator.isPrerelease(version), "\(version) is a post-release")
    }
    // Bare and numbered "a"/"b" suffixes stay alphas and betas for app publishers.
    #expect(VersionComparator.isPrerelease("2.0b"))
    #expect(VersionComparator.isNewer("2.0", than: "2.0b"))
    #expect(VersionComparator.isNewer("1.0", than: "1.0a"))
    #expect(VersionComparator.isPrerelease("1.0a1"))
    #expect(VersionComparator.isPrerelease("1.0b2"))
    #expect(VersionComparator.isNewer("1.0", than: "1.0a1"))
}

@Test func homebrewLetterSuffixesAreStable() {
    for version in ["3.5a", "3.5a_1", "9b", "1.1.1w", "9.9p1_1", "1.2.6,82ef0f61"] {
        #expect(!VersionComparator.isHomebrewPrerelease(version), "\(version) is stable in Homebrew")
    }
    #expect(VersionComparator.isHomebrewPrerelease("2.0.0-beta.1"))
    #expect(VersionComparator.isHomebrewPrerelease("1.0rc1"))
}

@Test func stableQualifiersAndCaskHashesAreNotPrereleases() {
    #expect(!VersionComparator.isPrerelease("2.0.0-stable"))
    #expect(!VersionComparator.isPrerelease("1.4.0-final"))
    #expect(!VersionComparator.isPrerelease("3.1.0-release"))
    #expect(!VersionComparator.isPrerelease("1.2.6,82ef0f61"))
    #expect(VersionComparator.compare("1.2.6,82ef0f61", "1.2.6") == .orderedSame)
    #expect(VersionComparator.isNewer("1.2.6,124", than: "1.2.6,123"))
    #expect(VersionComparator.isPrerelease("2.0.0-canary.1"))
    #expect(VersionComparator.isPrerelease("3.0.0-rc.1"))
}

@Test func namedSparkleChannelsArePrereleases() throws {
    let xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
      <channel>
        <item>
          <sparkle:channel>canary</sparkle:channel>
          <enclosure url="https://example.com/app-3.zip" sparkle:shortVersionString="3.0" sparkle:version="300" />
        </item>
        <item>
          <enclosure url="https://example.com/app-2.zip" sparkle:shortVersionString="2.0" sparkle:version="200" />
        </item>
      </channel>
    </rss>
    """
    let parser = SparkleFeedParser(data: Data(xml.utf8), baseURL: try #require(URL(string: "https://example.com/appcast.xml")))
    #expect(parser.parse(includePrereleases: false)?.version == "2.0")
    #expect(parser.parse(includePrereleases: true)?.version == "3.0")
    #expect(SparkleFeedParser.channel(named: "insider") == .prerelease)
    #expect(SparkleFeedParser.channel(named: "beta") == .beta)
    #expect(SparkleFeedParser.channel(named: "") == nil)
    #expect(SparkleFeedParser.channel(named: "stable") == nil)
}

@Test func sparkleComparesBuildsBeforeMarketingVersions() throws {
    let installed = correctnessApp(version: "1.4.2", build: "812")
    let xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
      <channel>
        <item><enclosure url="https://example.com/app.zip" sparkle:shortVersionString="1.4.2 (812)" sparkle:version="812" /></item>
      </channel>
    </rss>
    """
    let parser = SparkleFeedParser(data: Data(xml.utf8), baseURL: try #require(URL(string: "https://example.com/appcast.xml")))
    let item = try #require(parser.parse())
    #expect(item.version == "1.4.2")
    #expect(!item.isNewer(than: installed), "An annotated marketing version must not create a phantom update")

    // A version-scheme reset with a higher build is still an update.
    let reset = SparkleFeedItem(version: "24.1", buildVersion: "900", hasMarketingVersion: true,
                                sourcePrereleaseChannel: nil, releaseNotes: nil, downloadURL: nil,
                                installationType: .application, hasEdSignature: true,
                                minimumSystemVersion: nil, maximumSystemVersion: nil, hardwareRequirements: nil)
    #expect(reset.isNewer(than: correctnessApp(version: "2023.12", build: "812")))
    let candidate = reset.availableUpdate(for: correctnessApp(version: "2023.12", build: "812"),
                                          fallbackURL: try #require(URL(string: "https://example.com"))).primaryCandidate
    #expect(candidate.isNewer(than: correctnessApp(version: "2023.12", build: "812")))
    #expect(candidate.isInstalled(in: correctnessApp(version: "24.1", build: "900")))
}

@Test func buildOnlySparkleInstallReachesItsTarget() {
    let installed = correctnessApp(version: "2.3.1", build: "456")
    #expect(AppInstallationVerification.targetReached(observed: installed, version: "456", build: "456", comparesBuild: true))
    #expect(!AppInstallationVerification.targetReached(observed: installed, version: "457", build: "457", comparesBuild: true))
    let original = correctnessApp(version: "2.3.0", build: "455")
    #expect(AppInstallationVerification.evaluate(original: original, observed: installed,
                                                 targetVersion: "456", targetBuild: "456",
                                                 comparesBuild: true) == .changed(targetReached: true))
}

@Test func skippedReleaseMatchesAcrossSourceSpellings() {
    let homebrew = UpdateCandidate(availableVersion: "2.0,1234", source: .homebrew, releaseNotes: nil, actionURL: nil,
                                   homebrewToken: "fixture", sourcePrereleaseChannel: nil, requiresHomebrewAdoption: false)
    #expect(homebrew.matchesExclusionVersion("2.0 (build 1234)"))
    #expect(homebrew.matchesExclusionVersion("2.0,1234"))
    #expect(!homebrew.matchesExclusionVersion("2.0 (build 1235)"))
    #expect(!homebrew.matchesExclusionVersion("2.1"))
}

@MainActor
@Test func ignoringAnAppAlsoHidesItsHomebrewCask() throws {
    let suite = "UpkeepTests.IgnoredCask.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(testSuiteName: suite))
    defer { defaults.removeTestDomain(forName: suite) }
    let store = UpkeepStore(settings: AppSettings(defaults: defaults))
    let app = InstalledApp(name: "Widget", bundleIdentifier: "test.widget", installedVersion: "1.0",
                           buildVersion: nil, url: URL(fileURLWithPath: "/Applications/Widget.app"),
                           sparkleFeedURL: nil, githubRepository: nil, hasAppStoreReceipt: false)
    let cask = HomebrewPackage(token: "widget", displayName: "Widget", description: nil, homepage: nil, license: nil,
                               installedVersion: "1.0", currentVersion: "1.1", kind: .cask, isOutdated: true,
                               isDependency: false, dependencies: [])
    store.apps = [app]
    store.homebrewPackages = [cask]
    let update = AvailableUpdate(app: app, availableVersion: "1.1", source: .homebrew,
                                 releaseNotes: nil, actionURL: nil, homebrewToken: "widget")
    store.updates = [update]
    #expect(store.availableBatchUpdateItems.count == 1)

    store.ignore(app)
    #expect(store.isExcluded(cask))
    #expect(store.exclusion(for: cask)?.mode == .ignored, "The Homebrew row must show why it is hidden")
    #expect(store.availableBatchUpdateItems.isEmpty, "The ignored app must not return as a Homebrew row")

    store.restore(app: app)
    #expect(!store.isExcluded(cask))

    store.skip(update)
    #expect(store.isExcluded(cask))
    #expect(store.availableBatchUpdateItems.isEmpty)
    #expect(store.exclusion(for: app, version: "1.1")?.mode == .skipped)
}

private func correctnessApp(version: String, build: String) -> InstalledApp {
    InstalledApp(name: "Correctness Fixture", bundleIdentifier: "test.upkeep.correctness",
                 installedVersion: version, buildVersion: build,
                 url: URL(fileURLWithPath: "/fixture/Correctness.app"),
                 sparkleFeedURL: URL(string: "https://example.invalid/feed"),
                 githubRepository: nil, hasAppStoreReceipt: false)
}
