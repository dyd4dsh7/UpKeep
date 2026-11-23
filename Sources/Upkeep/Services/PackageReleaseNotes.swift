import Foundation

/// Release notes for a Homebrew or developer package version, from the
/// package's GitHub releases.
struct PackageReleaseNotes: Equatable, Sendable {
    let version: String
    let notes: String
    let url: URL?
}

/// How to find a package's GitHub repository.
struct PackageReleaseNotesRequest: Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case repository(String)
        case npm(String)
        case pypi(String)
        case rubyGems(String)
        case crate(String)
    }

    let source: Source
    let version: String

    var key: String { "\(source)|\(version)" }

    static func make(for package: HomebrewPackage) -> PackageReleaseNotesRequest? {
        let version = package.isOutdated ? package.currentVersion : package.installedVersion
        guard let repository = package.homepage.flatMap({ githubRepository(fromURL: $0.absoluteString) }) else { return nil }
        // Homebrew versions can carry a revision ("1.2.3_1"); releases do not.
        return PackageReleaseNotesRequest(source: .repository(repository), version: homebrewUpstreamVersion(version))
    }

    static func make(for package: DeveloperPackage) -> PackageReleaseNotesRequest? {
        let version = package.isOutdated ? package.latestVersion : package.currentVersion
        let identifier = package.registryIdentifier ?? package.name
        let source: Source
        switch package.manager {
        case .node: source = .repository("nodejs/node")
        case .bun: source = .repository("oven-sh/bun")
        case .deno: source = .repository("denoland/deno")
        case .nvm: source = .repository("nvm-sh/nvm")
        case .npm, .pnpm, .yarn:
            guard !identifier.contains(where: \.isWhitespace) else { return nil }
            source = .npm(identifier)
        case .uv where ItemDescriptions.isPythonRuntime(package):
            return nil
        case .uv, .pipx, .python:
            guard !identifier.contains(where: \.isWhitespace) else { return nil }
            source = .pypi(identifier)
        case .rubyGems: source = .rubyGems(identifier)
        case .cargo: source = .crate(identifier)
        case .githubCLI, .go:
            guard let repository = ItemDescriptions.githubRepository(from: identifier) else { return nil }
            source = .repository(repository)
        default:
            return nil
        }
        return PackageReleaseNotesRequest(source: source, version: version)
    }

    static func homebrewUpstreamVersion(_ version: String) -> String {
        guard let underscore = version.lastIndex(of: "_"),
              version[version.index(after: underscore)...].allSatisfy(\.isNumber) else { return version }
        return String(version[..<underscore])
    }
}

/// "git+https://github.com/owner/repo.git", "github:owner/repo" and
/// "https://github.com/owner/repo/tree/main/packages/x" all name owner/repo.
func githubRepository(fromURL value: String) -> String? {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let pattern = #"(?:github\.com[:/]|^github:)([A-Za-z0-9][A-Za-z0-9-]*)/([A-Za-z0-9._-]+?)(?:\.git)?(?:[/#?]|$)"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let owner = Range(match.range(at: 1), in: text), let repo = Range(match.range(at: 2), in: text)
    else { return nil }
    let name = String(text[repo])
    guard !["sponsors", "orgs", "settings"].contains(String(text[owner]).lowercased()), !name.isEmpty else { return nil }
    return "\(text[owner])/\(name)"
}

protocol PackageReleaseNotesProviding: Sendable {
    func releaseNotes(for request: PackageReleaseNotesRequest) async -> PackageReleaseNotes?
}

