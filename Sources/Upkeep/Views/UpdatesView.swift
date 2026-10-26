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

    var body: some View {
        let snapshot = listSnapshot
        VStack(spacing: 0) {
            if store.isScanning && store.apps.isEmpty {
                scanningState
                    .upkeepStateTransition()
            } else if snapshot.isEmpty {
                emptyState
                    .upkeepStateTransition()
            } else {
                VStack(spacing: 0) {
                    UpdateDecisionHeader(
                        recommendedCount: store.recommendedBatchUpdateItems.count,
                        attentionCount: store.availableBatchUpdateItems.count - store.recommendedBatchUpdateItems.count,
                        isWorking: store.isWorking(.unifiedBatch),
                        review: { store.isShowingBatchReview = true }
                    )
                    Divider()
                    List(selection: selectedUpdateItemID) {
                        if !snapshot.applications.isEmpty {
                            Section("Applications") {
                                ForEach(snapshot.applications) { UpdateCard(update: $0) }
                            }
                        }
                        if !snapshot.homebrewPackages.isEmpty {
                            Section("Homebrew Packages") {
                                ForEach(snapshot.homebrewPackages) { HomebrewUpdateCard(package: $0) }
                            }
                        }
                        if !snapshot.macOSUpdates.isEmpty {
                            Section("macOS") {
                                ForEach(snapshot.macOSUpdates) { MacOSUpdateCard(update: $0) }
                            }
                        }
                        if !snapshot.developerPackages.isEmpty {
                            Section("Developer Packages") {
                                ForEach(snapshot.developerPackages) { DeveloperUpdateCard(package: $0) }
                            }
                        }
                        if !snapshot.models.isEmpty {
                            Section("AI Models") {
                                ForEach(snapshot.models) { LocalModelUpdateCard(model: $0) }
                            }
                        }
                    }
                    .upkeepContentList()
                }
                .upkeepStateTransition()
            }
        }
        .upkeepAnimated(for: store.isScanning && store.apps.isEmpty ? "scanning" : snapshot.isEmpty ? "empty" : "content")
        .upkeepAnimated(for: snapshot.identity)
        .sheet(isPresented: $store.navigation.isShowingBatchReview) {
            BatchUpdateSheet(items: store.availableBatchUpdateItems)
                .environment(\.upkeepStoreReference, store)
        }
        .toolbar { listToolbar }
    }

    @ToolbarContentBuilder private var listToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            updateSortMenu
            updateFilterMenu
        }
        upkeepToolbarSpacer()
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
            ListControlLabel(
                systemImage: "list.bullet",
                isActive: viewState.sortOrder != .recommended
            )
        }
        .menuIndicator(.hidden)
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
            ListControlLabel(
                systemImage: "line.3.horizontal.decrease",
                isActive: viewState.filter != .all
            )
        }
        .menuIndicator(.hidden)
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

    private var selectedUpdateItemID: Binding<String?> {
        Binding(
            get: {
                if let selected = store.selectedApp,
                   appUpdates.contains(where: { $0.app.id == selected.id }) {
                    return "app:\(selected.id)"
                }
                return store.updateInspectorSelection?.listID
            },
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
        return store.filteredUpdates.sorted { compareUpdates($0, $1) }
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
                && (viewState.filter == .homebrew || !$0.isDependency)
                && (store.searchText.isEmpty || $0.displayName.localizedCaseInsensitiveContains(store.searchText))
        }.sorted { comparePackage($0.displayName, $0.installedVersion, $0.currentVersion, "Homebrew", $1.displayName, $1.installedVersion, $1.currentVersion, "Homebrew") }
    }

    private var systemUpdates: [MacOSUpdate] {
        guard viewState.filter == .all || viewState.filter == .macOS else { return [] }
        return store.macOSUpdates.filter { !$0.isFullInstaller && (store.searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(store.searchText)) }
            .sorted { comparePackage($0.title, $0.version, $0.version, "macOS", $1.title, $1.version, $1.version, "macOS") }
    }

    private var filteredDeveloperPackages: [DeveloperPackage] {
        guard viewState.filter == .developer else { return [] }
        return store.developerPackages.filter { $0.isOutdated && !store.isExcluded($0) && (store.searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(store.searchText)) }
            .sorted { comparePackage($0.name, $0.currentVersion, $0.latestVersion, $0.manager.rawValue, $1.name, $1.currentVersion, $1.latestVersion, $1.manager.rawValue) }
    }

    private var filteredModels: [LocalLLMModel] {
        guard viewState.filter == .models else { return [] }
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

    private var scanningState: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Checking for updates…")
                .font(.title3.weight(.medium))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: store.updateCheckState.symbol)
        } description: {
            Text(store.searchText.isEmpty
                 ? (viewState.filter != .all
                    ? "No available updates match the selected category."
                    : store.updateCheckState.detail)
                 : "Try a different search term.")
        } actions: {
            if store.searchText.isEmpty {
                Button("Check Again") { Task { await store.scan() } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        if !store.searchText.isEmpty { return "No matching updates" }
        if store.updateCheckState != .complete { return store.updateCheckState.title }
        if viewState.filter != .all { return "No \(viewState.filter.rawValue)" }
        return "No updates found"
    }
}

struct BatchUpdateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @UpkeepStoreReference private var store
    @EnvironmentObject private var settings: AppSettings
    let items: [BatchUpdateItem]
    let isCVEReview: Bool

    @StateObject private var state: BatchUpdateSheetState

    init(items: [BatchUpdateItem], isCVEReview: Bool = false) {
        self.items = items
        self.isCVEReview = isCVEReview
        let initial = BatchUpdateSheetState(items: items)
        if isCVEReview {
            initial.selectedIDs = Set(items.map(\.id))
            initial.expandedGroups = Set(items.map(\.riskGroup))
        }
        _state = StateObject(wrappedValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let summary = state.summary {
                resultsView(summary)
            } else {
                reviewView
            }
            Divider()
            footer
        }
        .frame(minWidth: 780, idealWidth: 840, minHeight: 560, idealHeight: 620)
        .interactiveDismissDisabled(state.isRunning)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: state.summary == nil ? "checklist" : resultHeaderIcon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(state.summary == nil ? Color.accentColor : resultHeaderColor)
                .frame(width: 44, height: 44)
                .background(
                    (state.summary == nil ? Color.accentColor : resultHeaderColor).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(state.summary == nil ? (isCVEReview ? "Update Affected Software" : "Review Updates") : "Update Results")
                    .font(.title2.bold())
                if state.summary != nil {
                    Text(headerSubtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if state.summary == nil {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(state.selectedIDs.count)")
                        .font(.title2.bold().monospacedDigit())
                    Text("of \(visibleItems.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(20)
    }

    private var reviewView: some View {
        VStack(spacing: 0) {
            if isCVEReview {
                Text("Only affected software with available updates is included. Review version changes below. External updaters still require you to finish there; available updates may not fix every advisory.")
                    .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 14)
            }
            HStack(spacing: 12) {
                Button(state.selectedIDs.isEmpty ? (isCVEReview ? "Select All" : "Select Recommended") : "Deselect All") {
                    state.selectedIDs = state.selectedIDs.isEmpty
                        ? Set(visibleItems.filter { isCVEReview || $0.isRecommendedByDefault }.map(\.id))
                        : []
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 11)

            if selectedItems.contains(where: \.mayRequireAdministratorPassword) {
                Label(
                    "Selected Homebrew casks may open Terminal and request your administrator password.",
                    systemImage: "lock.shield.fill"
                )
                .font(.callout)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }

            List {
                ForEach(visibleRiskGroups) { group in
                    let groupItems = visibleItems.filter { $0.riskGroup == group }
                    if !groupItems.isEmpty {
                        Section {
                            if state.expandedGroups.contains(group) {
                                ForEach(groupItems) { item in
                                    BatchReviewRow(item: item, isSelected: selectionBinding(for: item))
                                }
                            }
                        } header: {
                            BatchGroupHeader(
                                group: group,
                                itemCount: groupItems.count,
                                selectedCount: groupItems.count { state.selectedIDs.contains($0.id) },
                                isExpanded: state.expandedGroups.contains(group)
                            ) {
                                withAnimation(.snappy(duration: 0.18)) {
                                    if state.expandedGroups.contains(group) {
                                        state.expandedGroups.remove(group)
                                    } else {
                                        state.expandedGroups.insert(group)
                                    }
                                }
                            }
                        }
                        .listSectionSeparator(.hidden)
                    }
                }
            }
            .upkeepContentList()

        }
    }

    private func resultsView(_ summary: BatchUpdateSummary) -> some View {
        List(summary.results) { result in
            HStack(spacing: 12) {
                Image(systemName: resultIcon(result.outcome))
                    .foregroundStyle(resultColor(result.outcome))
                    .font(.title3)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(result.item.name).fontWeight(.semibold)
                        Spacer()
                        Text(result.outcome.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(resultColor(result.outcome))
                    }
                    Text(result.detail).font(.caption).foregroundStyle(.secondary)
                    if let warning = result.warning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .upkeepContentList()
    }

    private var footer: some View {
        HStack {
            if state.isRunning, let progress = store.batchUpdateProgress {
                ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
                    .frame(width: 150)
                Text("\(progress.itemName) · \(progress.completed)/\(progress.total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(state.summary == nil ? "Cancel" : "Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(state.isRunning)
            if state.summary == nil {
                Button(batchButtonTitle) {
                    let selected = visibleItems.filter { state.selectedIDs.contains($0.id) }
                    state.isRunning = true
                    Task {
                        state.summary = isCVEReview
                            ? await store.performCVEBatchUpdates(selected)
                            : await store.performBatchUpdates(selected)
                        state.isRunning = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(state.selectedIDs.isEmpty || state.isRunning)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private func selectionBinding(for item: BatchUpdateItem) -> Binding<Bool> {
        Binding(
            get: { state.selectedIDs.contains(item.id) },
            set: { selected in
                if selected { state.selectedIDs.insert(item.id) }
                else { state.selectedIDs.remove(item.id) }
            }
        )
    }

    private var visibleRiskGroups: [UpdateRiskGroup] {
        UpdateRiskGroup.allCases.filter { group in
            isCVEReview || settings.sidebarViewMode == .advanced || ![.prerelease, .dependency, .developer].contains(group)
        }
    }

    private var visibleItems: [BatchUpdateItem] {
        items.filter { visibleRiskGroups.contains($0.riskGroup) }
    }

    private var selectedItems: [BatchUpdateItem] { visibleItems.filter { state.selectedIDs.contains($0.id) } }

    private var selectedRunningApps: [InstalledApp] {
        store.runningAppsForBatch(selectedItems)
    }

    private var batchButtonTitle: String {
        if !selectedRunningApps.isEmpty { return "Quit Apps and Update \(state.selectedIDs.count)" }
        return "Update \(state.selectedIDs.count)"
    }

    private var headerSubtitle: String {
        guard let summary = state.summary else { return "Choose what Upkeep should update, then review each action." }
        var parts = ["\(summary.updatedCount) updated"]
        if summary.openedCount > 0 { parts.append("\(summary.openedCount) need attention") }
        if summary.failedCount > 0 { parts.append("\(summary.failedCount) failed") }
        return parts.joined(separator: " · ")
    }

    private var resultHeaderIcon: String { state.summary?.failedCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill" }
    private var resultHeaderColor: Color { state.summary?.failedCount == 0 ? .green : .orange }
    private func resultIcon(_ outcome: BatchUpdateResult.Outcome) -> String {
        switch outcome { case .updated: "checkmark.circle.fill"; case .opened: "arrow.up.right.circle.fill"; case .failed: "xmark.circle.fill" }
    }
    private func resultColor(_ outcome: BatchUpdateResult.Outcome) -> Color {
        switch outcome { case .updated: .green; case .opened: .blue; case .failed: .red }
    }
}

@MainActor
private final class BatchUpdateSheetState: ObservableObject {
    @Published var selectedIDs: Set<String>
    @Published var summary: BatchUpdateSummary?
    @Published var isRunning = false
    @Published var expandedGroups: Set<UpdateRiskGroup> = [.automatic, .manual]

    init(items: [BatchUpdateItem]) {
        selectedIDs = Set(items.filter(\.isRecommendedByDefault).map(\.id))
    }
}

private struct BatchGroupHeader: View {
    let group: UpdateRiskGroup
    let itemCount: Int
    let selectedCount: Int
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: group.systemImage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(groupColor)
                    .frame(width: 22)
                Text(group.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if selectedCount > 0 {
                    Text("\(selectedCount) selected")
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                }
                Text("\(itemCount)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .accessibilityLabel("\(group.title), \(itemCount) updates")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(group.detail)
    }

    private var groupColor: Color {
        switch group {
        case .automatic: .green
        case .manual: .orange
        case .major: .red
        case .prerelease: .purple
        case .dependency: .blue
        case .developer: .indigo
        }
    }
}

private struct BatchReviewRow: View {
    @UpkeepStoreReference private var store
    let item: BatchUpdateItem
    @Binding var isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Toggle("", isOn: $isSelected)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .fixedSize()
                .accessibilityLabel(item.name)
            itemIcon
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(item.name).fontWeight(.semibold)
                    if isAppRunning {
                        RunningBadge()
                    }
                }
                Text(item.actionDescription).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VersionTransitionView(current: item.currentVersion, latest: displayedVersion)
            if item.opensExternalUpdater {
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
                    .help("Requires completion outside Upkeep")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
        .listRowSeparator(.hidden)
    }

    private var displayedVersion: String {
        if case let .application(update) = item { return update.displayAvailableVersion }
        return item.availableVersion
    }

    private var isAppRunning: Bool {
        switch item {
        case let .application(update):
            store.isRunning(update.app)
        case let .homebrew(package):
            package.kind == .cask && store.homebrewPackageApp(for: package).map { store.isRunning($0) } == true
        case .developer, .model:
            false
        }
    }

    @ViewBuilder private var itemIcon: some View {
        switch item {
        case let .application(update): AppIcon(url: update.app.url, size: 34)
        case .homebrew: PackageSourceIcon(name: "homebrew", size: 34)
        case let .developer(package): PackageManagerIcon(manager: package.manager, size: 34)
        case let .model(model): LocalModelRuntimeIcon(runtime: model.runtime, size: 34)
        }
    }
}

private struct DeveloperUpdateCard: View {
    @UpkeepStoreReference private var store
    let package: DeveloperPackage
    var body: some View {
        StandardItemRow(isSelected: store.updateInspectorSelection == .developer(package.id)) {
            PackageManagerIcon(manager: package.manager, size: 36)
        } content: {
            VStack(alignment: .leading, spacing: 4) {
                ItemIdentityView(
                    title: package.name,
                    detail: [package.manager.rawValue, package.installationContext].compactMap { $0 }.joined(separator: " · "),
                    prereleaseChannel: package.prereleaseChannel,
                    prereleaseIsInstalled: package.prereleaseIsInstalled
                )
                CVEStatusBadge(item: CVEInventoryItem(package))
            }
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
            VStack(alignment: .leading, spacing: 4) {
                ItemIdentityView(
                    title: update.app.name,
                    detail: appUpdateDetail,
                    isRunning: store.isRunning(update.app),
                    prereleaseChannel: update.prereleaseChannel,
                    prereleaseIsInstalled: update.prereleaseIsInstalled,
                    showsIntelWarning: update.app.needsAppleSiliconMigration
                )
                CVEStatusBadge(item: CVEInventoryItem(update.app))
            }
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
            VStack(alignment: .leading, spacing: 4) {
                ItemIdentityView(
                    title: package.displayName,
                    detail: package.kind.rawValue
                        + (package.isRevisionUpdate ? " · Rebuild update" : "")
                        + (package.isDependency ? " · Dependency" : "")
                        + (package.kind == .cask ? " · May require password" : ""),
                    prereleaseChannel: package.prereleaseChannel,
                    prereleaseIsInstalled: package.prereleaseIsInstalled
                )
                CVEStatusBadge(item: CVEInventoryItem(package))
            }
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
