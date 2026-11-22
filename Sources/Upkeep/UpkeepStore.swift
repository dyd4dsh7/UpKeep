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
    case verification(String)

    var errorDescription: String? {
        switch self {
        case let .couldNotOpen(source): "Could not open \(source)."
        case let .verification(message): message
        }
    }
}

@MainActor
final class UpkeepStore: ObservableObject {
    let settings: AppSettings
    private let dependencies: UpkeepDependencies

    // Shared update routines record errors for single-item alerts. A batch item
    // reads the same information into its result without publishing a second
    // alert or overwriting an unrelated operation's error.
    @MainActor
    private final class BatchItemError {
        let owner: ObjectIdentifier
        var message: String?

        init(owner: UpkeepStore) {
            self.owner = ObjectIdentifier(owner)
        }
    }

    @TaskLocal private static var batchItemError: BatchItemError?

    var errorMessage: String? {
        get {
            if let item = Self.batchItemError, item.owner == ObjectIdentifier(self) { return item.message }
            return scanState.errorMessage
        }
        set {
            if let item = Self.batchItemError, item.owner == ObjectIdentifier(self) {
                item.message = newValue
            } else {
                scanState.errorMessage = newValue
            }
        }
    }

    func scanHomebrewServices() async {
        guard !library.isCheckingHomebrewServices else { return }
        library.isCheckingHomebrewServices = true
        library.homebrewServicesCheckedAt = Date()
        defer { library.isCheckingHomebrewServices = false }
        do {
            library.homebrewServices = try await dependencies.homebrew.services()
            library.homebrewServicesSucceededAt = Date()
            library.homebrewServicesFailure = nil
        } catch {
            library.homebrewServicesFailure = error.localizedDescription
        }
    }
    let cveScanState = CVEScanState()
    private var automaticCVETask: Task<Void, Never>?
    private var automaticCVEGeneration: UUID?
    private var automaticCVEOwnsScan = false
    let library = UpkeepLibraryState()
    var navigation = UpkeepNavigationState()
    let scanState: UpkeepScanState
    let updateExecutionState = UpkeepUpdateExecutionState()
    let mutationCoordinator = MutationCoordinator()
    var diagnostics = UpkeepDiagnosticsState()

    private let refreshScheduler = RefreshScheduler()
    private let fullScanCoordinator = FullScanCoordinator()
    private var developerVersionRequestID: UUID?
    private var runningApplicationObservers = Set<AnyCancellable>()
    private var featureStateObservers = Set<AnyCancellable>()
    private var isRootChangeScheduled = false
    private var didStart = false
    private let startedAt = Date()
    private var appListProjection = ListProjectionCache<InstalledApp, ListProjectionKey<String>>()
    private var adoptableListProjection = ListProjectionCache<AdoptableApp, ListProjectionKey<String>>()
    private var developerListProjection = ListProjectionCache<DeveloperPackage, ListProjectionKey<DeveloperListFilterKey>>()
    private var homebrewListProjection = ListProjectionCache<HomebrewPackage, ListProjectionKey<HomebrewFilter>>()
    private var primaryCountProjection: (inventory: UInt64, exclusions: UInt64, expiresAt: Date?, value: Int)?
    private var applicationCountProjection: (apps: UInt64, homebrew: UInt64, updates: UInt64, counts: [SidebarDestination: Int])?
    private struct VisibleUpdateCountKey: Equatable { let apps, homebrew, updates, exclusions: UInt64 }
    private var visibleUpdateCountProjection: (key: VisibleUpdateCountKey, expiresAt: Date?, counts: [SidebarDestination: Int])?
    private var searchProjection: (generation: UInt64, query: String, results: GlobalSearchResults)?
    private var versionCache: [String: [String]] = [:]
    private var versionCacheRequests: [String: UUID] = [:]
    private let externalUpdateVerifier: ExternalUpdateVerifier

