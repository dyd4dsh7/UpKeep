import Foundation

/// Shared release-selection and staged-install policy. Unknown requirements fail
/// closed; the publisher's own updater remains available for unsupported bundles.
struct AppCompatibility: Sendable {
    let systemVersion: String
    let isAppleSilicon: Bool

    static var current: Self {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return Self(systemVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
                    isAppleSilicon: AppArchitectureInspector.isAppleSilicon)
    }

    func permits(minimum: String?, maximum: String? = nil, hardware: String? = nil) -> Bool {
        if let minimum {
            guard Self.validSystemVersion(minimum),
                  VersionComparator.compare(systemVersion, minimum) != .orderedAscending else { return false }
        }
        if let maximum {
            guard Self.validSystemVersion(maximum),
                  VersionComparator.compare(systemVersion, maximum) != .orderedDescending else { return false }
        }
        if let hardware {
            let requirements = hardware.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            guard !requirements.isEmpty,
                  requirements.allSatisfy({ $0 == "arm64" && isAppleSilicon }) else { return false }
        }
        return true
    }

    func validateBundle(at url: URL) throws {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw CompatibilityError.unverified }
        let architectures = AppArchitectureInspector.architectures(at: url, info: info)
        try validateBundle(info: info, architectures: architectures)
    }

    func validateBundle(info: [String: Any], architectures: [String]) throws {
        let supported = isAppleSilicon ? ["arm64", "x86_64"] : ["x86_64"]
        guard architectures.contains(where: supported.contains) else {
            throw CompatibilityError.architecture
        }
        if info["LSMinimumSystemVersion"] != nil && !(info["LSMinimumSystemVersion"] is String) {
            throw CompatibilityError.unverified
        }
        if info["LSMinimumSystemVersionByArchitecture"] != nil
            && !(info["LSMinimumSystemVersionByArchitecture"] is [String: String]) {
            throw CompatibilityError.unverified
        }
        guard permits(minimum: info["LSMinimumSystemVersion"] as? String) else {
            throw CompatibilityError.systemVersion
        }
        if let byArchitecture = info["LSMinimumSystemVersionByArchitecture"] as? [String: String] {
            let selected = isAppleSilicon && architectures.contains("arm64") ? "arm64" : "x86_64"
            guard permits(minimum: byArchitecture[selected]) else { throw CompatibilityError.systemVersion }
        }
    }

    private static func validSystemVersion(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return (1...3).contains(parts.count) && parts.allSatisfy {
            !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) && UInt64($0) != nil
        }
    }

    enum CompatibilityError: LocalizedError {
        case unverified, architecture, systemVersion
        var errorDescription: String? {
            switch self {
            case .unverified: "The downloaded app's compatibility could not be verified. Use the app's own updater."
            case .architecture: "The downloaded app has no verified executable for this Mac. Use the app's own updater."
            case .systemVersion: "The downloaded app does not support this macOS version. The installed app was preserved."
            }
        }
    }
}
