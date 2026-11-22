import Foundation

/// electron-updater's `generic` provider. The app ships `app-update.yml` with a
/// base `url`, and its updater reads `<channel>-mac.yml` from that folder.
enum ElectronUpdateFeed {
    static let cacheMaximumAge: TimeInterval = 10 * 60
    static let manifestLimit = 1_024 * 1_024

    /// The manifest URL for a generic-provider config. Returns nil for other
    /// providers, non-HTTPS URLs, and URLs that need electron-updater's
    /// `${…}` substitutions, which Upkeep cannot expand.
    static func manifestURL(fromConfig contents: String) -> URL? {
        guard topLevelValue(named: "provider", in: contents)?.lowercased() == "generic",
              let base = topLevelValue(named: "url", in: contents),
              !base.contains("${"),
              var components = URLComponents(string: base),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false
        else { return nil }
        let channel = topLevelValue(named: "channel", in: contents) ?? "latest"
        guard channel.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        components.fragment = nil
        var path = components.percentEncodedPath
        if !path.hasSuffix("/") { path += "/" }
        components.percentEncodedPath = path + "\(channel)-mac.yml"
        return components.url
    }

    /// The release version a `latest-mac.yml` manifest offers to every install.
    /// A staged rollout (`stagingPercentage` below 100) only reaches some installs,
    /// and Upkeep cannot tell whether the app's own updater would accept it, so
    /// those releases are left until the rollout finishes.
    static func version(fromManifest contents: String) -> String? {
        if let staging = topLevelValue(named: "stagingPercentage", in: contents).flatMap(Double.init),
           staging < 100 {
            return nil
        }
        return topLevelValue(named: "version", in: contents)
    }

    /// Hides a prerelease from a stable install unless prereleases are included.
    /// An installed prerelease is already on that channel, so it keeps its feed.
    static func offeredVersion(
        _ version: String?,
        installedVersion: String,
        includePrereleases: Bool
    ) -> String? {
        guard let version else { return nil }
        guard !includePrereleases,
              VersionComparator.isPrerelease(version),
              !VersionComparator.isPrerelease(installedVersion)
        else { return version }
        return nil
    }

    /// Nil when the manifest is valid but its release is still being staged.
    static func latestVersion(from manifestURL: URL) async throws -> String? {
        let data = try await PublisherResponseCache.shared.data(
            for: "electron-" + manifestURL.absoluteString,
            maximumAge: cacheMaximumAge
        ) {
            var request = URLRequest(url: manifestURL)
            request.timeoutInterval = 15
            request.setValue("Upkeep/1.0", forHTTPHeaderField: "User-Agent")
            let (data, http) = try await PublisherHTTPClient.data(
                for: request,
                maximumBytes: manifestLimit
            )
            guard 200..<300 ~= http.statusCode else {
                throw UpdateSourceError.httpStatus(http.statusCode)
            }
            return data
        }
        guard let contents = String(data: data, encoding: .utf8),
              topLevelValue(named: "version", in: contents) != nil
        else { throw UpdateSourceError.malformedData("The update manifest has no version.") }
        return version(fromManifest: contents)
    }

    /// Reads an unindented `key: value` line. Indented keys belong to nested
    /// entries such as `files`, whose `url` is a download, not the feed.
    private static func topLevelValue(named key: String, in contents: String) -> String? {
        let pattern = "(?m)^\(NSRegularExpression.escapedPattern(for: key)):[ \\t]*['\"]?([^'\"\\s#]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: contents, range: NSRange(contents.startIndex..., in: contents)),
              let range = Range(match.range(at: 1), in: contents)
        else { return nil }
        return String(contents[range])
    }
}
