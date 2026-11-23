import Combine
import Foundation
import Observation

enum OperationID: Hashable, Sendable {
    case applicationUpdate(String)
    case homebrewPackage(String)
    case homebrewAdoption(String)
    case developerPackage(String)
    case localModel(String)
    case macOSUpdate(String)
    case historyRestore(UUID)
    case applicationRefresh(String)
    case applicationUninstall(String)
    case homebrewRefresh(String)
    case appManagementPermissionCheck
    case developerRefresh(String)
    case developerScan(DeveloperPackageManager?)
    case packageCleanup(String)
    /// Installing a Homebrew formula to replace a duplicate group.
    case duplicateReplacement(String)
    case localModelScan
    case localModelRuntimeScan(LocalModelRuntime)
    case homebrewInventoryScan
    case homebrewCatalogScan
    case macOSSourceScan
    case unifiedBatch
    case batchItem(String)
}

@MainActor
@Observable
final class UpkeepLibraryState: ObservableObject {
    private(set) var appGeneration: UInt64 = 0
    private(set) var adoptableGeneration: UInt64 = 0
    private(set) var developerGeneration: UInt64 = 0
    private(set) var homebrewGeneration: UInt64 = 0
    private(set) var primaryUpdateGeneration: UInt64 = 0
    // Stable legacy publisher; all sends remain inside this MainActor model.
    @ObservationIgnored nonisolated(unsafe) let objectWillChange = ObservableObjectPublisher()
    private(set) var generation: UInt64 = 0
    private func changed() { generation &+= 1 }
    var apps: [InstalledApp] = [] { willSet { objectWillChange.send() } didSet { appGeneration &+= 1; changed(); rebuildAppLookups() } }
    var updates: [AvailableUpdate] = [] { willSet { objectWillChange.send() } didSet { primaryUpdateGeneration &+= 1; changed(); rebuildUpdateLookup() } }
    var homebrewPackages: [HomebrewPackage] = [] { willSet { objectWillChange.send() } didSet { homebrewGeneration &+= 1; primaryUpdateGeneration &+= 1; changed(); rebuildHomebrewLookups() } }
    var homebrewServices: [HomebrewService] = [] { willSet { objectWillChange.send() } }
    var homebrewServicesCheckedAt: Date? { willSet { objectWillChange.send() } }
    var homebrewServicesSucceededAt: Date? { willSet { objectWillChange.send() } }
    var homebrewServicesFailure: String? { willSet { objectWillChange.send() } }
    var isCheckingHomebrewServices = false { willSet { objectWillChange.send() } }
    var adoptableApps: [AdoptableApp] = [] { willSet { objectWillChange.send() } didSet { adoptableGeneration &+= 1; changed(); rebuildAdoptableLookups() } }
    var macOSUpdates: [MacOSUpdate] = [] { willSet { objectWillChange.send() } didSet { primaryUpdateGeneration &+= 1; changed() } }
    var updateHistory: [UpdateRecord] = [] { willSet { objectWillChange.send() } didSet { changed() } }
    var developerPackages: [DeveloperPackage] = [] { willSet { objectWillChange.send() } didSet { developerGeneration &+= 1; primaryUpdateGeneration &+= 1; changed(); rebuildDeveloperPackageLookup() } }
    var installedDeveloperManagers: [DeveloperPackageManager] = [] { willSet { objectWillChange.send() } }
    var localModels: [LocalLLMModel] = [] { willSet { objectWillChange.send() } didSet { primaryUpdateGeneration &+= 1; changed(); rebuildLocalModelLookup() } }

    private var appByID: [String: InstalledApp] = [:]
    private var appIndexByProductName: [String: Int] = [:]
    private var appNameVariants: [String: Set<String>] = [:]
    private var updateByAppID: [String: AvailableUpdate] = [:]
    private var homebrewPackageByID: [String: HomebrewPackage] = [:]
    private var caskIndexByProductName: [String: Int] = [:]
    private var homebrewNameVariants: [String: Set<String>] = [:]
    private var adoptableAppByID: [String: AdoptableApp] = [:]
    private var adoptableAppByAppID: [String: AdoptableApp] = [:]
    private var developerPackageByID: [String: DeveloperPackage] = [:]
    private var localModelByID: [String: LocalLLMModel] = [:]

