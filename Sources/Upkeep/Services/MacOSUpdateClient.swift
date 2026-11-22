import AppKit
import Foundation

enum MacOSScanScope: Sendable { case updates, installers }

struct MacOSUpdateClient: Sendable {
    struct Report: Sendable {
        let updates: [MacOSUpdate]
        let currentVersion: String
        let currentBuild: String
        let isRunningBeta: Bool
        let updatesSucceeded: Bool
        let installersSucceeded: Bool
        let warnings: [String]
        static let empty = Report(
            updates: [], currentVersion: "", currentBuild: "", isRunningBeta: false,
            updatesSucceeded: true, installersSucceeded: true, warnings: []
        )
    }

    /// Full-installer listings change only when Apple publishes a new
    /// installer, but `softwareupdate --list-full-installers` takes about two
    /// seconds. Automatic full scans reuse a recent successful listing; the
    /// macOS page's own installer refresh always asks again.
    static let installerListingMaximumAge: TimeInterval = 6 * 60 * 60
    /// `softwareupdate --list` is the slowest remaining scan step (about
    /// 0.8–2 s). Automatic full scans reuse a successful listing for an hour;
    /// the macOS page's own check always asks Apple again.
    static let updateListingMaximumAge: TimeInterval = 60 * 60

    func scan(includeInstallers: Bool = true) async -> Report {
        await scan(checkUpdates: true, includeInstallers: includeInstallers, reuseRecentListings: true)
    }

    func scan(scope: MacOSScanScope) async -> Report {
        await scan(checkUpdates: scope == .updates, includeInstallers: scope == .installers, reuseRecentListings: false)
    }

    private func scan(checkUpdates: Bool, includeInstallers: Bool, reuseRecentListings: Bool) async -> Report {
        var warnings: [String] = []
        // The two listings are independent; run them together.
        async let updatesCommand: (data: Data?, error: Error?) = checkUpdates
            ? listing(["--list", "--product-types", "macOS"], cache: .updatesShared,
                      maximumAge: Self.updateListingMaximumAge, reuseRecent: reuseRecentListings)
            : (Data(), nil)
        async let installersCommand: (data: Data?, error: Error?) = includeInstallers
            ? listing(["--list-full-installers"], cache: .shared,
                      maximumAge: Self.installerListingMaximumAge, reuseRecent: reuseRecentListings)
            : (Data(), nil)
        let (updatesResult, installersResult) = await (updatesCommand, installersCommand)
        if let error = updatesResult.error { warnings.append("Available updates: \(error.localizedDescription)") }
        if let error = installersResult.error { warnings.append("Full installers: \(error.localizedDescription)") }
        let updatesOutput = updatesResult.data ?? Data()
        let installersOutput = installersResult.data ?? Data()
        let updates = parseUpdates(String(data: updatesOutput, encoding: .utf8) ?? "")
        let installers = parseInstallers(String(data: installersOutput, encoding: .utf8) ?? "")
        let version = ProcessInfo.processInfo.operatingSystemVersionString
        // SystemVersion.plist holds the same values sw_vers prints, without
        // launching two processes; fall back to sw_vers if it is unreadable.
        let system = SystemVersionInfo.current
        let build: String
        let extra: String
        if let system {
            build = system.build
            extra = system.extra
        } else {
            build = await shellValue("/usr/bin/sw_vers", ["-buildVersion"])
            extra = await shellValue("/usr/bin/sw_vers", ["-productVersionExtra"])
        }
        return Report(
            updates: updates + installers.filter { installer in
                !updates.contains(where: { $0.version == installer.version })
            },
            currentVersion: version,
            currentBuild: build,
            isRunningBeta: !extra.isEmpty || version.localizedCaseInsensitiveContains("beta"),
            updatesSucceeded: updatesResult.error == nil,
            installersSucceeded: installersResult.error == nil,
            warnings: warnings
        )
    }

