import SwiftUI

struct GlobalSearchView: View {
    @EnvironmentObject private var store: UpkeepStore
    @StateObject private var searchState = GlobalSearchState()

    var body: some View {
        let results = GlobalSearch(store: store).results
        VStack(spacing: 0) {
            if results.isEmpty {
                ContentUnavailableView {
                    Label("No Results", systemImage: "magnifyingglass")
                } description: {
                    Text("No apps, packages, models, system updates, or history match “\(displayQuery)”.")
                } actions: {
                    Button("Clear Search") { store.searchText = "" }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .upkeepStateTransition()
            } else {
                List(selection: $searchState.selection) {
                    if !results.apps.isEmpty {
                        Section("Applications") {
                            ForEach(results.apps) { app in appRow(app) }
                        }
                    }
                    if !results.adoptableApps.isEmpty {
                        Section("Adoptable Apps") {
                            ForEach(results.adoptableApps) { item in adoptableRow(item) }
                        }
                    }
                    if !results.homebrewPackages.isEmpty {
                        Section("Homebrew Packages") {
                            ForEach(results.homebrewPackages) { package in homebrewRow(package) }
                        }
                    }
                    if !results.developerPackages.isEmpty {
                        Section("Developer Packages") {
                            ForEach(results.developerPackages) { package in developerRow(package) }
                        }
                    }
                    if !results.models.isEmpty {
                        Section("AI Models") {
                            ForEach(results.models) { model in modelRow(model) }
                        }
                    }
                    if !results.macOSUpdates.isEmpty {
                        Section("macOS") {
                            ForEach(results.macOSUpdates) { update in macOSRow(update) }
                        }
                    }
                    if !results.history.isEmpty {
                        Section("Update History") {
                            ForEach(results.history) { record in historyRow(record) }
                        }
                    }
                }
                .listStyle(.inset)
                .onChange(of: searchState.selection) { _, newSelection in
                    guard let newSelection else { return }
                    activate(newSelection)
                }
                .onChange(of: query) { _, _ in
                    searchState.selection = nil
                }
                .upkeepStateTransition()
            }
        }
        .upkeepAnimated(for: results.isEmpty ? "empty:\(query)" : results.identity)
    }

    private var query: String {
        store.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayQuery: String {
        store.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func appRow(_ app: InstalledApp) -> some View {
        StandardItemRow(isSelected: searchState.selection == .application(app.id)) {
            AppIcon(url: app.url, size: 36)
        } content: {
            ItemIdentityView(
                title: app.name,
                detail: appSourceSummary(app),
                isRunning: store.isRunning(app),
                prereleaseChannel: app.prereleaseChannel,
                prereleaseIsInstalled: app.prereleaseChannel != nil
            )
        } accessories: {
            InstalledVersionView(version: app.installedVersion)
        }
        .tag(SearchResultSelection.application(app.id))
    }

    private func adoptableRow(_ item: AdoptableApp) -> some View {
        StandardItemRow(isSelected: searchState.selection == .adoptable(item.id)) {
            AppIcon(url: item.app.url, size: 36)
        } content: {
            ItemIdentityView(title: item.app.name, detail: "Adoptable · Homebrew \(item.caskToken)")
        } accessories: {
            VersionTransitionView(current: item.app.installedVersion, latest: item.caskVersion)
        }
        .tag(SearchResultSelection.adoptable(item.id))
    }

    private func homebrewRow(_ package: HomebrewPackage) -> some View {
        StandardItemRow(isSelected: searchState.selection == .homebrew(package.id)) {
            BundledPackageIcon(name: "homebrew", size: 36)
        } content: {
            ItemIdentityView(
                title: package.displayName,
                detail: "Homebrew \(package.kind.rawValue)" + (package.isDependency ? " · Dependency" : "")
            )
        } accessories: {
            VersionTransitionView(current: package.installedVersion, latest: package.isOutdated ? package.currentVersion : nil)
        }
        .tag(SearchResultSelection.homebrew(package.id))
    }

    private func developerRow(_ package: DeveloperPackage) -> some View {
        StandardItemRow(isSelected: searchState.selection == .developer(package.id)) {
            PackageManagerIcon(manager: package.manager)
        } content: {
            ItemIdentityView(title: package.name, detail: package.manager.rawValue)
        } accessories: {
            VersionTransitionView(current: package.currentVersion, latest: package.isOutdated ? package.latestVersion : nil)
        }
        .tag(SearchResultSelection.developer(package.id))
    }

    private func modelRow(_ model: LocalLLMModel) -> some View {
        StandardItemRow(isSelected: searchState.selection == .model(model.id)) {
            LocalModelRuntimeIcon(runtime: model.runtime, size: 36)
        } content: {
            ItemIdentityView(
                title: model.name,
                detail: model.variant.map { "\(model.runtime.rawValue) · \($0)" } ?? model.runtime.rawValue
            )
        } accessories: {
            VersionTransitionView(current: model.installedRevision, latest: model.isOutdated ? model.latestRevision : nil)
        }
        .tag(SearchResultSelection.model(model.id))
    }

    private func macOSRow(_ update: MacOSUpdate) -> some View {
        StandardItemRow(isSelected: searchState.selection == .macOS(update.id)) {
            Image(systemName: update.isFullInstaller ? "internaldrive" : "apple.logo")
                .font(.title2).foregroundStyle(update.isBeta ? .purple : .blue)
        } content: {
            ItemIdentityView(
                title: update.title,
                detail: update.isFullInstaller ? "Full macOS installer" : "macOS system update",
                prereleaseChannel: update.prereleaseChannel
            )
        } accessories: {
            InstalledVersionView(version: update.version)
            Button { Task { await store.prepareMacOSUpdate(update) } } label: {
                WorkingActionLabel(
                    isWorking: store.isWorking(.macOSUpdate(update.id)),
                    idleTitle: "Open",
                    workingTitle: "Opening…"
                )
            }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(store.isWorking(.macOSUpdate(update.id)))
        }
        .tag(SearchResultSelection.macOS(update.id))
    }

    private func historyRow(_ record: UpdateRecord) -> some View {
        StandardItemRow(isSelected: searchState.selection == .history(record.id)) {
            Image(systemName: historyIcon(record.kind)).foregroundStyle(.blue)
        } content: {
            ItemIdentityView(
                title: record.name,
                detail: "\(record.kind.rawValue) · \(record.date.formatted(date: .abbreviated, time: .shortened))"
            )
        } accessories: {
            VersionTransitionView(current: record.fromVersion, latest: record.toVersion)
        }
        .tag(SearchResultSelection.history(record.id))
    }

    private func activate(_ selection: SearchResultSelection) {
        store.selectedApp = nil
        store.updateInspectorSelection = nil
        switch selection {
        case let .application(id):
            store.selectedApp = store.app(forID: id)
        case let .adoptable(id):
            store.selectedApp = store.adoptableApp(forID: id)?.app
        case let .homebrew(id):
            store.selectedPackageID = id
            store.updateInspectorSelection = .homebrew(id)
        case let .developer(id):
            store.selectedDeveloperPackageID = id
            store.updateInspectorSelection = .developer(id)
        case let .model(id):
            store.selectedLocalModelID = id
            store.updateInspectorSelection = .model(id)
        case .macOS:
            store.selection = .macOSUpdates
        case .history:
            store.selection = .history
        }
    }

    private func appSourceSummary(_ app: InstalledApp) -> String {
        let sources = store.sources(for: app)
        if sources.isEmpty {
            if app.updateManagement.isExternallyManaged { return app.updateManagement.rawValue }
            return app.hasBuiltInUpdater ? "Built-in updater" : "No update source"
        }
        return sources.map(\.rawValue).joined(separator: " · ")
    }

    private func historyIcon(_ kind: UpdateRecordKind) -> String {
        switch kind {
        case .app: "app.fill"
        case .homebrew: "shippingbox.fill"
        case .macOS: "apple.logo"
        case .developer: "chevron.left.forwardslash.chevron.right"
        case .model: "brain.head.profile.fill"
        }
    }
}

private enum SearchResultSelection: Hashable {
    case application(String)
    case adoptable(String)
    case homebrew(String)
    case developer(String)
    case model(String)
    case macOS(String)
    case history(UUID)
}

@MainActor
private final class GlobalSearchState: ObservableObject {
    @Published var selection: SearchResultSelection?
}