    func app(forID id: String) -> InstalledApp? {
        appByID[id]
    }

    func update(for appID: String) -> AvailableUpdate? {
        updateByAppID[appID]
    }

    func homebrewPackage(forID id: String) -> HomebrewPackage? {
        homebrewPackageByID[id]
    }

    func adoptableApp(forID id: String) -> AdoptableApp? {
        adoptableAppByID[id]
    }

    func adoptableApp(forAppID id: String) -> AdoptableApp? {
        adoptableAppByAppID[id]
    }

    func developerPackage(forID id: String) -> DeveloperPackage? {
        developerPackageByID[id]
    }

    func localModel(forID id: String) -> LocalLLMModel? {
        localModelByID[id]
    }

    func homebrewPackage(forAppNamed name: String) -> HomebrewPackage? {
        (appNameVariants[name] ?? Self.productNameVariants(name))
            .compactMap { caskIndexByProductName[$0] }
            .min()
            .map { homebrewPackages[$0] }
    }

    func app(for package: HomebrewPackage) -> InstalledApp? {
        (homebrewNameVariants[package.displayName] ?? Self.productNameVariants(package.displayName))
            .union(homebrewNameVariants[package.token] ?? Self.productNameVariants(package.token))
            .union(package.appMatchNames)
            .compactMap { appIndexByProductName[$0] }
            .min()
            .map { apps[$0] }
    }

    private func rebuildAppLookups() {
        appByID = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        appIndexByProductName.removeAll(keepingCapacity: true)
        appNameVariants.removeAll(keepingCapacity: true)
        for (index, app) in apps.enumerated() {
            let variants = appNameVariants[app.name] ?? Self.productNameVariants(app.name)
            appNameVariants[app.name] = variants
            for name in variants where appIndexByProductName[name] == nil {
                appIndexByProductName[name] = index
            }
        }
    }

