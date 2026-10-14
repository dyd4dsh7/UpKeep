import Foundation

/// Interactive authorization runs outside CommandRunner's owned process group.
/// Task cancellation alone cannot stop that command. Keep awaiting its monitor
/// (which can request verified process shutdown) before releasing reservations.
func awaitingInteractiveCommand<T: Sendable>(
    onCancellation: @escaping @Sendable () -> Void = {},
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try Task.checkCancellation()
    // An unstructured task inherits operation task locals, but not cancellation.
    let monitor = Task { try await operation() }
    let result = try await withTaskCancellationHandler {
        try await monitor.value
    } onCancel: {
        onCancellation()
    }
    try Task.checkCancellation()
    return result
}
