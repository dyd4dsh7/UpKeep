import Foundation
import Testing
@testable import Upkeep

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func withLock<T>(_ body: (inout Int) -> T) -> T { lock.lock(); defer { lock.unlock() }; return body(&value) }
}

private final class Calls: Sendable {
    let inventory = Counter()
    let outdated = Counter()
}

private func run(_ cache: DeveloperOutdatedCache, calls: Calls, inventory: String, outdated: String = "old",
                 at date: Date, cacheable: Bool = true) async -> (DeveloperCommandResult, Bool) {
    let result = await cache.inventoryAndOutdated(
        key: "npm|/fixture/npm",
        now: { date },
        inventory: { calls.inventory.withLock { $0 += 1 }; return (Data(inventory.utf8), 0) },
        outdated: { calls.outdated.withLock { $0 += 1 }; return (Data(outdated.utf8), 0) },
        isCacheable: { _, _ in cacheable }
    )
    return (result.outdated, result.reused)
}

@Test func unchangedInventoryReusesTheOutdatedResult() async {
    let cache = DeveloperOutdatedCache(), calls = Calls(), start = Date()
    _ = await run(cache, calls: calls, inventory: "a@1", outdated: "first", at: start)
    let (outdated, reused) = await run(cache, calls: calls, inventory: "a@1", outdated: "second", at: start.addingTimeInterval(60))
    #expect(reused)
    #expect(String(decoding: outdated.data, as: UTF8.self) == "first")
    #expect(calls.inventory.withLock { $0 } == 2, "The inventory is always checked")
    #expect(calls.outdated.withLock { $0 } == 1, "The slow outdated check ran once")
}

@Test func changedInventoryForcesAFreshOutdatedCheck() async {
    let cache = DeveloperOutdatedCache(), calls = Calls(), start = Date()
    _ = await run(cache, calls: calls, inventory: "a@1", outdated: "first", at: start)
    let (outdated, reused) = await run(cache, calls: calls, inventory: "a@2", outdated: "second", at: start.addingTimeInterval(60))
    #expect(!reused)
    #expect(String(decoding: outdated.data, as: UTF8.self) == "second")
    #expect(calls.outdated.withLock { $0 } == 2)
}

@Test func outdatedResultsExpire() async {
    let cache = DeveloperOutdatedCache(), calls = Calls(), start = Date()
    _ = await run(cache, calls: calls, inventory: "a@1", outdated: "first", at: start)
    let (_, reused) = await run(cache, calls: calls, inventory: "a@1", outdated: "second",
                                at: start.addingTimeInterval(DeveloperOutdatedCache.maximumAge + 1))
    #expect(!reused)
    #expect(calls.outdated.withLock { $0 } == 2)
}

@Test func failedOutdatedChecksAreNotCached() async {
    let cache = DeveloperOutdatedCache(), calls = Calls(), start = Date()
    _ = await run(cache, calls: calls, inventory: "a@1", at: start, cacheable: false)
    let (_, reused) = await run(cache, calls: calls, inventory: "a@1", at: start.addingTimeInterval(60))
    #expect(!reused)
    #expect(calls.outdated.withLock { $0 } == 2)
}

@Test func cachedResultsSurviveARelaunchAndStayFreshnessChecked() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("OutdatedCache-\(UUID())/developer-outdated.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let calls = Calls(), start = Date()

    _ = await run(DeveloperOutdatedCache(fileURL: url), calls: calls, inventory: "a@1", outdated: "saved", at: start)
    #expect(FileManager.default.fileExists(atPath: url.path))

    // A new instance (as after relaunching Upkeep) reads the saved result.
    let (outdated, reused) = await run(DeveloperOutdatedCache(fileURL: url), calls: calls,
                                       inventory: "a@1", outdated: "fresh", at: Date())
    #expect(reused)
    #expect(String(decoding: outdated.data, as: UTF8.self) == "saved")
    #expect(calls.outdated.withLock { $0 } == 1)

    // A changed inventory still forces a fresh check after relaunch.
    let (changed, reusedChanged) = await run(DeveloperOutdatedCache(fileURL: url), calls: calls,
                                             inventory: "a@2", outdated: "fresh", at: Date())
    #expect(!reusedChanged)
    #expect(String(decoding: changed.data, as: UTF8.self) == "fresh")
}

@Test func futureDatedEntriesAreNotTrusted() async {
    let cache = DeveloperOutdatedCache(), calls = Calls(), start = Date()
    _ = await run(cache, calls: calls, inventory: "a@1", at: start.addingTimeInterval(3_600))
    let (_, reused) = await run(cache, calls: calls, inventory: "a@1", at: start)
    #expect(!reused)
}

@Test func onlyThePackagedAppPersistsTheCache() async {
    // Tests run outside Upkeep's bundle, so the shared cache is memory-only.
    #expect(Bundle.main.bundleIdentifier != InstalledApp.upkeepBundleIdentifier)
    #expect(DeveloperOutdatedCache.defaultFileURL().path.contains("/Caches/"))
}
