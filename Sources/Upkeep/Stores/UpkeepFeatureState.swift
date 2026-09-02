import Combine
import Foundation

enum OperationID: Hashable, Sendable {
    case applicationUpdate(String)
    case homebrewPackage(String)
    case homebrewAdoption(String)
    case developerPackage(String)
    case localModel(String)
    case macOSUpdate(String)
    case historyRestore(UUID)
    case applicationRefresh(String)
    case homebrewRefresh(String)
    case appManagementPermissionCheck
    case developerRefresh(String)
    case developerScan(DeveloperPackageManager?)
    case packageCleanup(String)
    case localModelScan
    case homebrewBatch
    case unifiedBatch
    case batchItem(String)
}

@MainActor
final class UpkeepLibraryState: ObservableObject {
    @Published var apps: [InstalledApp] = [] { didSet { rebuildAppLookups() } }
    @Published var updates: [AvailableUpdate] = [] { didSet { rebuildUpdateLookup() } }
    @Published var homebrewPackages: [HomebrewPackage] = [] { didSet { rebuildHomebrewLookups() } }
    @Published var adoptableApps: [AdoptableApp] = [] { didSet { rebuildAdoptableLookups() } }
    @Published var macOSUpdates: [MacOSUpdate] = []
    @Published var updateHistory: [UpdateRecord] = []
    @Published var developerPackages: [DeveloperPackage] = [] { didSet { rebuildDeveloperPackageLookup() } }
    @Published var installedDeveloperManagers: [DeveloperPackageManager] = []
    @Published var localModels: [LocalLLMModel] = [] { didSet { rebuildLocalModelLookup() } }

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
            let names = displayNames.union(tokenNames)
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
        let normalized = value.lowercased().filter(\.isLetter)
        var values: Set<String> = [normalized]
        for suffix in ["desktop", "app"] where normalized.hasSuffix(suffix) && normalized.count > suffix.count {
            values.insert(String(normalized.dropLast(suffix.count)))
        }
        return values
    }
}

@MainActor
final class UpkeepNavigationState: ObservableObject {
    @Published var selection: SidebarDestination = .updates
    @Published var homebrewFilter: HomebrewFilter = .all
    @Published var appListFilter: AppListFilter = .all
    @Published var appSortOrder: AppSortOrder = .recommended
    @Published var appSortAscending = true
    @Published var homebrewSortOrder: HomebrewSortOrder = .recommended
    @Published var homebrewSortAscending = true
    @Published var developerManagerFilter: DeveloperManagerFilter = .all
    @Published var selectedPackageID: String?
    @Published var selectedDeveloperPackageID: String?
    @Published var selectedDeveloperVersion = ""
    @Published var selectedLocalModelID: String?
    @Published var availableDeveloperVersions: [String] = []
    @Published var isLoadingDeveloperVersions = false
    @Published var selectedApp: InstalledApp?
    @Published var updateInspectorSelection: UpdateInspectorSelection?
    @Published var searchText = ""
    @Published var pendingRevert: UpdateRecord?
    @Published var pendingRunningAppConfirmation: RunningAppConfirmation?
    @Published var pendingHomebrewAuthorizationConfirmation: HomebrewAuthorizationConfirmation?
    @Published var isShowingBatchReview = false
}

@MainActor
final class UpkeepScanState: ObservableObject {
    @Published var isScanning = false
    @Published var lastChecked: Date?
    @Published var nextScheduledCheck: Date?
    @Published var errorMessage: String?
    @Published var scanWarnings: [ScanWarning] = []
    @Published var failedAppSources: [String: Set<UpdateSource>] = [:]
    @Published var completedCheckState: UpdateCheckState?
    @Published var macOSStatus: ScanStatus?

    init(lastChecked: Date?) {
        self.lastChecked = lastChecked
    }
}

@MainActor
final class UpkeepUpdateExecutionState: ObservableObject {
    @Published var activeOperations = Set<OperationID>()
    @Published var activities: [OperationID: UpdateActivity] = [:]
    @Published var batchUpdateProgress: BatchUpdateProgress?
    @Published var appManagementPermissionCheck: AppManagementPermissionCheck?
    @Published var runningBundleIdentifiers = Set<String>()
    @Published var runningApplicationPaths = Set<String>()
    @Published var externalUpdateVerifications: [String: ExternalUpdateVerification] = [:]
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
final class UpkeepDiagnosticsState: ObservableObject {
    @Published var diagnosticEntries = DiagnosticsStore.shared.entries()
    @Published var diagnosticsSearchText = ""
    @Published var diagnosticsLevelFilter = DiagnosticLevelFilter.all
    @Published var diagnosticsCategoryFilter: DiagnosticCategory?
}
