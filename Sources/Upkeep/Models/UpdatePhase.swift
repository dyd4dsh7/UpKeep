import Foundation

enum UpdatePhase: Equatable, Sendable {
    case confirmation, quitting, backingUp, downloading, preparing, installing
    case updating, adopting, refreshing, queued, opening

    var title: String {
        switch self {
        case .confirmation: "Confirm…"
        case .quitting: "Quitting…"
        case .backingUp: "Backing Up…"
        case .downloading: "Downloading…"
        case .preparing: "Preparing…"
        case .installing: "Installing…"
        case .updating: "Updating…"
        case .adopting: "Adopting…"
        case .refreshing: "Refreshing…"
        case .queued: "Waiting…"
        case .opening: "Opening…"
        }
    }

    var showsProgress: Bool { self != .confirmation && self != .queued }
}

struct UpdateActivity {
    let targets: Set<MutationTarget>
    var phase: UpdatePhase
    var startedAt: Date = Date()
    var result: OperationResult?
    var label: String = "Update operation"
    var commandError: String?
    var verification: OperationVerificationDetail?
    var commandLog: String = ""
}

struct OperationVerificationDetail {
    let requested: String
    let observed: String
    let targetReached: Bool
}

enum OperationResult: String {
    case verified = "Installed change verified"
    case unchanged = "Installed state unchanged"
    case unverified = "Verification unavailable"
    case registered = "Registration verified"
}

struct CompletedOperation: Identifiable {
    let id: UUID
    let operation: OperationID
    let startedAt: Date
    let finishedAt: Date
    let result: OperationResult
    let label: String
    let commandError: String?
    let verification: OperationVerificationDetail?
    let commandLog: String
}

typealias UpdateProgressReporter = @Sendable (UpdatePhase) async -> Void
