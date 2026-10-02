import Foundation
import Testing
@testable import Upkeep

private actor HeldFullScanPass {
    private(set) var calls = 0
    private var continuation: CheckedContinuation<Void, Never>?
    func run() async {
        calls += 1
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}

private enum FullScanFixtureError: Error { case timedOut }
@MainActor
private func waitForScanFixture(_ condition: @MainActor () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !(await condition()) {
        guard ContinuousClock.now < deadline else { throw FullScanFixtureError.timedOut }
        try await Task.sleep(for: .milliseconds(1))
    }
}

@MainActor
@Test func fullScanCoordinatorCoalescesJoinedRequestsAndPreservesRequestsDuringFollowup() async throws {
    let coordinator = FullScanCoordinator()
    let gate = HeldFullScanPass()
    var transitions: [Bool] = []
    var returned = 0
    let owner = Task {
        let owned = await coordinator.run(pass: { await gate.run() }, runningChanged: { transitions.append($0) })
        returned += 1
        return owned
    }
    try await waitForScanFixture { await gate.calls == 1 }
    var joined = 0
    func join() async -> Bool {
        joined += 1
        let owned = await coordinator.run(pass: { Issue.record("Joined caller started its own pass") },
            runningChanged: { _ in Issue.record("Joined caller changed running state") })
        returned += 1
        return owned
    }
    let second = Task { await join() }
    let third = Task { await join() }
    try await waitForScanFixture { joined == 2 }
    await gate.release()
    try await waitForScanFixture { await gate.calls == 2 }
    #expect(returned == 0)
    let fourth = Task { await join() }
    try await waitForScanFixture { joined == 3 }
    await gate.release()
    try await waitForScanFixture { await gate.calls == 3 }
    #expect(returned == 0)
    await gate.release()
    #expect(await owner.value)
    #expect(!(await second.value))
    #expect(!(await third.value))
    #expect(!(await fourth.value))
    #expect(returned == 4)
    #expect(transitions == [true, false])
}
