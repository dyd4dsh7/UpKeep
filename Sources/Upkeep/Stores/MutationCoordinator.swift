import Combine
import Foundation
import Observation

enum MutationTarget: Hashable {
    case applicationPath(String)
    case bundleIdentifier(String)
    case homebrew(String)
    case developerEnvironment(String)
    case packageEnvironment(String)
    case model(String)
    case modelRuntime(LocalModelRuntime)
}

enum MutationContext {
    @TaskLocal static var owner: UUID?
}

/// Reserves targets before any suspension, including quitting apps and copying backups.
/// Nested steps of one operation share ownership; unrelated actions cannot overlap.
@MainActor
@Observable
final class MutationCoordinator: ObservableObject {
    @ObservationIgnored nonisolated(unsafe) let objectWillChange = ObservableObjectPublisher()
    private var reservations: [UUID: Set<MutationTarget>] = [:]
    private var depths: [UUID: Int] = [:]

    func isBusy(_ targets: Set<MutationTarget>) -> Bool {
        reservations.contains { owner, reserved in
            owner != MutationContext.owner && !reserved.isDisjoint(with: targets)
        }
    }

    func withAccess<T>(
        to targets: Set<MutationTarget>,
        otherwise failure: @autoclosure () -> T,
        operation: () async -> T
    ) async -> T {
        guard !isBusy(targets) else { return failure() }
        let owner = MutationContext.owner ?? UUID()
        objectWillChange.send()
        reservations[owner, default: []].formUnion(targets)
        depths[owner, default: 0] += 1
        defer {
            objectWillChange.send()
            depths[owner, default: 1] -= 1
            if depths[owner] == 0 {
                reservations[owner] = nil
                depths[owner] = nil
            }
        }
        return await MutationContext.$owner.withValue(owner) {
            await operation()
        }
    }
}
