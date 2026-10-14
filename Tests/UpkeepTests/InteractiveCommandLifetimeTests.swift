import Foundation
import Testing
@testable import Upkeep

private actor InteractiveLifetimeProbe {
    enum Failure: Error { case terminalExit }
    let fails: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var started = false
    private(set) var completed = false
    private(set) var owner: UUID?
    private(set) var monitorWasCancelled = false

    init(fails: Bool = false) { self.fails = fails }

    func run() async throws -> Int {
        started = true
        owner = MutationContext.owner
        if !released { await withCheckedContinuation { continuation = $0 } }
        monitorWasCancelled = Task.isCancelled
        completed = true
        if fails { throw Failure.terminalExit }
        return 0
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
@Test(arguments: [false, true])
func cancelledInteractiveMonitorKeepsMutationReservationUntilOutcome(fails: Bool) async throws {
    let coordinator = MutationCoordinator()
    let targets: Set<MutationTarget> = [.packageEnvironment("homebrew")]
    let probe = InteractiveLifetimeProbe(fails: fails)
    var callerFinished = false
    let caller = Task {
        await coordinator.withAccess(to: targets, otherwise: false) {
            defer { callerFinished = true }
            do {
                _ = try await awaitingInteractiveCommand { try await probe.run() }
                return false
            } catch is CancellationError {
                return !fails
            } catch is InteractiveLifetimeProbe.Failure {
                return fails
            } catch {
                Issue.record("Unexpected monitor error: \(error)")
                return false
            }
        }
    }
    for _ in 0..<1_000 {
        if await probe.started { break }
        try? await Task.sleep(for: .milliseconds(1))
    }
    #expect(await probe.started)
    #expect(await probe.owner != nil)
    caller.cancel()
    // Give a cancellation-propagating implementation time to unwind its lock.
    try? await Task.sleep(for: .milliseconds(20))
    #expect(!callerFinished)
    #expect(coordinator.isBusy(targets))
    let competingMutation = await coordinator.withAccess(to: targets, otherwise: false) { true }
    #expect(!competingMutation)
    #expect(!(await probe.completed))
    await probe.release()
    #expect(await caller.value)
    #expect(await probe.completed)
    #expect(!(await probe.monitorWasCancelled))
    #expect(callerFinished)
    #expect(!coordinator.isBusy(targets))
    #expect(await coordinator.withAccess(to: targets, otherwise: false) { true })
}

@Test func alreadyCancelledInteractiveCallerDoesNotLaunchCommand() async {
    let probe = InteractiveLifetimeProbe()
    await probe.release()
    let caller = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        do {
            _ = try await awaitingInteractiveCommand { try await probe.run() }
            return false
        } catch is CancellationError { return true }
        catch { return false }
    }
    #expect(await caller.value)
    #expect(!(await probe.started))
}

@MainActor
@Test(arguments: ["", "not an exit status", "256"])
func terminalMonitorWaitsForAValidCompletionReceipt(initialReceipt: String) async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Upkeep-Terminal-Receipt-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let status = root.appendingPathComponent("status")
    let pid = root.appendingPathComponent("pid")
    try Data(initialReceipt.utf8).write(to: status)
    try Data("123".utf8).write(to: pid)
    var finished = false
    let monitor = Task {
        defer { finished = true }
        try await waitForTerminalStatus(at: status, processIDURL: pid,
            launchTimeout: .zero, pollInterval: .milliseconds(1), processIsRunning: { _ in true })
    }
    try? await Task.sleep(for: .milliseconds(20))
    #expect(!finished)
    try Data("0".utf8).write(to: status, options: .atomic)
    try await monitor.value
    #expect(finished)
}
