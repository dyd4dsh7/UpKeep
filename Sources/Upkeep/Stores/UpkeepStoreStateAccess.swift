import Foundation

@MainActor
extension UpkeepStore {
    var apps: [InstalledApp] { get { library.apps } set { library.apps = newValue } }
    var updates: [AvailableUpdate] { get { library.updates } set { library.updates = newValue } }
    var homebrewPackages: [HomebrewPackage] { get { library.homebrewPackages } set { library.homebrewPackages = newValue } }
    var adoptableApps: [AdoptableApp] { get { library.adoptableApps } set { library.adoptableApps = newValue } }
    var macOSUpdates: [MacOSUpdate] { get { library.macOSUpdates } set { library.macOSUpdates = newValue } }
    var updateHistory: [UpdateRecord] { get { library.updateHistory } set { library.updateHistory = newValue } }
    var developerPackages: [DeveloperPackage] { get { library.developerPackages } set { library.developerPackages = newValue } }
    var installedDeveloperManagers: [DeveloperPackageManager] { get { library.installedDeveloperManagers } set { library.installedDeveloperManagers = newValue } }
    var localModels: [LocalLLMModel] { get { library.localModels } set { library.localModels = newValue } }

    var selection: SidebarDestination { get { navigation.selection } set { navigation.selection = newValue } }
    var homebrewFilter: HomebrewFilter { get { navigation.homebrewFilter } set { navigation.homebrewFilter = newValue } }
    var appListFilter: AppListFilter { get { navigation.appListFilter } set { navigation.appListFilter = newValue } }
    var appSortOrder: AppSortOrder { get { navigation.appSortOrder } set { navigation.appSortOrder = newValue } }
    var appSortAscending: Bool { get { navigation.appSortAscending } set { navigation.appSortAscending = newValue } }
    var homebrewSortOrder: HomebrewSortOrder { get { navigation.homebrewSortOrder } set { navigation.homebrewSortOrder = newValue } }
    var homebrewSortAscending: Bool { get { navigation.homebrewSortAscending } set { navigation.homebrewSortAscending = newValue } }
    var developerManagerFilter: DeveloperManagerFilter { get { navigation.developerManagerFilter } set { navigation.developerManagerFilter = newValue } }
    var selectedPackageID: String? { get { navigation.selectedPackageID } set { navigation.selectedPackageID = newValue } }
    var selectedDeveloperPackageID: String? { get { navigation.selectedDeveloperPackageID } set { navigation.selectedDeveloperPackageID = newValue } }
    var selectedDeveloperVersion: String { get { navigation.selectedDeveloperVersion } set { navigation.selectedDeveloperVersion = newValue } }
    var selectedLocalModelID: String? { get { navigation.selectedLocalModelID } set { navigation.selectedLocalModelID = newValue } }
    var availableDeveloperVersions: [String] { get { navigation.availableDeveloperVersions } set { navigation.availableDeveloperVersions = newValue } }
    var isLoadingDeveloperVersions: Bool { get { navigation.isLoadingDeveloperVersions } set { navigation.isLoadingDeveloperVersions = newValue } }
    var selectedApp: InstalledApp? { get { navigation.selectedApp } set { navigation.selectedApp = newValue } }
    var updateInspectorSelection: UpdateInspectorSelection? { get { navigation.updateInspectorSelection } set { navigation.updateInspectorSelection = newValue } }
    var searchText: String { get { navigation.searchText } set { navigation.searchText = newValue } }
    var pendingRevert: UpdateRecord? { get { navigation.pendingRevert } set { navigation.pendingRevert = newValue } }
    var pendingRunningAppConfirmation: RunningAppConfirmation? { get { navigation.pendingRunningAppConfirmation } set { navigation.pendingRunningAppConfirmation = newValue } }
    var pendingHomebrewAuthorizationConfirmation: HomebrewAuthorizationConfirmation? {
        get { navigation.pendingHomebrewAuthorizationConfirmation }
        set { navigation.pendingHomebrewAuthorizationConfirmation = newValue }
    }
    var isShowingBatchReview: Bool { get { navigation.isShowingBatchReview } set { navigation.isShowingBatchReview = newValue } }

    var isScanning: Bool { get { scanState.isScanning } set { scanState.isScanning = newValue } }
    var lastChecked: Date? { get { scanState.lastChecked } set { scanState.lastChecked = newValue } }
    var nextScheduledCheck: Date? { get { scanState.nextScheduledCheck } set { scanState.nextScheduledCheck = newValue } }
    var errorMessage: String? { get { scanState.errorMessage } set { scanState.errorMessage = newValue } }
    var scanWarnings: [ScanWarning] { get { scanState.scanWarnings } set { scanState.scanWarnings = newValue } }
    var batchUpdateProgress: BatchUpdateProgress? { get { updateExecutionState.batchUpdateProgress } set { updateExecutionState.batchUpdateProgress = newValue } }
    var appManagementPermissionCheck: AppManagementPermissionCheck? {
        get { updateExecutionState.appManagementPermissionCheck }
        set { updateExecutionState.appManagementPermissionCheck = newValue }
    }
    var runningBundleIdentifiers: Set<String> { get { updateExecutionState.runningBundleIdentifiers } set { updateExecutionState.runningBundleIdentifiers = newValue } }
    var runningApplicationPaths: Set<String> { get { updateExecutionState.runningApplicationPaths } set { updateExecutionState.runningApplicationPaths = newValue } }
    var externalUpdateVerifications: [String: ExternalUpdateVerification] {
        get { updateExecutionState.externalUpdateVerifications }
        set { updateExecutionState.externalUpdateVerifications = newValue }
    }

    var diagnosticEntries: [DiagnosticEntry] { get { diagnostics.diagnosticEntries } set { diagnostics.diagnosticEntries = newValue } }
    var diagnosticsSearchText: String { get { diagnostics.diagnosticsSearchText } set { diagnostics.diagnosticsSearchText = newValue } }
    var diagnosticsLevelFilter: DiagnosticLevelFilter { get { diagnostics.diagnosticsLevelFilter } set { diagnostics.diagnosticsLevelFilter = newValue } }
    var diagnosticsCategoryFilter: DiagnosticCategory? { get { diagnostics.diagnosticsCategoryFilter } set { diagnostics.diagnosticsCategoryFilter = newValue } }
}
