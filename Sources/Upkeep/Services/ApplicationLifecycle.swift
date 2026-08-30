import AppKit

struct RunningApplications {
    let identifiers: Set<String>
    let paths: Set<String>

    func contains(_ app: InstalledApp) -> Bool {
        if let identifier = app.bundleIdentifier, identifiers.contains(identifier) { return true }
        return paths.contains(app.url.resolvingSymlinksInPath().standardizedFileURL.path)
    }
}

@MainActor
protocol ApplicationLifecycleManaging: Sendable {
    func runningApplications() -> RunningApplications
    func quit(_ apps: [InstalledApp]) async throws
}

struct WorkspaceApplicationLifecycle: ApplicationLifecycleManaging {
    func runningApplications() -> RunningApplications {
        let apps = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        return RunningApplications(
            identifiers: Set(apps.compactMap(\.bundleIdentifier)),
            paths: Set(apps.compactMap(\.bundleURL).map { $0.resolvingSymlinksInPath().standardizedFileURL.path })
        )
    }

    func quit(_ apps: [InstalledApp]) async throws {
        guard !apps.contains(where: \.isUpkeep) else { throw LifecycleError.cannotQuitUpkeep }
        let targets = RunningApplications(
            identifiers: Set(apps.compactMap(\.bundleIdentifier)),
            paths: Set(apps.map { $0.url.resolvingSymlinksInPath().standardizedFileURL.path })
        )
        let processes = NSWorkspace.shared.runningApplications.filter { process in
            if let identifier = process.bundleIdentifier, targets.identifiers.contains(identifier) { return true }
            return process.bundleURL.map { targets.paths.contains($0.resolvingSymlinksInPath().standardizedFileURL.path) } ?? false
        }
        guard !processes.contains(where: { $0.processIdentifier == ProcessInfo.processInfo.processIdentifier }) else {
            throw LifecycleError.cannotQuitUpkeep
        }
        for process in processes where !process.isTerminated { process.terminate() }
        for _ in 0..<40 {
            if apps.allSatisfy({ !runningApplications().contains($0) }) { return }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw LifecycleError.couldNotQuit(apps.filter { runningApplications().contains($0) }.map(\.name))
    }

    enum LifecycleError: LocalizedError {
        case cannotQuitUpkeep
        case couldNotQuit([String])
        var errorDescription: String? {
            switch self {
            case .cannotQuitUpkeep: "Upkeep cannot quit itself to perform an update. Download its signed release and replace it after quitting."
            case let .couldNotQuit(names): "Could not quit \(names.formatted()). Quit these apps manually, then try again."
            }
        }
    }
}
