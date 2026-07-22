import SwiftUI

struct UpkeepSidebarView: View {
    @EnvironmentObject private var store: UpkeepStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        List(selection: $store.selection) {
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
    }

    private func item(_ destination: SidebarDestination) -> some View {
        Label {
            HStack {
                Text(destination.rawValue)
                Spacer()
                let count = store.count(for: destination)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } icon: {
            Image(systemName: destination.systemImage)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.secondary)
                .frame(width: 18)
        }
        .tag(destination)
    }
}
