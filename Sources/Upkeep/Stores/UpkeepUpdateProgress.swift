import Foundation

@MainActor
extension UpkeepStore {
    func beginUpdateActivity(_ operation: OperationID, targets: Set<MutationTarget>, phase: UpdatePhase) {
        updateExecutionState.begin(operation, targets: targets, phase: phase, label: operationLabel(for: operation))
    }

    func setUpdatePhase(_ phase: UpdatePhase, for operation: OperationID) {
        updateExecutionState.setPhase(phase, for: operation)
    }

    func endUpdateActivity(_ operation: OperationID) {
        updateExecutionState.finish(operation)
    }

    func recordOperationVerification(_ result: OperationResult, for operation: OperationID, commandError: String? = nil,
                                     verification: OperationVerificationDetail? = nil) {
        updateExecutionState.recordVerification(result, for: operation, commandError: commandError, verification: verification)
    }

    private func operationLabel(for operation: OperationID) -> String {
        switch operation {
        case let .applicationUpdate(id): updates.first { $0.id == id }?.app.name ?? "Application update"
        case let .homebrewPackage(id): homebrewPackages.first { $0.id == id }?.displayName ?? "Homebrew update"
        case let .homebrewAdoption(id): adoptableApps.first { $0.id == id }?.app.name ?? "Homebrew registration"
        case let .developerPackage(id): developerPackages.first { $0.id == id }?.name ?? "Developer package update"
        case let .localModel(id): localModels.first { $0.id == id }?.name ?? "Model update"
        default: "Update operation"
        }
    }

    func updatePhase(for operation: OperationID) -> UpdatePhase? {
        if let activity = updateExecutionState.activities[operation] { return activity.phase }
        let targets = mutationTargets(for: operation)
        // Application and cask rows can represent the same install. A different
        // developer package sharing a manager is only waiting for that manager.
        let sharedTargets = targets.filter {
            switch $0 {
            case .developerEnvironment, .packageEnvironment, .modelRuntime: return false
            default: return true
            }
        }
        if let activity = updateExecutionState.activities.values.first(where: {
            !$0.targets.isDisjoint(with: sharedTargets)
        }) { return activity.phase }
        if let confirmation = pendingHomebrewAuthorizationConfirmation,
           !authorizationTargets(confirmation).isDisjoint(with: targets) { return .confirmation }
        if let confirmation = pendingRunningAppConfirmation,
           !mutationTargets(for: confirmation).isDisjoint(with: targets) { return .confirmation }
        return isWorking(operation) ? .queued : nil
    }

    private func authorizationTargets(_ confirmation: HomebrewAuthorizationConfirmation) -> Set<MutationTarget> {
        switch confirmation.action {
        case let .update(update): mutationTargets(for: .application(update))
        case let .package(package): mutationTargets(for: .homebrew(package))
        case let .adopt(item): mutationTargets(for: item)
        }
    }
}

extension BatchUpdateItem {
    var updateOperationID: OperationID {
        switch self {
        case let .application(update): .applicationUpdate(update.id)
        case let .homebrew(package): .homebrewPackage(package.id)
        case let .developer(package): .developerPackage(package.id)
        case let .model(model): .localModel(model.id)
        }
    }
}

extension RunningAppConfirmation {
    var operationID: OperationID {
        switch action {
        case let .update(update): .applicationUpdate(update.id)
        case let .package(package): .homebrewPackage(package.id)
        case let .adopt(item): .homebrewAdoption(item.id)
        case let .restore(record): .historyRestore(record.id)
        }
    }
}
