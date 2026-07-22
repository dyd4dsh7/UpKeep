import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: UpkeepStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationSplitView {
            UpkeepSidebarView()
                .navigationSplitViewColumnWidth(min: 215, ideal: 235, max: 300)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .inspector(isPresented: inspectorPresented) {
                    inspectorContent
                        .inspectorColumnWidth(
                            min: UpkeepLayout.inspectorMinimumWidth,
                            ideal: UpkeepLayout.inspectorIdealWidth,
                            max: UpkeepLayout.inspectorMaximumWidth
                        )
                }
        }
        .navigationTitle(navigationTitle)
        .navigationSubtitle(navigationSubtitle)
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "Search Upkeep")
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
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            AppBrand.refreshDockPresentationIfNeeded(
                updateCount: settings.showDockBadge ? store.totalUpdateCount : 0
            )
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
        .alert("The operation couldn’t be completed", isPresented: Binding(
            get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(store.errorMessage ?? "Unknown error") }
        .upkeepRunningAppConfirmationAlert(store)
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
        if !store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            GlobalSearchView()
        } else {
            destinationDetail
        }
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
        case .appStore, .testFlight, .setapp, .microsoftAutoUpdate,
             .sparkle, .homebrewApps, .github, .noSource:
            AllAppsView(
                apps: store.apps(for: store.selection).filter { store.searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(store.searchText) },
                title: store.selection.rawValue,
                systemImage: store.selection.headerSystemImage
            )
        }
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: {
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

    private var selectedHomebrewPackage: HomebrewPackage? {
        guard let id = store.selectedPackageID else { return nil }
        return store.homebrewPackages.first { $0.id == id }
    }

    private var selectedDeveloperPackage: DeveloperPackage? {
        guard let id = store.selectedDeveloperPackageID else { return nil }
        return store.developerPackages.first { $0.id == id }
    }

    private var selectedLocalModel: LocalLLMModel? {
        guard let id = store.selectedLocalModelID else { return nil }
        return store.localModels.first { $0.id == id }
    }

    @ViewBuilder private func updateInspector(_ selection: UpdateInspectorSelection) -> some View {
        switch selection {
        case let .homebrew(id):
            PackageDetail(package: store.homebrewPackages.first { $0.id == id })
        case let .developer(id):
            DeveloperPackageDetail(package: store.developerPackages.first { $0.id == id })
        case let .model(id):
            LocalModelDetail(model: store.localModels.first { $0.id == id })
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
