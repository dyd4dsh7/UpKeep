import AppKit
import SwiftUI

private struct UpdateListSnapshot {
    let applications: [AvailableUpdate]
    let homebrewPackages: [HomebrewPackage]
    let macOSUpdates: [MacOSUpdate]
    let developerPackages: [DeveloperPackage]
    let models: [LocalLLMModel]

    var isEmpty: Bool {
        applications.isEmpty && homebrewPackages.isEmpty && macOSUpdates.isEmpty
            && developerPackages.isEmpty && models.isEmpty
    }

    var identity: String {
        let appIDs = applications.map { "app:\($0.app.id)" }
        let packageIDs = homebrewPackages.map { "homebrew:\($0.id)" }
        let systemIDs = macOSUpdates.map { "macos:\($0.id)" }
        let developerIDs = developerPackages.map { "developer:\($0.id)" }
        let modelIDs = models.map { "model:\($0.id)" }
        return (appIDs + packageIDs + systemIDs + developerIDs + modelIDs).joined(separator: "|")
    }
}

struct UpdatesView: View {
    @UpkeepStoreReference private var store
    @EnvironmentObject private var viewState: UpdateViewState
    @FocusState private var updatesFocused: Bool

    var body: some View {
        let snapshot = listSnapshot
        // Resolved once per body; rows compare against it instead of each
        // re-deriving the sorted application list.
        let selectedID = selectedItemID(in: snapshot)
        ScrollViewReader { proxy in
            ScrollView {
                // Eager measurement keeps selection from correcting estimated
                // heights above the current scroll position.
                VStack(alignment: .leading, spacing: 17) {
                    UpdateDecisionHeader(review: { store.isShowingBatchReview = true })
                    if !snapshot.isEmpty || viewState.filter != .all {
                        queueToolbar
                        if snapshot.isEmpty {
                            emptyState
                        } else {
                            updateGroups(snapshot, selectedID: selectedID)
                        }
                    }
                }
                .padding(.horizontal, UpkeepLayout.pageInset)
                .padding(.vertical, 20)
                .frame(maxWidth: 1_200)
                .frame(maxWidth: .infinity)
            }
            .focusable()
            .focused($updatesFocused)
            .focusEffectDisabled()
            .onMoveCommand { direction in
                moveSelection(direction, snapshot: snapshot, selectedID: selectedID, proxy: proxy)
            }
            // Return opens details (selecting the first row if none); ⌘Return
            // runs the selected row's primary action; Escape closes details.
            .onKeyPress(.return, phases: .down) { press in
                handleReturn(press, snapshot: snapshot, selectedID: selectedID, proxy: proxy)
            }
            .onKeyPress(.escape) {
                guard selectedID != nil else { return .ignored }
                selectedUpdateItemID.wrappedValue = nil
                return .handled
            }
        }
        .upkeepAnimated(for: snapshot.identity)
        .sheet(isPresented: $store.navigation.isShowingBatchReview) {
            BatchUpdateSheet(items: store.availableBatchUpdateItems)
                .environment(\.upkeepStoreReference, store)
        }
        .toolbar { listToolbar }
    }

    private var queueToolbar: some View {
        HStack(spacing: 10) {
            Text("Updates by source")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            updateFilterMenu
            updateSortMenu
        }
    }

