import Foundation

/// Compares an installed bundle with the pre-mutation snapshot and requested target.
/// Command exit status is deliberately separate from the observed installation.
enum AppInstallationVerification: Equatable, Sendable {
    case unverified
    case unchanged
    case changed(targetReached: Bool)

    static func evaluate(original: InstalledApp, observed: InstalledApp?,
                         targetVersion: String, targetBuild: String? = nil,
                         comparesBuild: Bool = false) -> Self {
        guard let identifier = original.bundleIdentifier, !identifier.isEmpty,
              let observed, observed.bundleIdentifier == identifier,
              observed.url.standardizedFileURL == original.url.standardizedFileURL,
              !observed.installedVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .unverified
        }
        guard observed.installedVersion != original.installedVersion || observed.buildVersion != original.buildVersion else {
            return .unchanged
        }
        return .changed(targetReached: targetReached(observed: observed, version: targetVersion,
                                                     build: targetBuild, comparesBuild: comparesBuild))
    }

    /// `comparesBuild` follows Sparkle, whose `sparkle:version` is compared with
    /// CFBundleVersion. Build-only feeds have no comparable marketing version.
    static func targetReached(observed: InstalledApp, version: String, build: String? = nil,
                              comparesBuild: Bool = false) -> Bool {
        if comparesBuild, let targetBuild = build, !targetBuild.isEmpty,
           let observedBuild = observed.buildVersion, !observedBuild.isEmpty {
            return VersionComparator.compare(observedBuild, targetBuild) != .orderedAscending
        }
        let comparison = VersionComparator.compare(observed.installedVersion, version)
        let reached: Bool
        if comparison == .orderedDescending { reached = true }
        else if comparison == .orderedAscending { reached = false }
        else if let targetBuild = build, !targetBuild.isEmpty {
            reached = VersionComparator.compare(observed.buildVersion ?? "", targetBuild) != .orderedAscending
        } else { reached = true }
        return reached
    }
}
