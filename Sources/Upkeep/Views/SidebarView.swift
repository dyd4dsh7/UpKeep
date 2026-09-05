import SwiftUI

struct UpkeepSidebarView: View {
    @EnvironmentObject private var store: UpkeepStore
    @EnvironmentObject private var settings: AppSettings

    @AppStorage("sidebarSourcesExpanded") private var sourcesExpanded = true

    var body: some View {
        List(selection: $store.navigation.selection) {
            item(.updates)

            Section("Library") {
                item(.allApps)
                if settings.sidebarViewMode == .advanced, settings.checkHomebrew {
                    item(.adoptable)
                }
            }

            if !packageDestinations.isEmpty {
                Section("Packages") {
                    ForEach(packageDestinations, id: \.self) { item($0) }
                }
            }

            Section("System") {
                if settings.checkMacOS { item(.macOSUpdates) }
                item(.history)
            }

            if settings.sidebarViewMode == .advanced {
                Section("Sources", isExpanded: $sourcesExpanded) {
                    item(.appStore)
                    item(.testFlight)
                    item(.setapp)
                    item(.microsoftAutoUpdate)
                    item(.steam)
                    item(.otherUpdaters)
                    item(.homebrewApps)
                    item(.sparkle)
                    item(.github)
                    item(.noSource)
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

    private var packageDestinations: [SidebarDestination] {
        var destinations: [SidebarDestination] = []
        if settings.checkHomebrew { destinations.append(.homebrewPackages) }
        if settings.sidebarViewMode == .advanced {
            if store.installedDeveloperManagers.contains(where: settings.enabledDeveloperManagers.contains) {
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
                .symbolRenderingMode(.hierarchical)
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