    private func updateGroups(_ snapshot: UpdateListSnapshot, selectedID: String?) -> some View {
        VStack(spacing: 14) {
            updateSection("Applications", items: snapshot.applications) { update in
                selectionRow(id: "app:\(update.app.id)", selectedID: selectedID) { UpdateCard(update: update) }
            }
            updateSection("Homebrew Packages", items: snapshot.homebrewPackages) { package in
                selectionRow(id: UpdateInspectorSelection.homebrew(package.id).listID, selectedID: selectedID) {
                    HomebrewUpdateCard(package: package)
                }
            }
            updateSection("macOS", items: snapshot.macOSUpdates) { update in
                MacOSUpdateCard(update: update).padding(.horizontal, 8)
            }
            updateSection("Developer Packages", items: snapshot.developerPackages) { package in
                selectionRow(id: UpdateInspectorSelection.developer(package.id).listID, selectedID: selectedID) {
                    DeveloperUpdateCard(package: package)
                }
            }
            updateSection("AI Models", items: snapshot.models) { model in
                selectionRow(id: UpdateInspectorSelection.model(model.id).listID, selectedID: selectedID) {
                    LocalModelUpdateCard(model: model)
                }
            }
        }
    }

    @ViewBuilder private func updateSection<Item: Identifiable, Row: View>(
        _ title: String,
        items: [Item],
        @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                WorkspaceSectionLabel(title: title, count: items.count)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                Divider().opacity(0.62)
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        row(item)
                        if item.id != items.last?.id {
                            Divider().opacity(0.6).padding(.leading, 58)
                        }
                    }
                }
                .padding(5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .upkeepSurface()
        }
    }

    private func selectionRow<Row: View>(id: String, selectedID: String?, @ViewBuilder content: () -> Row) -> some View {
        let isSelected = selectedID == id
        return content()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                // The scroll view's own focus ring is disabled; mark the keyboard row instead.
                if isSelected && updatesFocused {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectedUpdateItemID.wrappedValue = id
                updatesFocused = true
            }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAction {
                selectedUpdateItemID.wrappedValue = id
                updatesFocused = true
            }
            .id(id)
    }

    private func moveSelection(_ direction: MoveCommandDirection, snapshot: UpdateListSnapshot, selectedID: String?, proxy: ScrollViewProxy) {
        guard direction == .up || direction == .down else { return }
        let ids = snapshot.applications.map { "app:\($0.app.id)" }
            + snapshot.homebrewPackages.map { UpdateInspectorSelection.homebrew($0.id).listID }
            + snapshot.developerPackages.map { UpdateInspectorSelection.developer($0.id).listID }
            + snapshot.models.map { UpdateInspectorSelection.model($0.id).listID }
        guard !ids.isEmpty else { return }
        let current = selectedID.flatMap { ids.firstIndex(of: $0) }
        let next = current.map { min(max(0, $0 + (direction == .down ? 1 : -1)), ids.count - 1) }
            ?? (direction == .down ? 0 : ids.count - 1)
        selectedUpdateItemID.wrappedValue = ids[next]
        proxy.scrollTo(ids[next])
    }

    private func keyboardRowIDs(_ snapshot: UpdateListSnapshot) -> [String] {
        snapshot.applications.map { "app:\($0.app.id)" }
            + snapshot.homebrewPackages.map { UpdateInspectorSelection.homebrew($0.id).listID }
            + snapshot.developerPackages.map { UpdateInspectorSelection.developer($0.id).listID }
            + snapshot.models.map { UpdateInspectorSelection.model($0.id).listID }
    }

    private func handleReturn(_ press: KeyPress, snapshot: UpdateListSnapshot, selectedID: String?,
                              proxy: ScrollViewProxy) -> KeyPress.Result {
        guard let selectedID else {
            guard let first = keyboardRowIDs(snapshot).first else { return .ignored }
            selectedUpdateItemID.wrappedValue = first
            proxy.scrollTo(first)
            return .handled
        }
        guard press.modifiers.contains(.command) else { return .handled }
        performPrimaryAction(for: selectedID, in: snapshot)
        return .handled
    }

    /// Same action as the row's primary button, including its confirmations.
    private func performPrimaryAction(for id: String, in snapshot: UpdateListSnapshot) {
        if let update = snapshot.applications.first(where: { "app:\($0.app.id)" == id }) {
            guard !store.isUpdating(update) else { return }
            Task { await store.performUpdate(update) }
        } else if let package = snapshot.homebrewPackages.first(where: { UpdateInspectorSelection.homebrew($0.id).listID == id }) {
            guard !store.isWorking(.homebrewPackage(package.id)) else { return }
            Task { await store.updatePackage(package) }
        } else if let package = snapshot.developerPackages.first(where: { UpdateInspectorSelection.developer($0.id).listID == id }) {
            guard !store.isWorking(.developerPackage(package.id)) else { return }
            Task { await store.updateDeveloperPackage(package) }
        } else if let model = snapshot.models.first(where: { UpdateInspectorSelection.model($0.id).listID == id }) {
            guard !store.isWorking(.localModel(model.id)) else { return }
            Task { await store.updateLocalModel(model) }
        }
    }

    @ToolbarContentBuilder private var listToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            ScanToolbarButton()
        }
    }

    private var updateSortMenu: some View {
        Menu {
            Section("Sort") {
                updateSortButton("Default", order: .recommended)
                updateSortButton("Name: A–Z", order: .name)
                updateSortButton("Name: Z–A", order: .name, ascending: false)
                updateSortButton("Install Date", order: .installDate, ascending: false)
                updateSortButton("Recently Updated", order: .recentlyUpdated, ascending: false)
                updateSortButton("Source", order: .source)
                updateSortButton("Installed Version", order: .installedVersion)
                updateSortButton("Available Version", order: .availableVersion)
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
                .foregroundStyle(viewState.sortOrder == .recommended ? Color.primary : .accentColor)
        }
        .fixedSize()
        .toolbarControlLabel("Sort updates")
    }

    private var updateFilterMenu: some View {
        Menu {
            Section("Filter") {
                ForEach(UpdateListFilter.allCases) { filter in
                    Button {
                        viewState.filter = filter
                    } label: {
                        MenuSelectionLabel(title: filter.rawValue, isSelected: viewState.filter == filter)
                    }
                }
            }
        } label: {
            Label(viewState.filter == .all ? "All Sources" : viewState.filter.rawValue,
                  systemImage: "line.3.horizontal.decrease")
        }
        .fixedSize()
        .toolbarControlLabel("Filter updates")
    }

    private func updateSortButton(
        _ title: String,
        order: UpdateSortOrder,
        ascending: Bool = true
    ) -> some View {
        Button {
            viewState.sortOrder = order
            viewState.sortAscending = ascending
        } label: {
            MenuSelectionLabel(
                title: title,
                isSelected: viewState.sortOrder == order &&
                    (order == .recommended || viewState.sortAscending == ascending)
            )
        }
    }

    /// The selected row's list ID, resolved against an already built snapshot.
    private func selectedItemID(in snapshot: UpdateListSnapshot) -> String? {
        if let selected = store.selectedApp,
           snapshot.applications.contains(where: { $0.app.id == selected.id }) {
            return "app:\(selected.id)"
        }
        return store.updateInspectorSelection?.listID
    }

    private var selectedUpdateItemID: Binding<String?> {
        Binding(
            get: { selectedItemID(in: listSnapshot) },
            set: { identifier in
                guard let identifier else {
                    store.selectedApp = nil
                    store.updateInspectorSelection = nil
                    return
                }
                if identifier.hasPrefix("app:") {
                    let id = String(identifier.dropFirst(4))
                    store.selectedApp = appUpdates.first { $0.app.id == id }?.app
                    store.updateInspectorSelection = nil
                } else if identifier.hasPrefix("homebrew:") {
                    let id = String(identifier.dropFirst("homebrew:".count))
                    store.selectedApp = nil
                    store.selectedPackageID = id
                    store.updateInspectorSelection = .homebrew(id)
                } else if identifier.hasPrefix("developer:") {
                    let id = String(identifier.dropFirst("developer:".count))
                    store.selectedApp = nil
                    store.selectedDeveloperPackageID = id
                    store.updateInspectorSelection = .developer(id)
                    if let package = store.developerPackages.first(where: { $0.id == id }) {
                        store.selectedDeveloperVersion = package.latestVersion
                        Task { await store.loadAvailableVersions(for: package) }
                    }
                } else if identifier.hasPrefix("model:") {
                    let id = String(identifier.dropFirst("model:".count))
                    store.selectedApp = nil
                    store.selectedLocalModelID = id
                    store.updateInspectorSelection = .model(id)
                }
            }
        )
    }

    private var appUpdates: [AvailableUpdate] {
        guard viewState.filter == .all || viewState.filter == .applications else { return [] }
        let updates = store.filteredUpdates
        guard viewState.sortOrder == .recommended else { return updates.sorted { compareUpdates($0, $1) } }
        // Decorate-sort-undecorate: the risk group is derived once per update
        // instead of twice per comparison.
        return updates
            .map { (update: $0, risk: BatchUpdateItem.application($0).riskGroup.rawValue) }
            .sorted { left, right in
                if left.risk != right.risk { return left.risk < right.risk }
                return left.update.app.name.localizedStandardCompare(right.update.app.name) == .orderedAscending
            }
            .map(\.update)
    }

    private var listSnapshot: UpdateListSnapshot {
        UpdateListSnapshot(
            applications: appUpdates,
            homebrewPackages: filteredPackages,
            macOSUpdates: systemUpdates,
            developerPackages: filteredDeveloperPackages,
            models: filteredModels
        )
    }

    private var filteredPackages: [HomebrewPackage] {
        guard viewState.filter == .all || viewState.filter == .homebrew else { return [] }
        let packages = viewState.filter == .all ? store.updatePlan.unrepresentedHomebrewUpdates : store.homebrewPackages
        return packages.filter {
            $0.isOutdated && !store.isExcluded($0)
                && (store.searchText.isEmpty || $0.displayName.localizedCaseInsensitiveContains(store.searchText))
        }.sorted { comparePackage($0.displayName, $0.installedVersion, $0.currentVersion, "Homebrew", $1.displayName, $1.installedVersion, $1.currentVersion, "Homebrew") }
    }

    private var systemUpdates: [MacOSUpdate] {
        guard viewState.filter == .all || viewState.filter == .macOS else { return [] }
        return store.macOSUpdates.filter { !$0.isFullInstaller && (store.searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(store.searchText)) }
            .sorted { comparePackage($0.title, $0.version, $0.version, "macOS", $1.title, $1.version, $1.version, "macOS") }
    }

    private var filteredDeveloperPackages: [DeveloperPackage] {
        guard viewState.filter == .all || viewState.filter == .developer else { return [] }
        return store.developerPackages.filter { $0.isOutdated && !store.isExcluded($0) && (store.searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(store.searchText)) }
            .sorted { comparePackage($0.name, $0.currentVersion, $0.latestVersion, $0.manager.rawValue, $1.name, $1.currentVersion, $1.latestVersion, $1.manager.rawValue) }
    }

    private var filteredModels: [LocalLLMModel] {
        guard viewState.filter == .all || viewState.filter == .models else { return [] }
        return store.visibleOutdatedLocalModels.filter { store.searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(store.searchText) }
            .sorted { comparePackage($0.name, $0.installedRevision, $0.latestRevision, $0.runtime.rawValue, $1.name, $1.installedRevision, $1.latestRevision, $1.runtime.rawValue) }
    }

    private func compareUpdates(_ left: AvailableUpdate, _ right: AvailableUpdate) -> Bool {
        if viewState.sortOrder == .recommended {
            let leftRisk = BatchUpdateItem.application(left).riskGroup.rawValue
            let rightRisk = BatchUpdateItem.application(right).riskGroup.rawValue
            if leftRisk != rightRisk { return leftRisk < rightRisk }
            return left.app.name.localizedStandardCompare(right.app.name) == .orderedAscending
        }
        if viewState.sortOrder == .installDate || viewState.sortOrder == .recentlyUpdated {
            let leftDate = viewState.sortOrder == .installDate ? left.app.installedAt : left.app.modifiedAt
            let rightDate = viewState.sortOrder == .installDate ? right.app.installedAt : right.app.modifiedAt
            let comparison = ListSorting.compareDates(
                leftDate, rightDate,
                leftName: left.app.name, rightName: right.app.name
            )
            return viewState.sortAscending
                ? comparison == .orderedAscending
                : comparison == .orderedDescending
        }
        return comparePackage(
            left.app.name, left.app.installedVersion, left.availableVersion, left.source.rawValue,
            right.app.name, right.app.installedVersion, right.availableVersion, right.source.rawValue
        )
    }

    private func comparePackage(
        _ leftName: String, _ leftCurrent: String, _ leftLatest: String, _ leftSource: String,
        _ rightName: String, _ rightCurrent: String, _ rightLatest: String, _ rightSource: String
    ) -> Bool {
        let comparison: ComparisonResult
        switch viewState.sortOrder {
        case .recommended: return leftName.localizedStandardCompare(rightName) == .orderedAscending
        case .name: comparison = leftName.localizedStandardCompare(rightName)
        case .source: comparison = leftSource.localizedStandardCompare(rightSource)
        case .installedVersion: comparison = VersionComparator.compare(leftCurrent, rightCurrent)
        case .availableVersion: comparison = VersionComparator.compare(leftLatest, rightLatest)
        case .installDate, .recentlyUpdated: comparison = leftName.localizedStandardCompare(rightName)
        }
        return viewState.sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
    }

    private var emptyState: some View {
        WorkspaceEmptyState(title: "No matching updates", systemImage: "line.3.horizontal.decrease",
                            description: Text("Try another source to see available updates.")) {
            Button("Show All Sources") { viewState.filter = .all }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 152)
        .upkeepSurface()
    }
}

