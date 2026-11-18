import SwiftUI

struct UpkeepSidebarView: View {
    @UpkeepStoreReference private var store
    @EnvironmentObject private var settings: AppSettings

    @Environment(\.colorScheme) private var scheme

    @AppStorage("sidebarSourcesExpanded") private var sourcesExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            brand
            destinations
            footer
        }
        .accentColor(UpkeepPalette.accent(in: scheme))
        .tint(UpkeepPalette.accent(in: scheme))
    }

    private var destinations: some View {
        List(selection: $store.navigation.selection) {
            Section {
                item(.updates)
            } header: {
                WorkspaceSectionLabel(title: "Overview")
            }

            Section {
                item(.allApps)
                if settings.sidebarViewMode == .advanced, settings.checkHomebrew {
                    item(.adoptable)
                }
            } header: {
                WorkspaceSectionLabel(title: "Library")
            }

            if !packageDestinations.isEmpty {
                Section {
                    ForEach(packageDestinations, id: \.self) { item($0) }
                } header: {
                    WorkspaceSectionLabel(title: "Packages")
                }
            }

            Section {
                if settings.checkMacOS { item(.macOSUpdates) }
                item(.cveChecker)
                item(.history)
            } header: {
                WorkspaceSectionLabel(title: "System")
            }

            if settings.sidebarViewMode == .advanced, !sourceDestinations.isEmpty {
                Section("Sources", isExpanded: $sourcesExpanded) {
                    ForEach(sourceDestinations, id: \.self) { item($0) }
                }
            }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, settings.listDensity == .compact ? 24 : 30)
        .upkeepAnimated(for: sidebarPresentationKey)
        .onChange(of: sidebarPresentationKey, initial: true) { _, _ in
            let selection = store.navigation.selection
            let packagePages: Set<SidebarDestination> = [.homebrewPackages, .developerPackages, .localModels]
            if (packagePages.contains(selection) && !packageDestinations.contains(selection))
                || (selection == .macOSUpdates && !settings.checkMacOS)
                || (selection == .adoptable && (!settings.checkHomebrew || settings.sidebarViewMode == .basic)) {
                store.navigation.selection = .allApps
            }
        }
    }

    private var brand: some View {
        HStack(spacing: 9) {
            AppBrandIcon(size: 30)
                .accessibilityHidden(true)
            Text("UpKeep")
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.6)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 9)
        .padding(.bottom, 13)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
                    .frame(width: 15)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.callout.weight(.medium))
                    if let checked = store.lastChecked {
                        Text("Last checked \(checked, format: .dateTime.month(.abbreviated).day().hour().minute())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            .controlSize(.regular)
        }
        .padding(.horizontal, 15)
        .padding(.bottom, 13)
    }

    private var statusTitle: String {
        switch store.updateCheckState {
        case .complete: "Sources checked"
        case .checking: "Checking sources…"
        case .partial: "Check incomplete"
        case .failed: "Check failed"
        case .disabled: "Checks disabled"
        case .notChecked: "Awaiting first check"
        }
    }

    private var statusSymbol: String {
        switch store.updateCheckState {
        case .complete: "checkmark.circle.fill"
        case .notChecked: "circle.dashed"
        default: store.updateCheckState.symbol
        }
    }

    private var statusColor: Color {
        switch store.updateCheckState {
        case .complete, .checking: UpkeepPalette.accent(in: scheme)
        case .partial, .failed: UpkeepColors.warning(in: scheme)
        case .notChecked, .disabled: .secondary
        }
    }

    private var sourceDestinations: [SidebarDestination] {
        let destinations: [SidebarDestination] = [
            .appStore, .testFlight, .setapp, .microsoftAutoUpdate, .steam,
            .otherUpdaters, .homebrewApps, .sparkle, .github, .noSource
        ]
        // Keep the selected destination visible while a scan replaces its inventory.
        return destinations.filter { store.count(for: $0) > 0 || store.navigation.selection == $0 }
    }

    private var packageDestinations: [SidebarDestination] {
        var destinations: [SidebarDestination] = []
        if settings.checkHomebrew { destinations.append(.homebrewPackages) }
        if settings.sidebarViewMode == .advanced {
            if store.showsDeveloperInventory {
                destinations.append(.developerPackages)
            }
            if settings.checkLocalModels, !store.localModels.isEmpty {
                destinations.append(.localModels)
            }
        }
        return destinations
    }

    private func item(_ destination: SidebarDestination) -> some View {
        let count = store.count(for: destination)
        return Label {
            Text(destination.rawValue)
                .lineLimit(1)
        } icon: {
            Image(systemName: destination.systemImage)
                .symbolRenderingMode(.monochrome)
                .frame(width: 18)
        }
        .badge(count)
        .tag(destination)
        .help(destination.rawValue)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(destination.rawValue)
        .accessibilityValue(count > 0 ? "\(count) items" : "No items")
    }

    private var sidebarPresentationKey: String {
        [
            settings.sidebarViewMode.rawValue,
            settings.listDensity.rawValue,
            settings.checkHomebrew.description,
            settings.checkMacOS.description,
            settings.checkLocalModels.description,
            settings.enabledDeveloperManagers.map(\.rawValue).sorted().joined(separator: ","),
            store.installedDeveloperManagers.map(\.rawValue).sorted().joined(separator: ","),
            store.localModels.isEmpty.description
        ].joined(separator: "|")
    }
}
