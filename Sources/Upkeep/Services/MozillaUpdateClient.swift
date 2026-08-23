import Foundation

struct MozillaUpdateClient: Sendable {
    func update(for app: InstalledApp) async throws -> AvailableUpdate? {
        do {
            let latest: String?
            let comparisonLatest: String?
            let sourceName: String
            if let channel = app.mozillaUpdateChannel,
               let product = app.mozillaUpdateProduct {
                let versions = try await fetchStringDictionary(
                    URL(string: "https://product-details.mozilla.org/1.0/\(product.rawValue)_versions.json")!
                )
                latest = Self.latestVersion(
                    for: channel,
                    product: product,
                    installedVersion: app.installedVersion,
                    versions: versions
                )
                comparisonLatest = latest
                sourceName = product == .firefox ? "Mozilla Firefox" : "Mozilla Thunderbird"
            } else if let channel = app.chromiumUpdateChannel {
                latest = try await chromiumVersion(for: channel)
                comparisonLatest = latest
                sourceName = "Google Chrome"
            } else if let channel = app.braveUpdateChannel {
                let brave = try await braveVersion(
                    for: channel,
                    installedBundleVersion: app.installedVersion
                )
                latest = brave?.display
                comparisonLatest = brave?.product
                sourceName = "Brave"
            } else {
                return nil
            }

            let installed = app.braveUpdateChannel == nil
                ? app.installedVersion
                : Self.braveProductVersion(app.installedVersion)
            guard let latest,
                  let comparisonLatest,
                  VersionComparator.isNewer(comparisonLatest, than: installed)
            else { return nil }

            return AvailableUpdate(
                app: app,
                availableVersion: latest,
                source: .developer,
                releaseNotes: "Available from \(sourceName)’s official update service.",
                actionURL: nil,
                homebrewToken: nil,
                sourcePrereleaseChannel: nil,
                requiresInAppInstallation: true
            )
        } catch let error as UpdateSourceError {
            throw error
        } catch {
            throw UpdateSourceError(error)
        }
    }

    static func latestVersion(
        for channel: MozillaUpdateChannel,
        product: MozillaUpdateProduct = .firefox,
        installedVersion: String,
        versions: [String: String]
    ) -> String? {
        if product == .thunderbird {
            return latestThunderbirdVersion(
                for: channel,
                installedVersion: installedVersion,
                versions: versions
            )
        }
        switch channel {
        case .release:
            return versions["LATEST_FIREFOX_VERSION"]
        case .developerEdition:
            return versions["FIREFOX_DEVEDITION"]
                ?? versions["LATEST_FIREFOX_DEVEL_VERSION"]
        case .nightly:
            return versions["FIREFOX_NIGHTLY"]
        case .esr:
            let installedMajor = installedVersion.prefix { $0.isNumber }
            return versions
                .filter { $0.key.hasPrefix("FIREFOX_ESR") }
                .map(\.value)
                .filter { $0.prefix { $0.isNumber } == installedMajor }
                .max {
                    VersionComparator.compare($0, $1) == .orderedAscending
                }
        }
    }

    private static func latestThunderbirdVersion(
        for channel: MozillaUpdateChannel,
        installedVersion: String,
        versions: [String: String]
    ) -> String? {
        switch channel {
        case .release:
            return versions["LATEST_THUNDERBIRD_VERSION"]
        case .developerEdition:
            return versions["LATEST_THUNDERBIRD_DEVEL_VERSION"]
        case .nightly:
            return versions["LATEST_THUNDERBIRD_NIGHTLY_VERSION"]
        case .esr:
            let installedMajor = installedVersion.prefix { $0.isNumber }
            return versions
                .filter { $0.key.hasPrefix("THUNDERBIRD_ESR") }
                .map(\.value)
                .filter { !$0.isEmpty && $0.prefix { $0.isNumber } == installedMajor }
                .max {
                    VersionComparator.compare($0, $1) == .orderedAscending
                }
        }
    }

