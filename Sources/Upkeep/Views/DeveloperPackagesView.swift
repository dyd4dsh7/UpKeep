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
            }
            .padding(.horizontal, 20).padding(.vertical, 10).background(.bar)
            .overlay(alignment: .bottom) { Divider() }

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
        List(store.filteredDeveloperPackages, selection: $store.selectedDeveloperPackageID) { package in
            DeveloperPackageRow(package: package).tag(package.id)
        }
        .listStyle(.inset)
        .onChange(of: store.selectedDeveloperPackageID) { _, identifier in
            if let identifier, let package = store.developerPackages.first(where: { $0.id == identifier }) {
                store.selectedDeveloperVersion = package.latestVersion
            }
        }
    }

    private var selectedPackage: DeveloperPackage? {
        guard let id = store.selectedDeveloperPackageID else { return store.filteredDeveloperPackages.first }
        return store.developerPackages.first { $0.id == id }
    }
}

struct PackageManagerIcon: View {
    let manager: DeveloperPackageManager
    var size: CGFloat = 32

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
        HStack(spacing: 14) {
            PackageManagerIcon(manager: package.manager)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(package.name).fontWeight(.semibold)
                    Text(package.manager.rawValue).font(.caption2.bold()).foregroundStyle(.secondary)
                }
                if package.isOutdated {
                    Text("\(package.currentVersion) → \(package.latestVersion)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                } else {
                    Label("Current · \(package.currentVersion)", systemImage: "checkmark")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if package.isOutdated {
                Button("Update") { Task { await store.updateDeveloperPackage(package) } }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(store.workingIDs.contains(package.id))
            }
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }.padding(.vertical, 6).contentShape(Rectangle())
    }
}

private struct DeveloperPackageDetail: View {
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
                    Text("This manager supports installing an explicit published version. The package manager will verify that the version exists.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        TextField("Version", text: $store.selectedDeveloperVersion).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                        Button("Install Version") {
                            Task { await store.installDeveloperPackage(package, version: store.selectedDeveloperVersion) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.selectedDeveloperVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.workingIDs.contains(package.id))
                    }
                    if package.currentVersion != package.latestVersion {
                        Button("Use latest (\(package.latestVersion))") { store.selectedDeveloperVersion = package.latestVersion }
                            .buttonStyle(.link)
                    }
                }
            }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
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
