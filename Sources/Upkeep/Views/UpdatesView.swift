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

            if !store.scanWarnings.isEmpty {
                ScanWarningsBanner(warnings: store.scanWarnings)
            }

            if store.isScanning && store.apps.isEmpty {
                scanningState
            } else if store.filteredUpdates.isEmpty && filteredPackages.isEmpty && systemUpdates.isEmpty && filteredDeveloperPackages.isEmpty && filteredModels.isEmpty {
                emptyState
            } else {
                List {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "\(warnings.count) update source \(warnings.count == 1 ? "warning" : "warnings")",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.callout.weight(.medium))
            .foregroundStyle(.orange)

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
            VStack(alignment: .leading, spacing: 3) {
                HStack { Text(package.name).fontWeight(.semibold).lineLimit(1); Text(package.manager.rawValue).font(.caption2.bold()).foregroundStyle(.secondary).lineLimit(1) }
                Text("Global developer package").font(.caption).foregroundStyle(.secondary)
            }
        } accessories: {
            VersionTransitionView(current: package.currentVersion, latest: package.latestVersion)
            Button("Update") { Task { await store.updateDeveloperPackage(package) } }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(store.workingIDs.contains(package.id))
            Menu {
                Button("Skip Version \(package.latestVersion)") { store.skip(package) }
                Button("Ignore \(package.name)") { store.ignore(package) }
            } label: { MoreMenuIcon() }.menuStyle(.borderlessButton).menuIndicator(.hidden)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectedDeveloperPackageID = package.id
            store.selectedDeveloperVersion = package.latestVersion
            store.selection = .developerPackages
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
            VStack(alignment: .leading, spacing: 3) {
                HStack { Text(update.title).fontWeight(.semibold); if update.isBeta { Text("BETA").font(.caption2.bold()).foregroundStyle(.purple) } }
                Text("macOS \(update.version)" + (update.requiresRestart ? " · Restart required" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } accessories: {
            Button("Open Software Update") { Task { await store.prepareMacOSUpdate(update) } }
                .buttonStyle(.bordered).controlSize(.small)
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
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(update.app.name)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    SourceBadge(source: update.source)
                    if store.isRunning(update.app) { RunningBadge() }
                }

                if let notes = update.releaseNotes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("A newer version is available from \(update.source.rawValue).")
                        .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
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
            Menu {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([update.app.url]) }
                Divider()
                Button("Skip Version \(update.availableVersion)") { store.skip(update) }
                Button("Ignore \(update.app.name)") { store.ignore(update.app) }
            } label: { MoreMenuIcon() }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
        }
        .contentShape(Rectangle())
        .onTapGesture { store.selectedApp = update.app }
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
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(package.displayName).fontWeight(.semibold).lineLimit(1)
                    SourceBadge(source: .homebrew)
                    if package.isDependency { Text("DEPENDENCY").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary) }
                }
                Text(package.description ?? "Homebrew \(package.kind.rawValue.lowercased())")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        } accessories: {
            VersionTransitionView(current: package.installedVersion, latest: package.currentVersion)
            Button("Update") { Task { await store.updatePackage(package) } }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(store.workingIDs.contains(package.id))
            Menu {
                Button("Skip Version \(package.currentVersion)") { store.skip(package) }
                Button("Ignore \(package.displayName)") { store.ignore(package) }
            } label: { MoreMenuIcon() }.menuStyle(.borderlessButton).menuIndicator(.hidden)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectedPackageID = package.id
            store.selection = .homebrewPackages
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
            VStack(alignment: .leading, spacing: 3) {
                HStack { Text(model.name).fontWeight(.semibold).lineLimit(1); Text(model.runtime.rawValue).font(.caption2.bold()).foregroundStyle(.secondary).lineLimit(1) }
                Text(model.variant ?? "Local language model").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        } accessories: {
            VersionTransitionView(current: model.installedRevision, latest: model.latestRevision)
            Button("Update") { Task { await store.updateLocalModel(model) } }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(store.workingIDs.contains(model.id))
            Menu {
                Button("Skip This Revision") { store.skip(model) }
                Button("Ignore \(model.name)") { store.ignore(model) }
            } label: { MoreMenuIcon() }.menuStyle(.borderlessButton).menuIndicator(.hidden)
        }
        .contentShape(Rectangle())
        .onTapGesture { store.selectedLocalModelID = model.id; store.selection = .localModels }
    }
}
