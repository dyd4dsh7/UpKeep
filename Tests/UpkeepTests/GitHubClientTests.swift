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
