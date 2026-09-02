import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: UpkeepStore
    @EnvironmentObject private var settings: AppSettings
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var sidebarCollapsedForInspector = false

    var body: some View {
        GeometryReader { geometry in
            workspace
                .onChange(of: inspectorPresented.wrappedValue) { _, _ in
                    adaptSidebar(to: geometry.size.width)
                }
                .onChange(of: geometry.size.width) { _, width in
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
        } else if sidebarCollapsedForInspector {
            sidebarCollapsedForInspector = false
            columnVisibility = .all
        }
    }

    private var workspace: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            UpkeepSidebarView()
                .navigationSplitViewColumnWidth(min: 215, ideal: 235, max: 300)
                // Keep independent alerts on separate branches. Chaining multiple
                // alert modifiers on the split-view root causes the last alert to
                // suppress Homebrew's authorization prompt on macOS.
                .upkeepHomebrewAuthorizationAlert(store)
        } detail: {
            detail
                // The window owns its minimum size. Avoid feeding changing list,
                // banner, and inspector minima back into AppKit's split layout.
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .upkeepRunningAppConfirmationAlert(store)
                .inspector(isPresented: inspectorPresented) {
                    inspectorContent
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .inspectorColumnWidth(UpkeepLayout.inspectorIdealWidth)
                }
        }
        .navigationTitle(navigationTitle)
        .navigationSubtitle(navigationSubtitle)
        .searchable(text: $store.navigation.searchText, placement: .toolbar, prompt: "Search Upkeep")
        .sheet(isPresented: Binding(
            get: { !settings.hasCompletedSetup },
            set: { _ in }
        )) {
            SetupView()
                .environmentObject(settings)
                .interactiveDismissDisabled()
        }
        .task {
            MenuBarController.shared.configure(store: store, settings: settings)
            if settings.hasCompletedSetup { await store.start() }
            refreshDockBadge()
            refreshMenuBar()
        }
        .onChange(of: settings.hasCompletedSetup) { _, completed in
            guard completed else { return }
            Task { await store.start() }
        }
        .onChange(of: store.totalUpdateCount, initial: true) { _, _ in
            refreshDockBadge()
            refreshMenuBar()
        }
        .onChange(of: settings.showMenuBarItem) { _, _ in
            refreshMenuBar()
        }
        .onChange(of: settings.showMenuBarCount) { _, _ in
            refreshMenuBar()
        }
        .onChange(of: settings.showDockBadge) { _, _ in
            refreshDockBadge()
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
        }
        .onChange(of: store.searchText) { _, value in
            if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                store.selectedApp = nil
                store.updateInspectorSelection = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshDockBadge()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            AppBrand.refreshDockPresentationIfNeeded(
                updateCount: settings.showDockBadge ? store.totalUpdateCount : 0
            )
        }
        .alert("The operation couldn’t be completed", isPresented: Binding(
            get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(store.errorMessage ?? "Unknown error") }
    }

    private func refreshMenuBar() {
        MenuBarController.shared.refresh(
            updateCount: store.totalUpdateCount,
            showCount: settings.showMenuBarCount,
            isVisible: settings.showMenuBarItem
        )
    }

    private func refreshDockBadge() {
        AppBrand.applyDockPresentation(
            updateCount: settings.showDockBadge ? store.totalUpdateCount : 0
        )
    }

    private var basicSidebarDestinations: Set<SidebarDestination> {
        [.updates, .allApps, .homebrewPackages, .macOSUpdates, .history]
    }

    @ViewBuilder private var detail: some View {
        VStack(spacing: 0) {
            if store.selection != .history {
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
            set: { isPresented in
                if !isPresented {
                    store.selectedApp = nil
                    store.updateInspectorSelection = nil
                    store.selectedPackageID = nil
                    store.selectedDeveloperPackageID = nil
                    store.selectedLocalModelID = nil
                }
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

    private var navigationSubtitle: String {
        if !store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Results across apps, packages, models, macOS, and history"
        }
        switch store.selection {
        case .updates:
            if store.isScanning { return "Looking for new versions…" }
            return store.totalUpdateCount == 1 ? "1 available update" : "\(store.totalUpdateCount) available updates"
        case .allApps:
            return "\(store.apps.count) applications scanned"
        case .adoptable:
            return "\(store.adoptableApps.count) apps available for Homebrew adoption"
        case .homebrewPackages:
            return "\(store.homebrewPackages.count) installed · \(store.outdatedPackageCount) updates"
        case .developerPackages:
            return "\(store.developerPackages.count) installed · \(store.outdatedDeveloperPackageCount) updates"
        case .localModels:
            return "\(store.localModels.count) installed · \(store.outdatedLocalModelCount) updates"
        case .macOSUpdates:
            return "\(store.macOSUpdates.count) available releases"
        case .history:
            return "\(store.updateHistory.count) recorded updates"
        default:
            let count = store.count(for: store.selection)
            return count == 1 ? "1 app" : "\(count) apps"
        }
    }
}

extension View {
    func upkeepHomebrewAuthorizationAlert(_ store: UpkeepStore) -> some View {
        alert(item: Binding(
            get: { store.pendingHomebrewAuthorizationConfirmation },
            set: { store.pendingHomebrewAuthorizationConfirmation = $0 }
        )) { confirmation in
            Alert(
                title: Text("Administrator Password May Be Required"),
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
            return "\(itemName) is a Homebrew cask. If Homebrew cannot read the existing app bundle, Upkeep will open Terminal and ask for your macOS password to repair readable permissions inside that app only, then retry adoption."
        }
        return "\(itemName) is a Homebrew cask. Its installer or cleanup steps may need administrator approval. If required, Upkeep will open Terminal and macOS will ask for your password."
    }
}
