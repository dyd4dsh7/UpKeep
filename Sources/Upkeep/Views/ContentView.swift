import SwiftUI

struct ContentView: View {
    @UpkeepStoreReference private var store
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @UpkeepState private var columnVisibility: NavigationSplitViewVisibility = .all
    @UpkeepState private var sidebarCollapsedForInspector = false
    @UpkeepState private var showingOperations = false

    var body: some View {
        GeometryReader { geometry in
            workspace
                .onChange(of: inspectorPresented.wrappedValue) { _, _ in
                    adaptSidebar(to: geometry.size.width)
                }
                .onChange(of: geometry.size.width, initial: true) { _, width in
                    adaptSidebar(to: width)
                }
                .onChange(of: columnVisibility) { _, visibility in
                    if sidebarCollapsedForInspector, visibility != .detailOnly {
                        sidebarCollapsedForInspector = false
                        inspectorPresented.wrappedValue = false
                    }
                }
        }
    }

    private func adaptSidebar(to width: CGFloat) {
        if inspectorPresented.wrappedValue && width < 1_000 {
            sidebarCollapsedForInspector = true
            columnVisibility = .detailOnly
        } else if sidebarCollapsedForInspector && width >= 1_000 {
            // At narrow widths, reopening the native sidebar preserves the
            // detail width by growing the window. Keep navigation collapsed
            // until there is room, or the user explicitly shows it.
            sidebarCollapsedForInspector = false
            columnVisibility = .all
        }
    }