    private func rebuildUpdateLookup() {
        updateByAppID = Dictionary(updates.map { ($0.app.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func rebuildHomebrewLookups() {
        homebrewPackageByID = Dictionary(
            homebrewPackages.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        caskIndexByProductName.removeAll(keepingCapacity: true)
        // Retain only names in the current inventory, keeping memory bounded and
        // allowing lookups of external snapshots to fall back to normalization.
        homebrewNameVariants.removeAll(keepingCapacity: true)
        for (index, package) in homebrewPackages.enumerated() where package.kind == .cask {
            let displayNames = homebrewNameVariants[package.displayName]
                ?? Self.productNameVariants(package.displayName)
            homebrewNameVariants[package.displayName] = displayNames
            let tokenNames = homebrewNameVariants[package.token] ?? Self.productNameVariants(package.token)
            homebrewNameVariants[package.token] = tokenNames
            let names = displayNames.union(tokenNames).union(package.appMatchNames)
            for name in names where caskIndexByProductName[name] == nil {
                caskIndexByProductName[name] = index
            }
        }
    }

    private func rebuildAdoptableLookups() {
        adoptableAppByID = Dictionary(
            adoptableApps.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        adoptableAppByAppID = Dictionary(
            adoptableApps.map { ($0.app.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func rebuildDeveloperPackageLookup() {
        developerPackageByID = Dictionary(
            developerPackages.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func rebuildLocalModelLookup() {
        localModelByID = Dictionary(
            localModels.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private static func productNameVariants(_ value: String) -> Set<String> {
        homebrewProductNameVariants(value)
    }
}

@MainActor
@Observable
final class UpkeepNavigationState: ObservableObject {
    // Stable legacy publisher; all sends remain inside this MainActor model.
    @ObservationIgnored nonisolated(unsafe) let objectWillChange = ObservableObjectPublisher()
    var selection: SidebarDestination = .updates {
        willSet { objectWillChange.send() }
        didSet { selectionClearedByUninstall = false }
    }
    /// After an uninstall the list shows nothing selected instead of jumping to
    /// the next item, until the user picks something or changes section.
    var selectionClearedByUninstall = false { willSet { objectWillChange.send() } }
    var homebrewFilter: HomebrewFilter = .all { willSet { objectWillChange.send() } }
    var appListFilter: AppListFilter = .all { willSet { objectWillChange.send() } }
    var appSortOrder: AppSortOrder = .recommended { willSet { objectWillChange.send() } }
    var appSortAscending = true { willSet { objectWillChange.send() } }
    var homebrewSortOrder: HomebrewSortOrder = .recommended { willSet { objectWillChange.send() } }
    var homebrewSortAscending = true { willSet { objectWillChange.send() } }
    var developerManagerFilter: DeveloperManagerFilter = .all { willSet { objectWillChange.send() } }
    var selectedPackageID: String? {
        willSet { objectWillChange.send() }
        didSet { if selectedPackageID != nil { selectionClearedByUninstall = false } }
    }
    var selectedDeveloperPackageID: String? {
        willSet { objectWillChange.send() }
        didSet { if selectedDeveloperPackageID != nil { selectionClearedByUninstall = false } }
    }
    var selectedDeveloperVersion = "" { willSet { objectWillChange.send() } }
    var selectedLocalModelID: String? {
        willSet { objectWillChange.send() }
        didSet { if selectedLocalModelID != nil { selectionClearedByUninstall = false } }
    }
    var availableDeveloperVersions: [String] = [] { willSet { objectWillChange.send() } }
    var isLoadingDeveloperVersions = false { willSet { objectWillChange.send() } }
    var selectedApp: InstalledApp? {
        willSet { objectWillChange.send() }
        didSet { if selectedApp != nil { selectionClearedByUninstall = false } }
    }
    var updateInspectorSelection: UpdateInspectorSelection? { willSet { objectWillChange.send() } }
    var requestedSearchResult: SearchResultSelection? { willSet { objectWillChange.send() } }
    var inventoryReveal: InventoryReveal? { willSet { objectWillChange.send() } }
    var searchText = "" { willSet { objectWillChange.send() } }
    var pendingRevert: UpdateRecord? { willSet { objectWillChange.send() } }
    var pendingRunningAppConfirmation: RunningAppConfirmation? { willSet { objectWillChange.send() } }
    var pendingHomebrewAuthorizationConfirmation: HomebrewAuthorizationConfirmation? { willSet { objectWillChange.send() } }
    var isShowingBatchReview = false { willSet { objectWillChange.send() } }
    /// Applied after a destination change clears the previous inspector selection.
    @ObservationIgnored var pendingUpdateReveal: PendingUpdateTarget?
}

@MainActor
@Observable
final class UpkeepScanState: ObservableObject {
    // Stable legacy publisher; all sends remain inside this MainActor model.
    @ObservationIgnored nonisolated(unsafe) let objectWillChange = ObservableObjectPublisher()
    var generation: UUID?
    var revision: UInt64 = 0
    var latestFullRevision: UInt64 = 0
    var sourceRevisions: [String: UInt64] = [:]
    var progress: ScanProgress? { willSet { objectWillChange.send() } }
    var firstResultSeconds: TimeInterval? { willSet { objectWillChange.send() } }
    var isScanning = false { willSet { objectWillChange.send() } }
    var lastChecked: Date? { willSet { objectWillChange.send() } }
    var nextScheduledCheck: Date? { willSet { objectWillChange.send() } }
    var errorMessage: String? { willSet { objectWillChange.send() } }
    var scanWarnings: [ScanWarning] = [] { willSet { objectWillChange.send() } }
    var failedAppSources: [String: Set<UpdateSource>] = [:] { willSet { objectWillChange.send() } }
    var completedCheckState: UpdateCheckState? { willSet { objectWillChange.send() } }
    var macOSStatus: ScanStatus? { willSet { objectWillChange.send() } }

    init(lastChecked: Date?) {
        self.lastChecked = lastChecked
    }
}

@MainActor
@Observable
final class UpkeepUpdateExecutionState: ObservableObject {
    // Stable legacy publisher; all sends remain inside this MainActor model.
    @ObservationIgnored nonisolated(unsafe) let objectWillChange = ObservableObjectPublisher()
    var activeOperations = Set<OperationID>() { willSet { objectWillChange.send() } }
    private(set) var activities: [OperationID: UpdateActivity] = [:] { willSet { objectWillChange.send() } }
    private(set) var completedOperations: [CompletedOperation] = [] { willSet { objectWillChange.send() } }
    var batchUpdateProgress: BatchUpdateProgress? { willSet { objectWillChange.send() } }
    /// Checked between batch items; never interrupts an install in progress.
    var isBatchStopRequested = false { willSet { objectWillChange.send() } }
    var appManagementPermissionCheck: AppManagementPermissionCheck? { willSet { objectWillChange.send() } }
    var runningBundleIdentifiers = Set<String>() { willSet { objectWillChange.send() } }
    var runningApplicationPaths = Set<String>() { willSet { objectWillChange.send() } }
    var externalUpdateVerifications: [String: ExternalUpdateVerification] = [:] { willSet { objectWillChange.send() } }

    func begin(_ operation: OperationID, targets: Set<MutationTarget>, phase: UpdatePhase,
               label: String, at date: Date = Date()) {
        activities[operation] = UpdateActivity(targets: targets, phase: phase, startedAt: date, label: label)
    }

    func setPhase(_ phase: UpdatePhase, for operation: OperationID) {
        activities[operation]?.phase = phase
    }

    func recordVerification(_ result: OperationResult, for operation: OperationID,
                            commandError: String? = nil, verification: OperationVerificationDetail? = nil) {
        activities[operation]?.result = result
        activities[operation]?.commandError = commandError
        activities[operation]?.verification = verification
    }

    /// Input has already passed command-log redaction. Bound the aggregate too,
    /// since an operation can execute multiple individually bounded commands.
    func appendRedactedCommandLog(_ text: String, for operation: OperationID) {
        guard let previous = activities[operation]?.commandLog else { return }
        let marker = "\n[Log output truncated]\n"
        guard !previous.hasSuffix(marker) else { return }
        let limit = 32_768
        if previous.count + text.count <= limit {
            activities[operation]?.commandLog = previous + text
        } else {
            let prefix = String((previous + text).prefix(limit - marker.count))
            activities[operation]?.commandLog = prefix + marker
        }
    }

    func finish(_ operation: OperationID, at date: Date = Date()) {
        guard let activity = activities.removeValue(forKey: operation) else { return }
        completedOperations.insert(CompletedOperation(id: UUID(), operation: operation,
            startedAt: activity.startedAt, finishedAt: date, result: activity.result ?? .unverified,
            label: activity.label, commandError: activity.commandError, verification: activity.verification,
            commandLog: activity.commandLog), at: 0)
        completedOperations = Array(completedOperations.prefix(100))
    }

}

struct ExternalUpdateVerification: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case waiting
        case completed
        case attention
    }

    let state: State
    let detail: String
}

@MainActor
@Observable
final class UpkeepDiagnosticsState: ObservableObject {
    // Stable legacy publisher; all sends remain inside this MainActor model.
    @ObservationIgnored nonisolated(unsafe) let objectWillChange = ObservableObjectPublisher()
    var diagnosticEntries = DiagnosticsStore.shared.entries() { willSet { objectWillChange.send() } }
    var diagnosticsSearchText = "" { willSet { objectWillChange.send() } }
    var diagnosticsLevelFilter = DiagnosticLevelFilter.all { willSet { objectWillChange.send() } }
    var diagnosticsCategoryFilter: DiagnosticCategory? { willSet { objectWillChange.send() } }
}
