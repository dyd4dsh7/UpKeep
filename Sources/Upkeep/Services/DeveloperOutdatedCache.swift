import Foundation

typealias DeveloperCommandResult = (data: Data, status: Int32)

/// Reuses a package manager's slow "outdated" result while its installed
/// inventory is byte-for-byte unchanged. Installing, updating, or removing a
/// package (in Upkeep or elsewhere) changes the inventory and so forces a fresh
/// check; otherwise a result is reused for at most `maximumAge`.
actor DeveloperOutdatedCache {
    static let shared = DeveloperOutdatedCache()
    static let maximumAge: TimeInterval = 30 * 60

    private struct Entry {
        let inventory: Data
        let outdated: DeveloperCommandResult
        let date: Date
    }

    private var entries: [String: Entry] = [:]

    private func fresh(for key: String, now: Date) -> Entry? {
        guard let entry = entries[key], now.timeIntervalSince(entry.date) < Self.maximumAge else {
            entries[key] = nil
            return nil
        }
        return entry
    }

    private func store(_ key: String, inventory: Data, outdated: DeveloperCommandResult, at date: Date) {
        entries[key] = Entry(inventory: inventory, outdated: outdated, date: date)
    }

    func removeAll() { entries.removeAll() }

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
                return (inventory, cached.outdated, true)
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
