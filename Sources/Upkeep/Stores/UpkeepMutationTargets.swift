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
            if let token = update.homebrewToken {
                targets.insert(.homebrew("Cask:\(token)"))
                targets.insert(.packageEnvironment("homebrew"))
            }
            return targets
        case let .homebrew(package):
            var targets: Set<MutationTarget> = [.homebrew(package.id), .packageEnvironment("homebrew")]
            if package.kind == .cask, let app = homebrewPackageApp(for: package) {
                targets.formUnion(mutationTargets(for: app))
            }
            return targets
        case let .developer(package):
            var targets: Set<MutationTarget> = [.developerEnvironment(URL(fileURLWithPath: package.executablePath).resolvingSymlinksInPath().standardizedFileURL.path),
                    .packageEnvironment(package.manager.assetName.lowercased())]
            targets.formUnion(runtimeOwnerTargets(package.executablePath))
            if [.node, .npm, .pnpm, .yarn].contains(package.manager) {
                targets.insert(nodeDirectoryTarget(package.executablePath))
                targets.formUnion(nodeRuntimeTargets(package.executablePath))
            }
            if package.manager == .cargo || package.manager == .rustup {
                // Cargo may use a toolchain executable rather than the Rustup
                // proxy. Toolchain replacement/removal affects both paths.
                targets.insert(.packageEnvironment("rust-toolchain"))
            }
            if [.python, .pipx, .uv].contains(package.manager) {
                targets.insert(.packageEnvironment("python-runtime"))
            }
            if package.manager == .asdf || package.manager == .mise {
                switch (package.registryIdentifier ?? package.name).lowercased() {
                case "python", "python3": targets.insert(.packageEnvironment("python-runtime"))
                case "rust": targets.insert(.packageEnvironment("rust-toolchain"))
                case "ruby": targets.insert(.packageEnvironment("rubygems"))
                default: break
                }
            }
            return targets
        case let .model(model): return [.model(model.id), .modelRuntime(model.runtime)]
        }
    }

    func mutationTargets(for item: AdoptableApp) -> Set<MutationTarget> {
        mutationTargets(for: item.app).union([.homebrew("Cask:\(item.caskToken)"), .packageEnvironment("homebrew")])
    }

    func mutationTargets(for target: PackageCleanupTarget) -> Set<MutationTarget> {
        var targets: Set<MutationTarget> = [.packageEnvironment(target.kind.rawValue.lowercased()),
         .developerEnvironment(URL(fileURLWithPath: target.executablePath).resolvingSymlinksInPath().standardizedFileURL.path)]
        targets.formUnion(runtimeOwnerTargets(target.executablePath))
        if target.kind == .npm || target.kind == .pnpm {
            targets.insert(nodeDirectoryTarget(target.executablePath))
            targets.formUnion(nodeRuntimeTargets(target.executablePath))
        }
        if target.kind == .uv { targets.insert(.packageEnvironment("python-runtime")) }
        return targets
    }

    private func nodeDirectoryTarget(_ executable: String) -> MutationTarget {
        // Resolve the directory, not the executable symlink: npm and pnpm may
        // point at different package scripts within the same Node installation.
        let directory = URL(fileURLWithPath: executable).deletingLastPathComponent()
            .resolvingSymlinksInPath().standardizedFileURL.path
        return .developerEnvironment("node-bin:\(directory)")
    }

    private func nodeRuntimeTargets(_ executable: String) -> Set<MutationTarget> {
        var targets: Set<MutationTarget> = []
        let runtime = developerNodeRuntimePath(for: URL(fileURLWithPath: executable))
        if let runtime { targets.insert(.developerEnvironment("node-runtime:\(runtime)")) }
        for path in [executable, runtime].compactMap({ $0 }) {
            targets.formUnion(runtimeOwnerTargets(path))
            if let root = nvmDirectory(for: path) {
                let canonical = URL(fileURLWithPath: root).resolvingSymlinksInPath().standardizedFileURL.path
                targets.insert(.developerEnvironment("nvm-root:\(canonical)"))
            }
        }
        return targets
    }

    private func runtimeOwnerTargets(_ executable: String) -> Set<MutationTarget> {
        Set(runtimeEnvironmentOwners(for: executable).map(MutationTarget.packageEnvironment))
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
        case let .localModel(id):
            return localModels.first { $0.id == id }.map { mutationTargets(for: .model($0)) } ?? [.model(id)]
        case let .localModelRuntimeScan(runtime): return [.modelRuntime(runtime)]
        case .localModelScan: return Set(LocalModelRuntime.allCases.map(MutationTarget.modelRuntime))
        case .homebrewInventoryScan, .homebrewCatalogScan: return [.packageEnvironment("homebrew")]
        case let .historyRestore(id):
            return updateHistory.first(where: { $0.id == id }).map { mutationTargets(for: $0) } ?? []
        default: return []
        }
    }

    func mutationTargets(for confirmation: RunningAppConfirmation) -> Set<MutationTarget> {
        switch confirmation.action {
        case let .update(update): return mutationTargets(for: .application(update))
        case let .package(package): return mutationTargets(for: .homebrew(package))
        case let .adopt(item): return mutationTargets(for: item)
        case let .restore(record): return mutationTargets(for: record)
        }
    }
}
