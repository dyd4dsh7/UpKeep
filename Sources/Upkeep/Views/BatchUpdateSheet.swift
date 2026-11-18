import SwiftUI

struct BatchUpdateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
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
            Group {
                if let summary = state.summary {
                    resultsView(summary)
                        .upkeepStateTransition()
                } else {
                    reviewView
                        .disabled(state.isRunning)
                        .upkeepStateTransition()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .upkeepAnimated(for: state.summary != nil, animation: UpkeepMotion.quick)
            footer
        }
        .frame(minWidth: 680, idealWidth: 800, minHeight: 420, idealHeight: 560)
        .upkeepWorkspaceAppearance()
        .interactiveDismissDisabled(state.isRunning)
    }

    private var header: some View {
        HStack(spacing: 16) {
            WorkspaceGlyph(systemImage: headerIcon, size: 44, color: headerColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(headerTitle)
                    .font(.system(size: 25, weight: .semibold))
                    .tracking(-0.6)
                    .accessibilityAddTraits(.isHeader)
                Text(headerSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(headerSubtitle)
            }
            Spacer(minLength: 10)
            headerCount
                .frame(width: 140, alignment: .trailing)
        }
        .padding(20)
    }

    private var headerCount: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if state.isRunning {
                if let progress = store.batchUpdateProgress, progress.total > 0 {
                    Text("\(progress.completed) of \(progress.total)")
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                        .upkeepAnimated(for: progress.completed, animation: UpkeepMotion.quick)
                    ProgressView(value: Double(progress.completed), total: Double(progress.total))
                        .accessibilityLabel("Batch update progress")
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Preparing updates")
                }
            } else if state.summary == nil {
                Text(selectedItems.count, format: .number)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .upkeepAnimated(for: selectedItems.count, animation: UpkeepMotion.quick)
                Text("of \(visibleItems.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var reviewView: some View {
        VStack(spacing: 0) {
            if isCVEReview {
                Text("Available updates may not fix every advisory. Finish any external updates in their source app.")
                    .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 14)
            }
            if !selectedItems.isEmpty || visibleItems.contains(where: { isCVEReview || $0.isRecommendedByDefault }) {
                HStack {
                    Button(selectedItems.isEmpty ? (isCVEReview ? "Select All" : "Select Recommended") : "Deselect All") {
                        state.selectedIDs = selectedItems.isEmpty
                            ? Set(visibleItems.filter { isCVEReview || $0.isRecommendedByDefault }.map(\.id))
                            : []
                    }
                    .buttonStyle(.link)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            if selectedItems.contains(where: \.mayRequireAdministratorPassword) {
                Label(
                    "Selected Homebrew casks may open Terminal and request your administrator password.",
                    systemImage: "lock.shield.fill"
                )
                .font(.callout)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 9)
            }

            ScrollView {
                VStack(spacing: 11) {
                    ForEach(visibleRiskGroups) { group in
                        let groupItems = visibleItems.filter { $0.riskGroup == group }
                        if !groupItems.isEmpty {
                            reviewGroup(group, items: groupItems)
                        }
                    }
                }
                .padding(20)
            }
            .upkeepAnimated(for: state.expandedGroups)
        }
    }

    private func reviewGroup(_ group: UpdateRiskGroup, items: [BatchUpdateItem]) -> some View {
        let expanded = state.expandedGroups.contains(group)
        return VStack(alignment: .leading, spacing: 0) {
            BatchGroupHeader(
                group: group,
                itemCount: items.count,
                selectedCount: items.count { state.selectedIDs.contains($0.id) },
                isExpanded: expanded
            ) {
                if expanded {
                    state.expandedGroups.remove(group)
                } else {
                    state.expandedGroups.insert(group)
                }
            }
            if expanded {
                Text(group.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 10)
                ForEach(items) { item in
                    Divider()
                    BatchReviewRow(item: item, isSelected: selectionBinding(for: item))
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 5)
        .upkeepSurface()
    }

    @ViewBuilder private func resultsView(_ summary: BatchUpdateSummary) -> some View {
        if summary.results.isEmpty {
            WorkspaceEmptyState(
                "No updates ran",
                systemImage: "clock.arrow.circlepath",
                description: Text("Close this review and check the current update list before trying again.")
            )
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    resultGroup(.failed, title: "Couldn’t finish", in: summary)
                    resultGroup(.opened, title: "Finish in source app", in: summary)
                    resultGroup(.updated, title: "Updated", in: summary)
                }
                .padding(20)
            }
        }
    }

    @ViewBuilder private func resultGroup(
        _ outcome: BatchUpdateResult.Outcome,
        title: String,
        in summary: BatchUpdateSummary
    ) -> some View {
        let results = summary.results.filter { $0.outcome == outcome }
        if !results.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: resultIcon(outcome))
                        .foregroundStyle(resultColor(outcome))
                        .accessibilityHidden(true)
                    WorkspaceSectionLabel(title: title, count: results.count)
                }
                .padding(.vertical, 9)
                ForEach(results) { result in
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.item.name).font(.callout.weight(.semibold))
                        Text(result.detail).font(.callout).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if let warning = result.warning {
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(UpkeepColors.warning(in: colorScheme))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 14)
            .upkeepSurface()
        }
    }

    private var footer: some View {
        WorkspaceDialogFooter {
            Spacer()
            if state.summary != nil {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(state.isRunning)
                Button(state.isRunning ? "Updating…" : batchButtonTitle, action: submit)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedItems.isEmpty || state.isRunning)
            }
        }
    }

    private func submit() {
        let selected = selectedItems
        guard !selected.isEmpty, !state.isRunning else { return }
        state.isRunning = true
        Task {
            state.summary = isCVEReview
                ? await store.performCVEBatchUpdates(selected)
                : await store.performBatchUpdates(selected)
            state.isRunning = false
        }
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
        if !selectedRunningApps.isEmpty { return "Quit Apps and Update \(selectedItems.count)" }
        return selectedItems.isEmpty ? "Update Selected" : "Update \(selectedItems.count)"
    }

    private var headerTitle: String {
        if state.summary != nil { return "Update Results" }
        if state.isRunning { return "Updating Software" }
        return isCVEReview ? "Update Affected Software" : "Review Updates"
    }

    private var headerSubtitle: String {
        if let summary = state.summary {
            return WorkspaceSummary.count(summary.results.count, "update reviewed", "updates reviewed")
        }
        if state.isRunning {
            return store.batchUpdateProgress?.itemName ?? "Preparing selected updates…"
        }
        return "Choose which updates to run."
    }

    private var headerIcon: String {
        if let summary = state.summary {
            if summary.results.isEmpty { return "clock.arrow.circlepath" }
            if summary.failedCount > 0 { return resultIcon(.failed) }
            return resultIcon(summary.openedCount > 0 ? .opened : .updated)
        }
        return state.isRunning ? "arrow.triangle.2.circlepath" : "checklist"
    }

    private var headerColor: Color {
        guard let summary = state.summary, !summary.results.isEmpty else { return .accentColor }
        if summary.failedCount > 0 { return UpkeepColors.warning(in: colorScheme) }
        return resultColor(summary.openedCount > 0 ? .opened : .updated)
    }

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
    @Published var expandedGroups: Set<UpdateRiskGroup> = [.automatic, .manual, .major]

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
        .buttonStyle(.borderless)
        .accessibilityLabel("\(group.title), \(WorkspaceSummary.count(itemCount, "update", "updates"))")
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
