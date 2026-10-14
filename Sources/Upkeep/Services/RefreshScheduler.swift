import Foundation

/// Owns the replaceable periodic wake-up, independently of scan execution.
/// Cancelling a wake-up does not cancel a scan that has already started.
@MainActor
final class RefreshScheduler {
    typealias Sleep = @Sendable (TimeInterval) async throws -> Void
    private let now: @Sendable () -> Date
    private let sleep: Sleep
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0

    init(now: @escaping @Sendable () -> Date = { Date() },
         sleep: @escaping Sleep = { try await Task.sleep(for: .seconds($0)) }) {
        self.now = now
        self.sleep = sleep
    }

    deinit { task?.cancel() }

    func schedule(at date: Date?, action: @escaping @MainActor () async -> Void) {
        generation &+= 1
        task?.cancel()
        task = nil
        guard let date else { return }
        let expectedGeneration = generation
        let delay = max(0, date.timeIntervalSince(now()))
        let sleep = sleep
        task = Task { [weak self] in
            do { try await sleep(delay) }
            catch { return }
            guard !Task.isCancelled, let self, self.generation == expectedGeneration else { return }
            // Relinquish wake-up ownership before starting independently owned work.
            self.task = nil
            await action()
        }
    }
}
