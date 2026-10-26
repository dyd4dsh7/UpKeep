import Foundation

/// Bun's npm distribution provides independent stable-release metadata when
/// GitHub's unauthenticated API is unavailable. This only reads metadata.
enum BunReleaseLookup {
    static let githubURL = URL(string: "https://api.github.com/repos/oven-sh/bun/releases/latest")!
    static let npmURL = URL(string: "https://registry.npmjs.org/bun/latest")!

    static func latest(load: (URL) async -> Data?) async -> [String] {
        guard !Task.isCancelled else { return [] }
        if let data = await load(githubURL),
           let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
           release.draft != true, release.prerelease != true,
           let version = stableVersion(tag: release.tagName) {
            return Task.isCancelled ? [] : [version]
        }
        guard !Task.isCancelled else { return [] }
        if let data = await load(npmURL),
           let release = try? JSONDecoder().decode(NPMRelease.self, from: data),
           release.name == "bun", isStableVersion(release.version) {
            return Task.isCancelled ? [] : [release.version]
        }
        return []
    }

    private static func stableVersion(tag: String) -> String? {
        let version: String
        if tag.hasPrefix("bun-v") { version = String(tag.dropFirst(5)) }
        else if tag.hasPrefix("v") { version = String(tag.dropFirst()) }
        else { version = tag }
        return isStableVersion(version) ? version : nil
    }

    private static func isStableVersion(_ value: String) -> Bool {
        value.range(of: #"\A(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z"#,
                    options: .regularExpression) != nil
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let draft: Bool?
        let prerelease: Bool?
        enum CodingKeys: String, CodingKey { case tagName = "tag_name", draft, prerelease }
    }
    private struct NPMRelease: Decodable {
        let name: String
        let version: String
    }
}
