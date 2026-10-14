import Foundation

/// Owns per-app polling lifetimes. Replacing one app's verification does not
/// cancel another app's verification, and superseded discovery cannot publish.
@MainActor
final class ExternalUpdateVerifier {
    enum Result: Sendable {
        case installed(InstalledApp)
        case attention(lastObserved: InstalledApp?)
    }

    private struct Request {
        let id: UUID
        let task: Task<Void, Never>
    }
    private let discovery: any ApplicationDiscovering
    private let interval: Duration
    private let attempts: Int
    private var requests: [String: Request] = [:]

    init(discovery: any ApplicationDiscovering, interval: Duration, attempts: Int = 20) {
        self.discovery = discovery
        self.interval = interval
        self.attempts = max(1, attempts)
    }

    deinit { for request in requests.values { request.task.cancel() } }

    func start(_ update: AvailableUpdate, result: @escaping @MainActor (Result) async -> Void) {
        requests[update.id]?.task.cancel()
        let requestID = UUID()
        let discovery = discovery
        let interval = interval
        let attempts = attempts
        let task = Task { [weak self] in
            var lastObserved: InstalledApp?
            for _ in 0..<attempts {
                do { try await Task.sleep(for: interval) }
                catch { return }
                guard !Task.isCancelled, self?.requests[update.id]?.id == requestID else { return }
                let refreshed = await discovery.discover(at: update.app.url)
                guard !Task.isCancelled, self?.requests[update.id]?.id == requestID else { return }
                guard let refreshed else { continue }
                lastObserved = refreshed
                if update.primaryCandidate.isInstalled(in: refreshed) {
                    await result(.installed(refreshed))
                    if self?.requests[update.id]?.id == requestID { self?.requests[update.id] = nil }
                    return
                }
            }
            guard !Task.isCancelled, self?.requests[update.id]?.id == requestID else { return }
            await result(.attention(lastObserved: lastObserved))
            if self?.requests[update.id]?.id == requestID { self?.requests[update.id] = nil }
        }
        requests[update.id] = Request(id: requestID, task: task)
    }
}
