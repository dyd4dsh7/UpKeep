import Foundation

@MainActor
extension UpkeepStore {
    func beginUpdateActivity(_ operation: OperationID, targets: Set<MutationTarget>, phase: UpdatePhase) {
        updateExecutionState.activities[operation] = UpdateActivity(targets: targets, phase: phase)
    }

    func setUpdatePhase(_ phase: UpdatePhase, for operation: OperationID) {
        updateExecutionState.activities[operation]?.phase = phase
    }

    func endUpdateActivity(_ operation: OperationID) {
        updateExecutionState.activities[operation] = nil
    }

    func updatePhase(for operation: OperationID) -> UpdatePhase? {
        if let activity = updateExecutionState.activities[operation] { return activity.phase }
        let targets = mutationTargets(for: operation)
        // Application and cask rows can represent the same install. A different
        // developer package sharing a manager is only waiting for that manager.
        let sharedTargets = targets.filter {
            if case .developerEnvironment = $0 { return false }
            return true
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
        case let .adopt(item), let .updateAdoptable(item): mutationTargets(for: item)
        case .allPackages:
            Set(homebrewPackages.filter { $0.isOutdated && !isExcluded($0) }
                .flatMap { mutationTargets(for: .homebrew($0)) })
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
        case let .adopt(item), let .updateAdoptable(item): .homebrewAdoption(item.id)
        case .allPackages: .homebrewBatch
        case let .restore(record): .historyRestore(record.id)
        }
    }
}
