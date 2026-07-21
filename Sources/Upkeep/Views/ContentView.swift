import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: UpkeepStore

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 205, ideal: 220, max: 270)
        } detail: {
            detail
                .searchable(text: $store.searchText, placement: .toolbar, prompt: "Search")
                .toolbar { toolbar }
        }
        .task {
            AppBrand.applyApplicationIcon()
            await store.start()
        }
        .alert("The operation couldn’t be completed", isPresented: Binding(
            get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(store.errorMessage ?? "Unknown error") }
        .sheet(item: $store.selectedApp) { app in AppDetailView(app: app) }
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
        case .changelog: ChangelogView()
        case .settings: SettingsView()
        case .appStore, .sparkle, .homebrewApps, .github, .noSource:
            AllAppsView(
                apps: store.apps(for: store.selection).filter { store.searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(store.searchText) },
                title: store.selection.rawValue,
                subtitle: "\(store.count(for: store.selection)) apps"
            )
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { store.selection = .settings } label: { Label("Settings", systemImage: "gearshape") }
                .help("Open Upkeep settings")
        }
        ToolbarItem(placement: .primaryAction) {
            Button { Task { await store.scan() } } label: {
                if store.isScanning { ProgressView().controlSize(.small) }
                else { Label("Check Again", systemImage: "arrow.clockwise") }
            }
            .help("Check all sources for updates")
            .disabled(store.isScanning)
        }
    }
}

private struct Sidebar: View {
    @EnvironmentObject private var store: UpkeepStore

    var body: some View {
        VStack(spacing: 0) {
            brand
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
                }
                Section("System") {
                    item(.macOSUpdates, icon: "apple.logo")
                    item(.history, icon: "clock.arrow.circlepath")
                    item(.changelog, icon: "list.bullet.rectangle")
                    item(.settings, icon: "gearshape")
                }
            }
            .listStyle(.sidebar)
            status
        }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            AppBrandIcon(size: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text("Upkeep").font(.headline)
                Text("Every update. One place.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }.padding(16)
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

    private var status: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack(spacing: 7) {
                Circle().fill(store.isScanning ? .orange : .green).frame(width: 7, height: 7)
                Text(store.isScanning ? "Checking all sources…" : checkedText).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(14)
    }

    private var checkedText: String {
        store.lastChecked.map { "Checked " + $0.formatted(.relative(presentation: .named)) } ?? "Ready"
    }
}
