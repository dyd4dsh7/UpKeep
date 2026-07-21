import Foundation

struct GitHubClient: Sendable {
    func update(for app: InstalledApp) async throws -> AvailableUpdate? {
        guard app.sparkleFeedURL == nil, let repository = app.githubRepository,
              let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")
        else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Upkeep/0.2", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw UpdateSourceError.invalidResponse }
            // GitHub uses 404 when a valid repository has no published releases.
            if http.statusCode == 404 { return nil }
            guard http.statusCode == 200 else { throw UpdateSourceError.httpStatus(http.statusCode) }
            let release: Release
            do { release = try JSONDecoder().decode(Release.self, from: data) }
            catch { throw UpdateSourceError.malformedData(error.localizedDescription) }
            let version = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            guard VersionComparator.isNewer(version, than: app.installedVersion) else { return nil }
            return AvailableUpdate(
                app: app,
                availableVersion: version,
                source: .github,
                releaseNotes: release.body,
                actionURL: URL(string: release.htmlUrl),
                homebrewToken: nil
            )
        } catch { throw UpdateSourceError(error) }
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlUrl: String
        let body: String?
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
            case body
        }
    }
}