    static func braveProductVersion(_ bundleVersion: String) -> String {
        let components = bundleVersion.split(separator: ".")
        guard components.count >= 4, components[1] == "1" else { return bundleVersion }
        return components.dropFirst().joined(separator: ".")
    }

    static func newestBraveVersion(
        for channel: BraveUpdateChannel,
        releases: [BraveRelease]
    ) -> String? {
        newestBraveRelease(for: channel, releases: releases)?
            .tagName
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    private static func newestBraveRelease(
        for channel: BraveUpdateChannel,
        releases: [BraveRelease]
    ) -> BraveRelease? {
        let prefix = switch channel {
        case .release: "Release "
        case .beta: "Beta "
        case .dev: "Dev "
        case .nightly: "Nightly "
        }
        return releases
            .filter {
                $0.draft != true
                    && $0.name.hasPrefix(prefix)
                    && (channel != .release || $0.prerelease != true)
            }
            .max {
                let left = $0.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                let right = $1.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                return VersionComparator.compare(left, right) == .orderedAscending
            }
    }

    static func braveBundleVersion(productVersion: String, releaseName: String) -> String {
        let pattern = #"Chromium\s+(\d+)\."#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: releaseName,
                range: NSRange(releaseName.startIndex..., in: releaseName)
              ),
              let range = Range(match.range(at: 1), in: releaseName)
        else { return productVersion }
        return "\(releaseName[range]).\(productVersion)"
    }

    private func fetchStringDictionary(_ url: URL) async throws -> [String: String] {
        let data = try await fetch(url)
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    private func chromiumVersion(for channel: ChromiumUpdateChannel) async throws -> String? {
        #if arch(arm64)
        let platform = "mac_arm64"
        #else
        let platform = "mac"
        #endif
        let url = URL(
            string: "https://versionhistory.googleapis.com/v1/chrome/platforms/\(platform)/channels/\(channel.rawValue)/versions?page_size=20"
        )!
        let response = try JSONDecoder().decode(
            ChromiumVersionsResponse.self,
            from: try await fetch(url)
        )
        return response.versions.map(\.version).max {
            VersionComparator.compare($0, $1) == .orderedAscending
        }
    }

    private func braveVersion(
        for channel: BraveUpdateChannel,
        installedBundleVersion: String
    ) async throws -> (product: String, display: String)? {
        let url = URL(
            string: "https://api.github.com/repos/brave/brave-browser/releases?per_page=100"
        )!
        let releases: [BraveRelease]
        do {
            let data = try await PublisherResponseCache.shared.data(
                for: "github-brave_brave-browser",
                maximumAge: 30 * 60
            ) {
                try await PublisherHTTPClient.data(
                    from: url,
                    accepting: "application/vnd.github+json"
                )
            }
            releases = try JSONDecoder().decode([BraveRelease].self, from: data)
        } catch {
            releases = try await GitHubAtomClient.entries(
                repository: "brave/brave-browser"
            ).map {
                BraveRelease(
                    tagName: $0.tagName,
                    name: $0.title,
                    prerelease: !$0.title.hasPrefix("Release "),
                    draft: false
                )
            }
        }
        guard let release = Self.newestBraveRelease(for: channel, releases: releases) else {
            return nil
        }
        let product = release.tagName.trimmingCharacters(
            in: CharacterSet(charactersIn: "vV")
        )
        let display = installedBundleVersion.split(separator: ".").count >= 4
            ? Self.braveBundleVersion(productVersion: product, releaseName: release.name)
            : product
        return (product, display)
    }

    private func fetch(_ url: URL) async throws -> Data {
        try await PublisherHTTPClient.data(
            from: url,
            accepting: "application/vnd.github+json"
        )
    }

    struct BraveRelease: Decodable, Equatable {
        let tagName: String
        let name: String
        let prerelease: Bool?
        let draft: Bool?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name, prerelease, draft
        }
    }

    private struct ChromiumVersionsResponse: Decodable {
        struct Version: Decodable { let version: String }
        let versions: [Version]
    }
}
