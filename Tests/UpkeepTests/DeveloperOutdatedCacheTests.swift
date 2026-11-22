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