    init(
        settings: AppSettings = AppSettings(),
        dependencies: UpkeepDependencies = .live
    ) {
        self.settings = settings
        self.dependencies = dependencies
        self.externalUpdateVerifier = ExternalUpdateVerifier(discovery: dependencies.applicationDiscovery,
            interval: dependencies.externalVerificationInterval)
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
        if operation == .localModelScan, updateExecutionState.activeOperations.contains(where: {
            if case .localModelRuntimeScan = $0 { return true }
            return false
        }) { return true }
        return updateExecutionState.activeOperations.contains(operation)
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

    var globalSearchResults: GlobalSearchResults {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cached = searchProjection, cached.generation == library.generation, cached.query == query {
            return cached.results
        }
        let results = GlobalSearch(store: self).results
        searchProjection = (library.generation, query, results)
        return results
    }

    var visibleUpdates: [AvailableUpdate] { updates.filter { !isExcluded($0) } }
    var filteredUpdates: [AvailableUpdate] { matching(visibleUpdates, name: { $0.app.name }) }
    var filteredApps: [InstalledApp] {
        appListProjection.values(for: ListProjectionKey(generation: library.appGeneration, query: searchText, filter: "")) {
            matching(apps, name: \InstalledApp.name)
        }
    }
    var filteredAdoptableApps: [AdoptableApp] {
        adoptableListProjection.values(for: ListProjectionKey(generation: library.adoptableGeneration, query: searchText, filter: "")) {
            matching(adoptableApps, name: { $0.app.name })
        }
    }
    var outdatedPackageCount: Int { homebrewPackages.count { $0.isOutdated && !isExcluded($0) } }
    var outdatedDeveloperPackageCount: Int { developerPackages.count { $0.isOutdated && !isExcluded($0) } }
    var outdatedLocalModelCount: Int { localModels.count { $0.isOutdated && !isExcluded($0) } }
    var totalUpdateCount: Int {
        // Casks match apps by name, so the app list is an input too.
        let inventory = library.primaryUpdateGeneration &+ library.appGeneration
        let exclusions = settings.exclusionCacheRevision
        let now = Date()
        if let cached = primaryCountProjection, cached.inventory == inventory,
           cached.exclusions == exclusions, cached.expiresAt.map({ now < $0 }) ?? true {
            return cached.value
        }
        let value = UpdatePlan.primaryUpdateCount(
            applicationUpdates: visibleUpdates,
            homebrewUpdates: visibleHomebrewUpdates,
            macOSUpdates: macOSUpdates,
            developerUpdates: developerPackages.filter { $0.isOutdated && !isExcluded($0) },
            modelUpdates: visibleOutdatedLocalModels
        )
        primaryCountProjection = (inventory, exclusions, settings.nextExclusionExpiration, value)
        return value
    }

    var filteredDeveloperPackages: [DeveloperPackage] {
        let filter = DeveloperListFilterKey(manager: developerManagerFilter, showCurrent: settings.showCurrentDeveloperPackages)
        return developerListProjection.values(for: ListProjectionKey(generation: library.developerGeneration, query: searchText, filter: filter)) {
            matching(developerPackages.filter {
                (settings.showCurrentDeveloperPackages || $0.isOutdated) && developerManagerFilter.includes($0.manager)
            }, name: { $0.name })
        }
    }

    var packageCleanupTargets: [PackageCleanupTarget] {
        PackageCleanupTarget.available(
            homebrewURL: HomebrewClient.brewURL,
            installedManagers: installedDeveloperManagers,
            packages: developerPackages
        )
    }

    func scanCleanup(_ target: PackageCleanupTarget, onError: ((String) -> Void)? = nil) async -> PackageCleanupEstimate? {
        guard !mutationCoordinator.isBusy(mutationTargets(for: target)) else {
            let message = "Cleanup review must wait until this package environment finishes changing."
            if let onError { onError(message) } else { errorMessage = message }
            return nil
        }
        return await mutationCoordinator.withAccess(to: mutationTargets(for: target), otherwise: nil) {
            await scanCleanupUnlocked(target, onError: onError)
        }
    }

    private func scanCleanupUnlocked(_ target: PackageCleanupTarget, onError: ((String) -> Void)?) async -> PackageCleanupEstimate? {
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
        guard !mutationCoordinator.isBusy(mutationTargets(for: target)) else {
            let message = "Cleanup must wait until this package environment finishes changing."
            if let onError { onError(message) } else { errorMessage = message }
            return nil
        }
        return await mutationCoordinator.withAccess(to: mutationTargets(for: target), otherwise: nil) {
            await cleanUpUnlocked(target, onError: onError)
        }
    }

    private func cleanUpUnlocked(_ target: PackageCleanupTarget, onError: ((String) -> Void)?) async -> PackageCleanupResult? {
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
                "Measurement": result.message,
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
        let key = ListProjectionKey(generation: library.homebrewGeneration,
            // Casks inherit their app's skip rule, which depends on app updates.
            // Both counters only grow, so their sum changes whenever either does.
            relatedGeneration: homebrewFilter == .unmapped ? library.appGeneration
                : homebrewFilter == .updates ? library.appGeneration &+ library.primaryUpdateGeneration : 0,
            exclusions: homebrewFilter == .updates ? settings.exclusionCacheRevision : 0,
            query: searchText, filter: homebrewFilter)
        return homebrewListProjection.values(for: key,
            expiresAt: homebrewFilter == .updates ? settings.nextExclusionExpiration : nil) {
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
        apps.filter { application($0, belongsTo: destination) }
    }

    /// Source sidebar destinations whose counts come from `applications(for:)`.
    static let applicationSourceDestinations: [SidebarDestination] = [
        .appStore, .testFlight, .setapp, .microsoftAutoUpdate, .steam,
        .otherUpdaters, .homebrewApps, .sparkle, .github, .noSource
    ]

    /// Counts for every `applicationSourceDestinations` entry, computed in one
    /// pass over `apps` and cached until apps, Homebrew packages or updates change.
    func applicationSourceCounts() -> [SidebarDestination: Int] {
        let key = (apps: library.appGeneration, homebrew: library.homebrewGeneration,
                   updates: library.primaryUpdateGeneration)
        if let cached = applicationCountProjection, cached.apps == key.apps,
           cached.homebrew == key.homebrew, cached.updates == key.updates {
            return cached.counts
        }
        var counts = Dictionary(uniqueKeysWithValues: Self.applicationSourceDestinations.map { ($0, 0) })
        for app in apps {
            for destination in Self.applicationSourceDestinations where application(app, belongsTo: destination) {
                counts[destination, default: 0] += 1
            }
        }
        applicationCountProjection = (key.apps, key.homebrew, key.updates, counts)
        return counts
    }

    func application(_ app: InstalledApp, belongsTo destination: SidebarDestination) -> Bool {
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

    /// Sidebar badge: pending updates that are not skipped or ignored. Pages
    /// without updates of their own (History, CVE Checker) have no badge.
    /// Source-row visibility uses the inventory `applicationSourceCounts()`.
    func count(for destination: SidebarDestination) -> Int {
        switch destination {
        case .updates: totalUpdateCount
        case .allApps: visibleUpdates.count
        case .adoptable: adoptableApps.count { visibleUpdate(for: $0.app) != nil }
        case .homebrewPackages: outdatedPackageCount
        case .macOSUpdates: macOSUpdates.count { !$0.isFullInstaller }
        case .history, .cveChecker: 0
        case .developerPackages: outdatedDeveloperPackageCount
        case .localModels: outdatedLocalModelCount
        default: visibleUpdateSourceCounts()[destination]
            ?? visibleUpdates.count { application($0.app, belongsTo: destination) }
        }
    }

    /// Visible (non-excluded) update counts per `applicationSourceDestinations`
    /// entry, computed in one pass and cached until inventory or exclusions change.
    func visibleUpdateSourceCounts() -> [SidebarDestination: Int] {
        let key = VisibleUpdateCountKey(apps: library.appGeneration, homebrew: library.homebrewGeneration,
            updates: library.primaryUpdateGeneration, exclusions: settings.exclusionCacheRevision)
        let now = Date()
        if let cached = visibleUpdateCountProjection, cached.key == key,
           cached.expiresAt.map({ now < $0 }) ?? true {
            return cached.counts
        }
        var counts = Dictionary(uniqueKeysWithValues: Self.applicationSourceDestinations.map { ($0, 0) })
        for update in visibleUpdates {
            for destination in Self.applicationSourceDestinations where application(update.app, belongsTo: destination) {
                counts[destination, default: 0] += 1
            }
        }
        visibleUpdateCountProjection = (key, settings.nextExclusionExpiration, counts)
        return counts
    }

    func scan() async {
        let ownedRun = await fullScanCoordinator.run {
            await scanOnce()
        } runningChanged: { isScanning = $0 }
        if ownedRun { refreshCVEsAutomatically() }
        if ownedRun && didStart { scheduleNextRefresh() }
        if ownedRun { MemoryRelief.scheduleRelease() }
    }

    var cveInventory: [CVEInventoryItem] {
        apps.map(CVEInventoryItem.init) + homebrewPackages.map(CVEInventoryItem.init)
            + developerPackages.map(CVEInventoryItem.init)
    }

    func makeCVEClient() -> CVEInventoryClient {
        dependencies.makeCVEClient?() ?? CVEInventoryClient()
    }

    /// Coalesces inventory changes while a manual or automatic check is active.
    /// A CVE request never holds up the updater's own scan or operation queue.
    /// Unchanged inventory with fresh, successful results is not re-checked,
    /// and a changed inventory only re-checks new, changed or failed items.
    /// `force` re-checks everything (used when automatic checks are enabled).
    func refreshCVEsAutomatically(force: Bool = false) {
        guard settings.automaticallyCheckCVEs, dependencies.makeCVEClient != nil,
              automaticCVETask == nil, !cveInventory.isEmpty else { return }
        if !force, cveScanState.isCurrent(for: cveInventory) { return }
        let generation = UUID()
        automaticCVEGeneration = generation
        automaticCVETask = Task { [weak self] in
            guard let self else { return }
            defer {
                if automaticCVEGeneration == generation {
                    automaticCVETask = nil; automaticCVEGeneration = nil; automaticCVEOwnsScan = false
                }
            }
            if cveScanState.running {
                await cveScanState.waitForCompletion()
                if cveScanState.inventory == cveInventory && !cveScanState.results.contains(where: { $0.failure != nil }) { return }
            }
            repeat {
                guard settings.automaticallyCheckCVEs, !Task.isCancelled else { return }
                let inventory = cveInventory
                automaticCVEOwnsScan = cveScanState.start(inventory: inventory, client: makeCVEClient(),
                                                          reuseFreshResults: !force)
                await cveScanState.waitForCompletion()
                if inventory == cveInventory { return }
            } while settings.automaticallyCheckCVEs
        }
    }

    func setAutomaticCVEChecking(_ enabled: Bool) {
        settings.automaticallyCheckCVEs = enabled
        if enabled { refreshCVEsAutomatically(force: true) }
        else {
            if automaticCVEOwnsScan { cveScanState.cancel() }
            automaticCVETask?.cancel()
            automaticCVETask = nil
            automaticCVEGeneration = nil
            automaticCVEOwnsScan = false
        }
    }

    func waitForAutomaticCVECheck() async { await automaticCVETask?.value }

    var showsDeveloperInventory: Bool {
        settings.sidebarViewMode == .advanced
            && installedDeveloperManagers.contains(where: settings.enabledDeveloperManagers.contains)
    }

    private var pendingCVESoftware: CVEInventoryItem?

    func showCVESoftware(_ item: CVEInventoryItem) {
        if let id = item.id.removingPrefix("brew|"), !settings.checkHomebrew {
            showSoftwareInSearch(named: item.name, result: .homebrew(id))
        } else if let id = item.id.removingPrefix("developer|"), !showsDeveloperInventory {
            showSoftwareInSearch(named: item.name, result: .developer(id))
        } else {
            pendingCVESoftware = item
            navigation.searchText = ""
            if item.id.hasPrefix("app|") {
                navigation.selection = .allApps
                appListFilter = .all
            } else if item.id.hasPrefix("brew|") {
                navigation.selection = .homebrewPackages
                homebrewFilter = .all
            } else {
                navigation.selection = .developerPackages
                developerManagerFilter = .all
                settings.showCurrentDeveloperPackages = true
            }
        }
    }

    private func showSoftwareInSearch(named name: String, result: SearchResultSelection) {
        selectedApp = nil
        updateInspectorSelection = nil
        navigation.searchText = name
        navigation.requestedSearchResult = result
    }

    /// Apply focus after the destination change clears the previous inspector selection.
    func completeCVESoftwareNavigation() {
        guard let item = pendingCVESoftware else { return }
        pendingCVESoftware = nil
        if navigation.selection == .allApps, let id = item.id.removingPrefix("app|") {
            selectedApp = app(forID: id)
        } else if navigation.selection == .homebrewPackages, let id = item.id.removingPrefix("brew|") {
            selectedPackageID = homebrewPackage(forID: id)?.id
        } else if navigation.selection == .developerPackages, let id = item.id.removingPrefix("developer|") {
            selectedDeveloperPackageID = developerPackage(forID: id)?.id
        }
    }

    func showCVEInfo(for item: CVEInventoryItem) {
        selectedApp = nil
        updateInspectorSelection = nil
        navigation.searchText = ""
        cveScanState.filter = .all
        cveScanState.searchText = item.name
        cveScanState.requestedItemID = item.id
        navigation.selection = .cveChecker
    }

    func revealInventoryResult(_ result: InventoryReveal) {
        navigation.inventoryReveal = result
        navigation.searchText = ""
        navigation.selection = result.destination
    }

    private func publishScanProgress(_ event: ScanProgressEvent, generation: UUID, revision: UInt64, started: Date) {
        guard scanState.generation == generation else { return }
        switch event {
        case let .localModels(report, runtimes):
            if scanState.firstResultSeconds == nil { scanState.firstResultSeconds = Date().timeIntervalSince(started) }
            let owned = Set(LocalModelRuntime.allCases.filter { scanState.sourceRevisions["model.runtime|\($0.rawValue)", default: 0] > revision })
            var merged = Dictionary(report.models.filter { runtimes.contains($0.runtime) && !owned.contains($0.runtime) }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for previous in localModels where report.failedModelIDs.contains(previous.id)
                || report.failedRuntimes.contains(previous.runtime) || owned.contains(previous.runtime)
                || !runtimes.contains(previous.runtime) { merged[previous.id] = previous }
            localModels = merged.values.sorted(by: ScanResultReconciliation.modelOrder)
            if selectedLocalModelID == nil || !localModels.contains(where: { $0.id == selectedLocalModelID }) {
                selectedLocalModelID = localModels.first?.id
            }
        case let .developerPackages(report, managers):
            if scanState.firstResultSeconds == nil { scanState.firstResultSeconds = Date().timeIntervalSince(started) }
            let checkedManagers = managers.filter { scanState.sourceRevisions["developer|\($0.rawValue)", default: 0] <= revision }
            let previous = developerPackages.filter { checkedManagers.contains($0.manager) }
            developerPackages = developerPackages.filter { !checkedManagers.contains($0.manager) }
                + ScanResultReconciliation.developerPackages(fresh: report.packages.filter { checkedManagers.contains($0.manager) },
                    previous: previous, failedManagers: report.failedManagers,
                    failedExecutablePaths: report.failedExecutablePaths)
            developerPackages.sort(by: ScanResultReconciliation.developerOrder)
            installedDeveloperManagers = Array(Set(installedDeveloperManagers.filter {
                !checkedManagers.contains($0) || report.failedManagers.contains($0)
            }).union(report.installedManagers.filter { checkedManagers.contains($0) })).sorted { $0.rawValue < $1.rawValue }
        case let .macOS(report, includeInstallers, includePrereleases):
            if scanState.firstResultSeconds == nil { scanState.firstResultSeconds = Date().timeIntervalSince(started) }
            let previous = macOSUpdates
            let updatesPart = report.updatesSucceeded ? report.updates.filter { !$0.isFullInstaller }
                : previous.filter { !$0.isFullInstaller }
            let installersPart = !includeInstallers ? [] : report.installersSucceeded
                ? report.updates.filter(\.isFullInstaller) : previous.filter(\.isFullInstaller)
            macOSUpdates = (updatesPart + installersPart).filter { includePrereleases || !$0.isBeta }
            scanState.macOSStatus = report.updatesSucceeded ? .succeeded : .failed
        case let .homebrewInventory(packages):
            if scanState.firstResultSeconds == nil { scanState.firstResultSeconds = Date().timeIntervalSince(started) }
            homebrewPackages = preservingOwnedHomebrewPackages(packages, after: revision)
        case let .discovered(discovered):
            let current = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            apps = discovered.map { app in
                let owned = UpdateSource.allCases.contains {
                    scanState.sourceRevisions["app|\(app.id)|\($0.rawValue)", default: 0] > revision
                }
                return owned ? current[app.id] ?? app : app
            }
        case let .appSource(appID, source, update, warning, completed, total):
            if scanState.firstResultSeconds == nil { scanState.firstResultSeconds = Date().timeIntervalSince(started) }
            scanState.progress = ScanProgress(completed: completed, total: total, lastSource: source)
            guard scanState.sourceRevisions["app|\(appID)|\(source.rawValue)", default: 0] <= revision else { return }
            guard let app = apps.first(where: { $0.id == appID }) else { return }
            var candidates = updates.first(where: { $0.app.id == appID })?.candidates ?? []
            if warning == nil {
                candidates.removeAll { $0.source == source }
                scanState.failedAppSources[appID]?.remove(source)
            } else {
                scanState.failedAppSources[appID, default: []].insert(source)
            }
            if let update { candidates.append(contentsOf: update.candidates) }
            candidates = candidates.filter { $0.isNewer(than: app) }
            // Work on a local copy and publish once, only when something changed.
            var next = updates
            next.removeAll { $0.app.id == appID }
            if !candidates.isEmpty { Self.insertSortedByName(AvailableUpdate(app: app, candidates: candidates), into: &next) }
            if next != updates { updates = next }
        }
    }

    /// Equivalent to appending and then stable-sorting by name, without
    /// re-sorting an already sorted list.
    static func insertSortedByName(_ update: AvailableUpdate, into list: inout [AvailableUpdate]) {
        func ascending(_ left: AvailableUpdate, _ right: AvailableUpdate) -> Bool {
            left.app.name.localizedStandardCompare(right.app.name) == .orderedAscending
        }
        guard zip(list, list.dropFirst()).allSatisfy({ !ascending($1, $0) }) else {
            list.append(update)
            list.sort(by: ascending)
            return
        }
        // Upper bound: after every element that does not sort after `update`.
        var low = 0, high = list.count
        while low < high {
            let mid = (low + high) / 2
            if ascending(update, list[mid]) { high = mid } else { low = mid + 1 }
        }
        list.insert(update, at: low)
    }

    private func scanOnce() async {
        let generation = UUID()
        scanState.revision &+= 1
        let revision = scanState.revision
        scanState.latestFullRevision = revision
        scanState.sourceRevisions = scanState.sourceRevisions.filter { $0.value > revision }
        let started = Date()
        scanState.generation = generation
        scanState.progress = nil
        scanState.firstResultSeconds = nil
        defer { if scanState.generation == generation { scanState.progress = nil; scanState.generation = nil } }
        errorMessage = nil
        let previousCount = totalUpdateCount
        let scanSettings = settings.scanSettings
        let report = await SourceRequestPriority.$current.withValue(.background) {
            await dependencies.scanner.scan(settings: scanSettings) { event in
                await self.publishScanProgress(event, generation: generation, revision: revision, started: started)
            }
        }
        let history = await dependencies.history.records()
        let protectedKeys = Set(scanState.sourceRevisions.filter { $0.value > revision }.keys)
        let protectedUpdates = updates
        let protectedApps = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let protectedFailures = scanState.failedAppSources
        recordScanFreshness(report, settings: scanSettings, protecting: protectedKeys)
        scanState.completedCheckState = UpdateCheckState.completed(report: report, settings: scanSettings)
        scanState.macOSStatus = report.macOSUpdatesStatus
        scanState.failedAppSources = report.failedAppSources
        apps = report.apps
        for app in apps {
            settings.migrateExclusion(from: legacyExclusionKey(for: app), to: exclusionKey(for: app))
        }
        updates = mergedUpdates(from: report)
        if !protectedKeys.isEmpty {
            var restored: [AvailableUpdate] = []
            for app in apps {
                let sources = Set(UpdateSource.allCases.filter { protectedKeys.contains("app|\(app.id)|\($0.rawValue)") })
                let installed = sources.isEmpty ? app : protectedApps[app.id] ?? app
                if !sources.isEmpty, let index = apps.firstIndex(where: { $0.id == app.id }) { apps[index] = installed }
                var candidates = updates.first { $0.app.id == app.id }?.candidates.filter { !sources.contains($0.source) } ?? []
                candidates += protectedUpdates.first { $0.app.id == app.id }?.candidates.filter { sources.contains($0.source) } ?? []
                candidates = candidates.filter { $0.isNewer(than: installed) }
                if !candidates.isEmpty { restored.append(AvailableUpdate(app: installed, candidates: candidates)) }
                var failures = scanState.failedAppSources[app.id] ?? []
                failures.subtract(sources)
                failures.formUnion((protectedFailures[app.id] ?? []).intersection(sources))
                scanState.failedAppSources[app.id] = failures.isEmpty ? nil : failures
            }
            updates = restored.sorted { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending }
        }
        let protectedHomebrewPackages = homebrewPackages.filter {
            protectedKeys.contains("homebrew|\($0.kind.rawValue)|\($0.token)")
        }
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
        for package in protectedHomebrewPackages {
            homebrewPackages.removeAll { $0.id == package.id }
            homebrewPackages.append(package)
        }
        let registeredCasks = Set(homebrewPackages.filter { $0.kind == .cask }.map(\.token))
        adoptableApps.removeAll { registeredCasks.contains($0.caskToken) }
        homebrewPackages.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        macOSUpdates = ScanResultReconciliation.macOS(report, previous: macOSUpdates)
        updateHistory = history
        let protectedManagers = Set(DeveloperPackageManager.allCases.filter { protectedKeys.contains("developer|\($0.rawValue)") })
        let ownedPackages = developerPackages.filter { protectedManagers.contains($0.manager) }
        developerPackages = (ScanResultReconciliation.developer(report, previous: developerPackages).filter { !protectedManagers.contains($0.manager) } + ownedPackages).sorted(by: ScanResultReconciliation.developerOrder)
        installedDeveloperManagers = Array(Set(report.installedDeveloperManagers.filter { !protectedManagers.contains($0) })
            .union(installedDeveloperManagers.filter { protectedManagers.contains($0) })).sorted { $0.rawValue < $1.rawValue }
        let protectedRuntimes = Set(LocalModelRuntime.allCases.filter { protectedKeys.contains("model.runtime|\($0.rawValue)") })
        let ownedModels = localModels.filter { protectedRuntimes.contains($0.runtime) }
        localModels = (ScanResultReconciliation.models(report, previous: localModels).filter { !protectedRuntimes.contains($0.runtime) } + ownedModels).sorted(by: ScanResultReconciliation.modelOrder)
        let verifiedApps = report.apps.filter { app in
            guard !UpdateSource.allCases.contains(where: {
                protectedKeys.contains("app|\(app.id)|\($0.rawValue)")
            }) else { return false }
            let sources = enabledAppUpdateSources(for: app, checkAppStore: scanSettings.checkAppStore,
                checkSparkle: scanSettings.checkSparkle, checkGitHub: scanSettings.checkGitHub)
            return !sources.isEmpty && (report.failedAppSources[app.id] ?? []).isEmpty
        }
        settings.recordChecks(
            for: verifiedApps.map(exclusionKey(for:))
                + (report.homebrewInventoryStatus == .succeeded ? report.homebrewPackages.filter {
                    !protectedKeys.contains("homebrew|\($0.kind.rawValue)|\($0.token)")
                }.map(exclusionKey(for:)) : [])
                + report.developerPackages.filter { !protectedManagers.contains($0.manager) && !report.failedDeveloperManagers.contains($0.manager)
                    && !report.failedDeveloperExecutablePaths.contains($0.executablePath) }.map(exclusionKey(for:))
                + report.localModels.filter { !protectedRuntimes.contains($0.runtime) && !report.failedLocalModelIDs.contains($0.id)
                    && !report.failedLocalModelRuntimes.contains($0.runtime) }.map(exclusionKey(for:)),
            at: report.checkedAt
        )
        // Forget check records for items that are no longer installed.
        settings.pruneCheckRecords(
            keepingItemKeys: Set(apps.map(exclusionKey(for:)) + homebrewPackages.map(exclusionKey(for:))
                + developerPackages.map(exclusionKey(for:)) + localModels.map(exclusionKey(for:))),
            appIDs: Set(apps.map(\.id))
        )
        scanWarnings = reconciledScanWarnings(report.warnings, protectedKeys: protectedKeys)
        if scanState.completedCheckState == .complete,
           (scanState.failedAppSources.values.contains(where: { !$0.isEmpty })
            || protectedKeys.contains(where: { settings.sourceCheckFreshness[$0]?.failure != nil })) {
            scanState.completedCheckState = .partial
        }
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

    private func reconciledScanWarnings(_ reported: [ScanWarning], protectedKeys: Set<String>) -> [ScanWarning] {
        guard !protectedKeys.isEmpty else { return reported }
        var warnings: [ScanWarning] = []
        for warning in reported {
            if warning.itemNamesByID != nil {
                let protectedIDs = Set(apps.filter { app in
                    UpdateSource.allCases.contains { source in
                        source.warningSource == warning.source && protectedKeys.contains("app|\(app.id)|\(source.rawValue)")
                    }
                }.map(\.id))
                if let remaining = warning.removingItems(ids: protectedIDs) { warnings.append(remaining) }
                continue
            }
            var removed = Set(apps.filter { app in
                UpdateSource.allCases.contains { source in
                    source.warningSource == warning.source && protectedKeys.contains("app|\(app.id)|\(source.rawValue)")
                }
            }.map(\.name)).intersection(warning.itemNames)
            if warning.source == .developerPackages {
                removed.formUnion(DeveloperPackageManager.allCases.filter { protectedKeys.contains("developer|\($0.rawValue)") }.map(\.rawValue).filter { warning.itemNames.contains($0) })
            }
            if warning.source == .localModels {
                removed.formUnion(LocalModelRuntime.allCases.filter { protectedKeys.contains("model.runtime|\($0.rawValue)") }.map(\.rawValue).filter { warning.itemNames.contains($0) })
            }
            guard !removed.isEmpty else { warnings.append(warning); continue }
            let count = max(0, warning.affectedItemCount - removed.count)
            if count > 0 {
                warnings.append(ScanWarning(source: warning.source, itemNames: warning.itemNames.filter { !removed.contains($0) },
                    affectedItemCount: count, message: warning.message))
            }
        }
        for app in apps {
            for source in scanState.failedAppSources[app.id] ?? [] {
                let key = "app|\(app.id)|\(source.rawValue)"
                guard protectedKeys.contains(key) else { continue }
                warnings.append(ScanWarning(source: source.warningSource, itemNames: [app.name], itemNamesByID: [app.id: app.name],
                    message: settings.sourceCheckFreshness[key]?.failure ?? "This source could not be verified."))
            }
        }
        for manager in DeveloperPackageManager.allCases {
            let key = "developer|\(manager.rawValue)"
            if protectedKeys.contains(key), let failure = settings.sourceCheckFreshness[key]?.failure {
                warnings.append(ScanWarning(source: .developerPackages, itemNames: [manager.rawValue], message: failure))
            }
        }
        for runtime in LocalModelRuntime.allCases {
            let key = "model.runtime|\(runtime.rawValue)"
            if protectedKeys.contains(key), let failure = settings.sourceCheckFreshness[key]?.failure {
                warnings.append(ScanWarning(source: .localModels, itemNames: [runtime.rawValue], message: failure))
            }
        }
        return warnings
    }

    func refresh(_ app: InstalledApp, sources sourceFilter: Set<UpdateSource>? = nil) async {
        defer { refreshCVEsAutomatically() }
        let operationID = OperationID.applicationRefresh(app.id)
        guard !isWorking(operationID) else { return }
        updateExecutionState.activeOperations.insert(operationID)
        defer { updateExecutionState.activeOperations.remove(operationID) }
        scanState.revision &+= 1
        let revision = scanState.revision
        for source in enabledUpdateSources(for: app).filter({ sourceFilter?.contains($0) ?? true }) {
            scanState.sourceRevisions["app|\(app.id)|\(source.rawValue)"] = scanState.revision
        }

        let refreshedApp = await dependencies.applicationDiscovery.discover(at: app.url) ?? app
        guard !isAppRefreshSuperseded(app.id, revision: revision) else { return }
        if let index = apps.firstIndex(where: { $0.id == app.id }) { apps[index] = refreshedApp }
        if selectedApp?.id == app.id { selectedApp = refreshedApp }

        var scanSettings = settings.scanSettings
        scanSettings.appSourceFilter = sourceFilter
        let report = await dependencies.scanner.scan(app: refreshedApp, settings: scanSettings)
        guard !isAppRefreshSuperseded(app.id, revision: revision) else { return }
        let checkedAt = Date()
        recordAppSourceChecks(app: refreshedApp, settings: scanSettings, failed: report.failedSources, warnings: report.warnings, at: checkedAt)
        let enabledSources = enabledUpdateSources(for: refreshedApp).filter { sourceFilter?.contains($0) ?? true }
        let remainingFailures = sourceFilter == nil ? report.failedSources
            : (scanState.failedAppSources[app.id] ?? []).subtracting(enabledSources).union(report.failedSources)
        scanState.failedAppSources[app.id] = remainingFailures.isEmpty ? nil : remainingFailures
        var candidates = (updates.first(where: { $0.app.id == app.id })?.candidates ?? [])
            .filter { $0.isNewer(than: refreshedApp) }
        candidates.removeAll { candidate in
            candidate.source != .homebrew
                && enabledSources.contains(candidate.source)
                && !report.failedSources.contains(candidate.source)
        }
        candidates.append(contentsOf: report.updates.flatMap(\.candidates))

        if let existingPackage = homebrewPackage(for: refreshedApp), settings.checkHomebrew,
           sourceFilter?.contains(.homebrew) ?? true {
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

        // An install or newer scan may have claimed this app during the Homebrew request.
        guard !isAppRefreshSuperseded(app.id, revision: revision) else { return }
        candidates = candidates.filter {
            guard $0.isNewer(than: refreshedApp) else { return false }
            return !$0.requiresHomebrewAdoption
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
        for source in enabledSources.map(\.warningSource) {
            scanWarnings = reconcileSourceWarnings(existing: scanWarnings,
                fresh: report.warnings.filter { $0.source == source }, source: source,
                checkedName: app.name, checkedID: app.id)
        }
        scanWarnings.append(contentsOf: report.warnings.filter { !affectedSources.contains($0.source.rawValue) })
        if sourceFilter == nil && !enabledSources.isEmpty && report.failedSources.isEmpty {
            settings.recordCheck(for: exclusionKey(for: refreshedApp), at: checkedAt)
        }
        refreshDiagnostics()
    }

    /// A per-app refresh must not publish a bundle snapshot older than one an
    /// install or later scan has already claimed for the same app.
    private func isAppRefreshSuperseded(_ appID: String, revision: UInt64) -> Bool {
        guard scanState.latestFullRevision <= revision else { return true }
        return UpdateSource.allCases.contains {
            scanState.sourceRevisions["app|\(appID)|\($0.rawValue)", default: 0] > revision
        }
    }

    func scanMacOSSource(_ scope: MacOSScanScope) async {
        guard !isScanning, !isWorking(.macOSSourceScan) else { return }
        updateExecutionState.activeOperations.insert(.macOSSourceScan)
        defer { updateExecutionState.activeOperations.remove(.macOSSourceScan) }
        let key = scope == .updates ? "macos.updates" : "macos.installers"
        let prefix = scope == .updates ? "Available updates:" : "Full installers:"
        let fullRevision = scanState.latestFullRevision
        let attempt = Date()
        func recordFailure(_ message: String) {
            settings.recordSourceAttempt(key, at: attempt, failure: message)
            scanWarnings.removeAll { $0.source == .macOS && $0.message.hasPrefix(prefix) }
            scanWarnings.append(ScanWarning(source: .macOS, message: "\(prefix) \(message)"))
            if scope == .updates { scanState.macOSStatus = .failed }
        }
        do {
            let report = try await dependencies.scanner.macOS(scope: scope)
            guard scanState.latestFullRevision == fullRevision else { return }
            let succeeded = scope == .updates ? report.updatesSucceeded : report.installersSucceeded
            guard succeeded else {
                recordFailure(report.warnings.isEmpty ? "The source check failed." : report.warnings.joined(separator: "\n"))
                return
            }
            let installers = scope == .installers
            macOSUpdates = macOSUpdates.filter { $0.isFullInstaller != installers }
                + report.updates.filter { $0.isFullInstaller == installers && (settings.includePrereleaseUpdates || !$0.isBeta) }
            settings.recordSourceAttempt(key, at: attempt)
            scanWarnings.removeAll { $0.source == .macOS && $0.message.hasPrefix(prefix) }
            if scope == .updates { scanState.macOSStatus = .succeeded }
        } catch {
            guard scanState.latestFullRevision == fullRevision else { return }
            recordFailure(error.localizedDescription)
        }
    }

    func scanHomebrewCatalog() async {
        await mutationCoordinator.withAccess(to: [.packageEnvironment("homebrew")], otherwise: ()) {
            guard !self.isScanning, !self.isWorking(.homebrewCatalogScan) else { return }
            self.updateExecutionState.activeOperations.insert(.homebrewCatalogScan)
            defer { self.updateExecutionState.activeOperations.remove(.homebrewCatalogScan) }
            let fullRevision = self.scanState.latestFullRevision
            let attempt = Date()
            do {
                let catalog = try await self.dependencies.scanner.homebrewCatalog()
                guard self.scanState.latestFullRevision == fullRevision else { return }
                self.adoptableApps = HomebrewClient.adoptableApps(from: self.apps, catalog: catalog, excluding: self.homebrewPackages)
                self.scanWarnings.removeAll { $0.source == .homebrew && $0.message.hasPrefix("Cask catalog:") }
                self.settings.recordSourceAttempt("homebrew.catalog", at: attempt)
            } catch {
                guard self.scanState.latestFullRevision == fullRevision else { return }
                self.settings.recordSourceAttempt("homebrew.catalog", at: attempt, failure: error.localizedDescription)
                self.scanWarnings.removeAll { $0.source == .homebrew && $0.message.hasPrefix("Cask catalog:") }
                self.scanWarnings.append(ScanWarning(source: .homebrew, message: "Cask catalog: \(error.localizedDescription)"))
                self.errorMessage = "Could not refresh Homebrew catalogue: \(error.localizedDescription)"
            }
        }
    }

    func scanHomebrewInventory() async {
        defer { refreshCVEsAutomatically() }
        await mutationCoordinator.withAccess(to: [.packageEnvironment("homebrew")], otherwise: ()) {
            guard !self.isScanning, !self.isWorking(.homebrewInventoryScan) else { return }
            self.updateExecutionState.activeOperations.insert(.homebrewInventoryScan)
            defer { self.updateExecutionState.activeOperations.remove(.homebrewInventoryScan) }
            let fullRevision = self.scanState.latestFullRevision
            let attempt = Date()
            do {
                let packages = try await self.dependencies.scanner.homebrewInventory(includePrereleases: self.settings.includePrereleaseUpdates)
                guard self.scanState.latestFullRevision == fullRevision else { return }
                self.reconcileHomebrewInventory(packages)
                self.scanWarnings.removeAll { $0.source == .homebrew && $0.message.hasPrefix("Installed packages:") }
                self.settings.recordSourceAttempt("homebrew.inventory", at: attempt)
            } catch {
                guard self.scanState.latestFullRevision == fullRevision else { return }
                self.settings.recordSourceAttempt("homebrew.inventory", at: attempt, failure: error.localizedDescription)
                self.scanWarnings.removeAll { $0.source == .homebrew && $0.message.hasPrefix("Installed packages:") }
                self.scanWarnings.append(ScanWarning(source: .homebrew, message: "Installed packages: \(error.localizedDescription)"))
                self.errorMessage = "Could not refresh Homebrew inventory: \(error.localizedDescription)"
            }
        }
    }

    private func reconcileHomebrewInventory(_ packages: [HomebrewPackage]) {
        homebrewPackages = packages.map { package in
            guard package.kind == .cask, let app = matchingApp(for: package) else { return package }
            return package.reconciled(with: app)
        }
        var byApp: [String: AvailableUpdate] = [:]
        for update in updates {
            let retained = update.candidates.filter { $0.source != .homebrew }
            if !retained.isEmpty { byApp[update.app.id] = AvailableUpdate(app: update.app, candidates: retained) }
        }
        for package in homebrewPackages where package.kind == .cask && package.isOutdated {
            guard let app = matchingApp(for: package), UpdateScanner.allowsHomebrewCandidate(for: app) else { continue }
            let offer = AvailableUpdate(app: app, availableVersion: package.currentVersion, source: .homebrew,
                releaseNotes: nil, actionURL: nil, homebrewToken: package.token)
            let candidates = (byApp[app.id]?.candidates ?? []) + offer.candidates
            byApp[app.id] = AvailableUpdate(app: app, candidates: candidates)
        }
        updates = byApp.values.sorted { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending }
        let installedTokens = Set(homebrewPackages.filter { $0.kind == .cask }.map(\.token))
        adoptableApps.removeAll { installedTokens.contains($0.caskToken) }
    }

    func refresh(_ package: HomebrewPackage) async {
        defer { refreshCVEsAutomatically() }
        let operationID = OperationID.homebrewRefresh(package.id)
        guard !isWorking(operationID) else { return }
        updateExecutionState.activeOperations.insert(operationID)
        defer { updateExecutionState.activeOperations.remove(operationID) }
        let key = "homebrew|\(package.kind.rawValue)|\(package.token)"
        let attemptedAt = Date()
        do {
            guard let refreshed = try await dependencies.homebrew.package(
                token: package.token,
                kind: package.kind,
                includePrereleases: settings.includePrereleaseUpdates
            ) else {
                errorMessage = "Homebrew no longer reports \(package.displayName) as installed."
                settings.recordSourceAttempt(key, at: attemptedAt, failure: errorMessage)
                return
            }
            settings.recordSourceAttempt(key, at: attemptedAt)
            replaceHomebrewPackage(refreshed)
            if let app = homebrewPackageApp(for: refreshed) { await refresh(app) }
            settings.recordCheck(for: exclusionKey(for: refreshed), at: Date())
            refreshDiagnostics()
        } catch {
            errorMessage = "Could not refresh \(package.displayName): \(error.localizedDescription)"
            settings.recordSourceAttempt(key, at: attemptedAt, failure: errorMessage)
        }
    }

    func refresh(_ package: DeveloperPackage) async {
        defer { refreshCVEsAutomatically() }
        let operationID = OperationID.developerRefresh(package.id)
        guard !isWorking(operationID) else { return }
        updateExecutionState.activeOperations.insert(operationID)
        defer { updateExecutionState.activeOperations.remove(operationID) }
        let sourceKey = "developer.versions|\(package.id)"
        let attemptedAt = Date()
        let versions = await dependencies.developerPackages.availableVersions(
            for: package,
            includePrereleases: settings.includePrereleaseUpdates
        )
        guard let latest = versions.first else {
            errorMessage = "No published versions were returned for \(package.name)."
            settings.recordSourceAttempt(sourceKey, at: attemptedAt, failure: errorMessage)
            return
        }
        settings.recordSourceAttempt(sourceKey, at: attemptedAt)
        let refreshed = package.replacingLatestVersion(with: latest)
        if let index = developerPackages.firstIndex(where: { $0.id == package.id }) {
            developerPackages[index] = refreshed
        }
        versionCache[developerVersionCacheKey(for: refreshed)] = versions
        if selectedDeveloperPackageID == package.id {
            availableDeveloperVersions = versions
            selectedDeveloperVersion = latest
        }
        settings.recordCheck(for: exclusionKey(for: refreshed), at: Date())
        refreshDiagnostics()
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        await dependencies.history.maintainStorage()
        refreshRunningApplications()
        observeRunningApplications()
        if settings.checkOnLaunch { await scan() }
        scheduleNextRefresh()
    }

    func scheduleNextRefresh() {
        let nextDate = settings.refreshInterval.nextDate(
            after: lastChecked ?? startedAt,
            dailyTimeMinutes: settings.dailyRefreshTimeMinutes
        )
        nextScheduledCheck = nextDate
        refreshScheduler.schedule(at: nextDate) { [weak self] in
            await self?.scan()
        }
    }

    func scanDeveloperPackages(manager: DeveloperPackageManager?) async {
        defer { refreshCVEsAutomatically() }
        let identifier = OperationID.developerScan(manager)
        guard !isWorking(identifier) else { return }
        updateExecutionState.activeOperations.insert(identifier)
        defer { updateExecutionState.activeOperations.remove(identifier) }
        let managers = manager.map { Set([$0]) } ?? settings.enabledDeveloperManagers
        scanState.revision &+= 1
        let revision = scanState.revision
        for checked in managers { scanState.sourceRevisions["developer|\(checked.rawValue)"] = revision }
        let report = await dependencies.developerPackages.scan(
            enabledManagers: managers,
            includePrereleases: settings.includePrereleaseUpdates
        )
        guard scanState.latestFullRevision <= revision else { return }
        settings.recordSourceAttempts(Dictionary(uniqueKeysWithValues: managers.map { manager in
            let failed = report.hasFailures(for: manager)
            return ("developer|\(manager.rawValue)", failed ? "Some packages in this environment could not be verified." : "")
        }), at: Date())
        scanWarnings = reconcileSourceWarnings(
            existing: scanWarnings, fresh: report.scanWarnings, source: .developerPackages,
            checkedName: manager?.rawValue
        )
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
            developerPackages = ScanResultReconciliation.developerPackages(
                fresh: report.packages, previous: developerPackages,
                failedManagers: report.failedManagers,
                failedExecutablePaths: report.failedExecutablePaths
            ).sorted(by: ScanResultReconciliation.developerOrder)
            installedDeveloperManagers = report.installedManagers
            versionCache.removeAll()
        }
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
        defer { refreshCVEsAutomatically() }
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
                    activity: operationID,
                    metadata: updateDiagnosticMetadata(update)
                ) { try await self.dependencies.homebrew.upgradeCask(token: token) }
                let package = HomebrewPackage(token: token, displayName: update.app.name,
                    description: nil, homepage: nil, license: nil,
                    installedVersion: update.app.installedVersion, currentVersion: update.availableVersion,
                    kind: .cask, isOutdated: true, isDependency: false, dependencies: [])
                return await verifyCaskMutation(package, original: update.app, record: record,
                    commandSucceeded: succeeded, commandError: errorMessage, operationID: operationID)

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
                activity: operationID,
                metadata: updateDiagnosticMetadata(update)
            ) {
                try await self.dependencies.directAppInstaller.install(update: update) { phase in
                    await self.setUpdatePhase(phase, for: operationID)
                }
            }
            return await verifyDirectInstallation(update, record: record, commandSucceeded: succeeded,
                commandError: errorMessage, operationID: operationID)

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
        defer { refreshCVEsAutomatically() }
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
        let succeeded = await execute(label: package.displayName, activity: operationID, metadata: [
            "Source": "Homebrew",
            "From": package.installedVersion,
            "To": package.currentVersion
        ]) { try await self.dependencies.homebrew.upgrade(package) }
        if package.kind == .formula {
            return await verifyFormulaMutation(package, record: record, commandSucceeded: succeeded,
                commandError: errorMessage, operationID: operationID)
        }
        guard let original = matchingApp(for: package) else {
            return await verifyFormulaMutation(package, record: record, commandSucceeded: succeeded,
                commandError: errorMessage, operationID: operationID)
        }
        return await verifyCaskMutation(package, original: original, record: record,
            commandSucceeded: succeeded, commandError: errorMessage, operationID: operationID)
    }

    private func claimVerifiedAppState(_ app: InstalledApp) {
        scanState.revision &+= 1
        for source in UpdateSource.allCases {
            scanState.sourceRevisions["app|\(app.id)|\(source.rawValue)"] = scanState.revision
        }
    }

    private func verifyDirectInstallation(_ update: AvailableUpdate, record: UpdateRecord,
                                          commandSucceeded: Bool, commandError: String?,
                                          operationID: OperationID) async -> Bool {
        setUpdatePhase(.refreshing, for: operationID)
        let installed = await dependencies.applicationDiscovery.discover(at: update.app.url)
        let verification = AppInstallationVerification.evaluate(original: update.app, observed: installed,
            targetVersion: update.availableVersion, targetBuild: update.primaryCandidate.availableBuildVersion,
            comparesBuild: update.primaryCandidate.comparesBuildVersion)
        recordOperationVerification(verification == .unverified ? .unverified : verification == .unchanged ? .unchanged : .verified,
                                    for: operationID, commandError: commandError,
                                    verification: verification == .unverified ? nil : installed.map { app in
                                        OperationVerificationDetail(requested: update.availableVersion + (update.primaryCandidate.availableBuildVersion.map { " (build \($0))" } ?? ""),
                                            observed: app.installedVersion + (app.buildVersion.map { " (build \($0))" } ?? ""),
                                            targetReached: AppInstallationVerification.targetReached(observed: app,
                                                version: update.availableVersion, build: update.primaryCandidate.availableBuildVersion,
                                                comparesBuild: update.primaryCandidate.comparesBuildVersion))
                                    })
        guard verification != .unverified, let installed else {
            errorMessage = commandError ?? "The installed bundle for \(update.app.name) could not be verified. Its recovery backup was retained."
            return false
        }
        claimVerifiedAppState(installed)
        if let index = apps.firstIndex(where: { $0.id == update.app.id }) { apps[index] = installed }
        updates = updates.compactMap { candidate in
            guard candidate.app.id == update.app.id else { return candidate }
            let remaining = candidate.candidates.filter { $0.isNewer(than: installed) }
            return remaining.isEmpty ? nil : AvailableUpdate(app: installed, candidates: remaining)
        }
        guard verification != .unchanged else {
            await dependencies.history.discardBackup(for: record)
            errorMessage = commandError ?? "The installer finished, but \(update.app.name) is still installed at \(installed.installedVersion)."
            return false
        }
        let warning = await saveUpdateHistory(UpdateRecord(id: record.id, date: record.date, name: record.name,
            fromVersion: record.fromVersion, toVersion: installed.installedVersion, kind: record.kind,
            originalAppPath: record.originalAppPath, backupPath: record.backupPath, recoveryNote: record.recoveryNote,
            fromBuildVersion: update.app.buildVersion, toBuildVersion: installed.buildVersion))
        settings.recordCheck(for: exclusionKey(for: installed), at: Date())
        errorMessage = commandError.map { "Installed \(installed.installedVersion), but the installer reported: \($0)" } ?? warning
        if verification == .changed(targetReached: false), errorMessage == nil {
            errorMessage = "Installed \(installed.installedVersion), but the requested version or build for \(update.app.name) was not reached."
        }
        return commandSucceeded && verification == .changed(targetReached: true)
    }

    private func verifyCaskMutation(_ package: HomebrewPackage, original: InstalledApp,
                                    record: UpdateRecord?, commandSucceeded: Bool,
                                    commandError: String?, operationID: OperationID) async -> Bool {
        setUpdatePhase(.refreshing, for: operationID)
        let key = "homebrew|Cask|\(package.token)"
        let target = package.currentVersion.split(separator: ",", maxSplits: 1).map(String.init)
        let installedBundle = await dependencies.applicationDiscovery.discover(at: original.url)
        let verification = AppInstallationVerification.evaluate(original: original, observed: installedBundle,
            targetVersion: target.first ?? package.currentVersion, targetBuild: target.count == 2 ? target[1] : nil)
        recordOperationVerification(verification == .unverified ? .unverified : verification == .unchanged ? .unchanged : .verified,
                                    for: operationID, commandError: commandError,
                                    verification: verification == .unverified ? nil : installedBundle.map { app in
                                        OperationVerificationDetail(requested: package.currentVersion,
                                            observed: app.installedVersion + (app.buildVersion.map { " (build \($0))" } ?? ""),
                                            targetReached: AppInstallationVerification.targetReached(observed: app,
                                                version: target.first ?? package.currentVersion, build: target.count == 2 ? target[1] : nil))
                                    })
        guard verification != .unverified, let installed = installedBundle else {
            let message = "The installed bundle for \(package.displayName) could not be verified. Its recovery backup was retained."
            settings.recordSourceAttempt(key, at: Date(), failure: message)
            errorMessage = commandError ?? message
            return false
        }
        claimVerifiedAppState(installed)
        if let index = apps.firstIndex(where: { $0.id == original.id }) { apps[index] = installed }
        let versionComparison = VersionComparator.compare(installed.installedVersion, target.first ?? package.currentVersion)
        let buildPending = versionComparison == .orderedSame && target.count == 2
            && VersionComparator.isNewer(target[1], than: installed.buildVersion ?? "")
        let observed = HomebrewPackage(token: package.token, displayName: package.displayName,
            description: package.description, homepage: package.homepage, license: package.license,
            installedVersion: installed.installedVersion, currentVersion: package.currentVersion, kind: .cask,
            isOutdated: versionComparison == .orderedAscending || buildPending,
            isDependency: package.isDependency, dependencies: package.dependencies, tap: package.tap)
        replaceHomebrewPackage(observed)
        settings.recordSourceAttempt(key, at: Date())
        settings.recordCheck(for: exclusionKey(for: observed), at: Date())
        updates = updates.compactMap { update in
            guard update.app.id == original.id else { return update }
            let candidates = update.candidates.filter { $0.isNewer(than: installed) }
            return candidates.isEmpty ? nil : AvailableUpdate(app: installed, candidates: candidates)
        }
        guard verification != .unchanged else {
            if let record { await dependencies.history.discardBackup(for: record) }
            errorMessage = commandError ?? "Homebrew finished, but \(package.displayName) is still installed at \(installed.installedVersion)."
            return false
        }
        var historyWarning: String?
        if let record {
            historyWarning = await saveUpdateHistory(UpdateRecord(id: record.id, date: record.date, name: record.name,
                fromVersion: record.fromVersion, toVersion: installed.installedVersion, kind: record.kind,
                originalAppPath: record.originalAppPath, backupPath: record.backupPath, recoveryNote: record.recoveryNote,
                fromBuildVersion: original.buildVersion, toBuildVersion: installed.buildVersion))
        }
        errorMessage = commandError.map { "Installed \(installed.installedVersion), but Homebrew reported: \($0)" } ?? historyWarning
        if errorMessage == nil && observed.isOutdated {
            errorMessage = "Installed \(installed.installedVersion), but \(package.currentVersion) is still available for \(package.displayName)."
        }
        return commandSucceeded && errorMessage == nil && !observed.isOutdated
    }

    private func verifyFormulaMutation(
        _ package: HomebrewPackage, record: UpdateRecord?, commandSucceeded: Bool,
        commandError: String?, operationID: OperationID
    ) async -> Bool {
        setUpdatePhase(.refreshing, for: operationID)
        recordOperationVerification(.unverified, for: operationID, commandError: commandError)
        let attempt = Date()
        let sourceKey = "homebrew|\(package.kind.rawValue)|\(package.token)"
        do {
            guard let observed = try await dependencies.homebrew.package(token: package.token,
                kind: package.kind, includePrereleases: settings.includePrereleaseUpdates) else {
                settings.recordSourceAttempt(sourceKey, at: attempt, failure: "Package is no longer reported as installed.")
                errorMessage = "Homebrew finished, but \(package.displayName) is no longer reported as installed. Check Homebrew before retrying."
                return false
            }
            replaceHomebrewPackage(observed)
            settings.recordSourceAttempt(sourceKey, at: attempt, failure: nil)
            settings.recordCheck(for: exclusionKey(for: observed), at: attempt)
            let changed = observed.installedVersion != package.installedVersion
            recordOperationVerification(changed ? .verified : .unchanged, for: operationID, commandError: commandError,
                verification: OperationVerificationDetail(requested: package.currentVersion, observed: observed.installedVersion,
                    targetReached: !observed.isOutdated))
            if changed, let record {
                let actual = UpdateRecord(id: record.id, date: record.date, name: record.name,
                    fromVersion: record.fromVersion, toVersion: observed.installedVersion, kind: record.kind,
                    originalAppPath: record.originalAppPath, backupPath: record.backupPath,
                    recoveryNote: record.recoveryNote)
                let warning = await saveUpdateHistory(actual)
                if let warning { errorMessage = warning }
            }
            updateHistory = await dependencies.history.records()
            if let commandError, !commandSucceeded { errorMessage = commandError }
            else if !changed {
                errorMessage = "Homebrew completed the command, but \(package.displayName) is still installed at \(observed.installedVersion)."
            } else if observed.isOutdated {
                errorMessage = "Homebrew changed \(package.displayName) to \(observed.installedVersion), but \(observed.currentVersion) is still available."
            }
            return changed && !observed.isOutdated && errorMessage == nil
        } catch {
            settings.recordSourceAttempt(sourceKey, at: attempt, failure: error.localizedDescription)
            errorMessage = commandError ?? "Could not refresh \(package.displayName): \(error.localizedDescription)"
            return false
        }
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
            guard await updatePackageUnlocked(package) else {
                failureMessage = errorMessage ?? "Could not verify \(package.displayName)."
                break
            }
        }
        if let failureMessage {
            errorMessage = failureMessage

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
        let succeeded = await execute(label: item.app.name, activity: operationID, metadata: [
            "Source": "Homebrew adoption",
            "Installed": item.app.installedVersion,
            "Catalog": item.caskVersion
        ]) { try await self.dependencies.homebrew.adopt(item) }
        let commandError = errorMessage
        recordOperationVerification(.unverified, for: operationID, commandError: commandError)
        setUpdatePhase(.refreshing, for: operationID)
        let key = "homebrew|Cask|\(item.caskToken)"
        do {
            guard let observed = try await dependencies.homebrew.package(token: item.caskToken,
                kind: .cask, includePrereleases: settings.includePrereleaseUpdates) else {
                let message = "Homebrew adoption could not be verified for \(item.app.name). Check Homebrew before retrying."
                settings.recordSourceAttempt(key, at: Date(), failure: message)
                errorMessage = commandError ?? message
                return false
            }
            replaceHomebrewPackage(observed)
            adoptableApps.removeAll { $0.id == item.id }
            recordOperationVerification(.registered, for: operationID, commandError: commandError)
            settings.recordSourceAttempt(key, at: Date())
            settings.recordCheck(for: exclusionKey(for: observed), at: Date())
            errorMessage = commandError.map { "Homebrew registered \(item.app.name), but reported: \($0)" }
            return succeeded
        } catch {
            let message = "Homebrew adoption could not be verified for \(item.app.name): \(error.localizedDescription)"
            settings.recordSourceAttempt(key, at: Date(), failure: message)
            errorMessage = commandError ?? message
            return false
        }
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
        let succeeded = await execute(label: item.app.name, activity: operationID, metadata: [
            "Source": "Homebrew adoption",
            "From": item.app.installedVersion,
            "To": item.caskVersion
        ]) { try await self.dependencies.homebrew.installOrReplace(item) }
        let package = HomebrewPackage(token: item.caskToken, displayName: item.app.name,
            description: nil, homepage: nil, license: nil,
            installedVersion: item.app.installedVersion, currentVersion: item.caskVersion,
            kind: .cask, isOutdated: true, isDependency: false, dependencies: [])
        let verified = await verifyCaskMutation(package, original: item.app, record: record,
            commandSucceeded: succeeded, commandError: errorMessage, operationID: operationID)
        if verified { adoptableApps.removeAll { $0.id == item.id } }
        return verified
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
        if succeeded {
            reopenApplications(confirmation.apps)
        } else {
            // Most failures leave the original bundle in place; don't leave an
            // app the user was running closed because its update did not complete.
            await reopenIntactApplications(confirmation.apps)
        }
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
        defer { refreshCVEsAutomatically() }
        guard package.canUpdateAutomatically else {
            if let url = package.manager.homepage { _ = dependencies.externalOpener.open(url) }
            else { errorMessage = "\(package.name) must be updated with \(package.manager.rawValue)." }
            return
        }
        await installDeveloperPackage(package, version: package.latestVersion)
    }

    func installDeveloperPackage(_ package: DeveloperPackage, version: String) async {
        _ = await mutationCoordinator.withAccess(to: mutationTargets(for: .developer(package)), otherwise: false) {
            await installDeveloperPackageUnlocked(package, version: version)
        }
    }

    private func installDeveloperPackageUnlocked(_ package: DeveloperPackage, version: String) async -> Bool {
        guard package.canUpdateAutomatically else {
            if let url = package.manager.homepage { _ = dependencies.externalOpener.open(url) }
            else { errorMessage = "\(package.name) must be updated with \(package.manager.rawValue)." }
            return false
        }
        let selectedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedVersion.isEmpty else {
            errorMessage = "Enter a version to install."
            return false
        }
        let operationID = OperationID.developerPackage(package.id)
        guard !isWorking(operationID) else { return false }
        updateExecutionState.activeOperations.insert(operationID)
        defer { updateExecutionState.activeOperations.remove(operationID) }
        beginUpdateActivity(operationID, targets: mutationTargets(for: .developer(package)), phase: .installing)
        defer { endUpdateActivity(operationID) }

        setUpdatePhase(.installing, for: operationID)
        let succeeded = await execute(label: package.name, activity: operationID, metadata: [
            "Source": package.manager.rawValue,
            "From": package.currentVersion,
            "To": selectedVersion
        ]) {
            try await self.dependencies.developerPackages.install(package, version: selectedVersion)
        }
        let commandError = errorMessage
        recordOperationVerification(.unverified, for: operationID, commandError: commandError)
        setUpdatePhase(.refreshing, for: operationID)
        let report = await dependencies.developerPackages.scan(enabledManagers: [package.manager],
            includePrereleases: settings.includePrereleaseUpdates)
        scanState.revision &+= 1
        scanState.sourceRevisions["developer|\(package.manager.rawValue)"] = scanState.revision
        let targetFailed = report.failedManagers.contains(package.manager)
            || report.failedExecutablePaths.contains(package.executablePath)
        settings.recordSourceAttempt("developer|\(package.manager.rawValue)", at: Date(),
            failure: report.failedManagers.isEmpty && report.failedExecutablePaths.isEmpty ? nil : "Some packages could not be verified.")
        let previous = developerPackages.filter { $0.manager == package.manager }
        developerPackages = developerPackages.filter { $0.manager != package.manager }
            + ScanResultReconciliation.developerPackages(fresh: report.packages, previous: previous,
                failedManagers: report.failedManagers, failedExecutablePaths: report.failedExecutablePaths)
        developerPackages.sort(by: ScanResultReconciliation.developerOrder)
        guard !targetFailed, let observed = report.packages.first(where: { $0.id == package.id }) else {
            errorMessage = commandError ?? "The command finished, but \(package.name)'s installed version could not be verified. Refresh its manager before retrying."
            return false
        }
        recordOperationVerification(observed.currentVersion != package.currentVersion ? .verified : .unchanged,
                                    for: operationID, commandError: commandError,
                                    verification: OperationVerificationDetail(requested: selectedVersion, observed: observed.currentVersion,
                                        targetReached: VersionComparator.compare(observed.currentVersion, selectedVersion) == .orderedSame))
        if observed.currentVersion != package.currentVersion {
            let record = UpdateRecord(id: UUID(), date: Date(), name: package.name,
                fromVersion: package.currentVersion, toVersion: observed.currentVersion,
                kind: .developer, originalAppPath: nil, backupPath: nil,
                recoveryNote: "Package-manager updates do not have a universal rollback mechanism. Reinstall the previous version with \(package.manager.rawValue) if needed.")
            let historyWarning = await saveUpdateHistory(record)
            errorMessage = commandError ?? historyWarning
        }
        if !succeeded {
            if observed.currentVersion != package.currentVersion, let commandError {
                errorMessage = "Installed \(observed.currentVersion) for \(package.name), but the command reported: \(commandError)"
            } else { errorMessage = commandError }
        }
        else if observed.currentVersion == package.currentVersion {
            errorMessage = "The command finished, but \(package.name) is still installed at \(observed.currentVersion)."
        } else if VersionComparator.compare(observed.currentVersion, selectedVersion) != .orderedSame {
            errorMessage = "Installed \(observed.currentVersion) for \(package.name); the requested version was \(selectedVersion)."
        }
        settings.recordCheck(for: exclusionKey(for: observed), at: Date())
        return succeeded && errorMessage == nil
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

        let succeeded = await execute(label: package.name, activity: operationID, metadata: [
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

    @discardableResult
    func scanLocalModels(runtime: LocalModelRuntime? = nil) async -> LocalModelClient.Report? {
        let targets = Set((runtime.map { [$0] } ?? LocalModelRuntime.allCases).map(MutationTarget.modelRuntime))
        return await mutationCoordinator.withAccess(to: targets, otherwise: nil) {
            await scanLocalModelsUnlocked(runtime: runtime)
        }
    }

    private func scanLocalModelsUnlocked(runtime: LocalModelRuntime?) async -> LocalModelClient.Report? {
        let identifier = runtime.map(OperationID.localModelRuntimeScan) ?? .localModelScan
        guard !isWorking(identifier) else { return nil }
        updateExecutionState.activeOperations.insert(identifier)
        defer { updateExecutionState.activeOperations.remove(identifier) }
        scanState.revision &+= 1
        let revision = scanState.revision
        let checkedRuntimes = runtime.map { [$0] } ?? LocalModelRuntime.allCases
        for checked in checkedRuntimes { scanState.sourceRevisions["model.runtime|\(checked.rawValue)"] = revision }
        for model in localModels where checkedRuntimes.contains(model.runtime) { scanState.sourceRevisions["model|\(model.id)"] = revision }
        let report: LocalModelClient.Report
        if let runtime { report = await dependencies.localModels.scan(runtime: runtime) }
        else { report = await dependencies.localModels.scan() }
        guard scanState.latestFullRevision <= revision else { return nil }
        for model in report.models { scanState.sourceRevisions["model|\(model.id)"] = revision }
        var modelAttempts: [String: String] = [:]
        for model in report.models + localModels.filter({
            (runtime == nil || $0.runtime == runtime)
                && (report.failedModelIDs.contains($0.id) || report.failedRuntimes.contains($0.runtime))
        }) {
            modelAttempts["model|\(model.id)"] = report.failedModelIDs.contains(model.id) || report.failedRuntimes.contains(model.runtime)
                ? "The model source could not be verified." : ""
        }
        for checked in runtime.map({ [$0] }) ?? LocalModelRuntime.allCases {
            modelAttempts["model.runtime|\(checked.rawValue)"] = report.failedRuntimes.contains(checked)
                ? "This runtime could not be checked." : ""
        }
        settings.recordSourceAttempts(modelAttempts, at: Date())
        var merged = Dictionary(report.models.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for previous in localModels where (runtime != nil && previous.runtime != runtime)
            || report.failedModelIDs.contains(previous.id) || report.failedRuntimes.contains(previous.runtime) {
            merged[previous.id] = previous
        }
        localModels = merged.values.sorted(by: ScanResultReconciliation.modelOrder)
        scanWarnings = reconcileSourceWarnings(
            existing: scanWarnings, fresh: report.scanWarnings, source: .localModels,
            checkedName: runtime?.rawValue
        )
        if selectedLocalModelID == nil || !localModels.contains(where: { $0.id == selectedLocalModelID }) {
            selectedLocalModelID = localModels.first?.id
        }
        return report
    }

    func updateLocalModel(_ model: LocalLLMModel) async {
        _ = await mutationCoordinator.withAccess(to: mutationTargets(for: .model(model)), otherwise: false) {
            await updateLocalModelUnlocked(model)
        }
    }

    private func updateLocalModelUnlocked(_ model: LocalLLMModel) async -> Bool {
        let operationID = OperationID.localModel(model.id)
        guard !isWorking(operationID) else { return false }
        updateExecutionState.activeOperations.insert(operationID)
        defer { updateExecutionState.activeOperations.remove(operationID) }
        beginUpdateActivity(operationID, targets: mutationTargets(for: .model(model)), phase: .updating)
        defer { endUpdateActivity(operationID) }

        setUpdatePhase(.updating, for: operationID)
        let succeeded = await execute(label: model.name, activity: operationID, metadata: [
            "Source": model.runtime.rawValue,
            "From": model.installedRevision,
            "To": model.latestRevision
        ]) { try await self.dependencies.localModels.update(model) }
        let commandError = errorMessage
        recordOperationVerification(.unverified, for: operationID, commandError: commandError)
        setUpdatePhase(.refreshing, for: operationID)
        guard let report = await scanLocalModels(runtime: model.runtime),
              !report.failedRuntimes.contains(model.runtime), !report.failedModelIDs.contains(model.id),
              let observed = report.models.first(where: { $0.id == model.id }) else {
            errorMessage = commandError ?? "The command finished, but the installed revision of \(model.name) could not be verified. Refresh its runtime before retrying."
            return false
        }
        recordOperationVerification(observed.installedRevision != model.installedRevision ? .verified : .unchanged,
                                    for: operationID, commandError: commandError,
                                    verification: OperationVerificationDetail(requested: model.latestRevision, observed: observed.installedRevision,
                                        targetReached: observed.installedRevision == model.latestRevision))
        guard observed.installedRevision != model.installedRevision else {
            errorMessage = commandError ?? "The command finished, but \(model.name) is still installed at \(observed.installedRevision)."
            return false
        }
        let record = UpdateRecord(
            id: UUID(), date: Date(), name: model.name,
            fromVersion: model.installedRevision, toVersion: observed.installedRevision,
            kind: .model, originalAppPath: nil, backupPath: nil,
            recoveryNote: "Model files are managed by \(model.runtime.rawValue). Download the earlier model revision again if rollback is required."
        )
        let historyWarning = await saveUpdateHistory(record)
        errorMessage = commandError ?? historyWarning
        if errorMessage == nil && observed.isOutdated {
            errorMessage = "Installed \(observed.installedRevision), but \(observed.latestRevision) is still available for \(model.name)."
        }
        return succeeded && errorMessage == nil && !observed.isOutdated
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
        updateExecutionState.isBatchStopRequested = false
        defer {
            updateExecutionState.activeOperations.remove(batchID)
            updateExecutionState.isBatchStopRequested = false
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
            // Stop requests take effect only between items, never mid-install.
            if updateExecutionState.isBatchStopRequested {
                for remaining in items[index...] {
                    results.append(BatchUpdateResult(item: remaining, outcome: .notStarted,
                        detail: "Not started because the batch was stopped."))
                    endUpdateActivity(remaining.updateOperationID)
                }
                break
            }
            batchUpdateProgress = BatchUpdateProgress(completed: index, total: items.count, itemName: item.name)
            if let app = batchApp(for: item), isRunning(app) {
                results.append(BatchUpdateResult(
                    item: item,
                    outcome: .failed,
                    detail: "\(app.name) could not be quit. Quit it manually and try again."
                ))
                continue
            }
            let result = await Self.$batchItemError.withValue(BatchItemError(owner: self)) {
                await performBatchItem(item)
            }
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
        batchUpdateProgress = BatchUpdateProgress(completed: items.count, total: items.count, itemName: "Finishing updates")

        // Reopen every app the batch quit. Updated apps reopen as before; apps
        // whose update failed or did not start reopen only if still intact.
        let updatedItemIDs = Set(results.compactMap { $0.outcome == .updated ? $0.item.id : nil })
        let updatedApps = closedApps.filter { app in
            items.contains { updatedItemIDs.contains($0.id) && batchApp(for: $0)?.id == app.id }
        }
        reopenApplications(updatedApps)
        await reopenIntactApplications(closedApps.filter { app in !updatedApps.contains { $0.id == app.id } })
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
                        let succeeded = await execute(label: update.app.name, activity: progressID) {
                            try await self.dependencies.directAppInstaller.install(update: update) { phase in
                                await self.setUpdatePhase(phase, for: progressID)
                            }
                        }
                        guard await verifyDirectInstallation(update, record: record, commandSucceeded: succeeded,
                            commandError: errorMessage, operationID: progressID) else {
                            throw BatchUpdateError.verification(errorMessage ?? "Could not verify \(update.app.name).")
                        }
                        let installedVersion = apps.first { $0.id == update.app.id }?.installedVersion ?? update.availableVersion
                        return BatchUpdateResult(item: item, outcome: .updated,
                            detail: "Updated to \(installedVersion).", warning: errorMessage)

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
                    guard await updateAdoptableAppUnlocked(adoptable) else {
                        throw BatchUpdateError.verification(errorMessage ?? "Could not verify \(update.app.name).")
                    }
                } else {
                    let record = try await dependencies.history.prepareAppBackup(
                        app: update.app, toVersion: update.availableVersion, kind: .homebrew
                    )
                    setUpdatePhase(.updating, for: progressID)
                    let succeeded = await execute(label: update.app.name, activity: progressID) {
                        try await self.dependencies.homebrew.upgradeCask(token: token)
                    }
                    let package = HomebrewPackage(token: token, displayName: update.app.name,
                        description: nil, homepage: nil, license: nil,
                        installedVersion: update.app.installedVersion, currentVersion: update.availableVersion,
                        kind: .cask, isOutdated: true, isDependency: false, dependencies: [])
                    guard await verifyCaskMutation(package, original: update.app, record: record,
                        commandSucceeded: succeeded, commandError: errorMessage, operationID: progressID) else {
                        throw BatchUpdateError.verification(errorMessage ?? "Could not verify \(update.app.name).")
                    }
                }


            case let .homebrew(package):
                historyWarning = try await upgradeBatchPackage(package, progressID: progressID)

            case let .developer(package):
                if !package.canUpdateAutomatically {
                    guard let url = package.manager.homepage, dependencies.externalOpener.open(url) else {
                        throw BatchUpdateError.couldNotOpen(package.manager.rawValue)
                    }
                    return BatchUpdateResult(item: item, outcome: .opened,
                        detail: "Opened \(package.manager.rawValue). Complete the update there.")
                }
                guard await installDeveloperPackageUnlocked(package, version: package.latestVersion) else {
                    throw BatchUpdateError.verification(errorMessage ?? "Could not verify \(package.name).")
                }

            case let .model(model):
                guard await updateLocalModelUnlocked(model) else {
                    throw BatchUpdateError.verification(errorMessage ?? "Could not verify \(model.name).")
                }

            }
            let installedVersion: String
            if case let .model(model) = item {
                installedVersion = localModels.first { $0.id == model.id }?.installedRevision ?? item.availableVersion
            } else if case let .developer(package) = item {
                installedVersion = developerPackages.first { $0.id == package.id }?.currentVersion ?? item.availableVersion
            } else if case let .homebrew(package) = item {
                installedVersion = homebrewPackages.first { $0.token == package.token && $0.kind == package.kind }?.installedVersion ?? item.availableVersion
            } else if case let .application(update) = item, update.homebrewToken != nil {
                installedVersion = apps.first { $0.id == update.app.id }?.installedVersion ?? item.availableVersion
            } else { installedVersion = item.availableVersion }
            return BatchUpdateResult(item: item, outcome: .updated, detail: "Updated to \(installedVersion).", warning: historyWarning)
        } catch {
            return BatchUpdateResult(item: item, outcome: .failed, detail: error.localizedDescription)
        }
    }

    private func upgradeBatchPackage(_ package: HomebrewPackage, progressID: OperationID) async throws -> String? {
        setUpdatePhase(.updating, for: progressID)
        guard await updatePackageUnlocked(package) else {
            throw BatchUpdateError.verification(errorMessage ?? "Could not verify \(package.displayName).")
        }
        return nil
    }

    /// Lets the current batch item finish, then reports the rest as not started.
    func requestBatchStop() {
        guard isWorking(.unifiedBatch) else { return }
        updateExecutionState.isBatchStopRequested = true
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
        exclusion(for: update) != nil
    }

    func isExcluded(_ package: HomebrewPackage) -> Bool {
        exclusion(for: package) != nil
    }

    /// A cask that installs an app follows that app's skip or ignore rule;
    /// otherwise hiding the app row would resurface the same update as a cask.
    private func inheritedAppExclusion(for package: HomebrewPackage) -> UpdateExclusion? {
        guard package.kind == .cask, let app = matchingApp(for: package) else { return nil }
        if let ignored = settings.ignoredExclusion(for: exclusionKey(for: app)) { return ignored }
        guard let update = update(for: app),
              update.candidates.contains(where: { $0.homebrewToken == package.token }) else { return nil }
        return exclusion(for: update)
    }

    private func exclusion(for update: AvailableUpdate) -> UpdateExclusion? {
        settings.exclusion(for: exclusionKey(for: update.app)) {
            update.primaryCandidate.matchesExclusionVersion($0)
        }
    }

    func isExcluded(_ package: DeveloperPackage) -> Bool {
        settings.isExcluded(key: exclusionKey(for: package), version: package.latestVersion)
    }

    func isExcluded(_ model: LocalLLMModel) -> Bool {
        settings.isExcluded(key: exclusionKey(for: model), version: model.latestRevision)
    }

    func exclusion(for app: InstalledApp, version: String) -> UpdateExclusion? {
        guard let candidate = update(for: app)?.candidates.first(where: { $0.availableVersion == version }) else {
            return settings.exclusion(for: exclusionKey(for: app), version: version)
        }
        // Same matching as isExcluded, so a hidden update always shows its rule.
        return settings.exclusion(for: exclusionKey(for: app)) { candidate.matchesExclusionVersion($0) }
    }

    func exclusion(for package: HomebrewPackage) -> UpdateExclusion? {
        settings.exclusion(for: exclusionKey(for: package), version: package.exclusionVersion)
            ?? inheritedAppExclusion(for: package)
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
        exclude(.skipped, key: exclusionKey(for: package), name: package.displayName, category: "Homebrew", version: package.exclusionVersion, duration: duration)
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

        let succeeded = await execute(label: "Restore \(record.name)", activity: operationID, metadata: [
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
        MainWindow.open()
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
        activity: OperationID? = nil,
        metadata: [String: String] = [:],
        operation: () async throws -> Void
    ) async -> Bool {
        let startedAt = Date()
        let commandLog = OperationCommandLog()
        defer {
            if let activity { updateExecutionState.appendRedactedCommandLog(commandLog.text, for: activity) }
        }
        errorMessage = nil
        do {
            try await OperationCommandLogContext.$current.withValue(commandLog) { try await operation() }
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
        externalUpdateVerifications[update.id] = ExternalUpdateVerification(
            state: .waiting,
            detail: "Waiting for \(update.app.name) to finish the update…"
        )
        externalUpdateVerifier.start(update) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .installed(refreshed):
                await self.refresh(refreshed)
                guard !Task.isCancelled else { return }
                self.externalUpdateVerifications[update.id] = ExternalUpdateVerification(
                    state: .completed,
                    detail: "Verified \(refreshed.installedVersion) from the installed app bundle."
                )
            case let .attention(lastObserved):
                let reported = lastObserved?.installedVersion
                let detail = reported.map {
                    "\(update.app.name) still reports \($0). Finish its updater or restart the app, then refresh."
                } ?? "Could not read \(update.app.name)'s installed bundle. Finish its updater, then refresh."
                self.externalUpdateVerifications[update.id] = ExternalUpdateVerification(state: .attention, detail: detail)
                DiagnosticsStore.shared.record(.warning, category: .update,
                    "External update still needs verification", metadata: [
                        "Item": update.app.name, "Expected": update.availableVersion,
                        "Reported": reported ?? "Unavailable"
                    ])
                self.refreshDiagnostics()
            }
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

    /// After a failed or skipped update, reopen only bundles that still carry the
    /// original identity at the original path. A partial or unverified
    /// replacement is never launched.
    private func reopenIntactApplications(_ apps: [InstalledApp]) async {
        var intact: [InstalledApp] = []
        for app in apps {
            guard let identifier = app.bundleIdentifier, !identifier.isEmpty,
                  let observed = await dependencies.applicationDiscovery.discover(at: app.url),
                  observed.bundleIdentifier == identifier,
                  canonicalPath(observed.url) == canonicalPath(app.url) else { continue }
            intact.append(app)
        }
        guard !intact.isEmpty else { return }
        reopenApplications(intact)
    }

    func reopenApplications(_ apps: [InstalledApp]) {
        var reopened = Set<String>()
        for app in apps where reopened.insert(canonicalPath(app.url)).inserted
            && !dependencies.externalOpener.open(app.url) {
            if errorMessage == nil { errorMessage = "Upkeep could not reopen \(app.name)." }
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
        scanState.revision &+= 1
        scanState.sourceRevisions["homebrew|\(package.kind.rawValue)|\(package.token)"] = scanState.revision
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

    private func preservingOwnedHomebrewPackages(_ fresh: [HomebrewPackage], after revision: UInt64) -> [HomebrewPackage] {
        let owned = homebrewPackages.filter {
            scanState.sourceRevisions["homebrew|\($0.kind.rawValue)|\($0.token)", default: 0] > revision
        }
        let ownedIDs = Set(owned.map(\.id))
        return (fresh.filter { !ownedIDs.contains($0.id) } + owned).sorted {
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

    func recoveryStorage() async -> RecoveryStorage? {
        await dependencies.history.recoveryStorage()
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

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