    @MainActor
    func openSoftwareUpdateSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

private func parseUpdates(_ output: String) -> [MacOSUpdate] {
    let blocks = output.components(separatedBy: "* Label:").dropFirst()
    return blocks.compactMap { block in
        let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let first = lines.first else { return nil }
        let label = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = lines.dropFirst().joined(separator: " ")
        let title = capture(#"Title:\s*([^,]+)"#, in: detail) ?? label
        let version = capture(#"Version:\s*([^,]+)"#, in: detail) ?? versionFrom(label) ?? "Unknown"
        return MacOSUpdate(
            label: label,
            title: title,
            version: version,
            size: capture(#"Size:\s*([^,]+)"#, in: detail),
            requiresRestart: detail.localizedCaseInsensitiveContains("restart"),
            isBeta: isBetaName(title + " " + label),
            isFullInstaller: false
        )
    }
}

private func parseInstallers(_ output: String) -> [MacOSUpdate] {
    output.split(separator: "\n").compactMap { rawLine in
        let line = String(rawLine)
        guard line.contains("* Title:") else { return nil }
        let title = capture(#"Title:\s*([^,]+)"#, in: line) ?? "macOS"
        guard let version = capture(#"Version:\s*([^,]+)"#, in: line) else { return nil }
        return MacOSUpdate(
            label: "full-installer-\(version)",
            title: title,
            version: version,
            size: capture(#"Size:\s*([^,]+)"#, in: line),
            requiresRestart: true,
            isBeta: isBetaName(title + " " + version),
            isFullInstaller: true
        )
    }
}

private func capture(_ pattern: String, in value: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
          let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
          let range = Range(match.range(at: 1), in: value)
    else { return nil }
    return String(value[range]).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func versionFrom(_ value: String) -> String? {
    capture(#"\b(\d+(?:\.\d+){1,3})\b"#, in: value)
}

private func isBetaName(_ value: String) -> Bool {
    ["beta", "release candidate", " rc", "seed"].contains { value.localizedCaseInsensitiveContains($0) }
}

struct SystemVersionInfo: Equatable, Sendable {
    let build: String
    let extra: String

    static var current: SystemVersionInfo? {
        read(from: URL(fileURLWithPath: "/System/Library/CoreServices/SystemVersion.plist"))
    }

    static func read(from url: URL) -> SystemVersionInfo? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let build = plist["ProductBuildVersion"] as? String, !build.isEmpty else { return nil }
        return SystemVersionInfo(build: build, extra: plist["ProductVersionExtra"] as? String ?? "")
    }
}

/// Remembers the last successful full-installer listing for automatic scans.
/// The packaged app keeps it in its Caches folder so the first check after
/// launch can reuse it; tests use memory only.
actor MacOSInstallerListingCache {
    static let shared = MacOSInstallerListingCache(
        fileURL: Bundle.main.bundleIdentifier == InstalledApp.upkeepBundleIdentifier ? defaultFileURL() : nil
    )
    /// The same cache for `softwareupdate --list` (available macOS updates).
    static let updatesShared = MacOSInstallerListingCache(
        fileURL: Bundle.main.bundleIdentifier == InstalledApp.upkeepBundleIdentifier
            ? defaultFileURL().deletingLastPathComponent().appendingPathComponent("macos-updates.json") : nil
    )

    private struct Listing: Codable {
        let data: Data
        let date: Date
    }

    private let fileURL: URL?
    private var listing: Listing?
    private var loaded = false

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
    }

    static func defaultFileURL() -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("\(InstalledApp.upkeepBundleIdentifier)/macos-installers.json")
    }

    func recent(maximumAge: TimeInterval, now: Date = Date()) -> Data? {
        if !loaded {
            loaded = true
            if let fileURL, let data = try? Data(contentsOf: fileURL) {
                listing = try? JSONDecoder().decode(Listing.self, from: data)
            }
        }
        guard let listing else { return nil }
        let age = now.timeIntervalSince(listing.date)
        // A date in the future (for example after a clock change) is not trusted.
        guard age >= -60, age < maximumAge else { return nil }
        return listing.data
    }

    func store(_ data: Data, at date: Date = Date()) {
        let value = Listing(data: data, date: date)
        listing = value
        loaded = true
        guard let fileURL, let encoded = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoded.write(to: fileURL, options: .atomic)
    }
}

private func listing(_ arguments: [String], cache: MacOSInstallerListingCache, maximumAge: TimeInterval,
                     reuseRecent: Bool) async -> (data: Data?, error: Error?) {
    if reuseRecent, let cached = await cache.recent(maximumAge: maximumAge) { return (cached, nil) }
    let result = await commandResult(URL(fileURLWithPath: "/usr/sbin/softwareupdate"), arguments)
    if let data = result.data, result.error == nil { await cache.store(data) }
    return result
}

private func shellValue(_ path: String, _ arguments: [String]) async -> String {
    guard let data = try? await runCommand(URL(fileURLWithPath: path), arguments) else { return "" }
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

private func runCommand(_ executable: URL, _ arguments: [String]) async throws -> Data {
    let result = try await CommandRunner.run(executable, arguments, timeout: 120)
    guard result.status == 0 else {
        let message = String(decoding: result.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        throw MacOSUpdateError.commandFailed(message.isEmpty ? "Command exited with status \(result.status)." : message)
    }
    return result.output
}

private func commandResult(_ executable: URL, _ arguments: [String]) async -> (data: Data?, error: Error?) {
    do { return (try await runCommand(executable, arguments), nil) }
    catch { return (nil, error) }
}

private enum MacOSUpdateError: LocalizedError {
    case commandFailed(String)
    var errorDescription: String? {
        if case let .commandFailed(message) = self { return message }
        return nil
    }
}
