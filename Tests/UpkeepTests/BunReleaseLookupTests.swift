import Foundation
import Testing
@testable import Upkeep

private actor BunReleaseFixture {
    let github: Data?
    let npm: Data?
    var requests: [URL] = []
    init(github: String?, npm: String?) {
        self.github = github.map { Data($0.utf8) }
        self.npm = npm.map { Data($0.utf8) }
    }
    func load(_ url: URL) -> Data? {
        requests.append(url)
        return url == BunReleaseLookup.githubURL ? github : npm
    }
}

@Test func bunPrefersGitHubWithoutRequestingFallback() async {
    let fixture = BunReleaseFixture(github: #"{"tag_name":"bun-v1.4.4","draft":false,"prerelease":false}"#,
                                    npm: #"{"name":"bun","version":"1.4.3"}"#)
    #expect(await BunReleaseLookup.latest { await fixture.load($0) } == ["1.4.4"])
    #expect(await fixture.requests == [BunReleaseLookup.githubURL])
}

@Test func bunUsesOfficialNPMMetadataWhenGitHubIsUnavailable() async {
    // registryData returns nil for HTTP 403, 429, and transport failures.
    let fixture = BunReleaseFixture(github: nil, npm: #"{"name":"bun","version":"1.4.4"}"#)
    #expect(await BunReleaseLookup.latest { await fixture.load($0) } == ["1.4.4"])
    #expect(await fixture.requests == [BunReleaseLookup.githubURL, BunReleaseLookup.npmURL])
}

@Test func bunFallsBackFromInvalidOrNonStableGitHubRelease() async {
    for github in ["not JSON", #"{"tag_name":"canary"}"#,
                   #"{"tag_name":"bun-v1.5.0-beta.1"}"#,
                   #"{"tag_name":"bun-v1.5.0","draft":true}"#,
                   #"{"tag_name":"bun-v1.5.0","prerelease":true}"#] {
        let fixture = BunReleaseFixture(github: github, npm: #"{"name":"bun","version":"1.4.4"}"#)
        #expect(await BunReleaseLookup.latest { await fixture.load($0) } == ["1.4.4"])
    }
}

@Test func bunDoesNotInventVersionWhenBothSourcesFail() async {
    for npm in [nil, "not JSON", #"{"name":"another-package","version":"1.4.4"}"#,
                #"{"name":"bun","version":"canary"}"#,
                #"{"name":"bun","version":"1.5.0-beta.1"}"#,
                #"{"name":"bun","version":"1.4.4\n"}"#] {
        let fixture = BunReleaseFixture(github: nil, npm: npm)
        #expect(await BunReleaseLookup.latest { await fixture.load($0) }.isEmpty)
    }
}
