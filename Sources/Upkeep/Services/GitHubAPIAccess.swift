import Foundation

/// GitHub's API allows 60 requests an hour without signing in and 5,000 with a
/// token. Upkeep uses the GitHub CLI's sign-in when there is one, sends it only
/// to api.github.com, and stops asking GitHub once the limit is reached until
/// it resets, so one exhausted limit does not fail every later check.
actor GitHubAPIAccess {
    static let shared = GitHubAPIAccess()
    nonisolated static let apiHost = "api.github.com"
    /// How long a token, or the lack of one, is reused before asking `gh` again.
    static let tokenLifetime: TimeInterval = 60 * 60

    struct RateLimited: LocalizedError, Equatable {
        let resetsAt: Date
        let isSignedIn: Bool

        var errorDescription: String? {
            let time = resetsAt.formatted(date: .omitted, time: .shortened)
            return isSignedIn
                ? "GitHub’s hourly limit was reached. Checks resume at \(time)."
                : "GitHub’s hourly limit for checks without signing in was reached. Checks resume at \(time). Sign in with the GitHub CLI (gh auth login) to raise the limit."
        }
    }

    private var usesGitHubCLI = true
    private var token: String?
    private var tokenCheckedAt: Date?
    private var limitedUntil: Date?
    private let readToken: @Sendable () async -> String?
    private let now: @Sendable () -> Date

    init(
        readToken: @escaping @Sendable () async -> String? = GitHubAPIAccess.gitHubCLIToken,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.readToken = readToken
        self.now = now
    }

    func setUsesGitHubCLI(_ value: Bool) {
        guard value != usesGitHubCLI else { return }
        usesGitHubCLI = value
        token = nil
        tokenCheckedAt = nil
    }

    nonisolated static func isAPIRequest(_ request: URLRequest) -> Bool {
        request.url?.scheme?.lowercased() == "https" && request.url?.host?.lowercased() == apiHost
    }

    /// Adds the sign-in to an api.github.com request, or throws while the
    /// hourly limit is used up. Other requests pass through unchanged.
    func prepare(_ request: URLRequest) async throws -> URLRequest {
        guard Self.isAPIRequest(request) else { return request }
        if let limitedUntil {
            if limitedUntil > now() { throw RateLimited(resetsAt: limitedUntil, isSignedIn: token != nil) }
            self.limitedUntil = nil
        }
        guard request.value(forHTTPHeaderField: "Authorization") == nil,
              let token = await currentToken() else { return request }
        var authorized = request
        authorized.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return authorized
    }

    /// Notes an exhausted limit or a rejected token from a GitHub API response.
    func record(_ response: HTTPURLResponse, for request: URLRequest) {
        guard Self.isAPIRequest(request) else { return }
        switch response.statusCode {
        case 401 where request.value(forHTTPHeaderField: "Authorization") != nil:
            // An expired or revoked token: carry on without it until gh is asked again.
            token = nil
            tokenCheckedAt = now()
        case 403, 429:
            guard let resetsAt = Self.rateLimitReset(response) else { return }
            limitedUntil = resetsAt
        default:
            break
        }
    }

    var isRateLimited: Bool { limitedUntil.map { $0 > now() } ?? false }

    /// The reset time when a response says the limit is used up.
    nonisolated static func rateLimitReset(_ response: HTTPURLResponse) -> Date? {
        if response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0",
           let reset = response.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(TimeInterval.init) {
            return Date(timeIntervalSince1970: reset)
        }
        if let retryAfter = response.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init) {
            return Date().addingTimeInterval(retryAfter)
        }
        return nil
    }

    private func currentToken() async -> String? {
        guard usesGitHubCLI else { return nil }
        if let tokenCheckedAt, now().timeIntervalSince(tokenCheckedAt) < Self.tokenLifetime { return token }
        let value = await readToken()
        token = value.flatMap(Self.validToken)
        tokenCheckedAt = now()
        return token
    }

    nonisolated static func validToken(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard (20...255).contains(value.count), value.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return value
    }

    nonisolated static let gitHubCLICandidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh",
                                                  NSHomeDirectory() + "/.local/bin/gh"]

    /// `gh auth token` reads the CLI's stored sign-in for github.com.
    @Sendable static func gitHubCLIToken() async -> String? {
        guard let gh = gitHubCLICandidates.first(where: FileManager.default.isExecutableFile(atPath:)),
              let result = try? await CommandRunner.run(URL(fileURLWithPath: gh),
                                                        ["auth", "token", "--hostname", "github.com"], timeout: 10),
              result.status == 0 else { return nil }
        return String(decoding: result.output, as: UTF8.self)
    }
}

/// github.com/owner/repo/releases/latest redirects to the newest stable
/// release's tag. Unlike the API, it does not count against the hourly limit.
func githubLatestReleaseTag(repository: String) async -> String? {
    guard let url = URL(string: "https://github.com/\(repository)/releases/latest") else { return nil }
    var request = URLRequest(url: url)
    request.httpMethod = "HEAD"
    request.timeoutInterval = 15
    request.setValue("Upkeep/1.0", forHTTPHeaderField: "User-Agent")
    guard let (_, response) = try? await PublisherHTTPClient.data(for: request, maximumBytes: 1_024 * 1_024),
          200..<300 ~= response.statusCode,
          let path = response.url?.path else { return nil }
    return githubReleaseTag(fromPath: path)
}

func githubReleaseTag(fromPath path: String) -> String? {
    guard let range = path.range(of: "/releases/tag/") else { return nil }
    let tag = String(path[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return tag.isEmpty ? nil : (tag.removingPercentEncoding ?? tag)
}
