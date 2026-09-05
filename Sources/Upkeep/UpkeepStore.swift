import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers
import UserNotifications

struct RunningAppConfirmation: Identifiable {
    enum Action {
        case update(AvailableUpdate)
        case package(HomebrewPackage)
        case adopt(AdoptableApp)
        case updateAdoptable(AdoptableApp)
        case allPackages
        case restore(UpdateRecord)
    }

    let id = UUID()
    let apps: [InstalledApp]
    let action: Action

    var title: String { apps.count == 1 ? "Quit \(apps[0].name) and Continue?" : "Quit Running Apps and Continue?" }
    var message: String {
        let names = apps.map(\.name).formatted()
        return "\(names) \(apps.count == 1 ? "is" : "are") currently running. Upkeep must quit \(apps.count == 1 ? "it" : "them") before changing the application files and will reopen \(apps.count == 1 ? "it" : "them") after it finishes."
    }
    var buttonTitle: String {
        switch action {
        case .adopt: "Quit and Adopt"
        case .allPackages: "Quit Apps and Update"
        case .restore: "Quit and Restore"
        default: "Quit and Update"
        }
    }
}

struct HomebrewAuthorizationConfirmation: Identifiable {
    enum Action {
        case update(AvailableUpdate)
        case package(HomebrewPackage)
        case adopt(AdoptableApp)
        case updateAdoptable(AdoptableApp)
        case allPackages
    }

    let id = UUID()
    let itemName: String
    let action: Action
}

private enum BatchUpdateError: LocalizedError {
    case couldNotOpen(String)

    var errorDescription: String? {
        switch self {
        case let .couldNotOpen(source): "Could not open \(source)."
        }
    }
}

@MainActor
final class UpkeepStore: ObservableObject {
    let settings: AppSettings
    private let dependencies: UpkeepDependencies
    let library = UpkeepLibraryState()
    var navigation = UpkeepNavigationState()
    let scanState: UpkeepScanState
    let updateExecutionState = UpkeepUpdateExecutionState()
    let mutationCoordinator = MutationCoordinator()
    var diagnostics = UpkeepDiagnosticsState()

    private var periodicTask: Task<Void, Never>?
    private var scanRequested = false
    private var scanWaiters: [CheckedContinuation<Void, Never>] = []
    private var developerVersionRequestID: UUID?
    private var runningApplicationObservers = Set<AnyCancellable>()
    private var featureStateObservers = Set<AnyCancellable>()
    private var isRootChangeScheduled = false
    private var didStart = false
    private let startedAt = Date()
    private var versionCache: [String: [String]] = [:]
    private var versionCacheRequests: [String: UUID] = [:]
    private var externalVerificationTasks: [String: Task<Void, Never>] = [:]

    init(
        settings: AppSettings = AppSettings(),
        dependencies: UpkeepDependencies = .live
    ) {
        self.settings = settings
        self.dependencies = dependencies
        self.scanState = UpkeepScanState(lastChecked: settings.lastCompletedScanDate)
        bindFeatureState()
    }

    private func bindFeatureState() {
        [library.objectWillChange, navigation.objectWillChange, scanState.objectWillChange,
         updateExecutionState.objectWillChange, diagnostics.objectWillChange, mutationCoordinator.objectWillChange]
            .forEach { publisher in
                publisher
                    .sink { [weak self] _ in self?.scheduleRootChange() }
                    .store(in: &featureStateObservers)
            }
    }