actor PackageReleaseNotesClient: PackageReleaseNotesProviding {
    typealias Fetch = @Sendable (URL) async -> Data?
    private let fetch: Fetch
    private var repositories: [PackageReleaseNotesRequest.Source: String?] = [:]
    private var tags: [String: [String]] = [:]

    struct Release: Decodable, Sendable {
        let tagName: String
        let name: String?
        let body: String?
        let htmlUrl: String?
        let draft: Bool?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name", name, body, htmlUrl = "html_url", draft
        }
    }

    init(fetch: @escaping Fetch = PackageReleaseNotesClient.liveFetch) {
        self.fetch = fetch
    }

    func releaseNotes(for request: PackageReleaseNotesRequest) async -> PackageReleaseNotes? {
        guard let repository = await repository(for: request.source) else { return nil }
        // Tag names are small; full release lists can be many megabytes of
        // download links, so only the matching release is fetched.
        let names = await tagNames(in: repository)
        var tags = names.first(where: { Self.tag($0, matches: request.version) }).map { [$0] } ?? []
        tags += Self.candidateTags(for: request.version, from: names).filter { !tags.contains($0) }
        for tag in tags.prefix(5) {
            guard let encoded = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "https://api.github.com/repos/\(repository)/releases/tags/\(encoded)"),
                  let data = await fetch(url),
                  let release = try? JSONDecoder().decode(Release.self, from: data),
                  release.draft != true else { continue }
            guard let body = release.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else { return nil }
            return PackageReleaseNotes(version: request.version,
                                       notes: ReleaseNotesHTML.markdown(fromMarkdownWithHTML: body),
                                       url: release.htmlUrl.flatMap(URL.init(string:)))
        }
        return nil
    }

    private func tagNames(in repository: String) async -> [String] {
        if let cached = tags[repository] { return cached }
        struct Tag: Decodable { let name: String }
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/tags?per_page=100"),
              let data = await fetch(url) else { return [] }
        let names = ((try? JSONDecoder().decode([Tag].self, from: data)) ?? []).map(\.name)
        tags[repository] = names
        return names
    }

    static func tag(_ tag: String, matches version: String) -> Bool {
        let tag = tag.lowercased(), wanted = version.lowercased()
        if tag == wanted || tag == "v" + wanted { return true }
        return ["@", "-v", "-", "/v", "/", "_v"].contains { tag.hasSuffix($0 + wanted) }
    }

    /// Tags such as "v1.2.3", "1.2.3", "pkg@1.2.3", "pkg-v1.2.3" or "bun-v1.2.3".
    static func release(matching version: String, in releases: [Release]) -> Release? {
        releases.first { $0.draft != true && tag($0.tagName, matches: version) }
    }

    /// Tags to ask for when a version is not in the recent list, using the
    /// prefixes the repository's own tags use, such as "rust-v" or "v".
    static func candidateTags(for version: String, from tagNames: [String], limit: Int = 4) -> [String] {
        var counts: [String: Int] = [:]
        for name in tagNames {
            guard let range = name.range(of: #"[0-9]+(\.[0-9]+)+"#, options: .regularExpression) else { continue }
            counts[String(name[..<range.lowerBound]), default: 0] += 1
        }
        // The two commonest prefixes, then the plain forms most projects use:
        // tags are listed alphabetically, so other crates' or packages' tags
        // can crowd out the one that matters.
        let prefixes = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
        var tags: [String] = []
        for prefix in Array(prefixes.prefix(2)) + ["v", ""] where !tags.contains(prefix + version) {
            tags.append(prefix + version)
        }
        return Array(tags.prefix(limit))
    }

    private func repository(for source: PackageReleaseNotesRequest.Source) async -> String? {
        if let cached = repositories[source] { return cached }
        let resolved = await resolve(source)
        repositories[source] = resolved
        return resolved
    }

    private func resolve(_ source: PackageReleaseNotesRequest.Source) async -> String? {
        func json(_ string: String) async -> [String: Any]? {
            guard let url = URL(string: string), let data = await fetch(url) else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        func encoded(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value }
        switch source {
        case let .repository(repository):
            return repository
        case let .npm(name):
            guard let object = await json("https://registry.npmjs.org/\(encoded(name))/latest") else { return nil }
            let repository = (object["repository"] as? String) ?? ((object["repository"] as? [String: Any])?["url"] as? String)
            return [repository, object["homepage"] as? String].compactMap { $0 }.lazy.compactMap(githubRepository(fromURL:)).first
        case let .pypi(name):
            guard let info = (await json("https://pypi.org/pypi/\(encoded(name))/json"))?["info"] as? [String: Any] else { return nil }
            let projectURLs = (info["project_urls"] as? [String: String]) ?? [:]
            // Prefer the source repository over documentation or funding links.
            let ordered = projectURLs.sorted { left, right in
                let rank = { (key: String) in ["source", "repository", "code", "github", "homepage"].firstIndex { key.lowercased().contains($0) } ?? 9 }
                return rank(left.key) < rank(right.key)
            }.map(\.value) + [info["home_page"] as? String].compactMap { $0 }
            return ordered.lazy.compactMap(githubRepository(fromURL:)).first
        case let .rubyGems(name):
            guard let object = await json("https://rubygems.org/api/v1/gems/\(encoded(name)).json") else { return nil }
            return ["source_code_uri", "changelog_uri", "homepage_uri"].compactMap { object[$0] as? String }
                .lazy.compactMap(githubRepository(fromURL:)).first
        case let .crate(name):
            let crate = (await json("https://crates.io/api/v1/crates/\(encoded(name))"))?["crate"] as? [String: Any]
            return [crate?["repository"] as? String, crate?["homepage"] as? String].compactMap { $0 }
                .lazy.compactMap(githubRepository(fromURL:)).first
        }
    }

    @Sendable static func liveFetch(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Upkeep/1.0", forHTTPHeaderField: "User-Agent")
        if url.host == GitHubAPIAccess.apiHost {
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        }
        guard let (data, response) = try? await PublisherHTTPClient.data(for: request, maximumBytes: 8 * 1_024 * 1_024),
              200..<300 ~= response.statusCode else { return nil }
        return data
    }
}
