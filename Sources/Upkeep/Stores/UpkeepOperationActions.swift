import Foundation

@MainActor
extension UpkeepStore {
    func canRetryOperation(_ operation: OperationID) -> Bool {
        guard !isWorking(operation) else { return false }
        switch operation {
        case let .applicationUpdate(id):
            return updates.contains { $0.id == id && ($0.canInstallDirectly || $0.homebrewToken != nil) && !isExcluded($0) }
        case let .homebrewPackage(id):
            return homebrewPackages.contains { $0.id == id && $0.isOutdated && !isExcluded($0) }
        case let .homebrewAdoption(id): return adoptableApps.contains { $0.id == id }
        case let .developerPackage(id):
            return developerPackages.contains { $0.id == id && $0.isOutdated && $0.canUpdateAutomatically && !isExcluded($0) }
        case let .localModel(id): return localModels.contains { $0.id == id && $0.isOutdated && !isExcluded($0) }
        default: return false
        }
    }

    func retryCompletedOperation(_ operation: OperationID) async {
        guard canRetryOperation(operation) else { return }
        switch operation {
        case let .applicationUpdate(id):
            if let update = updates.first(where: { $0.id == id }) { await performUpdate(update) }
        case let .homebrewPackage(id):
            if let package = homebrewPackages.first(where: { $0.id == id }) { await updatePackage(package) }
        case let .homebrewAdoption(id):
            if let item = adoptableApps.first(where: { $0.id == id }) { await adopt(item) }
        case let .developerPackage(id):
            if let package = developerPackages.first(where: { $0.id == id }) { await updateDeveloperPackage(package) }
        case let .localModel(id):
            if let model = localModels.first(where: { $0.id == id }) { await updateLocalModel(model) }
        default: break
        }
    }

    func canCheckOperation(_ operation: OperationID) -> Bool {
        switch operation {
        case let .applicationUpdate(id), let .homebrewAdoption(id): apps.contains { $0.id == id }
        case let .homebrewPackage(id): homebrewPackages.contains { $0.id == id }
        case let .developerPackage(id): developerPackages.contains { $0.id == id }
        case let .localModel(id): localModels.contains { $0.id == id }
        default: false
        }
    }

    func checkCompletedOperation(_ operation: OperationID) async {
        guard !isWorking(operation) else { return }
        switch operation {
        case let .applicationUpdate(id), let .homebrewAdoption(id):
            if let app = apps.first(where: { $0.id == id }) { await refresh(app) }
        case let .homebrewPackage(id):
            if let package = homebrewPackages.first(where: { $0.id == id }) { await refresh(package) }
        case let .developerPackage(id):
            if let package = developerPackages.first(where: { $0.id == id }) {
                await scanDeveloperPackages(manager: package.manager)
            }
        case let .localModel(id):
            if let model = localModels.first(where: { $0.id == id }) { _ = await scanLocalModels(runtime: model.runtime) }
        default: break
        }
    }
}
