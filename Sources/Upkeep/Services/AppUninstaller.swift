import Foundation

protocol AppUninstalling: Sendable {
    /// Moves an application bundle to the Trash so the user can still restore
    /// it. Returns where it went, or nil when Finder moved it.
    @discardableResult
    func moveToTrash(_ url: URL) async throws -> URL?
    /// Moves an app's settings and caches to the Trash. Items that cannot be
    /// moved, such as containers macOS protects, are reported as failed.
    func moveDataToTrash(_ urls: [URL]) async -> AppDataTrashResult
}

struct AppDataTrashResult: Sendable {
    var moved: [TrashedItem] = []
    var failed: [URL] = []
}

extension AppUninstalling {
    func moveDataToTrash(_ urls: [URL]) async -> AppDataTrashResult {
        var result = AppDataTrashResult()
        for url in urls {
            do {
                var trashed: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
                if let trashed = trashed as URL? {
                    result.moved.append(TrashedItem(originalPath: url.path, trashPath: trashed.path))
                }
            } catch {
                DiagnosticsStore.shared.record(.warning, category: .command, "App data could not be moved to the Trash", metadata: [
                    "Path": url.path, "Error": error.localizedDescription
                ])
                result.failed.append(url)
            }
        }
        return result
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
    /// Moves an item to the Trash directly and says where it went.
    var trashItem: @Sendable (URL) throws -> URL? = { url in
        var trashed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        return trashed as URL?
    }
    /// Asks Finder to move an item to the Trash; returns its exit status and output.
    var runFinder: @Sendable (URL) async throws -> (status: Int32, output: String) = AppUninstaller.finderDelete
    var fileExists: @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }

    /// System Integrity Protection marks bundles such as Safari as restricted;
    /// nothing, including Finder with an administrator password, can remove them.
    static func isSystemProtected(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return false }
        return info.st_flags & UInt32(SF_RESTRICTED) != 0
    }

    func moveToTrash(_ url: URL) async throws -> URL? {
        do {
            return try trashItem(url)
        } catch {
            // App Store and installer-package apps are owned by root. Finder can
            // still trash them after asking for an administrator password.
            DiagnosticsStore.shared.record(.info, category: .command, "Moving app to Trash through Finder", metadata: [
                "App path": url.path,
                "Direct move error": error.localizedDescription
            ])
            try await trashWithFinder(url)
            // Finder does not say where in the Trash it put the app.
            return nil
        }
    }

    private func trashWithFinder(_ url: URL) async throws {
        let result: (status: Int32, output: String)
        do {
            result = try await runFinder(url)
        } catch {
            throw UninstallError.finderFailed(error.localizedDescription)
        }
        guard result.status == 0 else {
            let message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            // -128 is "User canceled", from the password prompt.
            if message.contains("-128") { throw UninstallError.cancelled }
            throw UninstallError.finderFailed(message)
        }
        guard !fileExists(url.path) else {
            throw UninstallError.stillInstalled
        }
    }

    @Sendable static func finderDelete(_ url: URL) async throws -> (status: Int32, output: String) {
        let script = """
        on run argv
            tell application "Finder" to delete (POSIX file (item 1 of argv) as alias)
        end run
        """
        // Leave time for the administrator password prompt.
        let result = try await CommandRunner.run(URL(fileURLWithPath: "/usr/bin/osascript"),
                                                 ["-e", script, url.path], timeout: 300)
        return (result.status, String(decoding: result.output, as: UTF8.self))
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
