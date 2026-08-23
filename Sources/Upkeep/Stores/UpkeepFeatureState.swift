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
    @Published var apps: [InstalledApp] = []
    @Published var updates: [AvailableUpdate] = []
    @Published var homebrewPackages: [HomebrewPackage] = []
    @Published var adoptableApps: [AdoptableApp] = []
    @Published var macOSUpdates: [MacOSUpdate] = []
    @Published var updateHistory: [UpdateRecord] = []
    @Published var developerPackages: [DeveloperPackage] = []
    @Published var installedDeveloperManagers: [DeveloperPackageManager] = []
    @Published var localModels: [LocalLLMModel] = []
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

    init(lastChecked: Date?) {
        self.lastChecked = lastChecked
    }
}

@MainActor
final class UpkeepUpdateExecutionState: ObservableObject {
    @Published var activeOperations = Set<OperationID>()
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
