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
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                ForEach(developerFilters, id: \.self) { filter in
                    Button {
                        store.developerManagerFilter = filter
                    } label: {
                        if filter == store.developerManagerFilter {
                            Label(filter.title, systemImage: "checkmark")
                        } else {
                            Text(filter.title)
                        }
                    }
                }
            } label: {
                Label(store.developerManagerFilter.title, systemImage: "line.3.horizontal.decrease.circle")
                    .lineLimit(1)
            }
            .fixedSize()
            .toolbarControlLabel("Filter developer packages")
            Menu {
                Button("Check All Managers") { Task { await store.scanDeveloperPackages(manager: nil) } }
                Divider()
                let javaScriptManagers = store.installedDeveloperManagers.filter(\.belongsToJavaScriptEcosystem)
                if !javaScriptManagers.isEmpty {
                    Button("Check JavaScript") {
                        Task {
                            for manager in javaScriptManagers { await store.scanDeveloperPackages(manager: manager) }
                        }
                    }
                }
                ForEach(store.installedDeveloperManagers.filter { !$0.belongsToJavaScriptEcosystem }) { manager in
                    Button("Check \(manager.rawValue)") { Task { await store.scanDeveloperPackages(manager: manager) } }
                }
            } label: {
                if isCheckingDeveloperPackages {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Check Packages", systemImage: "arrow.clockwise")
                }
            }
            .toolbarControlLabel("Check developer packages")
            .disabled(isCheckingDeveloperPackages)
        }
    }

    private var packageList: some View {
        List(sortedPackages, selection: $store.navigation.selectedDeveloperPackageID) { package in
            DeveloperPackageRow(
                store: store,
                package: package,
                isRefreshing: store.isRefreshing(package),
                exclusion: store.exclusion(for: package),
                isWorking: store.isWorking(.developerPackage(package.id))
            )
            .equatable()
            .tag(package.id)
        }
        .listStyle(.inset)
        .onAppear { ensurePackageSelection() }
        .onChange(of: store.filteredDeveloperPackages.map(\.id)) { _, _ in ensurePackageSelection() }
    }

    private var sortedPackages: [DeveloperPackage] {
        store.filteredDeveloperPackages.sorted { left, right in
            if left.isOutdated != right.isOutdated { return left.isOutdated }
            let nameOrder = left.name.localizedStandardCompare(right.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return (left.installationContext ?? left.executablePath).localizedStandardCompare(right.installationContext ?? right.executablePath) == .orderedAscending
        }
    }

    private func ensurePackageSelection() {
        guard !store.filteredDeveloperPackages.contains(where: { $0.id == store.selectedDeveloperPackageID }) else { return }
        store.selectedDeveloperPackageID = store.filteredDeveloperPackages.first?.id
    }

    private var isCheckingDeveloperPackages: Bool {
        store.isDeveloperScanRunning
    }

    private var developerFilters: [DeveloperManagerFilter] {
        var filters: [DeveloperManagerFilter] = [.all]
        if store.installedDeveloperManagers.contains(where: \.belongsToJavaScriptEcosystem) {
            filters.append(.javaScript)
        }
        filters.append(contentsOf: store.installedDeveloperManagers
            .filter { !$0.belongsToJavaScriptEcosystem }
            .map(DeveloperManagerFilter.manager))
        return filters
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
            if let image = BundledPackageImageCache.shared.image(named: name) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "shippingbox.fill").resizable().scaledToFit().padding(size * 0.2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
    }
}

@MainActor
private final class BundledPackageImageCache {
    static let shared = BundledPackageImageCache()

    private var images: [String: NSImage] = [:]
    private var missingImageNames = Set<String>()

    func image(named name: String) -> NSImage? {
        if let image = images[name] {
            return image
        }
        guard !missingImageNames.contains(name),
              let url = bundledPackageAssetURL(named: name),
              let image = NSImage(contentsOf: url) else {
            missingImageNames.insert(name)
            return nil
        }
        images[name] = image
        return image
    }
}

func bundledPackageAssetURL(named name: String) -> URL? {
    Bundle.module.url(forResource: name, withExtension: "png")
        ?? Bundle.module.url(forResource: name, withExtension: "svg")
}

func openDeveloperPackageFolder(_ package: DeveloperPackage) {
    let folderURL = URL(fileURLWithPath: package.executablePath)
        .deletingLastPathComponent()
        .standardizedFileURL
    NSWorkspace.shared.open(folderURL)
}

private struct DeveloperPackageRow: View, Equatable {
    let store: UpkeepStore
    let package: DeveloperPackage
    let isRefreshing: Bool
    let exclusion: UpdateExclusion?
    let isWorking: Bool

