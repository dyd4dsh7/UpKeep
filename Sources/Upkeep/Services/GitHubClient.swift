import Foundation

struct GitHubClient: Sendable {
    func update(for app: InstalledApp, includePrereleases: Bool = false) async throws -> AvailableUpdate? {
        guard let repository = app.githubRepository else { return nil }

        do {
            let releases = try await fetchReleases(repository: repository)
            let release = Self.newestRelease(
                in: releases,
                matching: app,
                includePrereleases: includePrereleases
            )
            guard let release else { return nil }
            guard let version = Self.version(from: release.tagName, matching: app) else { return nil }
            guard VersionComparator.isNewer(version, than: app.installedVersion) else { return nil }
            return AvailableUpdate(
                app: app,
                availableVersion: version,
                source: .github,
                releaseNotes: release.body,
                actionURL: URL(string: release.htmlUrl),
                homebrewToken: nil,
                sourcePrereleaseChannel: release.prereleaseChannel
            )
        } catch { throw UpdateSourceError(error) }
    }

    private func fetchReleases(repository: String) async throws -> [Release] {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=100") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Upkeep/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateSourceError.invalidResponse }
        // GitHub uses 404 when a valid repository has no published releases.
        if http.statusCode == 404 { return [] }
        guard http.statusCode == 200 else { throw UpdateSourceError.httpStatus(http.statusCode) }

        do {
            return try JSONDecoder().decode([Release].self, from: data)
        } catch { throw UpdateSourceError.malformedData(error.localizedDescription) }
    }

    static func newestRelease(in releases: [Release]) -> Release? {
        releases
            .filter { $0.draft != true }
            .max {
                let left = $0.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                let right = $1.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                return VersionComparator.compare(left, right) == .orderedAscending
            }
    }

    static func newestRelease(
        in releases: [Release],
        matching app: InstalledApp,
        includePrereleases: Bool
    ) -> Release? {
        releases
            .filter { $0.draft != true }
            .filter { version(from: $0.tagName, matching: app) != nil }
            .filter { release in
                guard !includePrereleases else { return true }
                guard release.prerelease != true,
                      let version = version(from: release.tagName, matching: app) else { return false }
                return !VersionComparator.isPrerelease(version)
            }
            .max { left, right in
                guard let leftVersion = version(from: left.tagName, matching: app),
                      let rightVersion = version(from: right.tagName, matching: app) else { return false }
                return VersionComparator.compare(leftVersion, rightVersion) == .orderedAscending
            }
    }

    /// GitHub repositories often publish releases for several products. Only accept
    /// unqualified version tags or tags explicitly qualified with this app/repository name.
    static func version(from tag: String, matching app: InstalledApp) -> String? {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstDigit = trimmed.firstIndex(where: \.isNumber) else { return nil }
        let prefix = String(trimmed[..<firstDigit])
        let normalizedPrefix = normalizeTagComponent(prefix)
        let repositoryName = app.githubRepository?.split(separator: "/").last.map(String.init) ?? ""
        let allowedPrefixes = Set([
            "", "v", "version", "release",
            normalizeTagComponent(app.name),
            normalizeTagComponent(repositoryName),
            normalizeTagComponent(app.name) + "v",
            normalizeTagComponent(repositoryName) + "v"
        ])
        guard allowedPrefixes.contains(normalizedPrefix) else { return nil }

        return String(trimmed[firstDigit...])
    }

    private static func normalizeTagComponent(_ value: String) -> String {
        value.lowercased().filter(\.isLetter)
    }

    struct Release: Decodable, Equatable {
        let tagName: String
        let htmlUrl: String
        let body: String?
        let prerelease: Bool?
        let draft: Bool?

        var prereleaseChannel: PrereleaseChannel? {
            guard prerelease == true else { return nil }
            let version = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            return VersionComparator.prereleaseChannel(for: version) ?? .prerelease
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
            case body, prerelease, draft
        }
    }
}
