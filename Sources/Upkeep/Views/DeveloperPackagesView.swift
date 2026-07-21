import AppKit
import SwiftUI

struct DeveloperPackagesView: View {
    @EnvironmentObject private var store: UpkeepStore

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(
                title: "Developer Packages",
                subtitle: "\(store.developerPackages.count) installed · \(store.outdatedDeveloperPackageCount) updates",
                systemImage: "chevron.left.forwardslash.chevron.right"
            )
            HStack {
                Picker("Manager", selection: $store.developerManagerFilter) {
                    Text("All").tag("all")
                    ForEach(store.installedDeveloperManagers) { manager in
                        Text(manager.rawValue).tag(manager.rawValue)
                    }
                }
                .pickerStyle(.segmented).frame(maxWidth: 560)
                Spacer()
                Menu {
                    Button("Check All Managers") { Task { await store.scanDeveloperPackages(manager: nil) } }
                    Divider()
                    ForEach(store.installedDeveloperManagers) { manager in
                        Button("Check \(manager.rawValue)") { Task { await store.scanDeveloperPackages(manager: manager) } }
                    }
                } label: { Label("Check Manager", systemImage: "arrow.clockwise") }
                Button(refreshTitle) { Task { await store.scanDeveloperPackages(manager: selectedManagerFilter) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.workingIDs.contains(refreshIdentifier))
            }
            .padding(.horizontal, 20).padding(.bottom, 10)

            if store.filteredDeveloperPackages.isEmpty {
                ContentUnavailableView(
                    "No packages found", systemImage: "checkmark.seal.fill",
                    description: Text("Installed package managers are checked automatically.")
                ).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    packageList.frame(minWidth: 390, idealWidth: 500)
                    DeveloperPackageDetail(package: selectedPackage).frame(minWidth: 310)
                }
            }
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

    private var selectedPackage: DeveloperPackage? {
        guard let id = store.selectedDeveloperPackageID else { return nil }
        return store.developerPackages.first { $0.id == id }
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

    private var selectedManagerFilter: DeveloperPackageManager? {
        store.installedDeveloperManagers.first { $0.rawValue == store.developerManagerFilter }
    }

    private var refreshTitle: String { selectedManagerFilter.map { "Check \($0.rawValue)" } ?? "Check All" }
    private var refreshIdentifier: String { "developer-scan-\(selectedManagerFilter?.rawValue ?? "all")" }
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
            ItemIdentityView(title: package.name, detail: rowDetail)
        } accessories: {
            packageVersions
            if package.isOutdated && !store.isExcluded(package) {
                Button("Update") { Task { await store.updateDeveloperPackage(package) } }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(store.workingIDs.contains(package.id))
                    .frame(width: 120)
            } else {
                Color.clear.frame(width: 120, height: 1).accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            if let exclusion = store.exclusion(for: package) {
                Button("Restore Updates") { store.restore(exclusion) }
            } else {
                if package.isOutdated { Button("Skip Version \(package.latestVersion)") { store.skip(package) } }
                Button("Ignore \(package.name)") { store.ignore(package) }
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
                    }
                    Spacer()
                    Menu {
                        if let exclusion = store.exclusion(for: package) {
                            Button("Restore Updates") { store.restore(exclusion) }
                        } else {
                            if package.isOutdated { Button("Skip Version \(package.latestVersion)") { store.skip(package) } }
                            Button("Ignore \(package.name)") { store.ignore(package) }
                        }
                    } label: { Image(systemName: "ellipsis.circle").font(.title2) }.menuStyle(.borderlessButton)
                }

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
                                Text(version == package.latestVersion ? "\(version) — Latest" : version).tag(version)
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
            }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: package.id + String(store.settings.includePrereleaseVersions)) {
            await store.loadAvailableVersions(for: package, force: store.settings.includePrereleaseVersions)
        }
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
