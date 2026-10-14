import Foundation

/// Serializes full scans and coalesces requests received during a pass into a
/// fresh follow-up. Every caller waits until all requested passes have finished.
@MainActor
final class FullScanCoordinator {
    private var isRunning = false
    private var needsFollowup = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Returns true only to the caller owning this run, for post-scan scheduling.
    func run(pass: @MainActor () async -> Void,
             runningChanged: @MainActor (Bool) -> Void) async -> Bool {
        if isRunning {
            needsFollowup = true
            await withCheckedContinuation { waiters.append($0) }
            return false
        }
        isRunning = true
        runningChanged(true)
        repeat {
            needsFollowup = false
            await pass()
        } while needsFollowup
        isRunning = false
        runningChanged(false)
        let completedWaiters = waiters
        waiters.removeAll()
        for waiter in completedWaiters { waiter.resume() }
        return true
    }
}
