import AppKit
import SwiftUI

struct UpdatesView: View {
    @EnvironmentObject private var store: UpkeepStore

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(
                title: "Updates",
                subtitle: subtitle,
                systemImage: "arrow.down.circle.fill"
            )

            if !store.scanWarningsHidden && !store.scanWarnings.isEmpty {
                ScanWarningsBanner(warnings: store.scanWarnings) {
                    withAnimation { store.scanWarningsHidden = true }
                }
            }

            if !store.availableBatchUpdateItems.isEmpty {
                batchUpdateBar
            }

            if store.isScanning && store.apps.isEmpty {
                scanningState
            } else if store.filteredUpdates.isEmpty && filteredPackages.isEmpty && systemUpdates.isEmpty && filteredDeveloperPackages.isEmpty && filteredModels.isEmpty {
                emptyState
            } else {
                List(selection: selectedUpdateItemID) {
                    if !store.filteredUpdates.isEmpty {
                        Section("Applications") {
                            ForEach(store.filteredUpdates) { UpdateCard(update: $0) }
                        }
                    }
                    if !filteredPackages.isEmpty {
                        Section("Homebrew Packages") {
                            ForEach(filteredPackages) { HomebrewUpdateCard(package: $0) }
                        }
                    }
                    if !systemUpdates.isEmpty {
                        Section("macOS") {
                            ForEach(systemUpdates) { MacOSUpdateCard(update: $0) }
                        }
                    }
                    if !filteredDeveloperPackages.isEmpty {
                        Section("Developer Packages") {
                            ForEach(filteredDeveloperPackages) { DeveloperUpdateCard(package: $0) }
                        }
                    }
                    if !filteredModels.isEmpty {
                        Section("AI Models") {
                            ForEach(filteredModels) { LocalModelUpdateCard(model: $0) }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $store.isShowingBatchReview) {
            BatchUpdateSheet(items: store.availableBatchUpdateItems)
                .environmentObject(store)
        }
    }

    private var batchUpdateBar: some View {
        HStack(spacing: 12) {
            Label(
                "\(store.availableBatchUpdateItems.count) actionable \(store.availableBatchUpdateItems.count == 1 ? "update" : "updates")",
                systemImage: "checklist"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            Spacer()
            if !systemUpdates.isEmpty {
                Text("macOS updates open separately")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Button("Review Updates…") { store.isShowingBatchReview = true }
                .buttonStyle(.borderedProminent)
                .disabled(store.workingIDs.contains("unified-update-batch"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var selectedUpdateItemID: Binding<String?> {
        Binding(
            get: {
                if let selected = store.selectedApp,
                   store.filteredUpdates.contains(where: { $0.app.id == selected.id }) {
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
                    store.selectedApp = store.filteredUpdates.first { $0.app.id == id }?.app
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

    private var filteredPackages: [HomebrewPackage] {
        store.homebrewPackages.filter {
            $0.isOutdated && !store.isExcluded($0) && (store.searchText.isEmpty || $0.displayName.localizedCaseInsensitiveContains(store.searchText))
        }
    }

    private var systemUpdates: [MacOSUpdate] {
        store.macOSUpdates.filter { !$0.isFullInstaller && (store.searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(store.searchText)) }
    }

    private var filteredDeveloperPackages: [DeveloperPackage] {
        store.developerPackages.filter { $0.isOutdated && !store.isExcluded($0) && (store.searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(store.searchText)) }
    }

    private var filteredModels: [LocalLLMModel] {
        store.visibleOutdatedLocalModels.filter { store.searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(store.searchText) }
    }

    private var subtitle: String {
        if store.isScanning { return "Looking for new versions…" }
        let total = store.totalUpdateCount
        if total == 0, !store.scanWarnings.isEmpty { return "Scan completed with warnings" }
        if total == 0 { return "No updates found" }
        return "\(total) updates available across apps and packages"
    }

    private var scanningState: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Checking your applications")
                .font(.title3.weight(.medium))
            Text("Comparing installed versions with trusted developer sources.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: store.scanWarnings.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
        } description: {
            Text(store.searchText.isEmpty
                 ? (store.scanWarnings.isEmpty
                    ? "Supported update sources reported no newer versions for your apps."
                    : "Some update sources could not be checked. Last-known results were preserved where possible.")
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
        return store.scanWarnings.isEmpty ? "No updates found" : "Scan incomplete"
    }
}

private struct BatchUpdateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: UpkeepStore
    let items: [BatchUpdateItem]

    @StateObject private var state: BatchUpdateSheetState

    init(items: [BatchUpdateItem]) {
        self.items = items
        _state = StateObject(wrappedValue: BatchUpdateSheetState(items: items))
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
        .frame(minWidth: 720, idealWidth: 780, minHeight: 560, idealHeight: 640)
        .interactiveDismissDisabled(state.isRunning)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: state.summary == nil ? "checklist" : resultHeaderIcon)
                .font(.system(size: 28))
                .foregroundStyle(state.summary == nil ? Color.accentColor : resultHeaderColor)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.summary == nil ? "Review Updates" : "Update Results")
                    .font(.title2.bold())
                Text(headerSubtitle).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var reviewView: some View {
        VStack(spacing: 0) {
            HStack {
                Button(state.selectedIDs.count == items.count ? "Deselect All" : "Select All") {
                    state.selectedIDs = state.selectedIDs.count == items.count ? [] : Set(items.map(\.id))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                Spacer()
                Text("\(state.selectedIDs.count) of \(items.count) selected")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            List(items) { item in
                BatchReviewRow(item: item, isSelected: selectionBinding(for: item))
            }
            .listStyle(.inset)

            if items.contains(where: \.opensExternalUpdater) {
                Label(
                    "External update actions open the trusted updater, app, or download page and may require you to finish manually.",
                    systemImage: "arrow.up.right.square"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
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
                }
            }
            .padding(.vertical, 6)
        }
        .listStyle(.inset)
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
            } else if state.summary == nil {
                Text("Updates run one at a time and continue if an individual item fails.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(state.summary == nil ? "Cancel" : "Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(state.isRunning)
            if state.summary == nil {
                Button(batchButtonTitle) {
                    let selected = items.filter { state.selectedIDs.contains($0.id) }
                    state.isRunning = true
                    Task {
                        state.summary = await store.performBatchUpdates(selected)
                        state.isRunning = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(state.selectedIDs.isEmpty || state.isRunning)
            }
        }
        .padding(16)
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

    private var selectedItems: [BatchUpdateItem] { items.filter { state.selectedIDs.contains($0.id) } }
    private var selectedRunningApps: [InstalledApp] {
        selectedItems.compactMap { item in
            switch item {
            case let .application(update): return update.homebrewToken == nil || !store.isRunning(update.app) ? nil : update.app
            case let .homebrew(package):
                guard package.kind == .cask,
                      let app = store.homebrewPackageApp(for: package),
                      store.isRunning(app) else { return nil }
                return app
            case .developer, .model: return nil
            }
        }
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

    init(items: [BatchUpdateItem]) {
        selectedIDs = Set(items.map(\.id))
    }
}

private struct BatchReviewRow: View {
    let item: BatchUpdateItem
    @Binding var isSelected: Bool

    var body: some View {
        Toggle(isOn: $isSelected) {
            HStack(spacing: 12) {
                itemIcon
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).fontWeight(.semibold)
                    Text(item.actionDescription).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VersionTransitionView(current: item.currentVersion, latest: item.availableVersion)
                if item.opensExternalUpdater {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.secondary)
                        .help("Requires completion outside Upkeep")
                }
            }
            .padding(.vertical, 5)
        }
        .toggleStyle(.checkbox)
    }

    @ViewBuilder private var itemIcon: some View {
        switch item {
        case let .application(update): AppIcon(url: update.app.url, size: 34)
        case .homebrew: BundledPackageIcon(name: "homebrew", size: 34)
        case let .developer(package): PackageManagerIcon(manager: package.manager, size: 34)
        case let .model(model): LocalModelRuntimeIcon(runtime: model.runtime, size: 34)
        }
    }
}

private struct ScanWarningsBanner: View {
    let warnings: [ScanWarning]
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    "\(warnings.count) update source \(warnings.count == 1 ? "warning" : "warnings")",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout.weight(.medium))
                .foregroundStyle(.orange)
                Spacer()
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Hide warnings until the next scan")
                    .accessibilityLabel("Hide update source warnings")
            }

            ForEach(warnings.prefix(3)) { warning in
                VStack(alignment: .leading, spacing: 2) {
                    Text(warning.title).font(.caption.weight(.semibold))
                    Text(warning.detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            if warnings.count > 3 {
                Text("And \(warnings.count - 3) more. Refresh after checking the affected sources.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct DeveloperUpdateCard: View {
    @EnvironmentObject private var store: UpkeepStore
    let package: DeveloperPackage
    var body: some View {
        StandardItemRow {
            PackageManagerIcon(manager: package.manager, size: 36)
        } content: {
            ItemIdentityView(
                title: package.name,
                detail: package.manager.rawValue,
                prereleaseChannel: package.prereleaseChannel,
                prereleaseIsInstalled: package.prereleaseIsInstalled
            )
        } accessories: {
            VersionTransitionView(current: package.currentVersion, latest: package.latestVersion)
            Button("Update") { Task { await store.updateDeveloperPackage(package) } }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(store.workingIDs.contains(package.id))
                .frame(width: 120)
            exclusionMenu(
                skipTitle: "Skip Version \(package.latestVersion)",
                ignoreTitle: "Ignore Indefinitely",
                skip: { store.skip(package) },
                ignore: { store.ignore(package) },
                skipFor: { store.skip(package, duration: $0) },
                ignoreFor: { store.ignore(package, duration: $0) }
            )
        }
        .tag(UpdateInspectorSelection.developer(package.id).listID)
        .contentShape(Rectangle())
        .contextMenu {
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
    @EnvironmentObject private var store: UpkeepStore
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
            Button("Open Software Update") { Task { await store.prepareMacOSUpdate(update) } }
                .buttonStyle(.bordered).controlSize(.small)
                .frame(width: 120)
        }
    }
}

struct UpdateCard: View {
    @EnvironmentObject private var store: UpkeepStore
    let update: AvailableUpdate

    var body: some View {
        StandardItemRow {
            AppIcon(url: update.app.url, size: 36)
        } content: {
            ItemIdentityView(
                title: update.app.name,
                detail: update.requiresInAppInstallation
                    ? "\(update.source.rawValue) · Open app to install"
                    : update.source.rawValue,
                isRunning: store.isRunning(update.app),
                prereleaseChannel: update.prereleaseChannel,
                prereleaseIsInstalled: update.prereleaseIsInstalled
            )
        } accessories: {
            VersionTransitionView(current: update.app.installedVersion, latest: update.availableVersion)
            Button {
                Task { await store.performUpdate(update) }
            } label: {
                if store.workingIDs.contains(update.id) { ProgressView().controlSize(.small) }
                else { Text(actionTitle) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(store.workingIDs.contains(update.id))
            .frame(width: 120)
            exclusionMenu(
                skipTitle: "Skip Version \(update.availableVersion)",
                ignoreTitle: "Ignore Indefinitely",
                skip: { store.skip(update) },
                ignore: { store.ignore(update.app) },
                skipFor: { store.skip(update, duration: $0) },
                ignoreFor: { store.ignore(update.app, duration: $0) }
            )
        }
        .tag("app:\(update.app.id)")
        .contentShape(Rectangle())
        .contextMenu {
            exclusionOptions(
                skipTitle: "Skip Version \(update.availableVersion)",
                skip: { store.skip(update) }, ignore: { store.ignore(update.app) },
                skipFor: { store.skip(update, duration: $0) },
                ignoreFor: { store.ignore(update.app, duration: $0) }
            )
        }
    }

    private var actionTitle: String {
        update.actionTitle
    }
}

private struct HomebrewUpdateCard: View {
    @EnvironmentObject private var store: UpkeepStore
    let package: HomebrewPackage

    var body: some View {
        StandardItemRow {
            BundledPackageIcon(name: "homebrew", size: 36)
        } content: {
            ItemIdentityView(
                title: package.displayName,
                detail: package.kind.rawValue + (package.isDependency ? " · Dependency" : ""),
                prereleaseChannel: package.prereleaseChannel,
                prereleaseIsInstalled: package.prereleaseIsInstalled
            )
        } accessories: {
            VersionTransitionView(current: package.installedVersion, latest: package.currentVersion)
            Button("Update") { Task { await store.updatePackage(package) } }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(store.workingIDs.contains(package.id))
                .frame(width: 120)
            exclusionMenu(
                skipTitle: "Skip Version \(package.currentVersion)",
                ignoreTitle: "Ignore Indefinitely",
                skip: { store.skip(package) },
                ignore: { store.ignore(package) },
                skipFor: { store.skip(package, duration: $0) },
                ignoreFor: { store.ignore(package, duration: $0) }
            )
        }
        .tag(UpdateInspectorSelection.homebrew(package.id).listID)
        .contentShape(Rectangle())
        .contextMenu {
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
    @EnvironmentObject private var store: UpkeepStore
    let model: LocalLLMModel

    var body: some View {
        StandardItemRow {
            LocalModelRuntimeIcon(runtime: model.runtime, size: 36)
        } content: {
            ItemIdentityView(
                title: model.name,
                detail: model.variant.map { "\(model.runtime.rawValue) · \($0)" } ?? model.runtime.rawValue,
                prereleaseChannel: model.prereleaseChannel
            )
        } accessories: {
            VersionTransitionView(current: model.installedRevision, latest: model.latestRevision)
            Button("Update") { Task { await store.updateLocalModel(model) } }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(store.workingIDs.contains(model.id))
                .frame(width: 120)
            exclusionMenu(
                skipTitle: "Skip This Revision",
                ignoreTitle: "Ignore Indefinitely",
                skip: { store.skip(model) },
                ignore: { store.ignore(model) },
                skipFor: { store.skip(model, duration: $0) },
                ignoreFor: { store.ignore(model, duration: $0) }
            )
        }
        .tag(UpdateInspectorSelection.model(model.id).listID)
        .contentShape(Rectangle())
        .contextMenu {
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
private func exclusionMenu(
    skipTitle: String,
    ignoreTitle: String,
    skip: @escaping () -> Void,
    ignore: @escaping () -> Void,
    skipFor: @escaping (UpdateExclusionDuration) -> Void,
    ignoreFor: @escaping (UpdateExclusionDuration) -> Void
) -> some View {
    Menu {
        UpdateExclusionOptions(
            skipTitle: skipTitle,
            ignoreTitle: ignoreTitle,
            skip: skip,
            ignore: ignore,
            skipFor: skipFor,
            ignoreFor: ignoreFor
        )
    } label: {
        Image(systemName: "ellipsis.circle")
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("Update options")
    .accessibilityLabel("Update options")
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
