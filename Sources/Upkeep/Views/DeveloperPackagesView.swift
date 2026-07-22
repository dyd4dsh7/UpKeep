import AppKit
import SwiftUI

struct DeveloperPackagesView: View {
    @EnvironmentObject private var store: UpkeepStore

    var body: some View {
        VStack(spacing: 0) {
            if store.filteredDeveloperPackages.isEmpty {
                ContentUnavailableView(
                    "No packages found", systemImage: "checkmark.seal.fill",
                    description: Text("Installed package managers are checked automatically.")
                ).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                packageList
            }
        }
        .toolbar { packageToolbar }
    }

    @ToolbarContentBuilder private var packageToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Manager", selection: $store.developerManagerFilter) {
                Text("All").tag("all")
                ForEach(store.installedDeveloperManagers) { manager in
                    Text(manager.rawValue).tag(manager.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(minWidth: 260, idealWidth: 420, maxWidth: 520)
        }
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Button("Check All Managers") { Task { await store.scanDeveloperPackages(manager: nil) } }
                Divider()
                ForEach(store.installedDeveloperManagers) { manager in
                    Button("Check \(manager.rawValue)") { Task { await store.scanDeveloperPackages(manager: manager) } }
                }
            } label: {
                if isCheckingDeveloperPackages {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Check Packages", systemImage: "arrow.clockwise")
                }
            }
            .help("Check installed package managers")
            .disabled(isCheckingDeveloperPackages)
        }
    }

    private var packageList: some View {
        List(sortedPackages, selection: $store.selectedDeveloperPackageID) { package in
            DeveloperPackageRow(package: package).tag(package.id)
        }
        .listStyle(.inset)
        .onAppear { ensurePackageSelection() }
        .onChange(of: store.filteredDeveloperPackages.map(\.id)) { _, _ in ensurePackageSelection() }
        .onChange(of: store.selectedDeveloperPackageID) { _, identifier in
            if let identifier, let package = store.developerPackages.first(where: { $0.id == identifier }) {
                Task { await store.loadAvailableVersions(for: package) }
            }
        }
    }

    private var sortedPackages: [DeveloperPackage] {
        store.filteredDeveloperPackages.sorted { left, right in
            if left.isOutdated != right.isOutdated { return left.isOutdated }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    private func ensurePackageSelection() {
        guard !store.filteredDeveloperPackages.contains(where: { $0.id == store.selectedDeveloperPackageID }) else { return }
        store.selectedDeveloperPackageID = store.filteredDeveloperPackages.first?.id
    }

    private var isCheckingDeveloperPackages: Bool {
        store.workingIDs.contains { $0.hasPrefix("developer-scan-") }
    }
}

struct PackageManagerIcon: View {
    let manager: DeveloperPackageManager
    var size: CGFloat = 36

    var body: some View {
        BundledPackageIcon(name: manager.assetName, size: size)
            .accessibilityLabel(manager.rawValue)
    }
}

struct BundledPackageIcon: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Group {
            if let url = Bundle.module.url(forResource: name, withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "shippingbox.fill").resizable().scaledToFit().padding(size * 0.2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
    }
}

private struct DeveloperPackageRow: View {
    @EnvironmentObject private var store: UpkeepStore
    let package: DeveloperPackage

    var body: some View {
        StandardItemRow {
            PackageManagerIcon(manager: package.manager)
        } content: {
            ItemIdentityView(
                title: package.name,
                detail: rowDetail,
                prereleaseChannel: package.prereleaseChannel,
                prereleaseIsInstalled: package.prereleaseIsInstalled
            )
        } accessories: {
            if store.isRefreshing(package) {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("Refreshing \(package.name)")
            }
            packageVersions
            if package.isOutdated && !store.isExcluded(package) {
                Button("Update") { Task { await store.updateDeveloperPackage(package) } }
                    .listRowPrimaryAction()
                    .disabled(store.workingIDs.contains(package.id))
            } else {
                Color.clear.frame(width: 108, height: 1).accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Refresh") { Task { await store.refresh(package) } }
                .disabled(store.workingIDs.contains("developer-refresh-\(package.id)"))
            Divider()
            if let exclusion = store.exclusion(for: package) {
                Button("Restore Updates") { store.restore(exclusion) }
            } else {
                if package.isOutdated {
                    Button("Update") { Task { await store.updateDeveloperPackage(package) } }
                    Divider()
                }
                UpdateExclusionOptions(
                    skipTitle: "Skip Version \(package.latestVersion)",
                    ignoreTitle: "Ignore \(package.name) Indefinitely",
                    skip: { store.skip(package) }, ignore: { store.ignore(package) },
                    skipFor: { store.skip(package, duration: $0) },
                    ignoreFor: { store.ignore(package, duration: $0) }
                )
            }
        }
    }

    private var rowDetail: String {
        package.manager.rawValue
    }

    @ViewBuilder private var packageVersions: some View {
        if let exclusion = store.exclusion(for: package) {
            ItemStatusView(
                title: exclusion.mode.rawValue,
                systemImage: exclusion.mode == .ignored ? "eye.slash" : "forward.end",
                color: .orange
            )
            InstalledVersionView(version: package.currentVersion)
        } else if package.isOutdated {
            VersionTransitionView(current: package.currentVersion, latest: package.latestVersion)
        } else {
            InstalledVersionView(version: package.currentVersion)
        }
    }
}

struct DeveloperPackageDetail: View {
    @EnvironmentObject private var store: UpkeepStore
    let package: DeveloperPackage?

    var body: some View {
        if let package {
            DeveloperPackageDetailContent(package: package).id(package.id)
        } else {
            ContentUnavailableView("Select a package", systemImage: "shippingbox")
        }
    }
}

private struct DeveloperPackageDetailContent: View {
    @EnvironmentObject private var store: UpkeepStore
    let package: DeveloperPackage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    PackageManagerIcon(manager: package.manager, size: 58)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(package.name).font(.largeTitle.bold())
                        Text(package.manager.packageLabel).foregroundStyle(.secondary)
                        ItemCheckStatus(
                            isRefreshing: store.isRefreshing(package),
                            lastChecked: store.lastChecked(for: package)
                        )
                    }
                    Spacer()
                }

                if package.isOutdated { updateCard }

                Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 12) {
                    GridRow { label("Installed"); Text(package.currentVersion).monospacedDigit() }
                    GridRow { label("Latest"); Text(package.latestVersion).monospacedDigit().foregroundStyle(package.isOutdated ? .blue : .primary) }
                    GridRow { label("Manager"); Text(package.manager.rawValue) }
                    GridRow { label("Executable"); Text(package.executablePath).lineLimit(2).textSelection(.enabled) }
                    if let homepage = package.manager.homepage { GridRow { label("Registry"); Link(homepage.host() ?? homepage.absoluteString, destination: packageURL ?? homepage) } }
                }
                .padding(18).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Install a Version").font(.title2.bold())
                    Text("Choose a published version from \(package.manager.rawValue). The newest available version is selected automatically.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Picker("Version", selection: $store.selectedDeveloperVersion) {
                            ForEach(store.availableDeveloperVersions, id: \.self) { version in
                                Text(versionMenuLabel(version, package: package)).tag(version)
                            }
                        }
                        .frame(maxWidth: 260)
                        .disabled(store.isLoadingDeveloperVersions)
                        if store.isLoadingDeveloperVersions { ProgressView().controlSize(.small) }
                        Button("Install Version") {
                            Task { await store.installDeveloperPackage(package, version: store.selectedDeveloperVersion) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.selectedDeveloperVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.workingIDs.contains(package.id))
                    }
                }
                PackageSecurityExplanation(manager: package.manager.rawValue)
            }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: package.id + String(store.settings.includePrereleaseUpdates)) {
            await store.loadAvailableVersions(for: package)
        }
    }

    private var updateCard: some View {
        InspectorUpdateStatusCard(subtitle: "Available through \(package.manager.rawValue)") {
            if let exclusion = store.exclusion(for: package) {
                Label(exclusion.mode.rawValue, systemImage: exclusion.mode == .ignored ? "eye.slash" : "forward.end")
                    .foregroundStyle(.orange)
                Button("Restore Updates") { store.restore(exclusion) }.buttonStyle(.borderedProminent)
            } else {
                Button("Update") { Task { await store.updateDeveloperPackage(package) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.workingIDs.contains(package.id))
            }
        } options: {
            Button("Refresh") { Task { await store.refresh(package) } }
                .disabled(store.workingIDs.contains("developer-refresh-\(package.id)"))
            Divider()
            if let exclusion = store.exclusion(for: package) {
                Button("Restore Updates") { store.restore(exclusion) }
            } else {
                UpdateExclusionOptions(
                    skipTitle: "Skip Version \(package.latestVersion)",
                    ignoreTitle: "Ignore \(package.name) Indefinitely",
                    skip: { store.skip(package) }, ignore: { store.ignore(package) },
                    skipFor: { store.skip(package, duration: $0) },
                    ignoreFor: { store.ignore(package, duration: $0) }
                )
            }
        }
    }

    private func versionMenuLabel(_ version: String, package: DeveloperPackage) -> String {
        var labels: [String] = []
        if version == package.latestVersion { labels.append("Latest") }
        if version == package.currentVersion { labels.append("Installed") }
        if let channel = VersionComparator.prereleaseChannel(for: version) {
            labels.append(channel.rawValue)
        }
        return labels.isEmpty ? version : "\(version) — \(labels.joined(separator: " · "))"
    }

    private var packageURL: URL? {
        let encoded = package.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? package.name
        switch package.manager {
        case .npm, .pnpm: return URL(string: "https://www.npmjs.com/package/\(encoded)")
        case .python: return URL(string: "https://pypi.org/project/\(encoded)")
        case .rubyGems: return URL(string: "https://rubygems.org/gems/\(encoded)")
        case .cargo: return URL(string: "https://crates.io/crates/\(encoded)")
        }
    }

    private func label(_ text: String) -> some View { Text(text).foregroundStyle(.secondary) }
}
