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

            if store.isScanning && store.apps.isEmpty {
                scanningState
            } else if store.filteredUpdates.isEmpty && filteredPackages.isEmpty && systemUpdates.isEmpty && filteredDeveloperPackages.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.filteredUpdates) { update in
                            UpdateCard(update: update)
                        }
                        ForEach(filteredPackages) { package in
                            HomebrewUpdateCard(package: package)
                        }
                        ForEach(systemUpdates) { update in
                            MacOSUpdateCard(update: update)
                        }
                        ForEach(filteredDeveloperPackages) { package in
                            DeveloperUpdateCard(package: package)
                        }
                    }
                    .padding(22)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var filteredPackages: [HomebrewPackage] {
        store.homebrewPackages.filter {
            $0.isOutdated && (store.searchText.isEmpty || $0.displayName.localizedCaseInsensitiveContains(store.searchText))
        }
    }

    private var systemUpdates: [MacOSUpdate] {
        store.macOSUpdates.filter { !$0.isFullInstaller && (store.searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(store.searchText)) }
    }

    private var filteredDeveloperPackages: [DeveloperPackage] {
        store.developerPackages.filter { $0.isOutdated && (store.searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(store.searchText)) }
    }

    private var subtitle: String {
        if store.isScanning { return "Looking for new versions…" }
        let total = store.updates.count + store.outdatedPackageCount + store.macOSUpdates.count(where: { !$0.isFullInstaller }) + store.outdatedDeveloperPackageCount
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
            Label(store.searchText.isEmpty ? "No updates found" : "No matching updates", systemImage: "checkmark.seal.fill")
        } description: {
            Text(store.searchText.isEmpty
                 ? "Supported update sources reported no newer versions for your apps."
                 : "Try a different search term.")
        } actions: {
            if store.searchText.isEmpty {
                Button("Check Again") { Task { await store.scan() } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DeveloperUpdateCard: View {
    @EnvironmentObject private var store: UpkeepStore
    let package: DeveloperPackage
    var body: some View {
        HStack(spacing: 16) {
            PackageManagerIcon(manager: package.manager, size: 52)
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(package.name).font(.headline); Text(package.manager.rawValue).font(.caption2.bold()).foregroundStyle(.purple) }
                Text("Global developer package").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(package.currentVersion) → \(package.latestVersion)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Button("Update") { Task { await store.updateDeveloperPackage(package) } }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .disabled(store.workingIDs.contains(package.id))
        }
        .padding(16).background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)) }
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
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.12))
                Image(systemName: "apple.logo").font(.title2).foregroundStyle(.blue)
            }.frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(update.title).font(.headline); if update.isBeta { Text("BETA").font(.caption2.bold()).foregroundStyle(.purple) } }
                Text("macOS \(update.version)" + (update.requiresRestart ? " · Restart required" : ""))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Software Update") { Task { await store.prepareMacOSUpdate(update) } }
                .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(16).background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)) }
    }
}

struct UpdateCard: View {
    @EnvironmentObject private var store: UpkeepStore
    let update: AvailableUpdate

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            AppIcon(url: update.app.url, size: 52)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(update.app.name)
                        .font(.headline)
                    SourceBadge(source: update.source)
                    Spacer()
                    versionText
                }

                if let notes = update.releaseNotes, !notes.isEmpty {
                    Text(notes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text("A newer version is available from \(update.source.rawValue).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button {
                        Task { await store.performUpdate(update) }
                    } label: {
                        if store.workingIDs.contains(update.id) {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(actionTitle)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(store.workingIDs.contains(update.id))

                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([update.app.url])
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08))
        }
        .contentShape(Rectangle())
        .onTapGesture { store.selectedApp = update.app }
    }

    private var versionText: some View {
        HStack(spacing: 5) {
            Text(update.app.installedVersion).foregroundStyle(.secondary)
            Image(systemName: "arrow.right").foregroundStyle(.tertiary)
            Text(update.availableVersion).fontWeight(.semibold)
        }
        .font(.caption.monospacedDigit())
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
        HStack(spacing: 16) {
            BundledPackageIcon(name: "homebrew", size: 52)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(package.displayName).font(.headline)
                    SourceBadge(source: .homebrew)
                    if package.isDependency { Text("DEPENDENCY").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary) }
                }
                Text(package.description ?? "Homebrew \(package.kind.rawValue.lowercased())")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text("\(package.installedVersion) → \(package.currentVersion)")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Button("Update") { Task { await store.updatePackage(package) } }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .disabled(store.workingIDs.contains(package.id))
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)) }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectedPackageID = package.id
            store.selection = .homebrewPackages
        }
    }
}