    /// Child feature objects can update several related properties in one
    /// synchronous phase. Publish once after that phase so SwiftUI does not
    /// invalidate the entire root view tree for every individual assignment.
    private func scheduleRootChange() {
        guard !isRootChangeScheduled else { return }
        isRootChangeScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isRootChangeScheduled = false
            objectWillChange.send()
        }
    }

    func isWorking(_ operation: OperationID) -> Bool {
        updateExecutionState.activeOperations.contains(operation)
            || mutationCoordinator.isBusy(mutationTargets(for: operation))
    }

    func isUpdating(_ update: AvailableUpdate) -> Bool {
        if mutationCoordinator.isBusy(mutationTargets(for: .application(update))) { return true }
        if isWorking(.applicationUpdate(update.id)) { return true }
        guard let token = update.homebrewToken else { return false }
        if let package = homebrewPackages.first(where: { $0.kind == .cask && $0.token == token }) {
            return isWorking(.homebrewPackage(package.id))
        }
        if let item = adoptableApps.first(where: { $0.caskToken == token && $0.app.id == update.app.id }) {
            return isWorking(.homebrewAdoption(item.id))
        }
        return false
    }

    var isDeveloperScanRunning: Bool {
        updateExecutionState.activeOperations.contains {
            if case .developerScan = $0 { return true }
            return false
        }
    }

    var visibleUpdates: [AvailableUpdate] { updates.filter { !isExcluded($0) } }
    var filteredUpdates: [AvailableUpdate] { matching(visibleUpdates, name: { $0.app.name }) }
    var filteredApps: [InstalledApp] { matching(apps, name: \InstalledApp.name) }
    var filteredAdoptableApps: [AdoptableApp] { matching(adoptableApps, name: { $0.app.name }) }
    var outdatedPackageCount: Int { homebrewPackages.count { $0.isOutdated && !isExcluded($0) } }
    var outdatedDeveloperPackageCount: Int { developerPackages.count { $0.isOutdated && !isExcluded($0) } }
    var outdatedLocalModelCount: Int { localModels.count { $0.isOutdated && !isExcluded($0) } }
    var totalUpdateCount: Int {
        // Badges do not include developer packages or models. Avoid comparing
        // their versions and building their batch-plan arrays on every count read.
        UpdatePlan.primaryUpdateCount(
            applicationUpdates: visibleUpdates,
            homebrewUpdates: visibleHomebrewUpdates,
            macOSUpdates: macOSUpdates
        )
    }
    var filteredDeveloperPackages: [DeveloperPackage] {
        matching(developerPackages.filter {
            (settings.showCurrentDeveloperPackages || $0.isOutdated) &&
            developerManagerFilter.includes($0.manager)
        }, name: { $0.name })
    }

    var packageCleanupTargets: [PackageCleanupTarget] {
        PackageCleanupTarget.available(
            homebrewURL: HomebrewClient.brewURL,
            installedManagers: installedDeveloperManagers,
            packages: developerPackages
        )
    }

    func scanCleanup(_ target: PackageCleanupTarget, onError: ((String) -> Void)? = nil) async -> PackageCleanupEstimate? {
        let operationID = OperationID.packageCleanup(target.id)
        guard !isWorking(operationID) else { return nil }
        updateExecutionState.activeOperations.insert(operationID)
        defer { updateExecutionState.activeOperations.remove(operationID) }

        let startedAt = Date()
        errorMessage = nil
        do {
            let estimate = try await dependencies.packageCleanup.scan(target)
            DiagnosticsStore.shared.record(.info, category: .command, "Package cleanup scan completed", metadata: [
                "Manager": target.title,
                "Scanned size": ByteCountFormatter.string(fromByteCount: estimate.bytes, countStyle: .file),
                "Duration": formattedDiagnosticDuration(since: startedAt)
            ])
            refreshDiagnostics()
            return estimate
        } catch {
            if let onError { onError(error.localizedDescription) }
            else { errorMessage = error.localizedDescription }
            DiagnosticsStore.shared.record(.error, category: .command, "Package cleanup scan failed", metadata: [
                "Manager": target.title,
                "Duration": formattedDiagnosticDuration(since: startedAt),
                "Error": error.localizedDescription
            ])
            refreshDiagnostics()
            return nil
        }
    }

    func cleanUp(_ target: PackageCleanupTarget, onError: ((String) -> Void)? = nil) async -> PackageCleanupResult? {
        let operationID = OperationID.packageCleanup(target.id)
        guard !isWorking(operationID) else { return nil }
        updateExecutionState.activeOperations.insert(operationID)
        defer { updateExecutionState.activeOperations.remove(operationID) }

        let startedAt = Date()
        errorMessage = nil
        do {
            let result = try await dependencies.packageCleanup.cleanup(target)
            DiagnosticsStore.shared.record(.info, category: .command, "Package cleanup completed", metadata: [
                "Manager": target.title,
                "Command": target.commandDescription,
                "Freed": ByteCountFormatter.string(fromByteCount: result.bytesFreed, countStyle: .file),
                "Duration": formattedDiagnosticDuration(since: startedAt)
            ])
            refreshDiagnostics()
            return result
        } catch {
            if let onError { onError(error.localizedDescription) }
            else { errorMessage = error.localizedDescription }
            DiagnosticsStore.shared.record(.error, category: .command, "Package cleanup failed", metadata: [
                "Manager": target.title,
                "Command": target.commandDescription,
                "Duration": formattedDiagnosticDuration(since: startedAt),
                "Error": error.localizedDescription
            ])
            refreshDiagnostics()
            return nil
        }
    }

    var visibleOutdatedLocalModels: [LocalLLMModel] {
        localModels.filter { $0.isOutdated && !isExcluded($0) }
    }

    var availableBatchUpdateItems: [BatchUpdateItem] { updatePlan.batchItems }

    var recommendedBatchUpdateItems: [BatchUpdateItem] { updatePlan.recommendedBatchItems }

    private var visibleHomebrewUpdates: [HomebrewPackage] {
        homebrewPackages.filter { $0.isOutdated && !isExcluded($0) }
    }

    var updatePlan: UpdatePlan {
        UpdatePlan(
            applicationUpdates: visibleUpdates,
            homebrewUpdates: visibleHomebrewUpdates,
            macOSUpdates: macOSUpdates,
            developerUpdates: developerPackages.filter {
                $0.isOutdated && $0.canUpdateAutomatically && !isExcluded($0)
            },
            modelUpdates: visibleOutdatedLocalModels
        )
    }

    var filteredHomebrewPackages: [HomebrewPackage] {
        let scoped = homebrewPackages.filter { package in
            switch homebrewFilter {
            case .all: true
            case .updates: package.isOutdated && !isExcluded(package)
            case .requested: !package.isDependency
            case .dependencies: package.isDependency
            case .casks: package.kind == .cask
            case .unmapped: package.kind == .cask && matchingApp(for: package) == nil
            }
        }
        return matching(scoped, name: { $0.displayName })
    }

    func app(forID id: String) -> InstalledApp? {
        library.app(forID: id)
    }

    func update(for app: InstalledApp) -> AvailableUpdate? {
        library.update(for: app.id)
    }

    func visibleUpdate(for app: InstalledApp) -> AvailableUpdate? {
        guard let update = library.update(for: app.id), !isExcluded(update) else { return nil }
        return update
    }

    func homebrewPackage(forID id: String) -> HomebrewPackage? {
        library.homebrewPackage(forID: id)
    }

    func adoptableApp(forID id: String) -> AdoptableApp? {
        library.adoptableApp(forID: id)
    }

    func adoptableApp(for app: InstalledApp) -> AdoptableApp? {
        library.adoptableApp(forAppID: app.id)
    }

    func developerPackage(forID id: String) -> DeveloperPackage? {
        library.developerPackage(forID: id)
    }

    func localModel(forID id: String) -> LocalLLMModel? {
        library.localModel(forID: id)
    }

    func applications(for destination: SidebarDestination) -> [InstalledApp] {
        apps.filter { app in
            switch destination {
            case .allApps: true
            case .appStore: app.updateManagement == .appStore
            case .testFlight: app.updateManagement == .testFlight
            case .setapp: app.updateManagement == .setapp
            case .microsoftAutoUpdate: app.updateManagement == .microsoftAutoUpdate
            case .steam: app.updateManagement == .steam
            case .otherUpdaters:
                [.adobeCreativeCloud, .jetBrainsToolbox, .spotify, .discord, .epicGames, .tailscale]
                    .contains(app.updateManagement)
            case .sparkle: app.updateManagement == .direct && app.sparkleFeedURL != nil
            case .homebrewApps: homebrewPackage(for: app) != nil
            case .github: app.updateManagement == .direct && app.githubRepository != nil
            case .noSource:
                sources(for: app).isEmpty
                    && !app.updateManagement.isExternallyManaged
                    && !app.hasBuiltInUpdater
            default: false
            }
        }
    }

    func source(for app: InstalledApp) -> UpdateSource? {
        library.update(for: app.id)?.source ?? sources(for: app).first
    }

    func sources(for app: InstalledApp) -> [UpdateSource] {
        var detected = Set<UpdateSource>()
        let update = library.update(for: app.id)
        if let update {
            detected.formUnion(update.candidates.map(\.source))
        }
        if app.updateManagement == .appStore { detected.insert(.appStore) }
        if homebrewPackage(for: app) != nil { detected.insert(.homebrew) }
        if app.updateManagement == .direct {
            if app.mozillaUpdateChannel != nil { detected.insert(.developer) }
            if app.sparkleFeedURL != nil { detected.insert(.sparkle) }
            if app.githubRepository != nil { detected.insert(.github) }
        }
        let preferredOrder: [UpdateSource] = [.appStore, .homebrew, .developer, .sparkle, .github]
        let ordered = preferredOrder.filter(detected.contains)
        guard let primary = update?.source else { return ordered }
        return [primary] + ordered.filter { $0 != primary }
    }

    func count(for destination: SidebarDestination) -> Int {
        switch destination {
        case .updates: totalUpdateCount
        case .allApps: apps.count
        case .adoptable: adoptableApps.count
        case .homebrewPackages: homebrewPackages.count
        case .macOSUpdates: macOSUpdates.count
        case .history: updateHistory.count
        case .developerPackages: developerPackages.count
        case .localModels: localModels.count
        default: applications(for: destination).count
        }
    }

    func scan() async {
        if isScanning {
            scanRequested = true
            await withCheckedContinuation { scanWaiters.append($0) }
            return
        }
        isScanning = true
        repeat {
            scanRequested = false
            await scanOnce()
        } while scanRequested
        isScanning = false
        let waiters = scanWaiters
        scanWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        if didStart { scheduleNextRefresh() }
    }

    private func scanOnce() async {
        errorMessage = nil
        let previousCount = totalUpdateCount
        let report = await dependencies.scanner.scan(settings: settings.scanSettings)
        scanState.completedCheckState = UpdateCheckState.completed(report: report, settings: settings.scanSettings)
        scanState.macOSStatus = report.macOSUpdatesStatus
        scanState.failedAppSources = report.failedAppSources
        apps = report.apps
        for app in apps {
            settings.migrateExclusion(from: legacyExclusionKey(for: app), to: exclusionKey(for: app))
        }
        updates = mergedUpdates(from: report)
        switch report.homebrewInventoryStatus {
        case .disabled:
            homebrewPackages = []
            adoptableApps = []
        case .failed:
            break
        case .succeeded:
            homebrewPackages = report.homebrewPackages
            if report.homebrewCatalogStatus == .succeeded { adoptableApps = report.adoptableApps }
            else if report.homebrewCatalogStatus == .disabled { adoptableApps = [] }
        }
        macOSUpdates = mergedMacOSUpdates(from: report)
        updateHistory = await dependencies.history.records()
        developerPackages = mergedDeveloperPackages(from: report)
        installedDeveloperManagers = report.installedDeveloperManagers
        localModels = mergedLocalModels(from: report)
        settings.recordChecks(
            for: report.apps.map(exclusionKey(for:))
                + report.homebrewPackages.map(exclusionKey(for:))
                + report.developerPackages.map(exclusionKey(for:))
                + report.localModels.map(exclusionKey(for:)),
            at: report.checkedAt
        )
        scanWarnings = report.warnings
        if !developerManagerFilter.isAvailable(in: installedDeveloperManagers) {
            developerManagerFilter = .all
        }
        lastChecked = report.checkedAt
        settings.lastCompletedScanDate = report.checkedAt
        if selectedPackageID == nil { selectedPackageID = filteredHomebrewPackages.first?.id }
        if selectedDeveloperPackageID == nil || !developerPackages.contains(where: { $0.id == selectedDeveloperPackageID }) {
            selectedDeveloperPackageID = developerPackages.first?.id
            selectedDeveloperVersion = developerPackages.first?.latestVersion ?? ""
        }
        if selectedLocalModelID == nil || !localModels.contains(where: { $0.id == selectedLocalModelID }) {
            selectedLocalModelID = localModels.first?.id
        }
        refreshDiagnostics()
        notifyIfNeeded(previousCount: previousCount)
    }

    /// Local verification also detects a same-version Intel-to-ARM replacement.
    func verifyAppleSiliconMigration(_ app: InstalledApp) async -> AppleSiliconVerification {
        let installed = await dependencies.applicationDiscovery.discover(at: app.url)
        let result = AppleSiliconVerification.result(original: app, installed: installed)
        guard let installed, result != .differentApp else { return result }
        if let index = apps.firstIndex(where: { $0.id == app.id }) { apps[index] = installed }
        if selectedApp?.id == app.id { selectedApp = installed }
        if let index = updates.firstIndex(where: { $0.app.id == app.id }) {
            let candidates = updates[index].candidates.filter { $0.isNewer(than: installed) }
            if candidates.isEmpty { updates.remove(at: index) }
            else { updates[index] = AvailableUpdate(app: installed, candidates: candidates) }
        }
        adoptableApps = adoptableApps.map { item in
            guard item.app.id == app.id else { return item }
            return AdoptableApp(app: installed, caskToken: item.caskToken, caskVersion: item.caskVersion)
        }
        return result
    }

    func refresh(_ app: InstalledApp) async {
        let operationID = OperationID.applicationRefresh(app.id)
        guard !isWorking(operationID) else { return }
        updateExecutionState.activeOperations.insert(operationID)
        defer { updateExecutionState.activeOperations.remove(operationID) }

        let refreshedApp = await dependencies.applicationDiscovery.discover(at: app.url) ?? app
        if let index = apps.firstIndex(where: { $0.id == app.id }) { apps[index] = refreshedApp }
        if selectedApp?.id == app.id { selectedApp = refreshedApp }

        let report = await dependencies.scanner.scan(app: refreshedApp, settings: settings.scanSettings)
        scanState.failedAppSources[app.id] = report.failedSources.isEmpty ? nil : report.failedSources
        var candidates = (updates.first(where: { $0.app.id == app.id })?.candidates ?? [])
            .filter { $0.isNewer(than: refreshedApp) }
        let enabledSources = enabledUpdateSources(for: refreshedApp)
        candidates.removeAll { candidate in
            candidate.source != .homebrew
                && enabledSources.contains(candidate.source)
                && !report.failedSources.contains(candidate.source)
        }
        candidates.append(contentsOf: report.updates.flatMap(\.candidates))

        if let existingPackage = homebrewPackage(for: refreshedApp), settings.checkHomebrew {
            do {
                if let refreshedPackage = try await dependencies.homebrew.package(
                    token: existingPackage.token,
                    kind: existingPackage.kind,
                    includePrereleases: settings.includePrereleaseUpdates
                ) {
                    replaceHomebrewPackage(refreshedPackage)
                    candidates.removeAll { $0.source == .homebrew && !$0.requiresHomebrewAdoption }
                    if refreshedPackage.reconciled(with: refreshedApp).isOutdated {
                        candidates.append(UpdateCandidate(
                            availableVersion: refreshedPackage.currentVersion,
                            source: .homebrew,
                            releaseNotes: nil,
                            actionURL: nil,
                            homebrewToken: refreshedPackage.token,
                            sourcePrereleaseChannel: nil,
                            requiresHomebrewAdoption: false
                        ))
                    }
                }
            } catch {
                errorMessage = "Could not refresh \(existingPackage.displayName): \(error.localizedDescription)"
            }
        }

        candidates = candidates.filter {
            !$0.requiresHomebrewAdoption
                || (refreshedApp.allowsHomebrewAdoption
                    && !settings.isHomebrewAdoptionIgnored(key: exclusionKey(for: refreshedApp)))
        }
        updates.removeAll { $0.app.id == app.id }
        if !candidates.isEmpty { updates.append(AvailableUpdate(app: refreshedApp, candidates: candidates)) }
        updates.sort { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending }

        let affectedSources = Set(enabledSources.map { source in
            switch source {
            case .appStore: ScanWarningSource.appStore.rawValue
            case .developer: ScanWarningSource.developer.rawValue
            case .sparkle: ScanWarningSource.sparkle.rawValue
            case .github: ScanWarningSource.github.rawValue
            case .homebrew: ScanWarningSource.homebrew.rawValue
            }
        })
        scanWarnings.removeAll { warning in
            affectedSources.contains(warning.source.rawValue) && warning.itemNames.contains(app.name)
        }
        scanWarnings.append(contentsOf: report.warnings)
        lastChecked = Date()
        settings.lastCompletedScanDate = lastChecked
        settings.recordCheck(for: exclusionKey(for: refreshedApp), at: lastChecked ?? Date())
        refreshDiagnostics()
    }

    func refresh(_ package: HomebrewPackage) async {
        let operationID = OperationID.homebrewRefresh(package.id)
        guard !isWorking(operationID) else { return }
        updateExecutionState.activeOperations.insert(operationID)
        defer { updateExecutionState.activeOperations.remove(operationID) }
        do {
            guard let refreshed = try await dependencies.homebrew.package(
                token: package.token,
                kind: package.kind,
                includePrereleases: settings.includePrereleaseUpdates
            ) else {
                errorMessage = "Homebrew no longer reports \(package.displayName) as installed."
                return
            }
            replaceHomebrewPackage(refreshed)
            if let app = homebrewPackageApp(for: refreshed) { await refresh(app) }
            lastChecked = Date()
            settings.lastCompletedScanDate = lastChecked
            settings.recordCheck(for: exclusionKey(for: refreshed), at: lastChecked ?? Date())
            refreshDiagnostics()
        } catch {
            errorMessage = "Could not refresh \(package.displayName): \(error.localizedDescription)"
        }
    }

    func refresh(_ package: DeveloperPackage) async {
        let operationID = OperationID.developerRefresh(package.id)
        guard !isWorking(operationID) else { return }
        updateExecutionState.activeOperations.insert(operationID)
        defer { updateExecutionState.activeOperations.remove(operationID) }
        let versions = await dependencies.developerPackages.availableVersions(
            for: package,
            includePrereleases: settings.includePrereleaseUpdates
        )
        guard let latest = versions.first else {
            errorMessage = "No published versions were returned for \(package.name)."
            return
        }
        let refreshed = package.replacingLatestVersion(with: latest)
        if let index = developerPackages.firstIndex(where: { $0.id == package.id }) {
            developerPackages[index] = refreshed
        }
        versionCache[developerVersionCacheKey(for: refreshed)] = versions
        if selectedDeveloperPackageID == package.id {
            availableDeveloperVersions = versions
            selectedDeveloperVersion = latest
        }
        lastChecked = Date()
        settings.lastCompletedScanDate = lastChecked
        settings.recordCheck(for: exclusionKey(for: refreshed), at: lastChecked ?? Date())
        refreshDiagnostics()
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        refreshRunningApplications()
        observeRunningApplications()
        if settings.checkOnLaunch { await scan() }
        scheduleNextRefresh()
    }

    func scheduleNextRefresh() {
        periodicTask?.cancel()
        let nextDate = settings.refreshInterval.nextDate(
            after: lastChecked ?? startedAt,
            dailyTimeMinutes: settings.dailyRefreshTimeMinutes
        )
        nextScheduledCheck = nextDate
        guard let nextDate else {
            periodicTask = nil
            return
        }
        periodicTask = Task { [weak self] in
            let delay = max(0, nextDate.timeIntervalSinceNow)
            do { try await Task.sleep(for: .seconds(delay)) }
            catch { return }
            guard !Task.isCancelled, let self else { return }
            await self.scan()
        }
    }

    func scanDeveloperPackages(manager: DeveloperPackageManager?) async {
        let identifier = OperationID.developerScan(manager)
        guard !isWorking(identifier) else { return }
        updateExecutionState.activeOperations.insert(identifier)
        defer { updateExecutionState.activeOperations.remove(identifier) }
        let managers = manager.map { Set([$0]) } ?? settings.enabledDeveloperManagers
        let report = await dependencies.developerPackages.scan(
            enabledManagers: managers,
            includePrereleases: settings.includePrereleaseUpdates
        )
        let warnings = report.warnings.map { ScanWarning(source: .developerPackages, message: $0) }
        scanWarnings = (scanWarnings.filter { $0.source != .developerPackages } + warnings)
        if let manager {
            guard !report.failedManagers.contains(manager) else { return }
            developerPackages.removeAll {
                $0.manager == manager && !report.failedExecutablePaths.contains($0.executablePath)
            }
            developerPackages.append(contentsOf: report.packages)
            developerPackages = Array(Dictionary(grouping: developerPackages, by: \.id).compactMap { $0.value.first })
            developerPackages.sort { $0.manager.rawValue == $1.manager.rawValue ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.manager.rawValue < $1.manager.rawValue }
            if !installedDeveloperManagers.contains(manager), report.installedManagers.contains(manager) { installedDeveloperManagers.append(manager) }
            versionCache = versionCache.filter { !$0.key.hasPrefix("\(manager.rawValue):") }
        } else {
            developerPackages = mergeDeveloperPackageResults(
                fresh: report.packages, previous: developerPackages,
                failedManagers: report.failedManagers,
                failedExecutablePaths: report.failedExecutablePaths
            ).sorted(by: developerPackageOrder)
            installedDeveloperManagers = report.installedManagers
            versionCache.removeAll()
        }
        lastChecked = Date()
        settings.lastCompletedScanDate = lastChecked
        if let package = selectedDeveloperPackage { await loadAvailableVersions(for: package, force: true) }
    }

    func loadAvailableVersions(for package: DeveloperPackage, force: Bool = false) async {
        guard selectedDeveloperPackageID == package.id else { return }
        let requestID = UUID()
        developerVersionRequestID = requestID
        defer {
            if developerVersionRequestID == requestID {
                isLoadingDeveloperVersions = false
            }
        }
        if selectedDeveloperVersion != package.latestVersion {
            selectedDeveloperVersion = package.latestVersion
        }
        isLoadingDeveloperVersions = true
        if availableDeveloperVersions != [package.latestVersion] {
            availableDeveloperVersions = [package.latestVersion]
        }
        let versions = await developerVersions(for: package, force: force)
        guard !Task.isCancelled, developerVersionRequestID == requestID else { return }
        if selectedDeveloperPackageID == package.id {
            availableDeveloperVersions = versions
            selectedDeveloperVersion = versions.contains(package.latestVersion)
                ? package.latestVersion
                : (versions.first ?? package.currentVersion)
            isLoadingDeveloperVersions = false
        }
    }

    func developerVersions(for package: DeveloperPackage, force: Bool = false) async -> [String] {
        let cacheKey = developerVersionCacheKey(for: package)
        if !force, let cached = versionCache[cacheKey] {
            return cached
        }
        let requestID = UUID()
        versionCacheRequests[cacheKey] = requestID
        let versions = await dependencies.developerPackages.availableVersions(
            for: package, includePrereleases: settings.includePrereleaseUpdates
        )
        if versionCacheRequests[cacheKey] == requestID {
            versionCache[cacheKey] = versions
            versionCacheRequests[cacheKey] = nil
        }
        return versions
    }

    private func developerVersionCacheKey(for package: DeveloperPackage) -> String {
        "\(package.id)|prereleases:\(settings.includePrereleaseUpdates)"
    }

    func performUpdate(_ update: AvailableUpdate) async {
        guard !isUpdating(update) else { return }
        if update.homebrewToken != nil {
            pendingHomebrewAuthorizationConfirmation = HomebrewAuthorizationConfirmation(
                itemName: update.app.name,
                action: .update(update)
            )
            return
        }
        await continueApplicationUpdate(update)
    }

    private func continueApplicationUpdate(_ update: AvailableUpdate) async {
        if update.homebrewToken != nil || update.canInstallDirectly,
           queueRunningAppConfirmation(for: [update.app], action: .update(update)) { return }
        _ = await performApplicationUpdate(update)
    }

    private func performApplicationUpdate(_ update: AvailableUpdate) async -> Bool {
        await mutationCoordinator.withAccess(to: mutationTargets(for: .application(update)), otherwise: false) {
            await performApplicationUpdateUnlocked(update)
        }
    }

    private func performApplicationUpdateUnlocked(_ update: AvailableUpdate) async -> Bool {
        let operationID = OperationID.applicationUpdate(update.id)
        guard !isWorking(operationID) else { return false }
        updateExecutionState.activeOperations.insert(operationID)
        defer { updateExecutionState.activeOperations.remove(operationID) }
        return await performUpdateNow(update)
    }

    private func performUpdateNow(_ update: AvailableUpdate) async -> Bool {
        if let token = update.homebrewToken {
            if let package = homebrewPackages.first(where: { $0.kind == .cask && $0.token == token }) {
                return await updatePackageNow(package)
            } else if let item = adoptableApps.first(where: { $0.caskToken == token && $0.app.id == update.app.id }) {
                return await updateAdoptableAppNow(item)
            } else {
                let operationID = OperationID.applicationUpdate(update.id)
                beginUpdateActivity(operationID, targets: mutationTargets(for: .application(update)), phase: .backingUp)
                defer { endUpdateActivity(operationID) }
                let record: UpdateRecord
                do {
                    record = try await dependencies.history.prepareAppBackup(
                        app: update.app, toVersion: update.availableVersion, kind: .homebrew
                    )
                } catch {
                    errorMessage = "Could not create a rollback backup: \(error.localizedDescription)"
                    recordUpdateFailure(item: update.app.name, action: "Prepare rollback backup", error: error)
                    return false
                }
                setUpdatePhase(.updating, for: operationID)
                let succeeded = await execute(
                    label: update.app.name,
                    metadata: updateDiagnosticMetadata(update)
                ) { try await self.dependencies.homebrew.upgradeCask(token: token) }
                if succeeded {
                    var historyError: Error?
                    do { try await dependencies.history.add(record) }
                    catch { historyError = error }
                    setUpdatePhase(.refreshing, for: operationID)
                    await scan()
                    if let historyError { recordHistoryFailure(item: update.app.name, error: historyError) }
                    reconcileHomebrewUpdate(token: token, name: update.app.name)
                } else {
                    await dependencies.history.discardBackup(for: record)
                }
                return succeeded
            }
        } else if update.canInstallDirectly {
            let operationID = OperationID.applicationUpdate(update.id)
            beginUpdateActivity(operationID, targets: mutationTargets(for: .application(update)), phase: .backingUp)
            defer { endUpdateActivity(operationID) }
            let record: UpdateRecord
            do {
                record = try await dependencies.history.prepareAppBackup(
                    app: update.app, toVersion: update.availableVersion, kind: .app
                )
            } catch {
                errorMessage = "Could not create a rollback backup: \(error.localizedDescription)"
                recordUpdateFailure(
                    item: update.app.name,
                    action: "Prepare rollback backup",
                    error: error
                )
                return false
            }
            let succeeded = await execute(
                label: update.app.name,
                metadata: updateDiagnosticMetadata(update)
            ) {
                try await self.dependencies.directAppInstaller.install(update: update) { phase in
                    await self.setUpdatePhase(phase, for: operationID)
                }
            }
            if succeeded {
                var historyError: Error?
                do { try await dependencies.history.add(record) }
                catch { historyError = error }
                setUpdatePhase(.refreshing, for: operationID)
                await scan()
                if let historyError {
                    recordHistoryFailure(item: update.app.name, error: historyError)
                }
            } else {
                await dependencies.history.discardBackup(for: record)
            }
            return succeeded
        } else if let actionURL = update.externalActionURL {
            let operationID = OperationID.applicationUpdate(update.id)
            beginUpdateActivity(operationID, targets: mutationTargets(for: .application(update)), phase: .opening)
            defer { endUpdateActivity(operationID) }
            let opened = dependencies.externalOpener.open(actionURL)
            recordExternalUpdateAction(update, opened: opened)
            return opened
        }
        return false
    }

    func updatePackage(_ package: HomebrewPackage) async {
        if package.kind == .cask {
            pendingHomebrewAuthorizationConfirmation = HomebrewAuthorizationConfirmation(
                itemName: package.displayName,
                action: .package(package)
            )
            return
        }
        await continuePackageUpdate(package)
    }

    private func continuePackageUpdate(_ package: HomebrewPackage) async {
        if package.kind == .cask,
           let app = matchingApp(for: package),
           queueRunningAppConfirmation(for: [app], action: .package(package)) { return }
        _ = await updatePackageNow(package)
    }

    private func updatePackageNow(_ package: HomebrewPackage) async -> Bool {
        await mutationCoordinator.withAccess(to: mutationTargets(for: .homebrew(package)), otherwise: false) {
            await updatePackageUnlocked(package)
        }
    }

    private func updatePackageUnlocked(_ package: HomebrewPackage) async -> Bool {
        let operationID = OperationID.homebrewPackage(package.id)
        guard !isWorking(operationID) else { return false }
        updateExecutionState.activeOperations.insert(operationID)
        defer { updateExecutionState.activeOperations.remove(operationID) }
        beginUpdateActivity(operationID, targets: mutationTargets(for: .homebrew(package)), phase: .backingUp)
        defer { endUpdateActivity(operationID) }

        let record = await recoveryRecord(for: package)
        if package.kind == .cask, matchingApp(for: package) != nil, record == nil { return false }
        setUpdatePhase(.updating, for: operationID)
        let succeeded = await execute(label: package.displayName, metadata: [
            "Source": "Homebrew",
            "From": package.installedVersion,
            "To": package.currentVersion
        ]) { try await self.dependencies.homebrew.upgrade(package) }
        if succeeded {
            var historyError: Error?
            if let record {
                do { try await dependencies.history.add(record) }
                catch { historyError = error }
            }
            setUpdatePhase(.refreshing, for: operationID)
            await scan()
            if let historyError { recordHistoryFailure(item: package.displayName, error: historyError) }
            reconcileHomebrewUpdate(token: package.token, name: package.displayName)
        } else if let record {
            await dependencies.history.discardBackup(for: record)
        }
        return succeeded
    }

    func updateAllPackages() async {
        if homebrewPackages.contains(where: { $0.isOutdated && !isExcluded($0) && $0.kind == .cask }) {
            pendingHomebrewAuthorizationConfirmation = HomebrewAuthorizationConfirmation(
                itemName: "Homebrew cask updates",
                action: .allPackages
            )
            return
        }
        await continueAllPackageUpdates()
    }

    private func continueAllPackageUpdates() async {
        let runningApps = homebrewPackages
            .filter { $0.isOutdated && !isExcluded($0) && $0.kind == .cask }
            .compactMap(matchingApp(for:))
        if queueRunningAppConfirmation(for: runningApps, action: .allPackages) { return }
        _ = await updateAllPackagesNow()
    }

    private func updateAllPackagesNow() async -> Bool {
        await mutationCoordinator.withAccess(to: Set(homebrewPackages.filter { $0.isOutdated && !isExcluded($0) }.flatMap { mutationTargets(for: .homebrew($0)) }), otherwise: false) {
            await updateAllPackagesUnlocked()
        }
    }

    private func updateAllPackagesUnlocked() async -> Bool {
        let operationID = OperationID.homebrewBatch
        guard !isWorking(operationID) else { return false }
        let startedAt = Date()
        updateExecutionState.activeOperations.insert(operationID)
        errorMessage = nil
        defer { updateExecutionState.activeOperations.remove(operationID) }
        var failureMessage: String?
        let attempted = homebrewPackages.filter { $0.isOutdated && !isExcluded($0) }
        for package in attempted {
            let record = await recoveryRecord(for: package)
            if package.kind == .cask, matchingApp(for: package) != nil, record == nil {
                failureMessage = errorMessage ?? "Could not create a rollback backup for \(package.displayName)."
                break
            }
            do {
                try await dependencies.homebrew.upgrade(package)
            } catch {
                if let record { await dependencies.history.discardBackup(for: record) }
                failureMessage = error.localizedDescription
                break
            }
            if let record {
                do { try await dependencies.history.add(record) }
                catch {
                    failureMessage = "\(package.displayName) was updated, but its rollback history could not be saved: \(error.localizedDescription)"
                    recordHistoryFailure(item: package.displayName, error: error)
                    break
                }
            }
        }
        await scan()
        if let failureMessage {
            errorMessage = failureMessage
        } else if scanWarnings.contains(where: { $0.source == .homebrew }) {
            errorMessage = "Homebrew finished, but Upkeep could not verify the result because Homebrew data did not refresh completely."
        } else {
            let remaining = attempted.filter { attemptedPackage in
                homebrewPackages.contains { $0.token == attemptedPackage.token && $0.kind == attemptedPackage.kind && $0.isOutdated }
            }
            if !remaining.isEmpty {
                errorMessage = "Homebrew finished, but \(remaining.map(\.displayName).joined(separator: ", ")) still report available updates."
            }
        }
        DiagnosticsStore.shared.record(
            errorMessage == nil ? .info : .error,
            category: .update,
            errorMessage == nil ? "Homebrew batch update completed" : "Homebrew batch update needs attention",
            metadata: [
                "Attempted": "\(attempted.count)",
                "Duration": formattedDiagnosticDuration(since: startedAt),
                "Result": errorMessage ?? "All attempted packages refreshed successfully"
            ]
        )
        refreshDiagnostics()
        return errorMessage == nil
    }

    func adopt(_ item: AdoptableApp) async {
        pendingHomebrewAuthorizationConfirmation = HomebrewAuthorizationConfirmation(
            itemName: item.app.name,
            action: .adopt(item)
        )
    }

    func checkAppManagementPermission() async {
        let operationID = OperationID.appManagementPermissionCheck
        guard !isWorking(operationID) else { return }
        updateExecutionState.activeOperations.insert(operationID)
        defer { updateExecutionState.activeOperations.remove(operationID) }

        appManagementPermissionCheck = await AppManagementPermissionChecker.check(
            using: homebrewPermissionCheckApps
        )
    }

    func openAppManagementSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles"
        ), dependencies.externalOpener.open(url) else {
            errorMessage = "Could not open App Management settings."
            return
        }
    }

    var homebrewPermissionCheckApps: [InstalledApp] {
        var appsByID = Dictionary(uniqueKeysWithValues: adoptableApps.map { ($0.app.id, $0.app) })
        for package in homebrewPackages where package.kind == .cask {
            if let app = homebrewPackageApp(for: package) {
                appsByID[app.id] = app
            }
        }
        return appsByID.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func continueAdoption(_ item: AdoptableApp) async {
        if queueRunningAppConfirmation(for: [item.app], action: .adopt(item)) { return }
        _ = await adoptNow(item)
    }

    private func adoptNow(_ item: AdoptableApp) async -> Bool {
        await mutationCoordinator.withAccess(to: mutationTargets(for: item), otherwise: false) {
            await adoptUnlocked(item)
        }
    }

    private func adoptUnlocked(_ item: AdoptableApp) async -> Bool {
        let operationID = OperationID.homebrewAdoption(item.id)
        guard !isWorking(operationID) else { return false }
        updateExecutionState.activeOperations.insert(operationID)
        defer { updateExecutionState.activeOperations.remove(operationID) }
        beginUpdateActivity(operationID, targets: mutationTargets(for: item), phase: .adopting)
        defer { endUpdateActivity(operationID) }

        setUpdatePhase(.adopting, for: operationID)
        let succeeded = await execute(label: item.app.name, metadata: [
            "Source": "Homebrew adoption",
            "Installed": item.app.installedVersion,
            "Catalog": item.caskVersion
        ]) { try await self.dependencies.homebrew.adopt(item) }
        if succeeded {
            setUpdatePhase(.refreshing, for: operationID)
            await scan()
        }
        return succeeded
    }

    func updateAdoptableApp(_ item: AdoptableApp) async {
        pendingHomebrewAuthorizationConfirmation = HomebrewAuthorizationConfirmation(
            itemName: item.app.name,
            action: .updateAdoptable(item)
        )
    }

    private func continueAdoptableUpdate(_ item: AdoptableApp) async {
        if queueRunningAppConfirmation(for: [item.app], action: .updateAdoptable(item)) { return }
        _ = await updateAdoptableAppNow(item)
    }

    private func updateAdoptableAppNow(_ item: AdoptableApp) async -> Bool {
        await mutationCoordinator.withAccess(to: mutationTargets(for: item), otherwise: false) {
            await updateAdoptableAppUnlocked(item)
        }
    }

    private func updateAdoptableAppUnlocked(_ item: AdoptableApp) async -> Bool {
        let operationID = OperationID.homebrewAdoption(item.id)
        guard !isWorking(operationID) else { return false }
        updateExecutionState.activeOperations.insert(operationID)
        defer { updateExecutionState.activeOperations.remove(operationID) }
        beginUpdateActivity(operationID, targets: mutationTargets(for: item), phase: .backingUp)
        defer { endUpdateActivity(operationID) }

        let record: UpdateRecord
        do {
            record = try await dependencies.history.prepareAppBackup(
                app: item.app, toVersion: item.caskVersion, kind: .homebrew
            )
        } catch {
            errorMessage = "Could not create a rollback backup: \(error.localizedDescription)"
            recordUpdateFailure(item: item.app.name, action: "Prepare rollback backup", error: error)
            return false
        }
        setUpdatePhase(.updating, for: operationID)
        let succeeded = await execute(label: item.app.name, metadata: [
            "Source": "Homebrew adoption",
            "From": item.app.installedVersion,
            "To": item.caskVersion
        ]) { try await self.dependencies.homebrew.installOrReplace(item) }
        if succeeded {
            var historyError: Error?
            do { try await dependencies.history.add(record) }
            catch { historyError = error }
            setUpdatePhase(.refreshing, for: operationID)
            await scan()
            if let historyError { recordHistoryFailure(item: item.app.name, error: historyError) }
            reconcileHomebrewUpdate(token: item.caskToken, name: item.app.name)
        } else {
            await dependencies.history.discardBackup(for: record)
        }
        return succeeded
    }

    func isRunning(_ app: InstalledApp) -> Bool {
        if let bundleIdentifier = app.bundleIdentifier,
           runningBundleIdentifiers.contains(bundleIdentifier) { return true }
        return runningApplicationPaths.contains(canonicalPath(app.url))
    }

    func openUpdateManager(for app: InstalledApp) {
        let fileManager = FileManager.default
        let target: URL?
        switch app.updateManagement {
        case .testFlight:
            let installed = URL(fileURLWithPath: "/Applications/TestFlight.app")
            target = fileManager.fileExists(atPath: installed.path)
                ? installed
                : URL(string: "macappstore://apps.apple.com/app/testflight/id899247664")
        case .setapp:
            let installed = URL(fileURLWithPath: "/Applications/Setapp.app")
            target = fileManager.fileExists(atPath: installed.path)
                ? installed
                : URL(string: "https://setapp.com/apps")
        case .microsoftAutoUpdate:
            let installed = URL(fileURLWithPath: "/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app")
            target = fileManager.fileExists(atPath: installed.path) ? installed : app.url
        case .steam:
            target = URL(string: "steam://open/downloads")
        case .adobeCreativeCloud:
            let candidates = [
                URL(fileURLWithPath: "/Applications/Utilities/Adobe Creative Cloud/ACC/Creative Cloud.app"),
                URL(fileURLWithPath: "/Applications/Adobe Creative Cloud.app")
            ]
            target = candidates.first { fileManager.fileExists(atPath: $0.path) } ?? app.url
        case .jetBrainsToolbox:
            let candidates = [
                URL(fileURLWithPath: "/Applications/JetBrains Toolbox.app"),
                fileManager.homeDirectoryForCurrentUser
                    .appendingPathComponent("Applications/JetBrains Toolbox.app")
            ]
            target = candidates.first { fileManager.fileExists(atPath: $0.path) } ?? app.url
        case .spotify, .discord:
            target = app.url
        case .epicGames:
            let installed = URL(fileURLWithPath: "/Applications/Epic Games Launcher.app")
            target = fileManager.fileExists(atPath: installed.path) ? installed : app.url
        case .tailscale:
            target = app.url
        case .macOS:
            target = URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension")
        case .appStore:
            target = URL(string: "macappstore://showUpdatesPage")
        case .direct:
            target = app.url
        }
        guard let target, dependencies.externalOpener.open(target) else {
            errorMessage = "Could not open \(app.updateManagement.rawValue)."
            return
        }
    }

    func confirmRunningAppUpdate(_ confirmation: RunningAppConfirmation) async {
        await mutationCoordinator.withAccess(to: mutationTargets(for: confirmation), otherwise: ()) {
            await confirmRunningAppUpdateUnlocked(confirmation)
        }
    }

    private func confirmRunningAppUpdateUnlocked(_ confirmation: RunningAppConfirmation) async {
        pendingRunningAppConfirmation = nil
        let progressID = confirmation.operationID
        beginUpdateActivity(progressID, targets: mutationTargets(for: confirmation), phase: .quitting)
        defer { endUpdateActivity(progressID) }
        do {
            try await quitRunningApplications(for: confirmation.apps)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        endUpdateActivity(progressID)
        let succeeded: Bool
        switch confirmation.action {
        case let .update(update): succeeded = await performApplicationUpdate(update)
        case let .package(package): succeeded = await updatePackageNow(package)
        case let .adopt(item): succeeded = await adoptNow(item)
        case let .updateAdoptable(item): succeeded = await updateAdoptableAppNow(item)
        case .allPackages: succeeded = await updateAllPackagesNow()
        case let .restore(record): succeeded = await revertNow(record)
        }
        if succeeded { reopenApplications(confirmation.apps) }
    }

    func confirmHomebrewAuthorization(_ confirmation: HomebrewAuthorizationConfirmation) async {
        pendingHomebrewAuthorizationConfirmation = nil
        switch confirmation.action {
        case let .update(update): await continueApplicationUpdate(update)
        case let .package(package): await continuePackageUpdate(package)
        case let .adopt(item): await continueAdoption(item)
        case let .updateAdoptable(item): await continueAdoptableUpdate(item)
        case .allPackages: await continueAllPackageUpdates()
        }
    }

    func updateDeveloperPackage(_ package: DeveloperPackage) async {
        guard package.canUpdateAutomatically else {
            if let url = package.manager.homepage { _ = dependencies.externalOpener.open(url) }
            else { errorMessage = "\(package.name) must be updated with \(package.manager.rawValue)." }
            return
        }
        await installDeveloperPackage(package, version: package.latestVersion)
    }

    func installDeveloperPackage(_ package: DeveloperPackage, version: String) async {
        await mutationCoordinator.withAccess(to: mutationTargets(for: .developer(package)), otherwise: ()) {
            await installDeveloperPackageUnlocked(package, version: version)
        }
    }

    private func installDeveloperPackageUnlocked(_ package: DeveloperPackage, version: String) async {
        guard package.canUpdateAutomatically else {
            if let url = package.manager.homepage { _ = dependencies.externalOpener.open(url) }
            else { errorMessage = "\(package.name) must be updated with \(package.manager.rawValue)." }
            return
        }
        let selectedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedVersion.isEmpty else {
            errorMessage = "Enter a version to install."
            return
        }
        let operationID = OperationID.developerPackage(package.id)
        guard !isWorking(operationID) else { return }
        updateExecutionState.activeOperations.insert(operationID)
        defer { updateExecutionState.activeOperations.remove(operationID) }
        beginUpdateActivity(operationID, targets: mutationTargets(for: .developer(package)), phase: .installing)
        defer { endUpdateActivity(operationID) }

        setUpdatePhase(.installing, for: operationID)
        let succeeded = await execute(label: package.name, metadata: [
            "Source": package.manager.rawValue,
            "From": package.currentVersion,
            "To": selectedVersion
        ]) {
            try await self.dependencies.developerPackages.install(package, version: selectedVersion)
        }
        if succeeded {
            let record = UpdateRecord(
                id: UUID(), date: Date(), name: package.name,
                fromVersion: package.currentVersion, toVersion: selectedVersion,
                kind: .developer, originalAppPath: nil, backupPath: nil,
                recoveryNote: "Package-manager updates do not have a universal rollback mechanism. Reinstall the previous version with \(package.manager.rawValue) if needed."
            )
            let historyWarning = await saveUpdateHistory(record)
            setUpdatePhase(.refreshing, for: operationID)
            await scan()
            if let historyWarning { errorMessage = historyWarning }
        }
    }

    func uninstallDeveloperPackage(_ package: DeveloperPackage) async {
        await mutationCoordinator.withAccess(to: mutationTargets(for: .developer(package)), otherwise: ()) {
            await uninstallDeveloperPackageUnlocked(package)
        }
    }

    private func uninstallDeveloperPackageUnlocked(_ package: DeveloperPackage) async {
        let operationID = OperationID.developerPackage(package.id)
        guard !isWorking(operationID) else { return }
        updateExecutionState.activeOperations.insert(operationID)
        defer { updateExecutionState.activeOperations.remove(operationID) }

        let succeeded = await execute(label: package.name, metadata: [
            "Source": package.manager.rawValue,
            "Version": package.currentVersion,
            "Action": "Uninstall"
        ]) {
            try await self.dependencies.developerPackages.uninstall(package)
        }
        if succeeded {
            developerPackages.removeAll { $0.id == package.id }
            await scan()
        }
    }

    func scanLocalModels() async {
        let identifier = OperationID.localModelScan
        guard !isWorking(identifier) else { return }
        updateExecutionState.activeOperations.insert(identifier)
        defer { updateExecutionState.activeOperations.remove(identifier) }
        let report = await dependencies.localModels.scan()
        var merged = Dictionary(report.models.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for previous in localModels where report.failedModelIDs.contains(previous.id) || report.failedRuntimes.contains(previous.runtime) {
            merged[previous.id] = previous
        }
        localModels = merged.values.sorted(by: localModelOrder)
        scanWarnings = scanWarnings.filter { $0.source != .localModels }
            + report.warnings.map { ScanWarning(source: .localModels, message: $0) }
        if selectedLocalModelID == nil || !localModels.contains(where: { $0.id == selectedLocalModelID }) {
            selectedLocalModelID = localModels.first?.id
        }
        lastChecked = Date()
        settings.lastCompletedScanDate = lastChecked
    }

    func updateLocalModel(_ model: LocalLLMModel) async {
        await mutationCoordinator.withAccess(to: mutationTargets(for: .model(model)), otherwise: ()) {
            await updateLocalModelUnlocked(model)
        }
    }

    private func updateLocalModelUnlocked(_ model: LocalLLMModel) async {
        let operationID = OperationID.localModel(model.id)
        guard !isWorking(operationID) else { return }
        updateExecutionState.activeOperations.insert(operationID)
        defer { updateExecutionState.activeOperations.remove(operationID) }
        beginUpdateActivity(operationID, targets: mutationTargets(for: .model(model)), phase: .updating)
        defer { endUpdateActivity(operationID) }

        setUpdatePhase(.updating, for: operationID)
        let succeeded = await execute(label: model.name, metadata: [
            "Source": model.runtime.rawValue,
            "From": model.installedRevision,
            "To": model.latestRevision
        ]) { try await self.dependencies.localModels.update(model) }
        if succeeded {
            let record = UpdateRecord(
                id: UUID(), date: Date(), name: model.name,
                fromVersion: model.installedRevision, toVersion: model.latestRevision,
                kind: .model, originalAppPath: nil, backupPath: nil,
                recoveryNote: "Model files are managed by \(model.runtime.rawValue). Download the earlier model revision again if rollback is required."
            )
            let historyWarning = await saveUpdateHistory(record)
            setUpdatePhase(.refreshing, for: operationID)
            await scanLocalModels()
            if let historyWarning { errorMessage = historyWarning }
        }
    }

    func performBatchUpdates(_ items: [BatchUpdateItem]) async -> BatchUpdateSummary {
        await mutationCoordinator.withAccess(to: Set(items.flatMap { mutationTargets(for: $0) }), otherwise: BatchUpdateSummary(results: items.map { BatchUpdateResult(item: $0, outcome: .failed, detail: "A selected item is already being changed. Wait for that operation to finish, then try again.") })) {
            await performBatchUpdatesUnlocked(items)
        }
    }

    private func performBatchUpdatesUnlocked(_ items: [BatchUpdateItem]) async -> BatchUpdateSummary {
        let batchID = OperationID.unifiedBatch
        guard !items.isEmpty, !isWorking(batchID) else { return BatchUpdateSummary(results: []) }
        updateExecutionState.activeOperations.insert(batchID)
        errorMessage = nil
        defer {
            updateExecutionState.activeOperations.remove(batchID)
            batchUpdateProgress = nil
            for item in items { endUpdateActivity(item.updateOperationID) }
        }

        for item in items {
            beginUpdateActivity(item.updateOperationID, targets: mutationTargets(for: item), phase: .queued)
        }
        refreshRunningApplications()
        let runningApps = runningAppsForBatch(items)
        for item in items {
            if let app = batchApp(for: item), runningApps.contains(where: { $0.id == app.id }) {
                setUpdatePhase(.quitting, for: item.updateOperationID)
            }
        }
        if !runningApps.isEmpty { try? await quitRunningApplications(for: runningApps) }
        let closedApps = runningApps.filter { !isRunning($0) }
        for item in items { setUpdatePhase(.queued, for: item.updateOperationID) }

        var results: [BatchUpdateResult] = []
        for (index, item) in items.enumerated() {
            batchUpdateProgress = BatchUpdateProgress(completed: index, total: items.count, itemName: item.name)
            if let app = batchApp(for: item), isRunning(app) {
                results.append(BatchUpdateResult(
                    item: item,
                    outcome: .failed,
                    detail: "\(app.name) could not be quit. Quit it manually and try again."
                ))
                continue
            }
            let result = await performBatchItem(item)
            results.append(result)
            if result.outcome == .updated {
                setUpdatePhase(.queued, for: item.updateOperationID)
            } else {
                endUpdateActivity(item.updateOperationID)
            }
            DiagnosticsStore.shared.record(
                result.outcome == .failed ? .error : .info,
                category: .update,
                "Batch item \(result.outcome.rawValue.lowercased())",
                metadata: [
                    "Item": item.name,
                    "From": item.currentVersion,
                    "To": item.availableVersion,
                    "Detail": result.detail
                ]
            )
        }
        batchUpdateProgress = BatchUpdateProgress(completed: items.count, total: items.count, itemName: "Refreshing updates")

        if results.contains(where: { $0.outcome == .updated }) {
            for result in results where result.outcome == .updated {
                setUpdatePhase(.refreshing, for: result.item.updateOperationID)
            }
            await scan()
        }
        let updatedItemIDs = Set(results.compactMap { result in
            result.outcome == .updated ? result.item.id : nil
        })
        reopenApplications(closedApps.filter { app in
            items.contains { updatedItemIDs.contains($0.id) && batchApp(for: $0)?.id == app.id }
        })
        refreshDiagnostics()
        return BatchUpdateSummary(results: results)
    }

    private func performBatchItem(_ item: BatchUpdateItem) async -> BatchUpdateResult {
        let workID = OperationID.batchItem(item.id)
        updateExecutionState.activeOperations.insert(workID)
        defer { updateExecutionState.activeOperations.remove(workID) }

        let progressID = item.updateOperationID
        setUpdatePhase(.backingUp, for: progressID)
        var historyWarning: String?
        do {
            switch item {
            case let .application(update):
                guard let token = update.homebrewToken else {
                    if update.canInstallDirectly {
                        let record = try await dependencies.history.prepareAppBackup(
                            app: update.app, toVersion: update.availableVersion, kind: .app
                        )
                        do {
                            try await dependencies.directAppInstaller.install(update: update) { phase in
                                await self.setUpdatePhase(phase, for: progressID)
                            }
                        } catch {
                            await dependencies.history.discardBackup(for: record)
                            throw error
                        }
                        let warning = await saveUpdateHistory(record)
                        return BatchUpdateResult(
                            item: item, outcome: .updated,
                            detail: "Updated \(update.app.name) in Upkeep.", warning: warning
                        )
                    }
                    let target = update.externalActionURL
                    guard let target, dependencies.externalOpener.open(target) else {
                        throw BatchUpdateError.couldNotOpen(update.source.rawValue)
                    }
                    recordExternalUpdateAction(update, opened: true)
                    return BatchUpdateResult(
                        item: item,
                        outcome: .opened,
                        detail: update.requiresInAppInstallation
                            ? "Opened \(update.app.name). Complete the update with its built-in updater."
                            : "Opened \(update.source.rawValue). Complete the update there."
                    )
                }
                if let package = homebrewPackages.first(where: { $0.kind == .cask && $0.token == token }) {
                    historyWarning = try await upgradeBatchPackage(package, progressID: progressID)
                } else if let adoptable = adoptableApps.first(where: { $0.caskToken == token && $0.app.id == update.app.id }) {
                    let record = try await dependencies.history.prepareAppBackup(
                        app: adoptable.app, toVersion: adoptable.caskVersion, kind: .homebrew
                    )
                    setUpdatePhase(.updating, for: progressID)
                    do { try await dependencies.homebrew.installOrReplace(adoptable) }
                    catch {
                        await dependencies.history.discardBackup(for: record)
                        throw error
                    }
                    historyWarning = await saveUpdateHistory(record)
                } else {
                    let record = try await dependencies.history.prepareAppBackup(
                        app: update.app, toVersion: update.availableVersion, kind: .homebrew
                    )
                    setUpdatePhase(.updating, for: progressID)
                    do { try await dependencies.homebrew.upgradeCask(token: token) }
                    catch {
                        await dependencies.history.discardBackup(for: record)
                        throw error
                    }
                    historyWarning = await saveUpdateHistory(record)
                }

            case let .homebrew(package):
                historyWarning = try await upgradeBatchPackage(package, progressID: progressID)

            case let .developer(package):
                setUpdatePhase(.installing, for: progressID)
                try await dependencies.developerPackages.install(package, version: package.latestVersion)
                let record = UpdateRecord(
                    id: UUID(), date: Date(), name: package.name,
                    fromVersion: package.currentVersion, toVersion: package.latestVersion,
                    kind: .developer, originalAppPath: nil, backupPath: nil,
                    recoveryNote: "Package-manager updates do not have a universal rollback mechanism. Reinstall the previous version with \(package.manager.rawValue) if needed."
                )
                historyWarning = await saveUpdateHistory(record)

            case let .model(model):
                setUpdatePhase(.updating, for: progressID)
                try await dependencies.localModels.update(model)
                let record = UpdateRecord(
                    id: UUID(), date: Date(), name: model.name,
                    fromVersion: model.installedRevision, toVersion: model.latestRevision,
                    kind: .model, originalAppPath: nil, backupPath: nil,
                    recoveryNote: "Model files are managed by \(model.runtime.rawValue). Download the earlier model revision again if rollback is required."
                )
                historyWarning = await saveUpdateHistory(record)
            }
            return BatchUpdateResult(item: item, outcome: .updated, detail: "Updated to \(item.availableVersion).", warning: historyWarning)
        } catch {
            return BatchUpdateResult(item: item, outcome: .failed, detail: error.localizedDescription)
        }
    }

    private func upgradeBatchPackage(_ package: HomebrewPackage, progressID: OperationID) async throws -> String? {
        let record: UpdateRecord
        if package.kind == .cask, let app = matchingApp(for: package) {
            record = try await dependencies.history.prepareAppBackup(
                app: app, toVersion: package.currentVersion, kind: .homebrew
            )
        } else {
            record = UpdateRecord(
                id: UUID(), date: Date(), name: package.displayName,
                fromVersion: package.installedVersion, toVersion: package.currentVersion,
                kind: .homebrew, originalAppPath: nil, backupPath: nil,
                recoveryNote: "Homebrew formula versions cannot always be rolled back automatically. Restore from Time Machine or install a versioned formula when available."
            )
        }
        setUpdatePhase(.updating, for: progressID)
        do { try await dependencies.homebrew.upgrade(package) }
        catch {
            await dependencies.history.discardBackup(for: record)
            throw error
        }
        return await saveUpdateHistory(record)
    }

    func runningAppsForBatch(_ items: [BatchUpdateItem]) -> [InstalledApp] {
        Dictionary(items.compactMap(batchApp(for:)).filter(isRunning).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            .values
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func batchApp(for item: BatchUpdateItem) -> InstalledApp? {
        switch item {
        case let .application(update):
            return update.homebrewToken == nil && !update.canInstallDirectly ? nil : update.app
        case let .homebrew(package): return package.kind == .cask ? matchingApp(for: package) : nil
        case .developer, .model: return nil
        }
    }

    func isExcluded(_ update: AvailableUpdate) -> Bool {
        settings.isExcluded(key: exclusionKey(for: update.app), version: update.exclusionVersion)
    }

    func isExcluded(_ package: HomebrewPackage) -> Bool {
        settings.isExcluded(key: exclusionKey(for: package), version: package.currentVersion)
    }

    func isExcluded(_ package: DeveloperPackage) -> Bool {
        settings.isExcluded(key: exclusionKey(for: package), version: package.latestVersion)
    }

    func isExcluded(_ model: LocalLLMModel) -> Bool {
        settings.isExcluded(key: exclusionKey(for: model), version: model.latestRevision)
    }

    func exclusion(for app: InstalledApp, version: String) -> UpdateExclusion? {
        let candidate = update(for: app)?.candidates.first { $0.availableVersion == version }
        return settings.exclusion(for: exclusionKey(for: app), version: candidate?.exclusionVersion ?? version)
    }

    func exclusion(for package: HomebrewPackage) -> UpdateExclusion? {
        settings.exclusion(for: exclusionKey(for: package), version: package.currentVersion)
    }

    func exclusion(for package: DeveloperPackage) -> UpdateExclusion? {
        settings.exclusion(for: exclusionKey(for: package), version: package.latestVersion)
    }

    func exclusion(for model: LocalLLMModel) -> UpdateExclusion? {
        settings.exclusion(for: exclusionKey(for: model), version: model.latestRevision)
    }

    func ignoredExclusion(for app: InstalledApp) -> UpdateExclusion? {
        settings.ignoredExclusion(for: exclusionKey(for: app))
    }

    func skip(_ update: AvailableUpdate, duration: UpdateExclusionDuration? = nil) {
        exclude(.skipped, key: exclusionKey(for: update.app), name: update.app.name, category: "App", version: update.exclusionVersion, duration: duration)
    }

    func ignore(_ app: InstalledApp, duration: UpdateExclusionDuration? = nil) {
        exclude(.ignored, key: exclusionKey(for: app), name: app.name, category: "App", version: nil, duration: duration)
    }

    func skip(_ package: HomebrewPackage, duration: UpdateExclusionDuration? = nil) {
        exclude(.skipped, key: exclusionKey(for: package), name: package.displayName, category: "Homebrew", version: package.currentVersion, duration: duration)
    }

    func ignore(_ package: HomebrewPackage, duration: UpdateExclusionDuration? = nil) {
        exclude(.ignored, key: exclusionKey(for: package), name: package.displayName, category: "Homebrew", version: nil, duration: duration)
    }

    func skip(_ package: DeveloperPackage, duration: UpdateExclusionDuration? = nil) {
        exclude(.skipped, key: exclusionKey(for: package), name: package.name, category: package.manager.rawValue, version: package.latestVersion, duration: duration)
    }

    func ignore(_ package: DeveloperPackage, duration: UpdateExclusionDuration? = nil) {
        exclude(.ignored, key: exclusionKey(for: package), name: package.name, category: package.manager.rawValue, version: nil, duration: duration)
    }

    func skip(_ model: LocalLLMModel, duration: UpdateExclusionDuration? = nil) {
        exclude(.skipped, key: exclusionKey(for: model), name: model.name, category: model.runtime.rawValue, version: model.latestRevision, duration: duration)
    }

    func ignore(_ model: LocalLLMModel, duration: UpdateExclusionDuration? = nil) {
        exclude(.ignored, key: exclusionKey(for: model), name: model.name, category: model.runtime.rawValue, version: nil, duration: duration)
    }

    func restore(_ exclusion: UpdateExclusion) {
        settings.restore(exclusion)
        objectWillChange.send()
    }

    func restore(app: InstalledApp) {
        settings.restore(key: exclusionKey(for: app))
        objectWillChange.send()
    }

    func restoreAllExclusions() {
        settings.restoreAllExclusions()
        objectWillChange.send()
    }

    func isHomebrewAdoptionIgnored(_ app: InstalledApp) -> Bool {
        settings.isHomebrewAdoptionIgnored(key: exclusionKey(for: app))
    }

    func ignoreHomebrewAdoption(_ app: InstalledApp) {
        settings.setHomebrewAdoptionIgnored(true, key: exclusionKey(for: app))
        removeIgnoredHomebrewAdoptionCandidates(for: app)
    }

    func restoreHomebrewAdoption(_ app: InstalledApp) {
        settings.setHomebrewAdoptionIgnored(false, key: exclusionKey(for: app))
        objectWillChange.send()
    }

    func prepareMacOSUpdate(_ update: MacOSUpdate) async {
        let operationID = OperationID.macOSUpdate(update.id)
        guard !isWorking(operationID) else { return }
        updateExecutionState.activeOperations.insert(operationID)
        defer { updateExecutionState.activeOperations.remove(operationID) }

        do {
            try await dependencies.history.addMacOSPlan(update: update)
            updateHistory = await dependencies.history.records()
            openSoftwareUpdateSettings()
        } catch { errorMessage = error.localizedDescription }
    }

    func openBetaSettings() { openSoftwareUpdateSettings() }

    func revert(_ record: UpdateRecord) async {
        await mutationCoordinator.withAccess(to: mutationTargets(for: record), otherwise: ()) {
            guard let path = record.originalAppPath else { return }
            let url = URL(fileURLWithPath: path)
            var app = apps.first { $0.url.standardizedFileURL == url.standardizedFileURL }
            if app == nil { app = await dependencies.applicationDiscovery.discover(at: url) }
            if app?.isUpkeep == true || Bundle(url: url)?.bundleIdentifier == InstalledApp.upkeepBundleIdentifier {
                errorMessage = "Upkeep cannot restore itself while running. Quit Upkeep and copy the backup from \(record.backupPath ?? "History") to \(path) using Finder."
                return
            }
            if let app, queueRunningAppConfirmation(for: [app], action: .restore(record)) { return }
            _ = await revertNow(record)
        }
    }

    private func revertNow(_ record: UpdateRecord) async -> Bool {
        let operationID = OperationID.historyRestore(record.id)
        guard !isWorking(operationID) else { return false }
        updateExecutionState.activeOperations.insert(operationID)
        defer { updateExecutionState.activeOperations.remove(operationID) }

        let succeeded = await execute(label: "Restore \(record.name)", metadata: [
            "From": record.toVersion,
            "To": record.fromVersion,
            "Source": "History"
        ]) {
            try await dependencies.history.revert(record)
        }
        if succeeded { await scan() }
        return succeeded
    }

    func openMacOSRecoveryHelp() {
        if let url = URL(string: "https://support.apple.com/102551") { _ = dependencies.externalOpener.open(url) }
    }

    private func openSoftwareUpdateSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"),
              dependencies.externalOpener.open(url)
        else {
            errorMessage = "Could not open Software Update settings."
            return
        }
    }

    func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    }

    var selectedDeveloperPackage: DeveloperPackage? {
        guard let id = selectedDeveloperPackageID else { return nil }
        return developerPackages.first { $0.id == id }
    }

    private func notifyIfNeeded(previousCount: Int) {
        guard settings.notificationsEnabled, totalUpdateCount > 0, totalUpdateCount != previousCount else { return }
        let content = UNMutableNotificationContent()
        content.title = "Upkeep found updates"
        content.body = "\(totalUpdateCount) update\(totalUpdateCount == 1 ? " is" : "s are") available."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "upkeep-updates", content: content, trigger: nil))
    }

    private func exclude(_ mode: UpdateExclusionMode, key: String, name: String, category: String, version: String?, duration: UpdateExclusionDuration?) {
        if mode == .skipped, let version { settings.skip(key: key, name: name, category: category, version: version, duration: duration) }
        else { settings.ignore(key: key, name: name, category: category, duration: duration) }
        objectWillChange.send()
    }

    private func exclusionKey(for app: InstalledApp) -> String { app.updateExclusionKey }
    private func legacyExclusionKey(for app: InstalledApp) -> String { "app|\(app.id)" }
    private func exclusionKey(for package: HomebrewPackage) -> String { "homebrew|\(package.id)" }
    private func exclusionKey(for package: DeveloperPackage) -> String { "developer|\(package.id)" }
    private func exclusionKey(for model: LocalLLMModel) -> String { "model|\(model.id)" }

    private func execute(
        label: String,
        metadata: [String: String] = [:],
        operation: () async throws -> Void
    ) async -> Bool {
        let startedAt = Date()
        errorMessage = nil
        do {
            try await operation()
            DiagnosticsStore.shared.record(.info, category: .update, "Update action completed", metadata: metadata.merging([
                "Item": label,
                "Duration": formattedDiagnosticDuration(since: startedAt)
            ]) { _, new in new })
            refreshDiagnostics()
            return true
        } catch {
            errorMessage = error.localizedDescription
            DiagnosticsStore.shared.record(.error, category: .update, "Update action failed", metadata: metadata.merging([
                "Item": label,
                "Duration": formattedDiagnosticDuration(since: startedAt),
                "Error": error.localizedDescription
            ]) { _, new in new })
            refreshDiagnostics()
            return false
        }
    }

    func refreshDiagnostics() {
        diagnosticEntries = DiagnosticsStore.shared.entries()
    }

    func clearDiagnostics() {
        DiagnosticsStore.shared.clear()
        refreshDiagnostics()
    }

    func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.title = "Export Upkeep Diagnostics"
        panel.nameFieldStringValue = "Upkeep Diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DiagnosticsStore.shared.exportText().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "Could not export diagnostics: \(error.localizedDescription)"
        }
    }

    private func recordExternalUpdateAction(_ update: AvailableUpdate, opened: Bool) {
        DiagnosticsStore.shared.record(
            opened ? .info : .error,
            category: .update,
            opened ? "External update action opened" : "External update action could not open",
            metadata: [
                "Item": update.app.name,
                "Source": update.source.rawValue,
                "Installed": update.app.installedVersion,
                "Available": update.availableVersion
            ]
        )
        if opened {
            beginExternalUpdateVerification(update)
        } else {
            errorMessage = "Could not open the update action for \(update.app.name)."
        }
        refreshDiagnostics()
    }

    private func beginExternalUpdateVerification(_ update: AvailableUpdate) {
        externalVerificationTasks[update.id]?.cancel()
        externalUpdateVerifications[update.id] = ExternalUpdateVerification(
            state: .waiting,
            detail: "Waiting for \(update.app.name) to finish the update…"
        )
        externalVerificationTasks[update.id] = Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<20 {
                do { try await Task.sleep(for: self.dependencies.externalVerificationInterval) }
                catch { return }
                guard let refreshed = await self.dependencies.applicationDiscovery.discover(
                    at: update.app.url
                ) else { continue }
                guard !Task.isCancelled else { return }
                if update.primaryCandidate.isInstalled(in: refreshed) {
                    await self.refresh(refreshed)
                    guard !Task.isCancelled else { return }
                    self.externalUpdateVerifications[update.id] = ExternalUpdateVerification(
                        state: .completed,
                        detail: "Verified \(refreshed.installedVersion) from the installed app bundle."
                    )
                    self.externalVerificationTasks[update.id] = nil
                    return
                }
            }
            self.externalUpdateVerifications[update.id] = ExternalUpdateVerification(
                state: .attention,
                detail: "\(update.app.name) still reports \(update.app.installedVersion). Finish its updater or restart the app, then refresh."
            )
            DiagnosticsStore.shared.record(
                .warning,
                category: .update,
                "External update still needs verification",
                metadata: [
                    "Item": update.app.name,
                    "Expected": update.availableVersion,
                    "Reported": update.app.installedVersion
                ]
            )
            self.externalVerificationTasks[update.id] = nil
            self.refreshDiagnostics()
        }
    }

    func externalUpdateVerification(for app: InstalledApp) -> ExternalUpdateVerification? {
        externalUpdateVerifications[app.id]
    }

    func setGitHubRepository(_ value: String, for app: InstalledApp) async {
        guard let bundleIdentifier = app.bundleIdentifier else {
            errorMessage = "This app does not declare a bundle identifier, so Upkeep cannot save a reliable mapping."
            return
        }
        do {
            let repository = try await GitHubClient().validateRepository(value)
            settings.setGitHubRepository(repository, for: bundleIdentifier)
            let mappedApp = app.replacingGitHubRepository(repository)
            replaceApp(app, with: mappedApp)
            await refresh(mappedApp)
        } catch {
            errorMessage = "Could not use that GitHub source: \(error.localizedDescription)"
        }
    }

    func removeCustomGitHubRepository(for app: InstalledApp) async {
        guard let bundleIdentifier = app.bundleIdentifier else { return }
        settings.setGitHubRepository(nil, for: bundleIdentifier)
        let repository = AppDiscovery.trustedGitHubRepository(bundleIdentifier: bundleIdentifier)
        let remappedApp = app.replacingGitHubRepository(repository)
        replaceApp(app, with: remappedApp)
        await refresh(remappedApp)
    }

    private func replaceApp(_ oldApp: InstalledApp, with newApp: InstalledApp) {
        if let index = apps.firstIndex(where: { $0.id == oldApp.id }) {
            apps[index] = newApp
        }
        if selectedApp?.id == oldApp.id { selectedApp = newApp }
        updates = updates.map { update in
            update.app.id == oldApp.id
                ? AvailableUpdate(app: newApp, candidates: update.candidates)
                : update
        }
    }

    private func updateDiagnosticMetadata(_ update: AvailableUpdate) -> [String: String] {
        [
            "Source": update.source.rawValue,
            "From": update.app.installedVersion,
            "To": update.availableVersion
        ]
    }

    private func recordUpdateFailure(item: String, action: String, error: Error) {
        DiagnosticsStore.shared.record(.error, category: .update, "Update preparation failed", metadata: [
            "Item": item,
            "Action": action,
            "Error": error.localizedDescription
        ])
        refreshDiagnostics()
    }

    private func saveUpdateHistory(_ record: UpdateRecord) async -> String? {
        var warning: String?
        do { try await dependencies.history.add(record) }
        catch {
            recordHistoryFailure(item: record.name, error: error)
            warning = errorMessage
        }
        updateHistory = await dependencies.history.records()
        return warning
    }

    private func recordHistoryFailure(item: String, error: Error) {
        errorMessage = "\(item) was updated, but its rollback history could not be saved: \(error.localizedDescription)"
        DiagnosticsStore.shared.record(.error, category: .update, "Rollback history could not be saved", metadata: [
            "Item": item,
            "Error": error.localizedDescription
        ])
        refreshDiagnostics()
    }

    private func recoveryRecord(for package: HomebrewPackage) async -> UpdateRecord? {
        if package.kind == .cask, let app = matchingApp(for: package) {
            do {
                return try await dependencies.history.prepareAppBackup(
                    app: app, toVersion: package.currentVersion, kind: .homebrew
                )
            } catch {
                errorMessage = "Could not create a rollback backup: \(error.localizedDescription)"
                recordUpdateFailure(item: package.displayName, action: "Prepare rollback backup", error: error)
                return nil
            }
        }
        return UpdateRecord(
            id: UUID(), date: Date(), name: package.displayName,
            fromVersion: package.installedVersion, toVersion: package.currentVersion,
            kind: .homebrew, originalAppPath: nil, backupPath: nil,
            recoveryNote: "Homebrew formula versions cannot always be rolled back automatically. Restore from Time Machine or install a versioned formula when available."
        )
    }

    private func matchingApp(for package: HomebrewPackage) -> InstalledApp? {
        library.app(for: package)
    }

    func isUnmapped(_ package: HomebrewPackage) -> Bool {
        package.kind == .cask && matchingApp(for: package) == nil
    }

    func homebrewPackage(for app: InstalledApp) -> HomebrewPackage? {
        library.homebrewPackage(forAppNamed: app.name)
    }

    func homebrewPackageApp(for package: HomebrewPackage) -> InstalledApp? {
        matchingApp(for: package)
    }

    func isRefreshing(_ app: InstalledApp) -> Bool {
        isWorking(.applicationRefresh(app.id))
    }

    func isRefreshing(_ package: HomebrewPackage) -> Bool {
        isWorking(.homebrewRefresh(package.id))
            || homebrewPackageApp(for: package).map(isRefreshing) == true
    }

    func isRefreshing(_ package: DeveloperPackage) -> Bool {
        isWorking(.developerRefresh(package.id))
    }

    func lastChecked(for app: InstalledApp) -> Date? {
        settings.lastChecked(for: exclusionKey(for: app))
    }

    func lastChecked(for package: HomebrewPackage) -> Date? {
        settings.lastChecked(for: exclusionKey(for: package))
    }

    func lastChecked(for package: DeveloperPackage) -> Date? {
        settings.lastChecked(for: exclusionKey(for: package))
    }

    private func queueRunningAppConfirmation(for apps: [InstalledApp], action: RunningAppConfirmation.Action) -> Bool {
        refreshRunningApplications()
        let runningApps = Dictionary(uniqueKeysWithValues: apps.filter(isRunning).map { ($0.id, $0) })
            .values
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !runningApps.isEmpty else { return false }
        pendingRunningAppConfirmation = RunningAppConfirmation(apps: runningApps, action: action)
        return true
    }

    private func refreshRunningApplications() {
        let running = dependencies.applicationLifecycle.runningApplications()
        if running.identifiers != runningBundleIdentifiers { runningBundleIdentifiers = running.identifiers }
        if running.paths != runningApplicationPaths { runningApplicationPaths = running.paths }
    }

    private func observeRunningApplications() {
        guard runningApplicationObservers.isEmpty else { return }
        let notifications = NSWorkspace.shared.notificationCenter
        [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ].forEach { name in
            notifications.publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in self?.refreshRunningApplications() }
                }
                .store(in: &runningApplicationObservers)
        }
    }

    private func quitRunningApplications(for apps: [InstalledApp]) async throws {
        try await dependencies.applicationLifecycle.quit(apps)
        refreshRunningApplications()
    }

    func reopenApplications(_ apps: [InstalledApp]) {
        for app in apps where !dependencies.externalOpener.open(app.url) {
            errorMessage = "\(app.name) was updated, but Upkeep could not reopen it."
            DiagnosticsStore.shared.record(
                .warning,
                category: .update,
                "Could not reopen updated app",
                metadata: ["Item": app.name, "Path": app.url.path]
            )
        }
        refreshDiagnostics()
    }

    private func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func matching<T>(_ values: [T], name: (T) -> String) -> [T] {
        searchText.isEmpty ? values : values.filter { name($0).localizedCaseInsensitiveContains(searchText) }
    }

    private func enabledUpdateSources(for app: InstalledApp) -> Set<UpdateSource> {
        Set(enabledAppUpdateSources(
            for: app,
            checkAppStore: settings.checkAppStore,
            checkSparkle: settings.checkSparkle,
            checkGitHub: settings.checkGitHub
        ).map(\.source))
    }

    private func replaceHomebrewPackage(_ package: HomebrewPackage) {
        let package = homebrewPackageApp(for: package).map { package.reconciled(with: $0) } ?? package
        if let index = homebrewPackages.firstIndex(where: { $0.id == package.id }) {
            homebrewPackages[index] = package
        } else {
            homebrewPackages.append(package)
        }
        homebrewPackages.sort {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private func mergedUpdates(from report: ScanReport) -> [AvailableUpdate] {
        var merged = Dictionary(uniqueKeysWithValues: report.updates.map { ($0.id, $0) })
        let currentApps = Dictionary(uniqueKeysWithValues: report.apps.map { ($0.id, $0) })

        for previous in updates {
            guard let currentApp = currentApps[previous.id] else { continue }
            let failedSources = report.failedAppSources[previous.app.id] ?? []
            let retained = Self.retainableCandidates(
                in: previous, currentApp: currentApp, failedSources: failedSources
            )
            guard !retained.isEmpty else { continue }
            let retainedUpdate = AvailableUpdate(app: currentApp, candidates: retained)
            if let fresh = merged[previous.id] {
                merged[previous.id] = AvailableUpdate.merging([fresh, retainedUpdate])
            } else {
                merged[previous.id] = retainedUpdate
            }
        }

        if report.homebrewInventoryStatus == .failed {
            for previous in updates {
                guard let currentApp = currentApps[previous.id] else { continue }
                let retained = Self.retainableCandidates(
                    in: previous, currentApp: currentApp, failedSources: [.homebrew]
                ).filter { !$0.requiresHomebrewAdoption }
                guard !retained.isEmpty else { continue }
                let retainedUpdate = AvailableUpdate(app: currentApp, candidates: retained)
                if let fresh = merged[previous.id] {
                    merged[previous.id] = AvailableUpdate.merging([fresh, retainedUpdate])
                } else {
                    merged[previous.id] = retainedUpdate
                }
            }
        } else if report.homebrewCatalogStatus == .failed {
            for previous in updates {
                guard let currentApp = currentApps[previous.id] else { continue }
                let retained = Self.retainableCandidates(
                    in: previous, currentApp: currentApp, failedSources: [.homebrew]
                ).filter(\.requiresHomebrewAdoption)
                guard !retained.isEmpty else { continue }
                let retainedUpdate = AvailableUpdate(app: currentApp, candidates: retained)
                if let fresh = merged[previous.id] {
                    merged[previous.id] = AvailableUpdate.merging([fresh, retainedUpdate])
                } else {
                    merged[previous.id] = retainedUpdate
                }
            }
        }

        return merged.values.compactMap { update in
            let candidates = update.candidates.filter {
                !$0.requiresHomebrewAdoption || !settings.isHomebrewAdoptionIgnored(key: exclusionKey(for: update.app))
            }
            return candidates.isEmpty ? nil : AvailableUpdate(app: update.app, candidates: candidates)
        }
        .sorted { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending }
    }

    private func removeIgnoredHomebrewAdoptionCandidates(for app: InstalledApp) {
        updates = updates.compactMap { update in
            guard update.app.id == app.id else { return update }
            let candidates = update.candidates.filter { !$0.requiresHomebrewAdoption }
            return candidates.isEmpty ? nil : AvailableUpdate(app: update.app, candidates: candidates)
        }
    }

    static func retainableCandidates(
        in previous: AvailableUpdate,
        currentApp: InstalledApp,
        failedSources: Set<UpdateSource>
    ) -> [UpdateCandidate] {
        previous.candidates.filter {
            failedSources.contains($0.source)
                && $0.isNewer(than: currentApp)
        }
    }

    private func mergedMacOSUpdates(from report: ScanReport) -> [MacOSUpdate] {
        let currentUpdates = report.macOSUpdates.filter { !$0.isFullInstaller }
        let currentInstallers = report.macOSUpdates.filter(\.isFullInstaller)
        let updatesPart: [MacOSUpdate] = report.macOSUpdatesStatus == .failed
            ? macOSUpdates.filter { !$0.isFullInstaller }
            : currentUpdates
        let installersPart: [MacOSUpdate] = report.macOSInstallersStatus == .failed
            ? macOSUpdates.filter(\.isFullInstaller)
            : currentInstallers
        return updatesPart + installersPart
    }

    private func mergedDeveloperPackages(from report: ScanReport) -> [DeveloperPackage] {
        mergeDeveloperPackageResults(
            fresh: report.developerPackages,
            previous: developerPackages,
            failedManagers: report.failedDeveloperManagers,
            failedExecutablePaths: report.failedDeveloperExecutablePaths
        ).sorted(by: developerPackageOrder)
    }

    private func mergedLocalModels(from report: ScanReport) -> [LocalLLMModel] {
        guard report.localModelsStatus != .disabled else { return [] }
        var merged = Dictionary(report.localModels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for previous in localModels where report.failedLocalModelIDs.contains(previous.id)
            || report.failedLocalModelRuntimes.contains(previous.runtime) {
            merged[previous.id] = previous
        }
        return merged.values.sorted(by: localModelOrder)
    }

    private func developerPackageOrder(_ lhs: DeveloperPackage, _ rhs: DeveloperPackage) -> Bool {
        if lhs.manager != rhs.manager { return lhs.manager.rawValue < rhs.manager.rawValue }
        let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return (lhs.installationContext ?? lhs.executablePath).localizedStandardCompare(rhs.installationContext ?? rhs.executablePath) == .orderedAscending
    }

    private func localModelOrder(_ lhs: LocalLLMModel, _ rhs: LocalLLMModel) -> Bool {
        if lhs.runtime != rhs.runtime { return lhs.runtime.rawValue < rhs.runtime.rawValue }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private func reconcileHomebrewUpdate(token: String, name: String) {
        if let package = homebrewPackages.first(where: { $0.token == token }) {
            if package.isOutdated {
                errorMessage = "Homebrew completed the command, but \(name) still reports \(package.currentVersion) as available."
            }
            return
        }
        if scanWarnings.contains(where: { $0.source == .homebrew }) {
            errorMessage = "Homebrew completed the update for \(name), but Upkeep could not fully refresh Homebrew data. Review Diagnostics and refresh again."
        }
    }
}

func mergeDeveloperPackageResults(
    fresh: [DeveloperPackage],
    previous: [DeveloperPackage],
    failedManagers: Set<DeveloperPackageManager>,
    failedExecutablePaths: Set<String>
) -> [DeveloperPackage] {
    let retained = previous.filter {
        failedManagers.contains($0.manager) || failedExecutablePaths.contains($0.executablePath)
    }
    let acceptedFresh = fresh.filter { !failedManagers.contains($0.manager) }
    return Dictionary(grouping: retained + acceptedFresh, by: \.id).compactMap { $0.value.first }
}
