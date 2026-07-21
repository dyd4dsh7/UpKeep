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
                detail: update.source.rawValue,
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
        switch update.source {
        case .homebrew: "Update"
        case .appStore: "Open App Store"
        case .sparkle: "Download"
        case .github: "View Release"
        }
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
