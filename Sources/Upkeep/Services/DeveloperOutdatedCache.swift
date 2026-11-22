import Foundation

typealias DeveloperCommandResult = (data: Data, status: Int32)

/// Reuses a package manager's slow "outdated" result while its installed
/// inventory is byte-for-byte unchanged. Installing, updating, or removing a
/// package (in Upkeep or elsewhere) changes the inventory and so forces a fresh
/// check; otherwise a result is reused for at most `maximumAge`.
///
/// The packaged app keeps entries in its Caches folder so the first check after
/// launch can reuse them too. Tests and benchmarks use memory only.
actor DeveloperOutdatedCache {
    static let shared = DeveloperOutdatedCache(
        fileURL: Bundle.main.bundleIdentifier == InstalledApp.upkeepBundleIdentifier ? defaultFileURL() : nil
    )
    static let maximumAge: TimeInterval = 30 * 60
    static let maximumEntries = 64

    private struct Entry: Codable {
        let inventory: Data
        let outdated: Data
        let outdatedStatus: Int32
        let date: Date
    }

    private let fileURL: URL?
    private var entries: [String: Entry] = [:]
    private var loaded = false

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
    }

    static func defaultFileURL() -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("\(InstalledApp.upkeepBundleIdentifier)/developer-outdated.json")
    }

    private func isFresh(_ entry: Entry, now: Date) -> Bool {
        let age = now.timeIntervalSince(entry.date)
        // A date in the future (for example after a clock change) is not trusted.
        return age >= -60 && age < Self.maximumAge
    }

    private func fresh(for key: String, now: Date) -> Entry? {
        loadIfNeeded()
        guard let entry = entries[key], isFresh(entry, now: now) else {
            entries[key] = nil
            return nil
        }
        return entry
    }

    private func store(_ key: String, inventory: Data, outdated: DeveloperCommandResult, at date: Date) {
        loadIfNeeded()
        entries[key] = Entry(inventory: inventory, outdated: outdated.data, outdatedStatus: outdated.status, date: date)
        persist(now: date)
    }

    func removeAll() {
        entries.removeAll()
        loaded = true
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        let now = Date()
        entries = stored.filter { isFresh($0.value, now: now) }
    }

    private func persist(now: Date) {
        guard let fileURL else { return }
        let kept = entries.filter { isFresh($0.value, now: now) }
            .sorted { $0.value.date > $1.value.date }
            .prefix(Self.maximumEntries)
        entries = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Runs the inventory and outdated commands for one executable.
    /// - With no fresh entry, both run together (the fastest cold path).
    /// - With a fresh entry, only the inventory runs; the cached outdated
    ///   result is used if the inventory matches, otherwise outdated runs too.
    /// Only successful, parseable results are stored.
    func inventoryAndOutdated(
        key: String,
        now: @Sendable () -> Date = Date.init,
        inventory runInventory: @Sendable () async -> DeveloperCommandResult,
        outdated runOutdated: @Sendable () async -> DeveloperCommandResult,
        isCacheable: @Sendable (_ inventory: DeveloperCommandResult, _ outdated: DeveloperCommandResult) -> Bool
    ) async -> (inventory: DeveloperCommandResult, outdated: DeveloperCommandResult, reused: Bool) {
        if let cached = fresh(for: key, now: now()) {
            let inventory = await runInventory()
            if inventory.status == 0, inventory.data == cached.inventory {
                return (inventory, (cached.outdated, cached.outdatedStatus), true)
            }
            let outdated = await runOutdated()
            if isCacheable(inventory, outdated) { store(key, inventory: inventory.data, outdated: outdated, at: now()) }
            return (inventory, outdated, false)
        }
        async let inventoryCommand = runInventory()
        async let outdatedCommand = runOutdated()
        let (inventory, outdated) = await (inventoryCommand, outdatedCommand)
        if isCacheable(inventory, outdated) { store(key, inventory: inventory.data, outdated: outdated, at: now()) }
        return (inventory, outdated, false)
    }
}
