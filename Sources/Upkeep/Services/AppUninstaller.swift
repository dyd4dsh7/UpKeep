import Foundation

protocol AppUninstalling: Sendable {
    /// Moves an application bundle to the Trash so the user can still restore it.
    func moveToTrash(_ url: URL) async throws
}

struct AppUninstaller: AppUninstalling {
    /// System Integrity Protection marks bundles such as Safari as restricted;
    /// nothing, including Finder with an administrator password, can remove them.
    static func isSystemProtected(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return false }
        return info.st_flags & UInt32(SF_RESTRICTED) != 0
    }

    func moveToTrash(_ url: URL) async throws {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            // App Store and installer-package apps are owned by root. Finder can
            // still trash them after asking for an administrator password.
            DiagnosticsStore.shared.record(.info, category: .command, "Moving app to Trash through Finder", metadata: [
                "App path": url.path,
                "Direct move error": error.localizedDescription
            ])
            try await trashWithFinder(url)
        }
    }

    private func trashWithFinder(_ url: URL) async throws {
        let script = """
        on run argv
            tell application "Finder" to delete (POSIX file (item 1 of argv) as alias)
        end run
        """
        let result: CommandRunner.Result
        do {
            // Leave time for the administrator password prompt.
            result = try await CommandRunner.run(URL(fileURLWithPath: "/usr/bin/osascript"),
                                                 ["-e", script, url.path], timeout: 300)
        } catch {
            throw UninstallError.finderFailed(error.localizedDescription)
        }
        guard result.status == 0 else {
            let message = String(decoding: result.output, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if message.contains("-128") { throw UninstallError.cancelled }
            throw UninstallError.finderFailed(message)
        }
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw UninstallError.stillInstalled
        }
    }

    enum UninstallError: LocalizedError {
        case cancelled
        case finderFailed(String)
        case stillInstalled

        var errorDescription: String? {
            switch self {
            case .cancelled:
                "Uninstall was cancelled."
            case let .finderFailed(message):
                "Finder could not move the app to the Trash: \(message). Allow Upkeep to control Finder in Privacy & Security → Automation, or drag the app to the Trash yourself."
            case .stillInstalled:
                "Finder finished, but the app is still installed."
            }
        }
    }
}
