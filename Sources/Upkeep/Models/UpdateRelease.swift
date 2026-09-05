import Foundation

extension HomebrewPackage {
    /// An app's built-in updater can advance it beyond Homebrew's installation receipt.
    func reconciled(with app: InstalledApp) -> HomebrewPackage {
        guard kind == .cask,
              let catalogVersion = currentVersion.split(separator: ",").first,
              VersionComparator.isNewer(app.installedVersion, than: String(catalogVersion))
        else { return self }
        return HomebrewPackage(
            token: token, displayName: displayName, description: description, homepage: homepage,
            license: license, installedVersion: app.installedVersion, currentVersion: currentVersion,
            kind: kind, isOutdated: false, isDependency: isDependency, dependencies: dependencies
        )
    }
}

extension InstalledApp {
    static let upkeepBundleIdentifier = "nz.haydenthorn.Upkeep"
    var isUpkeep: Bool { bundleIdentifier == Self.upkeepBundleIdentifier }
}

extension UpdateCandidate {
    func isNewer(than app: InstalledApp) -> Bool {
        if !usesBuildVersionOnly {
            let comparison = VersionComparator.compare(availableVersion, app.installedVersion)
            if comparison != .orderedSame { return comparison == .orderedDescending }
        }
        guard let availableBuildVersion else { return false }
        return VersionComparator.isNewer(availableBuildVersion, than: app.buildVersion ?? app.installedVersion)
    }

    func isInstalled(in app: InstalledApp) -> Bool {
        if !usesBuildVersionOnly {
            let comparison = VersionComparator.compare(app.installedVersion, availableVersion)
            if comparison != .orderedSame { return comparison == .orderedDescending }
        }
        guard let availableBuildVersion else { return app.installedVersion == availableVersion }
        let installedBuild = app.buildVersion ?? app.installedVersion
        return installedBuild == availableBuildVersion || VersionComparator.isNewer(installedBuild, than: availableBuildVersion)
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
