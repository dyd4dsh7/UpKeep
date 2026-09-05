import SwiftUI

struct HomebrewView: View {
    @EnvironmentObject private var store: UpkeepStore
    @EnvironmentObject private var settings: AppSettings
    @State private var cleanupResult: PackageCleanupResult?

    var body: some View {
        let packages = sortedPackages
        PackageCleanupContainer(result: $cleanupResult, contentIdentity: packages.map(\.id)) {
            if HomebrewClient.brewURL == nil {
                ContentUnavailableView("Homebrew not installed", systemImage: "terminal", description: Text("Install Homebrew to manage packages here."))
                    .upkeepStateTransition()
            } else {
                packageList(packages)
                    .upkeepStateTransition()
            }
        }
        .toolbar { packageToolbar }
    }

    @ToolbarContentBuilder private var packageToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            PackageCleanupMenu(
                targets: store.packageCleanupTargets.filter { $0.kind == .homebrew },
                result: $cleanupResult
            )
        }
        upkeepToolbarSpacer()
        ToolbarItemGroup(placement: .primaryAction) {
            homebrewSortMenu
            homebrewFilterMenu
            ListDensityButton()
        }
        upkeepToolbarSpacer()
        ToolbarItem(placement: .primaryAction) {
            ScanToolbarButton()
        }
    }

    private var homebrewSortMenu: some View {
        Menu {
            Section("Sort") {
                homebrewSortButton("Default", order: .recommended)
                homebrewSortButton("Name: A–Z", order: .name)
                homebrewSortButton("Name: Z–A", order: .name, ascending: false)
                homebrewSortButton("Installed Version", order: .installedVersion)
                homebrewSortButton("Available Version", order: .availableVersion)
                homebrewSortButton("Package Type", order: .kind)
            }
        } label: {
            ListControlLabel(
                systemImage: "list.bullet",
                isActive: store.homebrewSortOrder != .recommended
            )
        }
        .menuIndicator(.hidden)
        .toolbarControlLabel("Sort Homebrew packages")
    }

    private var homebrewFilterMenu: some View {
        Menu {
            Section("Filter") {
                ForEach(visibleHomebrewFilters) { filter in
                    Button {
                        store.homebrewFilter = filter
                    } label: {
                        MenuSelectionLabel(title: filter.rawValue, isSelected: store.homebrewFilter == filter)
                    }
                }
            }
        } label: {
            ListControlLabel(
                systemImage: "line.3.horizontal.decrease",
                isActive: store.homebrewFilter != .all
            )
        }
        .menuIndicator(.hidden)
        .toolbarControlLabel("Filter Homebrew packages")
    }

    private func homebrewSortButton(
        _ title: String,
        order: HomebrewSortOrder,
        ascending: Bool = true
    ) -> some View {
        Button {
            store.homebrewSortOrder = order
            store.homebrewSortAscending = ascending
        } label: {
            MenuSelectionLabel(
                title: title,
                isSelected: store.homebrewSortOrder == order &&
                    (order == .recommended || store.homebrewSortAscending == ascending)
            )
        }
    }

    private func packageList(_ packages: [HomebrewPackage]) -> some View {
        List(packages, selection: $store.navigation.selectedPackageID) { package in
            PackageRow(
                store: store,
                package: package,
                isSelected: package.id == store.selectedPackageID,
                isRefreshing: store.isRefreshing(package),
                isUnmapped: store.isUnmapped(package),
                exclusion: store.exclusion(for: package),
                isWorking: store.isWorking(.homebrewPackage(package.id))
            )
            .equatable()
            .tag(package.id)
        }
        .listStyle(.inset)
        .onAppear { normalizeBasicFilter(); ensurePackageSelection(in: packages) }
        .onChange(of: packages.map(\.id)) { _, _ in ensurePackageSelection(in: packages) }
        .onChange(of: settings.sidebarViewMode) { _, _ in
            normalizeBasicFilter()
            ensurePackageSelection(in: packages)
        }
    }

    private var sortedPackages: [HomebrewPackage] {
        visiblePackages.sorted { left, right in
            let comparison: ComparisonResult
            switch store.homebrewSortOrder {
            case .recommended:
                if left.isOutdated != right.isOutdated { return left.isOutdated }
                comparison = left.displayName.localizedStandardCompare(right.displayName)
            case .name:
                comparison = left.displayName.localizedStandardCompare(right.displayName)
            case .installedVersion:
                comparison = VersionComparator.compare(left.installedVersion, right.installedVersion)
            case .availableVersion:
                comparison = VersionComparator.compare(left.currentVersion, right.currentVersion)
            case .kind:
                comparison = left.kind.rawValue.localizedStandardCompare(right.kind.rawValue)
            }
            return store.homebrewSortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    private var visiblePackages: [HomebrewPackage] {
        store.filteredHomebrewPackages.filter {
            settings.sidebarViewMode == .advanced || !$0.isDependency
        }
    }

    private var visibleHomebrewFilters: [HomebrewFilter] {
        HomebrewFilter.allCases.filter {
            settings.sidebarViewMode == .advanced || !$0.requiresAdvancedView
        }
    }

    private func normalizeBasicFilter() {
        if settings.sidebarViewMode == .basic, store.homebrewFilter.requiresAdvancedView {
            store.homebrewFilter = .all
        }
    }

    private func ensurePackageSelection(in packages: [HomebrewPackage]) {
        guard !packages.contains(where: { $0.id == store.selectedPackageID }) else { return }
        store.selectedPackageID = packages.first?.id
    }
}

private struct PackageRow: View, Equatable {
    let store: UpkeepStore
    let package: HomebrewPackage
    let isSelected: Bool
    let isRefreshing: Bool
    let isUnmapped: Bool
    let exclusion: UpdateExclusion?
    let isWorking: Bool

    nonisolated static func == (left: Self, right: Self) -> Bool {
        left.package == right.package
            && left.isSelected == right.isSelected
            && left.isRefreshing == right.isRefreshing
            && left.isUnmapped == right.isUnmapped
            && left.exclusion == right.exclusion
            && left.isWorking == right.isWorking
    }

    var body: some View {
        StandardItemRow(isSelected: isSelected) {
            PackageSourceIcon(name: "homebrew", size: 36)
        } content: {
            ItemIdentityView(
                title: package.displayName,
                detail: rowDetail,
                prereleaseChannel: package.prereleaseChannel,
                prereleaseIsInstalled: package.prereleaseIsInstalled
            )
        } accessories: {
            if isRefreshing {
                RefreshingIndicator(itemName: package.displayName)
            }
            if isUnmapped {
                Image(systemName: "questionmark.diamond.fill")
                    .foregroundStyle(.orange)
                    .help("No matching app bundle was found. This may be a command-line or non-GUI cask.")
                    .accessibilityLabel("Unmapped Homebrew cask")
            }
            UpdateVersionAccessory(
                currentVersion: package.installedVersion,
                availableVersion: package.currentVersion,
                showsUpdate: package.isOutdated,
                exclusion: exclusion
            )
            if package.isOutdated && exclusion == nil {
                Button { Task { await store.updatePackage(package) } } label: {
                    WorkingActionLabel(
                        isWorking: isWorking,
                        idleTitle: "Update",
                        phase: store.updatePhase(for: .homebrewPackage(package.id))
                    )
                }
                    .listRowPrimaryAction()
                    .disabled(isWorking)
            } else {
                Color.clear.frame(width: 108, height: 1).accessibilityHidden(true)
            }
        }
        .contextMenu {
            Button("Refresh") { Task { await store.refresh(package) } }
                .disabled(isRefreshing)
            Divider()
            if let exclusion {
                Button("Restore Updates") { store.restore(exclusion) }
            } else {
                if package.isOutdated {
                    Button("Update") { Task { await store.updatePackage(package) } }
                        .disabled(isWorking)
                    Divider()
                }
                UpdateExclusionOptions(
                    skipTitle: "Skip Version \(package.currentVersion)",
                    ignoreTitle: "Ignore \(package.displayName) Indefinitely",
                    skip: { store.skip(package) }, ignore: { store.ignore(package) },
                    skipFor: { store.skip(package, duration: $0) },
                    ignoreFor: { store.ignore(package, duration: $0) }
                )
            }
        }
    }

    private var rowDetail: String {
        var details = [package.kind.rawValue]
        if package.isDependency { details.append("Dependency") }
        if package.kind == .cask { details.append("May require password") }
        return details.joined(separator: " · ")
    }

}

struct PackageDetail: View {
    @EnvironmentObject private var store: UpkeepStore
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var inspection = AppSecurityInspectionModel()
    let package: HomebrewPackage?

    var body: some View {
        if let package {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(package.displayName).font(.title2.weight(.semibold))
                        Text(package.isOutdated ? "\(package.installedVersion) → \(package.currentVersion)" : package.installedVersion)
                            .font(.title3.monospacedDigit()).foregroundStyle(package.isOutdated ? .blue : .secondary)
                        if let description = package.description { Text(description).foregroundStyle(.secondary) }
                        ItemCheckStatus(
                            isRefreshing: store.isRefreshing(package),
                            lastChecked: store.lastChecked(for: package)
                        )
                    }
                    if package.isOutdated { updateCard(package) }
                    detailCard(package)
                    if settings.sidebarViewMode == .advanced {
                        versionSupport(package)
                    }
                    if settings.sidebarViewMode == .advanced, !package.dependencies.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Dependencies").font(.headline)
                            FlowLayout(spacing: 7) {
                                ForEach(package.dependencies, id: \.self) { Text($0).font(.caption).padding(7).background(.quaternary, in: RoundedRectangle(cornerRadius: 6)) }
                            }
                        }
                    }
                    if store.homebrewPackageApp(for: package) != nil {
                        AppPermissionsSection(report: inspection.report)
                        AppSecuritySection(report: inspection.report)
                    } else {
                        PackageSecurityExplanation(manager: "Homebrew")
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
            .task(id: package.id) {
                if let app = store.homebrewPackageApp(for: package) {
                    await inspection.load(app)
                }
            }
        } else {
            ContentUnavailableView("Select a package", systemImage: "shippingbox")
        }
    }

    private func updateCard(_ package: HomebrewPackage) -> some View {
        let isUpdating = store.isWorking(.homebrewPackage(package.id))
        let phase = store.updatePhase(for: .homebrewPackage(package.id))
        return InspectorUpdateStatusCard(
            title: phase?.title ?? (isUpdating ? "Updating…" : "Update available"),
            subtitle: isUpdating
                ? "Preparing and running Homebrew"
                : (package.kind == .cask
                    ? "May require administrator password in Terminal"
                    : "Available through Homebrew"),
            systemImage: isUpdating ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.down.circle.fill"
        ) {
            if let exclusion = store.exclusion(for: package) {
                Label(exclusion.mode.rawValue, systemImage: exclusion.mode == .ignored ? "eye.slash" : "forward.end")
                    .foregroundStyle(.orange)
                Button("Restore Updates") { store.restore(exclusion) }
                    .buttonStyle(.borderedProminent)
            } else {
                Button { Task { await store.updatePackage(package) } } label: {
                    WorkingActionLabel(isWorking: isUpdating, idleTitle: "Update", phase: phase)
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(isUpdating || phase != nil)
            }
        } options: {
            Button("Refresh") { Task { await store.refresh(package) } }
                .disabled(isUpdating || store.isWorking(.homebrewRefresh(package.id)))
            Divider()
            if let exclusion = store.exclusion(for: package) {
                Button("Restore Updates") { store.restore(exclusion) }
            } else {
                UpdateExclusionOptions(
                    skipTitle: "Skip Version \(package.currentVersion)",
                    ignoreTitle: "Ignore \(package.displayName) Indefinitely",
                    skip: { store.skip(package) }, ignore: { store.ignore(package) },
                    skipFor: { store.skip(package, duration: $0) },
                    ignoreFor: { store.ignore(package, duration: $0) }
                )
            }
        }
    }

    private func detailCard(_ package: HomebrewPackage) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow { label("Token"); Text(package.token).textSelection(.enabled) }
            GridRow { label("Install Type"); Text(package.isDependency ? "\(package.kind.rawValue) · Dependency" : package.kind.rawValue) }
            GridRow { label("Installed"); Text(package.installedVersion).monospacedDigit() }
            GridRow { label("Latest"); Text(package.currentVersion).monospacedDigit() }
            GridRow { label("Update status"); Text(package.isOutdated ? "Update available" : "Current") }
            if let license = package.license { GridRow { label("License"); Text(license) } }
            if let homepage = package.homepage { GridRow { label("Homepage"); Link(homepage.host() ?? homepage.absoluteString, destination: homepage) } }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
                .upkeepOutlinedInspectorCard()
    }

    private func versionSupport(_ package: HomebrewPackage) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Version Selection").font(.headline)
            if package.kind == .formula {
                Text("Homebrew exposes supported older releases as separately named versioned formulae, such as python@3.13. Select that formula from the package list to install or update it.")
            } else {
                Text("Homebrew casks normally expose only the current release, so historical cask installation is unavailable unless the cask itself is versioned.")
            }
        }
        .font(.callout).foregroundStyle(.secondary)
        .padding(16).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private func label(_ text: String) -> some View { Text(text).foregroundStyle(.secondary) }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 500; var x: CGFloat = 0; var y: CGFloat = 0; var line: CGFloat = 0
        for view in subviews { let size = view.sizeThatFits(.unspecified); if x + size.width > width { x = 0; y += line + spacing; line = 0 }; x += size.width + spacing; line = max(line, size.height) }
        return CGSize(width: width, height: y + line)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX; var y = bounds.minY; var line: CGFloat = 0
        for view in subviews { let size = view.sizeThatFits(.unspecified); if x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }; view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size)); x += size.width + spacing; line = max(line, size.height) }
    }
}
