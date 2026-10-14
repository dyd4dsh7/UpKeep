import Foundation
import Testing
@testable import Upkeep

private actor RequestLatch {
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if open { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        open = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor RequestOrder {
    var values: [String] = []
    func add(_ value: String) { values.append(value) }
}

private func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
    let start = ContinuousClock.now
    while start.duration(to: .now) < .seconds(3) {
        if await condition() { return true }
        await Task.yield()
    }
    return false
}

@Test func hostLimitDoesNotBlockOtherHostsAndGlobalLimitIsBounded() async throws {
    let gate = SourceRequestGate(globalLimit: 2, perHostLimit: 1)
    let latch = RequestLatch()
    let first = Task { try await gate.withPermit(host: "one.example") { await latch.wait() } }
    #expect(await eventually { await gate.activeCount == 1 })
    let sameHost = Task { try await gate.withPermit(host: "ONE.EXAMPLE") { await latch.wait() } }
    #expect(await eventually { await gate.pendingCount == 1 })
    let otherHost = Task { try await gate.withPermit(host: "two.example") { await latch.wait() } }
    #expect(await eventually { await gate.activeCount == 2 })
    #expect(await gate.pendingCount == 1)
    let thirdHost = Task { try await gate.withPermit(host: "three.example") { await latch.wait() } }
    #expect(await eventually { await gate.pendingCount == 2 })
    #expect(await gate.activeCount == 2)
    await latch.release()
    try await first.value
    try await sameHost.value
    try await otherHost.value
    try await thirdHost.value
    #expect(await gate.activeCount == 0)
    #expect(await gate.pendingCount == 0)
}

@Test func commandAdmissionKeepsCaseSensitiveExecutableKeysDistinct() async throws {
    let gate = SourceRequestGate(globalLimit: 2, perHostLimit: 1, caseInsensitiveKeys: false)
    let latch = RequestLatch()
    let first = Task { try await gate.withPermit(host: "/fixture/Tool") { await latch.wait() } }
    let second = Task { try await gate.withPermit(host: "/fixture/tool") { await latch.wait() } }
    #expect(await eventually { await gate.activeCount == 2 })
    #expect(await gate.pendingCount == 0)
    await latch.release()
    try await first.value
    try await second.value
    #expect(await gate.activeCount == 0)
}

@Test(arguments: [false, true])
func foregroundChecksPassQueuedBackgroundChecksUnlessBackgroundHasAged(aged: Bool) async throws {
    let gate = SourceRequestGate(globalLimit: 1, perHostLimit: 1, agingDelay: aged ? .zero : .seconds(15))
    let latch = RequestLatch(), order = RequestOrder()
    let held = Task { try await gate.withPermit(host: "held.example") { await latch.wait() } }
    #expect(await eventually { await gate.activeCount == 1 })
    let background = Task {
        try await gate.withPermit(host: "background.example", priority: .background) { await order.add("background") }
    }
    #expect(await eventually { await gate.pendingCount == 1 })
    let foreground = Task {
        try await gate.withPermit(host: "foreground.example", priority: .foreground) { await order.add("foreground") }
    }
    #expect(await eventually { await gate.pendingCount == 2 })
    await latch.release()
    try await held.value
    try await background.value
    try await foreground.value
    #expect(await order.values == (aged ? ["background", "foreground"] : ["foreground", "background"]))
}

@Test func cancellingQueuedCheckDoesNotConsumeOrLeakPermit() async throws {
    let gate = SourceRequestGate(globalLimit: 1, perHostLimit: 1)
    let latch = RequestLatch(), order = RequestOrder()
    let held = Task { try await gate.withPermit(host: "one.example") { await latch.wait() } }
    #expect(await eventually { await gate.activeCount == 1 })
    let cancelled = Task {
        try await gate.withPermit(host: "one.example") { await order.add("should not run") }
    }
    #expect(await eventually { await gate.pendingCount == 1 })
    cancelled.cancel()
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    #expect(await gate.pendingCount == 0)
    #expect(await gate.activeCount == 1)
    await latch.release()
    try await held.value
    let value = try await gate.withPermit(host: "one.example") { 42 }
    #expect(value == 42)
    #expect(await gate.activeCount == 0)
    #expect(await order.values.isEmpty)
}

@Test func failedRequestReleasesCapacityForRetry() async throws {
    struct FixtureFailure: Error {}
    let gate = SourceRequestGate(globalLimit: 1, perHostLimit: 1)
    await #expect(throws: FixtureFailure.self) {
        try await gate.withPermit(host: "example.com") { throw FixtureFailure() }
    }
    #expect(await gate.activeCount == 0)
    let retried = try await gate.withPermit(host: "example.com") { "retried" }
    #expect(retried == "retried")
    #expect(await gate.activeCount == 0)
}

@Test func expiredQueueWaiterNeverRunsAndDoesNotLeakCapacity() async throws {
    let gate = SourceRequestGate(globalLimit: 1, perHostLimit: 1)
    let latch = RequestLatch(), order = RequestOrder()
    let held = Task { try await gate.withPermit(host: "held") { await latch.wait() } }
    #expect(await eventually { await gate.activeCount == 1 })
    do {
        try await gate.withPermit(host: "queued", queueTimeout: .milliseconds(20)) { await order.add("expired") }
        Issue.record("Expected queue admission timeout")
    } catch SourceRequestGate.AdmissionFailure.timedOut {}
    #expect(await order.values.isEmpty)
    #expect(await gate.pendingCount == 0)
    #expect(await gate.activeCount == 1)
    await latch.release()
    try await held.value
    try await gate.withPermit(host: "queued", queueTimeout: .seconds(1)) { await order.add("retry") }
    #expect(await order.values == ["retry"])
    #expect(await gate.activeCount == 0)
}