private struct DeveloperUpdateCard: View {
    @UpkeepStoreReference private var store
    let package: DeveloperPackage
    var body: some View {
        StandardItemRow(isSelected: store.updateInspectorSelection == .developer(package.id)) {
            PackageManagerIcon(manager: package.manager, size: 36)
        } content: {
            ItemIdentityView(
                title: package.name,
                detail: [package.manager.rawValue, package.installationContext].compactMap { $0 }.joined(separator: " · "),
                prereleaseChannel: package.prereleaseChannel,
                prereleaseIsInstalled: package.prereleaseIsInstalled,
                cveItem: CVEInventoryItem(package)
            )
        } accessories: {
            if store.isRefreshing(package) {
                RefreshingIndicator(itemName: package.name)
            }
            VersionTransitionView(current: package.currentVersion, latest: package.latestVersion)
            Button { Task { await store.updateDeveloperPackage(package) } } label: {
                WorkingActionLabel(
                    isWorking: store.isWorking(.developerPackage(package.id)),
                    idleTitle: package.canUpdateAutomatically ? "Update" : "View Update",
                    phase: store.updatePhase(for: .developerPackage(package.id))
                )
            }
                .listRowPrimaryAction()
                .disabled(store.isWorking(.developerPackage(package.id)))
        }
        .tag(UpdateInspectorSelection.developer(package.id).listID)
        .contentShape(Rectangle())
        .contextMenu {
            Button(package.canUpdateAutomatically ? "Update" : "View Update") { Task { await store.updateDeveloperPackage(package) } }
                .disabled(store.isWorking(.developerPackage(package.id)))
            Button("Refresh") { Task { await store.refresh(package) } }
                .disabled(store.isRefreshing(package))
            Button("Open Folder") { openDeveloperPackageFolder(package) }
            Divider()
            exclusionOptions(
                skipTitle: "Skip Version \(package.latestVersion)",
                skip: { store.skip(package) }, ignore: { store.ignore(package) },
                skipFor: { store.skip(package, duration: $0) },
                ignoreFor: { store.ignore(package, duration: $0) }
            )
        }
    }
}

