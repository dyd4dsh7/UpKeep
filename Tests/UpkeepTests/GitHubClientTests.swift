import Foundation
import Testing
@testable import Upkeep

@Test func githubReleaseSelectionIncludesPrereleasesAndExcludesDrafts() throws {
    let releases = [
        GitHubClient.Release(
            tagName: "v1.9", htmlUrl: "https://example.com/stable", body: nil,
            prerelease: false, draft: false
        ),
        GitHubClient.Release(
            tagName: "v2.0-beta.2", htmlUrl: "https://example.com/beta", body: nil,
            prerelease: true, draft: false
        ),
        GitHubClient.Release(
            tagName: "v3.0", htmlUrl: "https://example.com/draft", body: nil,
            prerelease: false, draft: true
        )
    ]

    #expect(GitHubClient.newestRelease(in: releases)?.tagName == "v2.0-beta.2")
    #expect(releases[1].prereleaseChannel == .beta)
}

@Test func githubPrereleaseFlagIsPreservedForStableLookingTag() {
    let release = GitHubClient.Release(
        tagName: "v2.0", htmlUrl: "https://example.com/prerelease", body: nil,
        prerelease: true, draft: false
    )

    #expect(release.prereleaseChannel == .prerelease)
}

@Test func githubReleaseSelectionRejectsTagsForAnotherProduct() {
    let app = InstalledApp(
        name: "TablePro",
        bundleIdentifier: "com.tablepro.app",
        installedVersion: "0.58.0",
        buildVersion: nil,
        url: URL(fileURLWithPath: "/Applications/TablePro.app"),
        sparkleFeedURL: nil,
        githubRepository: "TablePlus/TablePro",
        hasAppStoreReceipt: false
    )
    let releases = [
        GitHubClient.Release(
            tagName: "plugin-oracle-v1.2.17", htmlUrl: "https://example.com/plugin", body: nil,
            prerelease: false, draft: false
        ),
        GitHubClient.Release(
            tagName: "v0.59.0", htmlUrl: "https://example.com/app", body: nil,
            prerelease: false, draft: false
        ),
        GitHubClient.Release(
            tagName: "v0.60.0-beta.1", htmlUrl: "https://example.com/beta", body: nil,
            prerelease: false, draft: false
        )
    ]

    #expect(GitHubClient.version(from: releases[0].tagName, matching: app) == nil)
    #expect(GitHubClient.newestRelease(in: releases, matching: app, includePrereleases: false)?.tagName == "v0.59.0")
    #expect(GitHubClient.newestRelease(in: releases, matching: app, includePrereleases: true)?.tagName == "v0.60.0-beta.1")
}

@Test func githubReleaseSelectionAcceptsAppQualifiedTags() {
    let app = InstalledApp(
        name: "Example App",
        bundleIdentifier: "com.example.app",
        installedVersion: "1.0.0",
        buildVersion: nil,
        url: URL(fileURLWithPath: "/Applications/Example App.app"),
        sparkleFeedURL: nil,
        githubRepository: "example/example-app",
        hasAppStoreReceipt: false
    )

    #expect(GitHubClient.version(from: "example-app-v1.2.0", matching: app) == "1.2.0")
    #expect(GitHubClient.version(from: "release-1.2.0", matching: app) == "1.2.0")
}
