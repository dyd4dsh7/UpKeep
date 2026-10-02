import Foundation
import Testing
@testable import Upkeep

private actor ControlledRefreshSleep {
    private var waits: [CheckedContinuation<Void, Never>] = []
    private(set) var delays: [TimeInterval] = []

    func sleep(_ delay: TimeInterval) async {
        delays.append(delay)
        await withCheckedContinuation { waits.append($0) }
    }

    func releaseFirst() { waits.removeFirst().resume() }
    var count: Int { waits.count }
}

private enum RefreshFixtureError: Error { case timedOut }

@MainActor
private func awaitRefreshFixture(_ condition: @MainActor () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !(await condition()) {
        guard ContinuousClock.now < deadline else { throw RefreshFixtureError.timedOut }
        try await Task.sleep(for: .milliseconds(1))
    }
}

@MainActor
@Test func replacingRefreshScheduleDiscardsAnOldWakeupEvenWhenSleepIgnoresCancellation() async throws {
    let clock = ControlledRefreshSleep()
    let anchor = Date(timeIntervalSince1970: 1_000)
    let scheduler = RefreshScheduler(now: { anchor }, sleep: { await clock.sleep($0) })
    var fired: [String] = []
    scheduler.schedule(at: anchor.addingTimeInterval(60)) { fired.append("old") }
    try await awaitRefreshFixture { await clock.count >= 1 }
    scheduler.schedule(at: anchor.addingTimeInterval(120)) { fired.append("new") }
    try await awaitRefreshFixture { await clock.count >= 2 }
    await clock.releaseFirst()
    for _ in 0..<20 { await Task.yield() }
    #expect(fired.isEmpty)
    await clock.releaseFirst()
    try await awaitRefreshFixture { !fired.isEmpty }
    #expect(fired == ["new"])
    #expect(await clock.delays == [60, 120])
}

@MainActor
@Test func disablingRefreshScheduleDiscardsItsPendingWakeup() async throws {
    let clock = ControlledRefreshSleep()
    let anchor = Date(timeIntervalSince1970: 1_000)
    let scheduler = RefreshScheduler(now: { anchor }, sleep: { await clock.sleep($0) })
    var fired = false
    scheduler.schedule(at: anchor.addingTimeInterval(-1)) { fired = true }
    try await awaitRefreshFixture { await clock.count >= 1 }
    #expect(await clock.delays == [0])
    scheduler.schedule(at: nil) { fired = true }
    await clock.releaseFirst()
    for _ in 0..<20 { await Task.yield() }
    #expect(!fired)
}
