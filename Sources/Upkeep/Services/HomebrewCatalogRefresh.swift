import Foundation

/// `brew info` reads Homebrew's cached formula and cask data but never refreshes
/// it; only commands such as `brew install` do. Before reading the inventory,
/// Upkeep runs the same refresh Homebrew runs before installs.
///
/// `brew update --auto-update` ignores HOMEBREW_NO_AUTO_UPDATE, so Upkeep
/// checks that opt-out itself, in the environment and in Homebrew's brew.env
/// files, and honours HOMEBREW_AUTO_UPDATE_SECS as the interval.
actor HomebrewCatalogRefresh {
    static let shared = HomebrewCatalogRefresh()
    /// Upkeep checks for updates, so it refreshes more often than Homebrew's
    /// 24-hour default for installs.
    static let defaultInterval: TimeInterval = 60 * 60

    private var lastRefresh: Date?

    func refreshIfDue(brew: URL, now: Date = Date()) async {
        let settings = HomebrewSettings.load(brew: brew)
        guard !settings.autoUpdateDisabled else { return }
        if let lastRefresh, now.timeIntervalSince(lastRefresh) < settings.autoUpdateInterval { return }
        lastRefresh = now
        let startedAt = Date()
        var environment = ProcessInfo.processInfo.environment
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        let result = try? await CommandRunner.run(brew, ["update", "--auto-update"], environment: environment, timeout: 120)
        DiagnosticsStore.shared.record(result?.status == 0 ? .info : .warning, category: .command,
            "Homebrew catalog refresh \(result?.status == 0 ? "completed" : "failed")", metadata: [
                "Duration": formattedDiagnosticDuration(since: startedAt),
                "Exit status": result.map { "\($0.status)" } ?? "did not run"
            ])
        // A failed refresh (offline, locked) still leaves the cached catalog usable.
    }
}

struct HomebrewSettings: Equatable, Sendable {
    let autoUpdateDisabled: Bool
    let autoUpdateInterval: TimeInterval

    /// Environment first, then the user, prefix and system brew.env files, in
    /// the precedence Homebrew documents (`man brew`, "ENVIRONMENT").
    static func load(
        brew: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> HomebrewSettings {
        let prefix = brew.deletingLastPathComponent().deletingLastPathComponent()
        let userFile = environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0).appendingPathComponent("homebrew/brew.env") }
            ?? home.appendingPathComponent(".homebrew/brew.env")
        let files = [userFile, prefix.appendingPathComponent("etc/homebrew/brew.env"), URL(fileURLWithPath: "/etc/homebrew/brew.env")]
        let fileValues = files.map { (try? String(contentsOf: $0, encoding: .utf8)).map(parseBrewEnv) ?? [:] }
        func value(_ key: String) -> String? {
            if let value = environment[key], !value.isEmpty { return value }
            return fileValues.lazy.compactMap { $0[key] }.first { !$0.isEmpty }
        }
        let interval = value("HOMEBREW_AUTO_UPDATE_SECS").flatMap(TimeInterval.init).flatMap { $0 >= 0 ? $0 : nil }
        return HomebrewSettings(autoUpdateDisabled: value("HOMEBREW_NO_AUTO_UPDATE") != nil,
            autoUpdateInterval: interval ?? HomebrewCatalogRefresh.defaultInterval)
    }

    /// brew.env holds `KEY=value` lines without shell expansion.
    static func parseBrewEnv(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") { line.removeFirst("export ".count) }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equals)...].trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'"))
            values[key] = value
        }
        return values
    }
}
