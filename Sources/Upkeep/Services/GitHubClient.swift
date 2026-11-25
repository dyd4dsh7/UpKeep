import Foundation

struct GitHubClient: Sendable {
    static func normalizedRepository(_ value: String) -> String? {
        var candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate = candidate.replacingOccurrences(
            of: #"^https?://github\.com/"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if candidate.hasSuffix(".git") { candidate.removeLast(4) }
        let parts = candidate.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 2,
              parts.allSatisfy({ part in
                  !part.isEmpty && part.allSatisfy {
                      $0.isLetter || $0.isNumber || "-._".contains($0)
                  }
              })
        else { return nil }
        return parts.map(String.init).joined(separator: "/")
    }

    func validateRepository(_ value: String) async throws -> String {
        guard let repository = Self.normalizedRepository(value) else {
            throw UpdateSourceError.malformedData("Enter a GitHub repository as owner/project.")
        }
        let releases = try await fetchReleases(repository: repository)
        guard releases.contains(where: { $0.draft != true }) else {
            throw UpdateSourceError.malformedData(
                "That repository does not have any published releases."
            )
        }
        return repository
    }

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
                releaseNotes: release.body.map(ReleaseNotesHTML.markdown(fromMarkdownWithHTML:)),
                actionURL: Self.installableAsset(in: release, for: app)?.downloadURL
                    ?? URL(string: release.htmlUrl),
                homebrewToken: nil,
                sourcePrereleaseChannel: release.prereleaseChannel,
                requiresInAppInstallation: app.hasBuiltInUpdater
            )
        } catch { throw UpdateSourceError(error) }
    }

    private func fetchReleases(repository: String) async throws -> [Release] {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=100") else { return [] }
        do {
            let data = try await PublisherResponseCache.shared.data(
                for: "github-\(repository.lowercased())",
                maximumAge: 30 * 60
            ) {
                var request = URLRequest(url: url)
                request.timeoutInterval = 15
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("Upkeep/1.0", forHTTPHeaderField: "User-Agent")
                let (data, http) = try await PublisherHTTPClient.data(for: request)
                // Repositories are often inferred from app metadata, so a missing,
                // renamed or private one (404) means "no releases", not a failed scan.
                // A user-entered mapping is still rejected because it has no releases.
                if http.statusCode == 404 { return Data("[]".utf8) }
                guard http.statusCode == 200 else {
                    throw UpdateSourceError.httpStatus(http.statusCode)
                }
                return data
            }
            return try JSONDecoder().decode([Release].self, from: data)
        } catch {
            return try await atomReleases(repository: repository)
        }
    }

    /// The Atom feed has no prerelease flag, so stability falls back to the tag.
    /// Used only when the API is unavailable (for example, rate limited).
    private func atomReleases(repository: String) async throws -> [Release] {
        let entries = try await GitHubAtomClient.entries(repository: repository)
        return entries.map {
            Release(
                tagName: $0.tagName,
                htmlUrl: $0.htmlURL,
                body: $0.content,
                prerelease: VersionComparator.isPrerelease($0.tagName),
                draft: false
            )
        }
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
        // An installed prerelease is already on that channel, so it keeps
        // following it instead of being offered the older stable release.
        let followsPrereleases = includePrereleases || VersionComparator.isPrerelease(app.installedVersion)
        return releases
            .filter { $0.draft != true }
            .filter { version(from: $0.tagName, matching: app) != nil }
            .filter { release in
                guard !followsPrereleases else { return true }
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

    static func installableAsset(in release: Release, for app: InstalledApp) -> Release.Asset? {
        let appName = normalizeAssetComponent(app.name)
        let repositoryName = normalizeAssetComponent(
            app.githubRepository?.split(separator: "/").last.map(String.init) ?? ""
        )
        return release.assets
            .filter {
                guard let url = $0.downloadURL else { return false }
                return ["zip", "dmg"].contains(url.pathExtension.lowercased())
            }
            .filter { asset in
                let name = asset.name.lowercased()
                guard name.contains("mac") || name.contains("darwin") || name.contains("osx")
                    || name.hasSuffix(".dmg")
                else { return false }
                let normalized = normalizeAssetComponent(name)
                return normalized.contains(appName) || normalized.contains(repositoryName)
            }
            .filter { assetMatchesCurrentArchitecture($0.name) }
            .sorted { left, right in
                let leftRank = assetRank(left.name)
                let rightRank = assetRank(right.name)
                return leftRank == rightRank
                    ? left.name.localizedStandardCompare(right.name) == .orderedAscending
                    : leftRank < rightRank
            }
            .first
    }

    private static func normalizeAssetComponent(_ value: String) -> String {
        value.lowercased().filter(\.isLetter)
    }

    private static func assetMatchesCurrentArchitecture(_ name: String) -> Bool {
        let value = name.lowercased()
        let declaresIntel = value.contains("x86_64") || value.contains("x64")
            || value.contains("amd64") || value.contains("intel")
        let declaresArm = value.contains("arm64") || value.contains("aarch64")
        if value.contains("universal") || (!declaresIntel && !declaresArm) { return true }
        #if arch(arm64)
        return declaresArm
        #else
        return declaresIntel
        #endif
    }

    private static func assetRank(_ name: String) -> Int {
        let value = name.lowercased()
        let isDiskImage = value.hasSuffix(".dmg")
        if value.contains("desktop") && isDiskImage { return 0 }
        if value.contains("desktop") { return 1 }
        if isDiskImage { return 2 }
        return 3
    }

    struct Release: Decodable, Equatable {
        let tagName: String
        let htmlUrl: String
        let body: String?
        let prerelease: Bool?
        let draft: Bool?
        let assets: [Asset]

        init(
            tagName: String,
            htmlUrl: String,
            body: String?,
            prerelease: Bool?,
            draft: Bool?,
            assets: [Asset] = []
        ) {
            self.tagName = tagName
            self.htmlUrl = htmlUrl
            self.body = body
            self.prerelease = prerelease
            self.draft = draft
            self.assets = assets
        }

        var prereleaseChannel: PrereleaseChannel? {
            guard prerelease == true else { return nil }
            let version = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            return VersionComparator.prereleaseChannel(for: version) ?? .prerelease
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
            case body, prerelease, draft, assets
        }

        struct Asset: Decodable, Equatable {
            let name: String
            let browserDownloadUrl: String

            var downloadURL: URL? { URL(string: browserDownloadUrl) }

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadUrl = "browser_download_url"
            }
        }
    }
}
