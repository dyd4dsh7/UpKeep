import Foundation

/// The `mas` command-line tool installs App Store updates without opening the
/// App Store. `mas update` needs root, so Upkeep runs it with sudo in Terminal,
/// where macOS asks for the administrator password.
enum MacAppStoreCLI {
    static let candidates = ["/opt/homebrew/bin/mas", "/usr/local/bin/mas"]

    /// Looked up once; installing mas takes effect after Upkeep restarts.
    static let executable: URL? = candidates.first(where: FileManager.default.isExecutableFile(atPath:))
        .map(URL.init(fileURLWithPath:))

    static var isInstalled: Bool { executable != nil }

    /// App Store listing URLs end in the app's numeric ID, such as
    /// apps.apple.com/us/app/xcode/id497799835?mt=12.
    static func appID(from url: URL?) -> String? {
        guard let path = url?.path else { return nil }
        guard let match = path.range(of: #"/id([0-9]{5,15})$"#, options: .regularExpression) else { return nil }
        return String(path[match].dropFirst(3))
    }
}

protocol AppStoreUpdating: Sendable {
    var isAvailable: Bool { get }
    func update(appID: String) async throws
}

struct MasAppStoreUpdater: AppStoreUpdating {
    var isAvailable: Bool { MacAppStoreCLI.isInstalled }

    func update(appID: String) async throws {
        guard let mas = MacAppStoreCLI.executable, appID.allSatisfy(\.isNumber) else {
            throw UpdateSourceError.malformedData("The mas command-line tool is not installed.")
        }
        _ = try await runInTerminal(URL(fileURLWithPath: "/usr/bin/sudo"), [mas.path, "update", appID],
                                    subject: "App Store update")
    }
}
