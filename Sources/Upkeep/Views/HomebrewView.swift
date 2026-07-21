import SwiftUI

struct HomebrewView: View {
    @EnvironmentObject private var store: UpkeepStore

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(
                title: "Homebrew",
                subtitle: "\(store.homebrewPackages.count) installed packages · \(store.outdatedPackageCount) updates",
                systemImage: "terminal.fill"
            )
            filterBar
            if HomebrewClient.brewURL == nil {
                ContentUnavailableView("Homebrew not installed", systemImage: "terminal", description: Text("Install Homebrew to manage packages here."))
            } else {
                HSplitView {
                    packageList.frame(minWidth: 390, idealWidth: 500)
                    PackageDetail(package: selectedPackage).frame(minWidth: 300)
                }
            }
        }
    }

    private var filterBar: some View {
        HStack {
            Picker("Filter", selection: $store.homebrewFilter) {
                ForEach(HomebrewFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 540)
            Spacer()
            if store.outdatedPackageCount > 0 {
                Button("Update All") { Task { await store.updateAllPackages() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.workingIDs.contains("homebrew-all"))
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 10)
    }

    private var packageList: some View {
        List(store.filteredHomebrewPackages, selection: $store.selectedPackageID) { package in
            PackageRow(package: package).tag(package.id)
        }.listStyle(.inset)
    }

    private var selectedPackage: HomebrewPackage? {
        guard let id = store.selectedPackageID else { return store.filteredHomebrewPackages.first }
        return store.homebrewPackages.first { $0.id == id }
    }
}

private struct PackageRow: View {
    @EnvironmentObject private var store: UpkeepStore
    let package: HomebrewPackage

    var body: some View {
        StandardItemRow {
            BundledPackageIcon(name: "homebrew", size: 36)
        } content: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(package.displayName).fontWeight(.semibold).lineLimit(1)
                    if package.isDependency { badge("DEPENDENCY") }
                    else if package.kind == .cask { badge("CASK") }
                    if let exclusion = store.exclusion(for: package) { badge(exclusion.mode.rawValue.uppercased()) }
                }
                Text(package.description ?? "Homebrew \(package.kind.rawValue.lowercased())")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        } accessories: {
            VersionTransitionView(current: package.installedVersion, latest: package.isOutdated ? package.currentVersion : nil)
            if package.isOutdated && !store.isExcluded(package) {
                Button("Update") { Task { await store.updatePackage(package) } }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(store.workingIDs.contains(package.id))
            }
            if package.isOutdated {
                Menu {
                    if let exclusion = store.exclusion(for: package) {
                        Button("Restore Updates") { store.restore(exclusion) }
                    } else {
                        Button("Skip Version \(package.currentVersion)") { store.skip(package) }
                        Button("Ignore \(package.displayName)") { store.ignore(package) }
                    }
                } label: { MoreMenuIcon() }.menuStyle(.borderlessButton).menuIndicator(.hidden)
            }
        }
        .contextMenu {
            if let exclusion = store.exclusion(for: package) {
                Button("Restore Updates") { store.restore(exclusion) }
            } else {
                if package.isOutdated { Button("Skip Version \(package.currentVersion)") { store.skip(package) } }
                Button("Ignore \(package.displayName)") { store.ignore(package) }
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            .padding(.horizontal, 5).padding(.vertical, 2).background(.quaternary, in: Capsule())
    }
}

private struct PackageDetail: View {
    @EnvironmentObject private var store: UpkeepStore
    let package: HomebrewPackage?

    var body: some View {
        if let package {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(package.displayName).font(.largeTitle.bold())
                        Text(package.isOutdated ? "\(package.installedVersion) → \(package.currentVersion)" : package.installedVersion)
                            .font(.title3.monospacedDigit()).foregroundStyle(package.isOutdated ? .blue : .secondary)
                        if let description = package.description { Text(description).foregroundStyle(.secondary) }
                    }
                    if package.isOutdated {
                        HStack {
                            if let exclusion = store.exclusion(for: package) {
                                Label(exclusion.mode.rawValue, systemImage: exclusion.mode == .ignored ? "eye.slash" : "forward.end").foregroundStyle(.orange)
                                Button("Restore Updates") { store.restore(exclusion) }
                            } else {
                                Button("Update") { Task { await store.updatePackage(package) } }.buttonStyle(.borderedProminent)
                                Menu("More") {
                                    Button("Skip Version \(package.currentVersion)") { store.skip(package) }
                                    Button("Ignore \(package.displayName)") { store.ignore(package) }
                                }
                            }
                        }
                    }
                    detailCard(package)
                    versionSupport(package)
                    if !package.dependencies.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Dependencies").font(.title2.bold())
                            FlowLayout(spacing: 7) {
                                ForEach(package.dependencies, id: \.self) { Text($0).font(.caption).padding(7).background(.quaternary, in: RoundedRectangle(cornerRadius: 6)) }
                            }
                        }
                    }
                }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView("Select a package", systemImage: "shippingbox")
        }
    }

    private func detailCard(_ package: HomebrewPackage) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 35, verticalSpacing: 12) {
            GridRow { label("Install Type"); Text(package.isDependency ? "Dependency" : package.kind.rawValue) }
            GridRow { label("Version"); Text(package.currentVersion).monospacedDigit() }
            if let license = package.license { GridRow { label("License"); Text(license) } }
            if let homepage = package.homepage { GridRow { label("Homepage"); Link(homepage.host() ?? homepage.absoluteString, destination: homepage) } }
        }.padding(18).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
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
