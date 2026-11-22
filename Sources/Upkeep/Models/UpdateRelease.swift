import Foundation

extension HomebrewPackage {
    /// An app's built-in updater can advance it beyond Homebrew's installation receipt.
    func reconciled(with app: InstalledApp) -> HomebrewPackage {
        guard kind == .cask,
              let catalogVersion = currentVersion.split(separator: ",").first,
              app.installedVersion.contains(where: \.isNumber),
              catalogVersion.contains(where: \.isNumber)
        else { return self }
        let comparison = VersionComparator.compare(app.installedVersion, String(catalogVersion))
        let target = currentVersion.split(separator: ",", maxSplits: 1).map(String.init)
        let buildReached = target.count == 1 || app.buildVersion.map {
            VersionComparator.compare($0, target[1]) != .orderedAscending
        } == true
        if comparison == .orderedDescending || (comparison == .orderedSame && buildReached) {
            return replacing(installedVersion: app.installedVersion, isOutdated: false)
        }
        // Homebrew reports auto-updating casks as current unless run with
        // --greedy, and its recorded version is stale once the app updates
        // itself. Compare the catalog with the app actually installed.
        if autoUpdates, !isOutdated, UpdateScanner.caskIsNewer(currentVersion, than: app) {
            return replacing(installedVersion: app.installedVersion, isOutdated: true)
        }
        return self
    }

    private func replacing(installedVersion: String, isOutdated: Bool) -> HomebrewPackage {
        HomebrewPackage(
            token: token, displayName: displayName, description: description, homepage: homepage,
            license: license, installedVersion: installedVersion, currentVersion: currentVersion,
            kind: kind, isOutdated: isOutdated, isDependency: isDependency, dependencies: dependencies,
            versionScheme: versionScheme, tap: tap, autoUpdates: autoUpdates, appArtifactNames: appArtifactNames
        )
    }
}

extension InstalledApp {
    static let upkeepBundleIdentifier = "nz.haydenthorn.Upkeep"
    var isUpkeep: Bool { bundleIdentifier == Self.upkeepBundleIdentifier }
}

extension UpdateCandidate {
    // Homebrew encodes an optional bundle build as "version,build".
    private var comparisonVersion: String {
        guard source == .homebrew else { return availableVersion }
        return availableVersion.split(separator: ",", maxSplits: 1).first.map(String.init) ?? availableVersion
    }

    private var comparisonBuild: String? {
        if let availableBuildVersion { return availableBuildVersion }
        guard source == .homebrew else { return nil }
        let parts = availableVersion.split(separator: ",", maxSplits: 1).map(String.init)
        return parts.count == 2 ? parts[1] : nil
    }

    /// Sparkle orders releases by `sparkle:version` against CFBundleVersion.
    /// Marketing strings may reset or carry annotations, so builds win when both exist.
    var comparesBuildVersion: Bool {
        usesBuildVersionOnly || (source == .sparkle && availableBuildVersion?.isEmpty == false)
    }

    private func comparableBuilds(with app: InstalledApp) -> (available: String, installed: String)? {
        guard comparesBuildVersion, let comparisonBuild,
              let installed = app.buildVersion, !installed.isEmpty else { return nil }
        return (comparisonBuild, installed)
    }

    func isNewer(than app: InstalledApp) -> Bool {
        if let builds = comparableBuilds(with: app) {
            return VersionComparator.isNewer(builds.available, than: builds.installed)
        }
        if !usesBuildVersionOnly {
            let comparison = VersionComparator.compare(comparisonVersion, app.installedVersion)
            if comparison != .orderedSame { return comparison == .orderedDescending }
        }
        guard let comparisonBuild else { return false }
        return VersionComparator.isNewer(comparisonBuild, than: app.buildVersion ?? app.installedVersion)
    }

    func isInstalled(in app: InstalledApp) -> Bool {
        if let builds = comparableBuilds(with: app) {
            return VersionComparator.compare(builds.installed, builds.available) != .orderedAscending
        }
        if !usesBuildVersionOnly {
            let comparison = VersionComparator.compare(app.installedVersion, comparisonVersion)
            if comparison != .orderedSame { return comparison == .orderedDescending }
        }
        guard let comparisonBuild else { return app.installedVersion == comparisonVersion }
        let installedBuild = app.buildVersion ?? app.installedVersion
        return installedBuild == comparisonBuild || VersionComparator.isNewer(installedBuild, than: comparisonBuild)
    }

    func matchesDownload(version: String, build: String?) -> Bool {
        if !usesBuildVersionOnly {
            guard version.contains(where: \.isNumber),
                  availableVersion.contains(where: \.isNumber),
                  VersionComparator.compare(version, availableVersion) == .orderedSame else { return false }
        }
        if let availableBuildVersion {
            guard let build else { return false }
            return build == availableBuildVersion
        }
        return true
    }

    var exclusionVersion: String {
        guard let availableBuildVersion else { return availableVersion }
        return "\(availableVersion) (build \(availableBuildVersion))"
    }

    /// Whether a stored skip (`exclusionVersion` from any source) names this release.
    /// Homebrew writes "2.0,1234" where Sparkle writes "2.0 (build 1234)".
    func matchesExclusionVersion(_ skipped: String) -> Bool {
        if skipped == exclusionVersion || skipped == availableVersion { return true }
        var skippedVersion = skipped
        var skippedBuild: String?
        if let range = skipped.range(of: " (build "), skipped.hasSuffix(")") {
            skippedVersion = String(skipped[..<range.lowerBound])
            skippedBuild = String(skipped[range.upperBound..<skipped.index(before: skipped.endIndex)])
        } else if let comma = skipped.firstIndex(of: ",") {
            skippedVersion = String(skipped[..<comma])
            skippedBuild = String(skipped[skipped.index(after: comma)...])
        }
        if usesBuildVersionOnly {
            guard let comparisonBuild else { return false }
            return VersionComparator.compare(skippedBuild ?? skippedVersion, comparisonBuild) == .orderedSame
        }
        guard skippedVersion.contains(where: \.isNumber),
              VersionComparator.compare(skippedVersion, comparisonVersion) == .orderedSame else { return false }
        guard let skippedBuild, let comparisonBuild else { return true }
        return VersionComparator.compare(skippedBuild, comparisonBuild) == .orderedSame
    }
}

extension AvailableUpdate {
    var exclusionVersion: String { primaryCandidate.exclusionVersion }
    var displayAvailableVersion: String {
        guard let build = primaryCandidate.availableBuildVersion,
              availableVersion == app.installedVersion || primaryCandidate.usesBuildVersionOnly
        else { return availableVersion }
        return primaryCandidate.usesBuildVersionOnly ? "Build \(build)" : "\(availableVersion) (\(build))"
    }

    var externalActionURL: URL? {
        if app.isUpkeep {
            // Self replacement needs a separate installer. Keep Upkeep running
            // while the user downloads the signed release and reads its instructions.
            return URL(string: "https://github.com/dyd4dsh7/UpKeep/releases")
        }
        return requiresInAppInstallation ? app.url : actionURL
    }
}

enum ModelReleaseChannel {
    static func detect(in variant: String?) -> PrereleaseChannel? {
        guard let variant else { return nil }
        let words = variant.lowercased().split { !$0.isLetter }
        for word in words {
            switch word {
            case "alpha": return .alpha
            case "beta": return .beta
            case "preview": return .preview
            case "rc": return .releaseCandidate
            case "nightly": return .nightly
            case "snapshot": return .snapshot
            case "dev": return .development
            default: continue
            }
        }
        return nil
    }
}
