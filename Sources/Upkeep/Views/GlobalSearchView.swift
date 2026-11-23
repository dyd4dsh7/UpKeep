import SwiftUI

struct GlobalSearchView: View {
    @UpkeepStoreReference private var store
    // AppKit can update List selection while SwiftUI reconciles its rows.
    // Keep this view-local value in State so it does not synchronously publish
    // an ObservableObject change from inside that update.
    @UpkeepState private var selection: SearchResultSelection?

    @UpkeepState private var scope = SearchScope.all
    @UpkeepState private var usesCompactHeader = false

    var body: some View {
        let allResults = store.globalSearchResults
        let results = allResults.inScope(scope)
        VStack(spacing: 0) {
            WorkspaceSummary(title: "Search Results",
                             detail: searchSummary(results.count),
                             systemImage: "magnifyingglass") {
                scopePicker(allResults)
            }
            if results.isEmpty {
                emptyState
            } else {
                resultList(results)
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width < 440 } action: {
            usesCompactHeader = $0
        }
        .onChange(of: query) { _, _ in resetSelection() }
        .onChange(of: scope) { _, _ in resetSelection() }
        .onChange(of: inspectorIsOpen) { wasOpen, isOpen in
            guard wasOpen, !isOpen else { return }
            switch selection {
            case .macOS, .history: break
            default: selection = nil
            }
        }
        .onChange(of: selection.map(results.contains) ?? true) { _, stillVisible in
            if !stillVisible { resetSelection() }
        }
        .onChange(of: store.navigation.requestedSearchResult, initial: true) { _, requested in
            guard let requested else { return }
            store.navigation.requestedSearchResult = nil
            if allResults.contains(requested) {
                scope = .all
                selection = requested
                activate(requested)
            }
        }
    }

    private var query: String {
        store.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func searchSummary(_ count: Int) -> String {
        let summary = WorkspaceSummary.count(count, "match", "matches")
        if usesCompactHeader, scope != .all { return "\(scope.rawValue) · \(summary)" }
        return summary
    }

    private var inspectorIsOpen: Bool {
        store.selectedApp != nil || store.updateInspectorSelection != nil
    }

    private var emptyState: some View {
        WorkspaceEmptyState(title: "No matches", systemImage: "magnifyingglass",
                            description: Text(scope == .all ? "Try a name, source, or version." : "Try another source to look for more matches.")) {
            if scope == .all {
                Button("Clear Search") { store.searchText = "" }
                    .buttonStyle(.bordered)
            } else {
                Button("Show All Sources") { scope = .all }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scopePicker(_ results: GlobalSearchResults) -> some View {
        Menu {
            ForEach(SearchScope.allCases) { option in
                Button {
                    scope = option
                } label: {
                    MenuSelectionLabel(
                        title: "\(option.rawValue) (\(results.inScope(option).count.formatted()))",
                        isSelected: option == scope
                    )
                }
            }
        } label: {
            Label(scope.rawValue, systemImage: "line.3.horizontal.decrease")
                .labelStyle(SearchScopeLabelStyle(compact: usesCompactHeader))
        }
        .help("Filter search results by source")
        .accessibilityLabel("Search sources")
        .accessibilityValue(scope.rawValue)
    }

    private func resultList(_ results: GlobalSearchResults) -> some View {
        List(selection: $selection) {
            resultSection(.apps, items: results.apps, key: SearchResultSelection.application, row: appRow)
            resultSection(.adoptable, items: results.adoptableApps, key: SearchResultSelection.adoptable, row: adoptableRow)
            resultSection(.homebrew, items: results.homebrewPackages, key: SearchResultSelection.homebrew, row: homebrewRow)
            resultSection(.developer, items: results.developerPackages, key: SearchResultSelection.developer, row: developerRow)
            resultSection(.models, items: results.models, key: SearchResultSelection.model, row: modelRow)
            resultSection(.macOS, items: results.macOSUpdates, key: SearchResultSelection.macOS, row: macOSRow)
            resultSection(.history, items: results.history, key: SearchResultSelection.history, row: historyRow)
        }
        .upkeepContentList()
        .accessibilityLabel("Search results")
        .onChange(of: selection) { _, newSelection in
            if let newSelection {
                activate(newSelection)
            } else {
                store.selectedApp = nil
                store.updateInspectorSelection = nil
            }
        }
        .onKeyPress(.return) {
            switch selection {
            case let .macOS(id): store.revealInventoryResult(.macOS(id))
            case let .history(id): store.revealInventoryResult(.history(id))
            default: return .ignored
            }
            return .handled
        }
    }

    @ViewBuilder
    private func resultSection<Item: Identifiable, Row: View>(
        _ scope: SearchScope,
        items: [Item],
        key: (Item.ID) -> SearchResultSelection,
        @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items.map { SearchRow(item: $0, id: key($0.id)) }) { result in
                    row(result.item).tag(result.id)
                }
            } header: {
                WorkspaceSectionLabel(title: scope.rawValue, count: items.count)
            }
        }
    }

    private func resetSelection() {
        selection = nil
        store.selectedApp = nil
        store.updateInspectorSelection = nil
    }

    private func appRow(_ app: InstalledApp) -> some View {
        StandardItemRow(isSelected: selection == .application(app.id)) {
            AppIcon(url: app.url, size: 36)
        } content: {
            ItemIdentityView(
                title: app.name,
                detail: appSourceSummary(app),
                isRunning: store.isRunning(app),
                prereleaseChannel: app.prereleaseChannel,
                prereleaseIsInstalled: app.prereleaseChannel != nil,
                showsIntelWarning: app.needsAppleSiliconMigration,
                cveItem: CVEInventoryItem(app)
            )
        } accessories: {
            InstalledVersionView(version: app.installedVersion)
        }
    }

    private func adoptableRow(_ item: AdoptableApp) -> some View {
        StandardItemRow(isSelected: selection == .adoptable(item.id)) {
            AppIcon(url: item.app.url, size: 36)
        } content: {
            ItemIdentityView(title: item.app.name, detail: "Adoptable · Homebrew \(item.caskToken)", showsIntelWarning: item.app.needsAppleSiliconMigration)
        } accessories: {
            VersionTransitionView(current: item.app.installedVersion, latest: item.caskVersion)
        }
    }

    private func homebrewRow(_ package: HomebrewPackage) -> some View {
        StandardItemRow(isSelected: selection == .homebrew(package.id)) {
            PackageSourceIcon(name: "homebrew", size: 36)
        } content: {
            ItemIdentityView(
                title: package.displayName,
                detail: "Homebrew \(package.kind.rawValue)" + (package.isDependency ? " · Dependency" : ""),
                cveItem: CVEInventoryItem(package)
            )
        } accessories: {
            VersionTransitionView(current: package.installedVersion, latest: package.isOutdated ? package.currentVersion : nil)
        }
    }

    private func developerRow(_ package: DeveloperPackage) -> some View {
        StandardItemRow(isSelected: selection == .developer(package.id)) {
            PackageManagerIcon(manager: package.manager)
        } content: {
            ItemIdentityView(title: package.name, detail: package.manager.rawValue, cveItem: CVEInventoryItem(package))
        } accessories: {
            VersionTransitionView(current: package.currentVersion, latest: package.isOutdated ? package.latestVersion : nil)
        }
    }

    private func modelRow(_ model: LocalLLMModel) -> some View {
        StandardItemRow(isSelected: selection == .model(model.id)) {
            LocalModelRuntimeIcon(runtime: model.runtime, size: 36)
        } content: {
            ItemIdentityView(
                title: model.name,
                detail: model.variant.map { "\(model.runtime.rawValue) · \($0)" } ?? model.runtime.rawValue
            )
        } accessories: {
            VersionTransitionView(current: model.installedRevision, latest: model.isOutdated ? model.latestRevision : nil)
        }
    }

    private func macOSRow(_ update: MacOSUpdate) -> some View {
        StandardItemRow(isSelected: selection == .macOS(update.id)) {
            Image(systemName: update.isFullInstaller ? "internaldrive" : "apple.logo")
                .font(.title2).foregroundStyle(update.isBeta ? .purple : .blue)
        } content: {
            ItemIdentityView(
                title: update.title,
                detail: update.isFullInstaller ? "Full macOS installer" : "macOS system update",
                prereleaseChannel: update.prereleaseChannel
            )
        } accessories: {
            InstalledVersionView(version: update.version, alignsWithTransitions: false)
            Button("Show Update") { store.revealInventoryResult(.macOS(update.id)) }
                .listRowPrimaryAction()
                .help("Show this item in the macOS workspace")
        }
    }

    private func historyRow(_ record: UpdateRecord) -> some View {
        StandardItemRow(isSelected: selection == .history(record.id)) {
            WorkspaceGlyph(systemImage: record.kind.systemImage, size: 34)
        } content: {
            ItemIdentityView(
                title: record.name,
                detail: "\(record.kind.rawValue) · \(record.date.formatted(date: .abbreviated, time: .shortened))"
            )
        } accessories: {
            VersionTransitionView(current: record.fromVersionLabel, latest: record.toVersionLabel)
            Button("Show Record") { store.revealInventoryResult(.history(record.id)) }
                .listRowPrimaryAction()
        }
    }

    private func activate(_ selection: SearchResultSelection) {
        switch selection {
        case let .application(id):
            store.updateInspectorSelection = nil
            store.selectedApp = store.app(forID: id)
        case let .adoptable(id):
            store.updateInspectorSelection = nil
            store.selectedApp = store.adoptableApp(forID: id)?.app
        case let .homebrew(id):
            store.selectedApp = nil
            store.updateInspectorSelection = .homebrew(id)
        case let .developer(id):
            store.selectedApp = nil
            store.updateInspectorSelection = .developer(id)
        case let .model(id):
            store.selectedApp = nil
            store.updateInspectorSelection = .model(id)
        case .macOS, .history:
            store.selectedApp = nil
            store.updateInspectorSelection = nil
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

}

private struct SearchRow<Item>: Identifiable {
    let item: Item
    let id: SearchResultSelection
}

private struct SearchScopeLabelStyle: LabelStyle {
    let compact: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
            if !compact { configuration.title }
        }
    }
}
