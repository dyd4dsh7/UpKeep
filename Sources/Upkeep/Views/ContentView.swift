import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var store: UpkeepStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 215, ideal: 235, max: 300)
        } detail: {
            detail
                .searchable(text: $store.searchText, placement: .toolbar, prompt: "Search apps and packages")
                .toolbar { toolbar }
        }
        .navigationTitle("Upkeep")
        .task {
            AppBrand.applyApplicationIcon(for: colorScheme)
            MenuBarController.shared.configure(store: store, settings: settings)
            await store.start()
            AppBrand.applyDockBadge(updateCount: store.totalUpdateCount)
            refreshMenuBar()
        }
        .onChange(of: store.totalUpdateCount, initial: true) { _, count in
            AppBrand.applyDockBadge(updateCount: count)
            refreshMenuBar()
        }
        .onChange(of: settings.showMenuBarItem) { _, _ in
            refreshMenuBar()
        }
        .onChange(of: settings.showMenuBarCount) { _, _ in
            refreshMenuBar()
        }
        .onChange(of: colorScheme) { _, newColorScheme in
            AppBrand.applyApplicationIcon(for: newColorScheme)
            AppBrand.applyDockBadge(updateCount: store.totalUpdateCount)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            AppBrand.applyApplicationIcon(for: colorScheme)
            AppBrand.applyDockBadge(updateCount: store.totalUpdateCount)
        }
        .alert("The operation couldn’t be completed", isPresented: Binding(
            get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(store.errorMessage ?? "Unknown error") }
        .sheet(item: $store.selectedApp) { app in AppDetailView(app: app) }
    }

    private func refreshMenuBar() {
        MenuBarController.shared.refresh(
            updateCount: store.totalUpdateCount,
            showCount: settings.showMenuBarCount,
            isVisible: settings.showMenuBarItem
        )
    }

    @ViewBuilder private var detail: some View {
        switch store.selection {
        case .updates: UpdatesView()
        case .allApps: AllAppsView(apps: store.filteredApps, title: "All Apps", subtitle: "\(store.apps.count) applications scanned")
        case .adoptable: AdoptableView()
        case .homebrewPackages: HomebrewView()
        case .macOSUpdates: MacOSUpdatesView()
        case .history: UpdateHistoryView()
        case .developerPackages: DeveloperPackagesView()
        case .localModels: LocalModelsView()
        case .appStore, .sparkle, .homebrewApps, .github, .noSource:
            AllAppsView(
                apps: store.apps(for: store.selection).filter { store.searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(store.searchText) },
                title: store.selection.rawValue,
                subtitle: "\(store.count(for: store.selection)) apps"
            )
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { store.selection = .updates } label: {
                Label(
                    statusTitle,
                    systemImage: statusIcon
                )
            }
            .labelStyle(.titleAndIcon)
            .foregroundStyle(statusColor)
            .help(statusHelp)
            .accessibilityLabel(statusTitle)
            Button { Task { await store.scan() } } label: {
                if store.isScanning { ProgressView().controlSize(.small) }
                else { Image(systemName: "arrow.clockwise") }
            }
            .accessibilityLabel("Check for Updates")
            .help("Check all sources for updates")
            .disabled(store.isScanning)

            SettingsLink { Image(systemName: "gearshape") }
                .accessibilityLabel("Settings")
                .help("Open Upkeep settings")
        }
    }

    private var statusTitle: String {
        if store.totalUpdateCount > 0 { return "\(store.totalUpdateCount) Updates" }
        return store.scanWarnings.isEmpty ? "Up to Date" : "Scan Warnings"
    }

    private var statusIcon: String {
        if store.totalUpdateCount > 0 { return "arrow.down.circle.fill" }
        return store.scanWarnings.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var statusColor: Color {
        if store.totalUpdateCount > 0 { return .accentColor }
        return store.scanWarnings.isEmpty ? .green : .orange
    }

    private var statusHelp: String {
        if store.totalUpdateCount > 0 { return "Open \(store.totalUpdateCount) available updates" }
        return store.scanWarnings.isEmpty
            ? "All supported apps and packages are up to date"
            : "Some update sources could not be checked"
    }
}

private struct Sidebar: View {
    @EnvironmentObject private var store: UpkeepStore

    var body: some View {
        List(selection: $store.selection) {
            Section("Updates") {
                item(.updates, icon: "arrow.down.circle")
            }
            Section("Installed") {
                item(.allApps, icon: "square.grid.2x2")
                item(.adoptable, icon: "arrow.down.app")
            }
            Section("Sources") {
                item(.appStore, icon: "bag")
                item(.homebrewApps, icon: "shippingbox")
                item(.sparkle, icon: "sparkles")
                item(.github, icon: "chevron.left.forwardslash.chevron.right")
                item(.noSource, icon: "questionmark.app")
            }
            Section("Packages") {
                item(.homebrewPackages, icon: "terminal")
                if !store.installedDeveloperManagers.isEmpty {
                    item(.developerPackages, icon: "chevron.left.forwardslash.chevron.right")
                }
                if !store.localModels.isEmpty {
                    item(.localModels, icon: "brain.head.profile")
                }
            }
            Section("System") {
                item(.macOSUpdates, icon: "apple.logo")
                item(.history, icon: "clock.arrow.circlepath")
            }
        }
        .listStyle(.sidebar)
    }

    private func item(_ destination: SidebarDestination, icon: String) -> some View {
        Label {
            HStack {
                Text(destination == .homebrewApps ? "Homebrew" : destination.rawValue)
                Spacer()
                let count = store.count(for: destination)
                if count > 0 { Text("\(count)").font(.caption).foregroundStyle(.secondary).monospacedDigit() }
            }
        } icon: { Image(systemName: icon) }
        .tag(destination)
    }
}
