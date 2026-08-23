import SwiftUI

struct UpkeepSidebarView: View {
    @EnvironmentObject private var store: UpkeepStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        List(selection: $store.navigation.selection) {
            item(.updates)

            Section("Library") {
                item(.allApps)
                if settings.sidebarViewMode == .advanced {
                    item(.adoptable)
                }
            }

            if settings.sidebarViewMode == .advanced {
                Section("Sources") {
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

            Section("Packages") {
                if settings.checkHomebrew { item(.homebrewPackages) }
                if settings.sidebarViewMode == .advanced,
                   !settings.enabledDeveloperManagers.isEmpty,
                   !store.installedDeveloperManagers.isEmpty {
                    item(.developerPackages)
                }
                if settings.sidebarViewMode == .advanced,
                   settings.checkLocalModels,
                   !store.localModels.isEmpty {
                    item(.localModels)
                }
            }

            Section("System") {
                if settings.checkMacOS { item(.macOSUpdates) }
                item(.history)
            }
        }
        .listStyle(.sidebar)
        .upkeepAnimated(for: sidebarPresentationKey)
    }

    private func item(_ destination: SidebarDestination) -> some View {
        let count = store.count(for: destination)
        return Label {
            HStack {
                Text(destination.rawValue)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
            }
        } icon: {
            Image(systemName: destination.systemImage)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 18)
        }
        .tag(destination)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(destination.rawValue)
        .accessibilityValue(count > 0 ? "\(count) items" : "No items")
    }

    private var sidebarPresentationKey: String {
        [
            settings.sidebarViewMode.rawValue,
            settings.checkHomebrew.description,
            settings.checkMacOS.description,
            settings.checkLocalModels.description,
            settings.enabledDeveloperManagers.map(\.rawValue).sorted().joined(separator: ","),
            store.installedDeveloperManagers.map(\.rawValue).sorted().joined(separator: ","),
            store.localModels.isEmpty.description
        ].joined(separator: "|")
    }
}