private struct MacOSUpdateCard: View {
    @UpkeepStoreReference private var store
    let update: MacOSUpdate
    var body: some View {
        StandardItemRow {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.12))
                Image(systemName: "apple.logo").font(.title2).foregroundStyle(.blue)
            }.frame(width: 36, height: 36)
        } content: {
            ItemIdentityView(
                title: update.title,
                detail: "macOS" + (update.requiresRestart ? " · Restart required" : ""),
                prereleaseChannel: update.prereleaseChannel
            )
        } accessories: {
            Button { Task { await store.prepareMacOSUpdate(update) } } label: {
                WorkingActionLabel(
                    isWorking: store.isWorking(.macOSUpdate(update.id)),
                    idleTitle: "Open Software Update",
                    workingTitle: "Opening…"
                )
            }
                .listRowPrimaryAction()
                .disabled(store.isWorking(.macOSUpdate(update.id)))
        }
    }
}

struct UpdateCard: View {
    @UpkeepStoreReference private var store
    let update: AvailableUpdate

    var body: some View {
        StandardItemRow(isSelected: store.selectedApp?.id == update.app.id) {
            AppIcon(url: update.app.url, size: 36)
        } content: {
            ItemIdentityView(
                title: update.app.name,
                detail: appUpdateDetail,
                isRunning: store.isRunning(update.app),
                prereleaseChannel: update.prereleaseChannel,
                prereleaseIsInstalled: update.prereleaseIsInstalled,
                showsIntelWarning: update.app.needsAppleSiliconMigration,
                cveItem: CVEInventoryItem(update.app)
            )
        } accessories: {
            if store.isRefreshing(update.app) {
                RefreshingIndicator(itemName: update.app.name)
            }
            VersionTransitionView(current: update.app.installedVersion, latest: update.displayAvailableVersion)
            Button {
                Task { await store.performUpdate(update) }
            } label: {
                WorkingActionLabel(isWorking: store.isUpdating(update), idleTitle: actionTitle, phase: store.updatePhase(for: .applicationUpdate(update.id)))
            }
            .listRowPrimaryAction()
            .disabled(store.isUpdating(update))
        }
        .tag("app:\(update.app.id)")
        .help(update.source.confidenceDetail)
        .contentShape(Rectangle())
        .contextMenu {
            Button(actionTitle) { Task { await store.performUpdate(update) } }
                .disabled(store.isUpdating(update))
            Button("Refresh") { Task { await store.refresh(update.app) } }
                .disabled(store.isWorking(.applicationRefresh(update.app.id)))
            Divider()
            exclusionOptions(
                skipTitle: "Skip Version \(update.displayAvailableVersion)",
                skip: { store.skip(update) }, ignore: { store.ignore(update.app) },
                skipFor: { store.skip(update, duration: $0) },
                ignoreFor: { store.ignore(update.app, duration: $0) }
            )
            if update.candidates.contains(where: \.requiresHomebrewAdoption) {
                if store.isHomebrewAdoptionIgnored(update.app) {
                    Button("Restore Homebrew Adoption") { store.restoreHomebrewAdoption(update.app) }
                } else {
                    Button("Ignore Homebrew Adoption") { store.ignoreHomebrewAdoption(update.app) }
                }
            }
            Divider()
            Button("Open") { NSWorkspace.shared.open(update.app.url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([update.app.url]) }
        }
    }

    private var actionTitle: String {
        update.actionTitle
    }

    private var appUpdateDetail: String {
        var parts = [update.source.rawValue]
        if update.homebrewToken != nil { parts.append("May require password") }
        return parts.joined(separator: " · ")
    }
}

private struct HomebrewUpdateCard: View {
    @UpkeepStoreReference private var store
    let package: HomebrewPackage

