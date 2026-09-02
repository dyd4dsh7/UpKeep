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
}

typealias UpdateProgressReporter = @Sendable (UpdatePhase) async -> Void