    private var workspace: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            UpkeepSidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 225, max: 300)
                // Keep independent alerts on separate branches. Chaining multiple
                // alert modifiers on the split-view root causes the last alert to
                // suppress Homebrew's authorization prompt on macOS.
                .upkeepHomebrewAuthorizationAlert(store)
        } detail: {
            detail
                .upkeepWorkspaceAppearance()
                // The window owns its minimum size. Avoid feeding changing list,
                // banner, and inspector minima back into AppKit's split layout.
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .upkeepRunningAppConfirmationAlert(store)
                .inspector(isPresented: inspectorPresented) {
                    inspectorContent
                        .upkeepWorkspaceAppearance()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .inspectorColumnWidth(min: UpkeepLayout.inspectorMinimumWidth,
                                              ideal: UpkeepLayout.inspectorIdealWidth,
                                              max: UpkeepLayout.inspectorMaximumWidth)
                }
        }
        .navigationTitle(navigationTitle)
        .toolbar {
            Button { showingOperations = true } label: {
                OperationsToolbarLabel(runningCount: store.updateExecutionState.activities.count)
            }
            .help(operationsHelp)
        }
        .sheet(isPresented: $showingOperations) {
            OperationCentreView(execution: store.updateExecutionState).environment(\.upkeepStoreReference, store)
        }
        .searchable(text: searchTextBinding, placement: .toolbar, prompt: "Search Upkeep")
        .sheet(isPresented: Binding(
            get: { !settings.hasCompletedSetup },
            set: { _ in }
        )) {
            SetupView()
                .environmentObject(settings)
                .interactiveDismissDisabled()
        }
        .task {
            #if DEBUG
            if UIFixture.settingsSection != nil { openSettings() }
            #endif
            // The menu bar, Dock and notifications reopen this window through it.
            MainWindow.openAction = openWindow
            if settings.hasCompletedSetup { await store.start() }
        }
        .onChange(of: settings.hasCompletedSetup) { _, completed in
            guard completed else { return }
            Task { await store.start() }
        }
        .onChange(of: settings.sidebarViewMode) { _, mode in
            if mode == .basic, !basicSidebarDestinations.contains(store.selection) {
                store.selection = .allApps
            }
        }
        .onChange(of: store.selection) { _, _ in
            store.selectedApp = nil
            store.updateInspectorSelection = nil
            store.searchText = ""
            store.navigation.requestedSearchResult = nil
            if store.navigation.inventoryReveal?.destination != store.selection {
                store.navigation.inventoryReveal = nil
            }
            store.completeCVESoftwareNavigation()
            store.completePendingUpdateReveal()
        }
        .alert("The operation couldn’t be completed", isPresented: Binding(
            get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(store.errorMessage ?? "Unknown error") }
    }

    private var operationsHelp: String {
        let running = store.updateExecutionState.activities.count
        return running == 0
            ? "Show update operations"
            : "Show update operations (\(WorkspaceSummary.count(running, "operation", "operations")) running)"
    }

    private var basicSidebarDestinations: Set<SidebarDestination> {
        [.updates, .allApps, .homebrewPackages, .macOSUpdates, .cveChecker, .history]
    }

    @ViewBuilder private var detail: some View {
        VStack(spacing: 0) {
            SelfUpdateBanner()
            if store.selection != .history && store.selection != .cveChecker {
                ScanStatusNotice(isMacOS: store.selection == .macOSUpdates)
            }
            ZStack {
                if isSearching {
                    GlobalSearchView()
                        .id("search")
                        .upkeepStateTransition()
                } else {
                    destinationDetail
                        .id(store.selection)
                        .upkeepStateTransition()
                }
            }
        }
        // Destination changes replace native Lists, toolbars, and inspectors.
        // Keeping the outgoing hierarchy alive in an animated transaction can
        // leave SwiftUI reading a disposed view phase during navigation.
    }

    @ViewBuilder private var destinationDetail: some View {
        switch store.selection {
        case .updates: UpdatesView()
        case .allApps: AllAppsView(
            apps: store.filteredApps,
            title: "All Apps",
            systemImage: SidebarDestination.allApps.headerSystemImage
        )
        case .adoptable: AdoptableView()
        case .homebrewPackages: HomebrewView()
        case .macOSUpdates: MacOSUpdatesView()
        case .cveChecker: CVECheckerView(packages: store.developerPackages, apps: store.apps, homebrew: store.homebrewPackages, state: store.cveScanState, makeClient: store.makeCVEClient,
            reviewUpdates: {
                store.navigation.searchText = ""
                store.navigation.selection = .updates
            }, showSoftware: store.showCVESoftware)
        case .history: UpdateHistoryView()
        case .developerPackages: DeveloperPackagesView()
        case .localModels: LocalModelsView()
        case .appStore, .testFlight, .setapp, .microsoftAutoUpdate, .steam, .otherUpdaters,
             .sparkle, .homebrewApps, .github, .noSource:
            AllAppsView(
                apps: store.applications(for: store.selection).filter { store.searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(store.searchText) },
                title: store.selection.rawValue,
                systemImage: store.selection.headerSystemImage
            )
        }
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: {
                if isSearching {
                    return store.selectedApp != nil || store.updateInspectorSelection != nil
                }
                switch store.selection {
                case .updates:
                    return store.selectedApp != nil || store.updateInspectorSelection != nil
                case .homebrewPackages: return selectedHomebrewPackage != nil
                case .developerPackages: return selectedDeveloperPackage != nil
                case .localModels: return selectedLocalModel != nil
                case .macOSUpdates, .history: return false
                default: return store.selectedApp != nil
                }
            },
            // Details open by selecting an item; the inspector only closes from here.
            set: { isPresented in
                if !isPresented { store.clearInspectorSelection() }
            }
        )
    }

    @ViewBuilder private var inspectorContent: some View {
        if isSearching {
            if let app = store.selectedApp {
                AppDetailView(app: app)
            } else if let inspector = store.updateInspectorSelection {
                updateInspector(inspector)
            }
        } else {
            switch store.selection {
            case .homebrewPackages:
                PackageDetail(package: selectedHomebrewPackage)
            case .developerPackages:
                DeveloperPackageDetail(package: selectedDeveloperPackage)
            case .localModels:
                LocalModelDetail(model: selectedLocalModel)
            default:
                if let app = store.selectedApp {
                    AppDetailView(app: app)
                } else if let inspector = store.updateInspectorSelection {
                    updateInspector(inspector)
                }
            }
        }
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { store.searchText },
            set: { value in
                guard value != store.searchText else { return }
                let oldQuery = store.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                let newQuery = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if oldQuery != newQuery {
                    store.selectedApp = nil
                    store.updateInspectorSelection = nil
                    store.navigation.requestedSearchResult = nil
                }
                store.searchText = value
            }
        )
    }

    private var isSearching: Bool {
        !store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedHomebrewPackage: HomebrewPackage? {
        guard let id = store.selectedPackageID else { return nil }
        return store.homebrewPackage(forID: id)
    }

    private var selectedDeveloperPackage: DeveloperPackage? {
        guard let id = store.selectedDeveloperPackageID else { return nil }
        return store.developerPackage(forID: id)
    }

    private var selectedLocalModel: LocalLLMModel? {
        guard let id = store.selectedLocalModelID else { return nil }
        return store.localModel(forID: id)
    }

    @ViewBuilder private func updateInspector(_ selection: UpdateInspectorSelection) -> some View {
        switch selection {
        case let .homebrew(id):
            PackageDetail(package: store.homebrewPackage(forID: id))
        case let .developer(id):
            DeveloperPackageDetail(package: store.developerPackage(forID: id))
        case let .model(id):
            LocalModelDetail(model: store.localModel(forID: id))
        }
    }

    private var navigationTitle: String {
        if !store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Search"
        }
        return store.selection == .homebrewApps ? "Homebrew Apps" : store.selection.rawValue
    }

}