    var body: some View {
        StandardItemRow(isSelected: store.updateInspectorSelection == .homebrew(package.id)) {
            PackageSourceIcon(name: "homebrew", size: 36)
        } content: {
            ItemIdentityView(
                title: package.displayName,
                detail: package.kind.rawValue
                    + (package.isRevisionUpdate ? " · Rebuild update" : "")
                    + (package.isVersionRollback ? " · Older version" : "")
                    + (package.isDependency ? " · Dependency" : "")
                    + (package.kind == .cask ? " · May require password" : ""),
                prereleaseChannel: package.prereleaseChannel,
                prereleaseIsInstalled: package.prereleaseIsInstalled,
                cveItem: CVEInventoryItem(package)
            )
        } accessories: {
            if store.isRefreshing(package) {
                RefreshingIndicator(itemName: package.displayName)
            }
            VersionTransitionView(current: package.installedVersion, latest: package.currentVersion)
            Button { Task { await store.updatePackage(package) } } label: {
                WorkingActionLabel(
                    isWorking: store.isWorking(.homebrewPackage(package.id)),
                    idleTitle: "Update",
                    phase: store.updatePhase(for: .homebrewPackage(package.id))
                )
            }
                .listRowPrimaryAction()
                .disabled(store.isWorking(.homebrewPackage(package.id)))
        }
        .tag(UpdateInspectorSelection.homebrew(package.id).listID)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Update") { Task { await store.updatePackage(package) } }
                .disabled(store.isWorking(.homebrewPackage(package.id)))
            Button("Refresh") { Task { await store.refresh(package) } }
                .disabled(store.isRefreshing(package))
            Divider()
            exclusionOptions(
                skipTitle: "Skip Version \(package.currentVersion)",
                skip: { store.skip(package) }, ignore: { store.ignore(package) },
                skipFor: { store.skip(package, duration: $0) },
                ignoreFor: { store.ignore(package, duration: $0) }
            )
        }
    }
}

