import Foundation

struct GitHubClient: Sendable {
    func update(for app: InstalledApp, includePrereleases: Bool = false) async throws -> AvailableUpdate? {
        guard let repository = app.githubRepository else { return nil }

        do {
            let release = try await fetchRelease(
                repository: repository, includePrereleases: includePrereleases
            )
            guard let release else { return nil }
            let version = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
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

    private func fetchRelease(repository: String, includePrereleases: Bool) async throws -> Release? {
        let suffix = includePrereleases ? "releases?per_page=100" : "releases/latest"
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/\(suffix)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Upkeep/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateSourceError.invalidResponse }
        // GitHub uses 404 when a valid repository has no published releases.
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw UpdateSourceError.httpStatus(http.statusCode) }

        do {
            if includePrereleases {
                return Self.newestRelease(in: try JSONDecoder().decode([Release].self, from: data))
            }
            return try JSONDecoder().decode(Release.self, from: data)
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