private struct OperationsToolbarLabel: View {
    let runningCount: Int

    var body: some View {
        Label {
            Text("Operations")
        } icon: {
            Image(systemName: "list.bullet.rectangle")
                .overlay(alignment: .topTrailing) {
                    if runningCount > 0 {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 7, height: 7)
                            .offset(x: 3, y: -3)
                            .accessibilityHidden(true)
                    }
                }
        }
        .accessibilityValue(runningCount > 0 ? "\(runningCount) running" : "")
    }
}

extension View {
    func upkeepHomebrewAuthorizationAlert(_ store: UpkeepStore) -> some View {
        alert(item: Binding(
            get: { store.pendingHomebrewAuthorizationConfirmation },
            set: { store.pendingHomebrewAuthorizationConfirmation = $0 }
        )) { confirmation in
            Alert(
                title: Text("Continue with Homebrew?"),
                message: Text(confirmation.action.authorizationMessage(itemName: confirmation.itemName)),
                primaryButton: .default(Text(confirmation.action.isAdoption ? "Continue Adoption" : "Continue Update")) {
                    Task { await store.confirmHomebrewAuthorization(confirmation) }
                },
                secondaryButton: .cancel()
            )
        }
    }

    func upkeepRunningAppConfirmationAlert(_ store: UpkeepStore) -> some View {
        alert(item: Binding(
            get: { store.pendingRunningAppConfirmation },
            set: { store.pendingRunningAppConfirmation = $0 }
        )) { confirmation in
            Alert(
                title: Text(confirmation.title),
                message: Text(confirmation.message),
                primaryButton: .destructive(Text(confirmation.buttonTitle)) {
                    Task { await store.confirmRunningAppUpdate(confirmation) }
                },
                secondaryButton: .cancel()
            )
        }
    }
}

private extension HomebrewAuthorizationConfirmation.Action {
    var isAdoption: Bool {
        switch self {
        case .adopt, .updateAdoptable: true
        case .update, .package, .allPackages: false
        }
    }

    func authorizationMessage(itemName: String) -> String {
        if isAdoption {
            return "Homebrew may need to repair read permissions inside \(itemName) before it can adopt the app. If needed, Terminal will ask for your administrator password and Upkeep will retry adoption."
        }
        return "The installer or cleanup for \(itemName) may need administrator approval. If needed, Terminal will ask for your administrator password."
    }
}