private struct LocalModelUpdateCard: View {
    @UpkeepStoreReference private var store
    let model: LocalLLMModel

    var body: some View {
        StandardItemRow(isSelected: store.updateInspectorSelection == .model(model.id)) {
            LocalModelRuntimeIcon(runtime: model.runtime, size: 36)
        } content: {
            LocalModelIdentityView(model: model)
        } accessories: {
            VersionTransitionView(current: model.installedRevision, latest: model.latestRevision)
            Button { Task { await store.updateLocalModel(model) } } label: {
                WorkingActionLabel(
                    isWorking: store.isWorking(.localModel(model.id)),
                    idleTitle: "Update",
                    phase: store.updatePhase(for: .localModel(model.id))
                )
            }
                .listRowPrimaryAction()
                .disabled(store.isWorking(.localModel(model.id)))
        }
        .tag(UpdateInspectorSelection.model(model.id).listID)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Update") { Task { await store.updateLocalModel(model) } }
                .disabled(store.isWorking(.localModel(model.id)))
            Divider()
            exclusionOptions(
                skipTitle: "Skip This Revision",
                skip: { store.skip(model) }, ignore: { store.ignore(model) },
                skipFor: { store.skip(model, duration: $0) },
                ignoreFor: { store.ignore(model, duration: $0) }
            )
        }
    }
}

@MainActor
private func exclusionOptions(
    skipTitle: String,
    skip: @escaping () -> Void,
    ignore: @escaping () -> Void,
    skipFor: @escaping (UpdateExclusionDuration) -> Void,
    ignoreFor: @escaping (UpdateExclusionDuration) -> Void
) -> some View {
    UpdateExclusionOptions(
        skipTitle: skipTitle,
        ignoreTitle: "Ignore Indefinitely",
        skip: skip,
        ignore: ignore,
        skipFor: skipFor,
        ignoreFor: ignoreFor
    )
}