    nonisolated static func == (left: Self, right: Self) -> Bool {
        left.package == right.package
            && left.isRefreshing == right.isRefreshing
            && left.exclusion == right.exclusion
            && left.isWorking == right.isWorking
    }

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
            if isRefreshing {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("Refreshing \(package.name)")
            }
            packageVersions
            if package.isOutdated && exclusion == nil {
                Button { Task { await store.updateDeveloperPackage(package) } } label: {
                    WorkingActionLabel(
                        isWorking: isWorking,
                        idleTitle: package.canUpdateAutomatically ? "Update" : "View Update"
                    )
                }
                    .listRowPrimaryAction()
                    .disabled(isWorking)
            } else {
                Color.clear.frame(width: 108, height: 1).accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Refresh") { Task { await store.refresh(package) } }
                .disabled(isRefreshing)
            Button("Open Folder") { openDeveloperPackageFolder(package) }
            Divider()
            if let exclusion {
                Button("Restore Updates") { store.restore(exclusion) }
            } else {
                if package.isOutdated {
                    Button(package.canUpdateAutomatically ? "Update" : "View Update") { Task { await store.updateDeveloperPackage(package) } }
                        .disabled(isWorking)
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
        [package.manager.rawValue, package.installationContext]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    @ViewBuilder private var packageVersions: some View {
        if let exclusion {
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
            DeveloperPackageDetailContent(package: package)
        } else {
            ContentUnavailableView("Select a package", systemImage: "shippingbox")
        }
    }
}

private struct DeveloperPackageDetailContent: View {
    @EnvironmentObject private var store: UpkeepStore
    @StateObject private var detailState = DeveloperPackageDetailState()
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
                    if let context = package.installationContext { GridRow { label("Installation"); Text(context) } }
                    GridRow { label("Executable"); Text(package.executablePath).lineLimit(2).textSelection(.enabled) }
                    if let homepage = package.manager.homepage { GridRow { label("Registry"); Link(homepage.host() ?? homepage.absoluteString, destination: packageURL ?? homepage) } }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))

                actionGrid

                if package.canUpdateAutomatically { VStack(alignment: .leading, spacing: 10) {
                    Text("Install a Version").font(.title2.bold())
                    Text("The newest version is ready to install. Load published versions to choose an older release.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Picker("Version", selection: Binding(
                            get: { detailState.versionState.selectedVersion },
                            set: { detailState.selectVersion($0) }
                        )) {
                            ForEach(detailState.versionState.availableVersions, id: \.self) { version in
                                Text(versionMenuLabel(version, package: package)).tag(version)
                            }
                        }
                        .frame(maxWidth: 260)
                        .disabled(detailState.versionState.isLoading)
                        if detailState.versionState.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 24)
                                .accessibilityLabel("Loading published versions")
                        } else {
                            Button {
                                Task {
                                    detailState.beginLoadingVersions()
                                    let versions = await store.developerVersions(for: package)
                                    guard detailState.packageID == package.id else { return }
                                    detailState.finishLoadingVersions(versions, for: package)
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("Load all published versions")
                            .accessibilityLabel("Load published versions")
                        }
                        Button {
                            Task { await store.installDeveloperPackage(package, version: detailState.versionState.selectedVersion) }
                        } label: {
                            WorkingActionLabel(
                                isWorking: store.isWorking(.developerPackage(package.id)),
                                idleTitle: "Install Version",
                                workingTitle: "Installing…"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(detailState.versionState.selectedVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isWorking(.developerPackage(package.id)))
                    }
                } }
                PackageSecurityExplanation(manager: package.manager.rawValue)
            }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog(
            "Uninstall \(package.name)?",
            isPresented: $detailState.isConfirmingUninstall,
            titleVisibility: .visible
        ) {
            Button("Uninstall", role: .destructive) {
                Task { await store.uninstallDeveloperPackage(package) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(uninstallConfirmationMessage)
        }
        .onAppear {
            detailState.prepare(for: package)
        }
        .onChange(of: package.id) { _, _ in
            detailState.prepare(for: package)
        }
    }

    private var actionGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], alignment: .leading, spacing: 10) {
            Button { openDeveloperPackageFolder(package) } label: {
                Label("Open Folder", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .help("Open the folder containing the \(package.manager.rawValue) executable")

            if let packageURL {
                Button { NSWorkspace.shared.open(packageURL) } label: {
                    Label("Open Package Page", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if let homepage = package.manager.homepage, homepage != packageURL {
                Button { NSWorkspace.shared.open(homepage) } label: {
                    Label("Manager Website", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if DeveloperPackageUninstallAdapters.supports(package) {
                Button(role: .destructive) { detailState.isConfirmingUninstall = true } label: {
                    WorkingActionLabel(
                        isWorking: store.isWorking(.developerPackage(package.id)),
                        idleTitle: "Uninstall",
                        workingTitle: "Uninstalling…"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(store.isWorking(.developerPackage(package.id)))
            }
        }
        .controlSize(.large)
        .buttonBorderShape(.capsule)
    }

    private var uninstallConfirmationMessage: String {
        switch package.manager {
        case .node, .fnm, .rustup:
            "This removes version \(package.currentVersion) and may also remove tools installed into that runtime. This cannot be undone by Upkeep."
        case .uv where package.registryIdentifier?.hasPrefix("python:") == true:
            "This removes version \(package.currentVersion) and may also remove tools installed into that runtime. This cannot be undone by Upkeep."
        default:
            "This removes \(package.name) \(package.currentVersion) using \(package.manager.rawValue). This cannot be undone by Upkeep."
        }
    }

    private var updateCard: some View {
        let isUpdating = store.isWorking(.developerPackage(package.id))
        return InspectorUpdateStatusCard(
            title: isUpdating ? "Updating…" : "Update available",
            subtitle: isUpdating ? "Running \(package.manager.rawValue)" : "Available through \(package.manager.rawValue)",
            systemImage: isUpdating ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.down.circle.fill"
        ) {
            if let exclusion = store.exclusion(for: package) {
                Label(exclusion.mode.rawValue, systemImage: exclusion.mode == .ignored ? "eye.slash" : "forward.end")
                    .foregroundStyle(.orange)
                Button("Restore Updates") { store.restore(exclusion) }.buttonStyle(.borderedProminent)
            } else {
                Button { Task { await store.updateDeveloperPackage(package) } } label: {
                    WorkingActionLabel(
                        isWorking: isUpdating,
                        idleTitle: package.canUpdateAutomatically ? "Update" : "View Update"
                    )
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(isUpdating)
            }
        } options: {
            Button("Refresh") { Task { await store.refresh(package) } }
                .disabled(isUpdating || store.isWorking(.developerRefresh(package.id)))
            Button("Open Folder") { openDeveloperPackageFolder(package) }
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
        let identifier = package.registryIdentifier ?? package.name
        let encoded = identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? identifier
        switch package.manager {
        case .node: return URL(string: "https://nodejs.org/en/download")
        case .bun: return URL(string: "https://bun.com/docs/installation")
        case .deno: return URL(string: "https://deno.com/runtime")
        case .npm, .pnpm: return URL(string: "https://www.npmjs.com/package/\(encoded)")
        case .yarn: return URL(string: "https://yarnpkg.com")
        case .vsCode: return URL(string: "https://marketplace.visualstudio.com/items?itemName=\(encoded)")
        case .uv, .pipx, .python: return URL(string: "https://pypi.org/project/\(encoded)")
        case .rubyGems: return URL(string: "https://rubygems.org/gems/\(encoded)")
        case .rustup: return URL(string: "https://rustup.rs")
        case .cargo: return URL(string: "https://crates.io/crates/\(encoded)")
        case .githubCLI: return URL(string: "https://github.com/\(identifier)")
        case .go: return URL(string: "https://pkg.go.dev/\(identifier)")
        case .composer: return URL(string: "https://packagist.org/packages/\(identifier)")
        case .dotnet: return URL(string: "https://www.nuget.org/packages/\(encoded)")
        case .macPorts: return URL(string: "https://ports.macports.org/port/\(encoded)")
        case .nix: return URL(string: "https://search.nixos.org/packages")
        case .mise: return URL(string: "https://mise.jdx.dev")
        case .asdf: return URL(string: "https://asdf-vm.com")
        case .volta: return URL(string: "https://volta.sh")
        case .fnm: return URL(string: "https://github.com/Schniz/fnm")
        }
    }

    private func label(_ text: String) -> some View { Text(text).foregroundStyle(.secondary) }
}

@MainActor
private final class DeveloperPackageDetailState: ObservableObject {
    struct VersionState {
        var selectedVersion = ""
        var availableVersions: [String] = []
        var isLoading = false
    }

    @Published var isConfirmingUninstall = false
    @Published private(set) var versionState = VersionState()
    private(set) var packageID: String?

    func prepare(for package: DeveloperPackage) {
        packageID = package.id
        versionState = VersionState(
            selectedVersion: package.latestVersion,
            availableVersions: [package.latestVersion],
            isLoading: false
        )
    }

    func selectVersion(_ version: String) {
        versionState.selectedVersion = version
    }

    func beginLoadingVersions() {
        versionState.isLoading = true
    }

    func finishLoadingVersions(_ versions: [String], for package: DeveloperPackage) {
        versionState = VersionState(
            selectedVersion: versions.contains(package.latestVersion)
                ? package.latestVersion
                : (versions.first ?? package.currentVersion),
            availableVersions: versions,
            isLoading: false
        )
    }
}
