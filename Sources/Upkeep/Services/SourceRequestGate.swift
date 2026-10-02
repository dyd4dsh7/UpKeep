import Foundation

enum SourceRequestPriority: Sendable {
    case foreground, background
    @TaskLocal static var current: Self = .foreground
}

/// Shared across scans and direct downloads. Limits apply to each redirect host.
actor SourceRequestGate {
    enum AdmissionFailure: Error { case timedOut }
    static let shared = SourceRequestGate(globalLimit: 8, perHostLimit: 2)
    private let globalLimit: Int
    private let perHostLimit: Int
    private let agingDelay: Duration
    private let caseInsensitiveKeys: Bool
    private var active: [UUID: String] = [:]
    private var queue: [Waiter] = []
    private struct Waiter {
        let id: UUID
        let host: String
        let priority: SourceRequestPriority
        let enqueued: ContinuousClock.Instant
        let continuation: CheckedContinuation<Void, any Error>
        let deadlineTask: Task<Void, Never>?
    }

    init(globalLimit: Int, perHostLimit: Int, agingDelay: Duration = .seconds(15), caseInsensitiveKeys: Bool = true) {
        self.globalLimit = max(1, globalLimit)
        self.perHostLimit = max(1, perHostLimit)
        self.agingDelay = agingDelay
        self.caseInsensitiveKeys = caseInsensitiveKeys
    }

    var pendingCount: Int { queue.count }
    var activeCount: Int { active.count }

    func withPermit<T: Sendable>(host: String, priority: SourceRequestPriority = SourceRequestPriority.current,
                                queueTimeout: Duration? = nil,
                                operation: @Sendable () async throws -> T) async throws -> T {
        let id = UUID()
        try await acquire(id: id, host: caseInsensitiveKeys ? host.lowercased() : host,
                          priority: priority, queueTimeout: queueTimeout)
        do {
            try Task.checkCancellation()
            let value = try await operation()
            release(id: id)
            return value
        } catch {
            release(id: id)
            throw error
        }
    }

    private func acquire(id: UUID, host: String, priority: SourceRequestPriority, queueTimeout: Duration?) async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                let deadlineTask = queueTimeout.map { duration in
                    Task {
                        do { try await Task.sleep(for: duration) } catch { return }
                        expire(id: id)
                    }
                }
                queue.append(Waiter(id: id, host: host, priority: priority, enqueued: .now,
                                    continuation: continuation, deadlineTask: deadlineTask))
                admit()
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    private func cancel(id: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        let waiter = queue.remove(at: index)
        waiter.deadlineTask?.cancel()
        waiter.continuation.resume(throwing: CancellationError())
        admit()
    }

    private func expire(id: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        queue.remove(at: index).continuation.resume(throwing: AdmissionFailure.timedOut)
        admit()
    }

    private func release(id: UUID) {
        active[id] = nil
        admit()
    }

    private func admit() {
        while active.count < globalLimit {
            let eligible = queue.indices.filter { index in
                active.values.filter { $0 == queue[index].host }.count < perHostLimit
            }
            guard let first = eligible.first else { return }
            // Foreground work gets the next eligible slot; older background work
            // is admitted after fifteen seconds to prevent perpetual starvation.
            let aged = eligible.first { queue[$0].enqueued.duration(to: .now) >= agingDelay }
            let foreground = eligible.first { queue[$0].priority == .foreground }
            let next = queue.remove(at: aged ?? foreground ?? first)
            next.deadlineTask?.cancel()
            active[next.id] = next.host
            next.continuation.resume()
        }
    }
}
