import Foundation
import Testing
@testable import Upkeep

@Test func bulkVersionSortPreservesScalarOrderingAndDuplicates() {
    let special = [
        "", "latest", "rolling", "Unknown", "1.0", "1.0.0", "v1.0", "1.0",
        "1.0+build.99", "1.0+build.12", "1.0-darwin-arm64", "1.0-universal",
        "1.0-beta.2", "1.0-rc.1", "1.0-beta.12", "1.0-alpha.1", "1.0-preview2",
        "001.02.003", "Version 4.2", "release-4.2.0", "2026.10", "2026.2",
        "openssl@3 3.5.1_2", "1.999999999999999999999999999999999999",
        "1.0-custom.12", "1.0-custom.2", "1.0-Édition", "1.0-édition"
    ]
    for input in [[], ["1.0"], special, Array(special.reversed())] {
        #expect(VersionComparator.sortedNewestFirst(input) == input.sorted(by: VersionComparator.newestFirst))
    }
    let large = (0..<2_000).map { index in "\((index * 719) % 2000).0.1" }
    #expect(VersionComparator.sortedNewestFirst(large) == large.sorted(by: VersionComparator.newestFirst))
    #expect(VersionComparator.sortedNewestFirst(["1.0-beta.2", "1.0", "1.0-rc.1", "1.0-beta.12"])
        == ["1.0", "1.0-rc.1", "1.0-beta.12", "1.0-beta.2"])
    #expect(VersionComparator.sortedNewestFirst(["1.0-arm64", "1.0"]) == ["1.0", "1.0-arm64"])
}

/// Differential coverage for the delimiter fast path against the original full
/// rule pipeline. Keep this reference independent of the optimization.
@Test func diagnosticFastPathMatchesFullRedactionRules() throws {
    let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    let rules = try [
        (#"(?i)(https?://)[^/\s:@]+:[^@\s/]+@"#, "$1<redacted>@"),
        (#"(?i)(authorization\s*[:=]\s*(?:bearer|basic)\s+)[^\s,;]+"#, "$1<redacted>"),
        (#"(?i)((?:api[_-]?key|access[_-]?token|auth[_-]?token|password|secret)\s*[:=]\s*)[^\s,;]+"#, "$1<redacted>"),
        (#"(?i)(https?://[^\s?#]+)\?[^\s#]+"#, "$1?<redacted>"),
        (#"(?i)([?&](?:token|key|signature|sig|password|secret|auth)=)[^&#\s]+"#, "$1<redacted>"),
        (#"\b(?:ghp|github_pat|sk|xox[baprs])[-_][A-Za-z0-9_-]{12,}\b"#, "<redacted-token>")
    ].map { (try NSRegularExpression(pattern: $0.0), $0.1) }
    var corpus = [
        "", "Current", "Application 42 completed", "Éditeur 日誌 👩🏽‍💻",
        home + "/Applications/Example.app", "https://user:password@example.com/feed",
        "Authorization: Bearer sampleCredential", "AUTHORIZATION = Basic sampleCredential",
        "?token=sampleCredential&key=otherCredential", "https://example.com/feed?anything=private",
        "ghp_1234567890abcdefghijklmnop", "github_pat_1234567890abcdefghijklmnop",
        "sk-1234567890abcdefghijklmnop", "xoxb-1234567890abcdefghijklmnop",
        "xoxp_1234567890abcdefghijklmnop", String(repeating: "👩🏽‍💻", count: 2_100),
        String(repeating: "a", count: 2_010) + " password=sampleCredential",
        "password=" + String(repeating: "x", count: 2_100)
    ]
    for key in ["apikey", "api_key", "api-key", "access_token", "auth-token", "password", "secret"] {
        for delimiter in [":", "=", " : ", "\t=\n", "：", "＝", "", "-", "_"] {
            corpus.append("\(key)\(delimiter)sampleCredential")
            corpus.append("\(key.uppercased())\(delimiter)sampleCredential; next")
        }
    }
    for input in corpus {
        var expected = input.replacingOccurrences(of: home, with: "~")
        for (expression, replacement) in rules {
            expected = expression.stringByReplacingMatches(
                in: expected, range: NSRange(expected.startIndex..<expected.endIndex, in: expected),
                withTemplate: replacement
            )
        }
        #expect(DiagnosticRedactor.redact(input) == String(expected.prefix(2_000)))
    }
}
