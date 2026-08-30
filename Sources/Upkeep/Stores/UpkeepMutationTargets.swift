import Foundation

@MainActor
extension UpkeepStore {
    func mutationTargets(for app: InstalledApp) -> Set<MutationTarget> {
        var targets: Set<MutationTarget> = [.applicationPath(app.url.resolvingSymlinksInPath().standardizedFileURL.path)]
        if let identifier = app.bundleIdentifier { targets.insert(.bundleIdentifier(identifier)) }
        return targets
    }

    func mutationTargets(for item: BatchUpdateItem) -> Set<MutationTarget> {
        switch item {
        case let .application(update):
            var targets = mutationTargets(for: update.app)
            if let token = update.homebrewToken { targets.insert(.homebrew("Cask:\(token)")) }
            return targets
        case let .homebrew(package):
            var targets: Set<MutationTarget> = [.homebrew(package.id)]
            if package.kind == .cask, let app = homebrewPackageApp(for: package) {
                targets.formUnion(mutationTargets(for: app))
            }
            return targets
        case let .developer(package):
            return [.developerEnvironment(URL(fileURLWithPath: package.executablePath).standardizedFileURL.path)]
        case let .model(model): return [.model(model.id)]
        }
    }

    func mutationTargets(for item: AdoptableApp) -> Set<MutationTarget> {
        mutationTargets(for: item.app).union([.homebrew("Cask:\(item.caskToken)")])
    }

    func mutationTargets(for record: UpdateRecord) -> Set<MutationTarget> {
        guard let path = record.originalAppPath else { return [] }
        let url = URL(fileURLWithPath: path)
        var targets: Set<MutationTarget> = [.applicationPath(url.resolvingSymlinksInPath().standardizedFileURL.path)]
        if let app = apps.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            targets.formUnion(mutationTargets(for: app))
        } else if let identifier = Bundle(url: url)?.bundleIdentifier {
            targets.insert(.bundleIdentifier(identifier))
        }
        return targets
    }

    func mutationTargets(for operation: OperationID) -> Set<MutationTarget> {
        switch operation {
        case let .applicationUpdate(id):
            return app(forID: id).map { mutationTargets(for: $0) } ?? []
        case let .homebrewPackage(id):
            return homebrewPackage(forID: id).map { mutationTargets(for: .homebrew($0)) } ?? []
        case let .homebrewAdoption(id):
            return adoptableApp(forID: id).map { mutationTargets(for: $0) } ?? []
        case let .developerPackage(id):
            return developerPackage(forID: id).map { mutationTargets(for: .developer($0)) } ?? []
        case let .localModel(id): return [.model(id)]
        case let .historyRestore(id):
            return updateHistory.first(where: { $0.id == id }).map { mutationTargets(for: $0) } ?? []
        default: return []
        }
    }

    func mutationTargets(for confirmation: RunningAppConfirmation) -> Set<MutationTarget> {
        switch confirmation.action {
        case let .update(update): return mutationTargets(for: .application(update))
        case let .package(package): return mutationTargets(for: .homebrew(package))
        case let .adopt(item), let .updateAdoptable(item): return mutationTargets(for: item)
        case let .restore(record): return mutationTargets(for: record)
        case .allPackages:
            return Set(homebrewPackages.filter { $0.isOutdated && !isExcluded($0) }
                .flatMap { mutationTargets(for: .homebrew($0)) })
        }
    }
}
