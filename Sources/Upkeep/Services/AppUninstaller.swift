import Foundation

protocol AppUninstalling: Sendable {
    /// Moves an application bundle to the Trash so the user can still restore it.
    func moveToTrash(_ url: URL) async throws
    /// Moves an app's settings and caches to the Trash. Returns the items that
    /// could not be moved, such as containers macOS protects.
    func moveDataToTrash(_ urls: [URL]) async -> [URL]
}

extension AppUninstalling {
    func moveDataToTrash(_ urls: [URL]) async -> [URL] {
        urls.filter { url in
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                return false
            } catch {
                DiagnosticsStore.shared.record(.warning, category: .command, "App data could not be moved to the Trash", metadata: [
                    "Path": url.path, "Error": error.localizedDescription
                ])
                return true
            }
        }
    }
}

/// Settings, caches and other data an app keeps in ~/Library. Folders are
/// matched by the app's bundle identifier, or by its exact name when no other
/// installed app shares it, so data other apps use is left alone.
enum AppDataLocator {
    struct Item: Hashable, Sendable {
        let url: URL
        /// The Library folder it is in, such as "Caches".
        let location: String
    }

    static var defaultLibrary: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
    }

    static func items(for app: InstalledApp, otherApps: [InstalledApp], library: URL = defaultLibrary) -> [Item] {
        guard let bundleID = app.bundleIdentifier?.trimmingCharacters(in: .whitespaces),
              bundleID.contains("."), !bundleID.contains("/"),
              !bundleID.lowercased().hasPrefix("com.apple.")
        else { return [] }
        let others = otherApps.filter { $0.id != app.id && $0.url != app.url }
        // Another copy of the same app uses the same data.
        guard !others.contains(where: { $0.bundleIdentifier?.caseInsensitiveCompare(bundleID) == .orderedSame }) else { return [] }

        var candidates: [(String, String)] = [
            ("Application Support", bundleID),
            ("Caches", bundleID),
            ("Preferences", "\(bundleID).plist"),
            ("Saved Application State", "\(bundleID).savedState"),
            ("HTTPStorages", bundleID),
            ("HTTPStorages", "\(bundleID).binarycookies"),
            ("WebKit", bundleID),
            ("Containers", bundleID),
            ("Application Scripts", bundleID),
            ("Logs", bundleID),
            ("Cookies", "\(bundleID).binarycookies")
        ]
        let name = app.name.trimmingCharacters(in: .whitespaces)
        let nameIsShared = others.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        if name.count >= 3, !name.contains("/"), !nameIsShared, !genericNames.contains(name.lowercased()) {
            candidates += [("Application Support", name), ("Caches", name), ("Logs", name)]
        }
        let fileManager = FileManager.default
        var items: [Item] = candidates.compactMap { location, component in
            let url = library.appendingPathComponent(location, isDirectory: true).appendingPathComponent(component)
            return fileManager.fileExists(atPath: url.path) ? Item(url: url, location: location) : nil
        }
        let byHost = library.appendingPathComponent("Preferences/ByHost", isDirectory: true)
        if let files = try? fileManager.contentsOfDirectory(atPath: byHost.path) {
            items += files.filter { $0.hasPrefix(bundleID + ".") && $0.hasSuffix(".plist") }.sorted()
                .map { Item(url: byHost.appendingPathComponent($0), location: "Preferences") }
        }
        var seen = Set<String>()
        return items.filter { seen.insert($0.url.standardizedFileURL.path.lowercased()).inserted }
    }

    /// Folder names many unrelated apps could share.
    static let genericNames: Set<String> = ["app", "apps", "data", "cache", "caches", "logs", "temp", "tmp",
                                           "updater", "update", "helper", "launcher", "setup", "installer"]

    /// "Application Support, Caches and Preferences".
    static func locationSummary(_ items: [Item]) -> String {
        var locations: [String] = []
        for item in items where !locations.contains(item.location) { locations.append(item.location) }
        return locations.formatted(.list(type: .and))
    }
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
