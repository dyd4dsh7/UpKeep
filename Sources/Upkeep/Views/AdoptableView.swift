import AppKit
import SwiftUI

struct AdoptableView: View {
    @UpkeepStoreReference private var store

    var body: some View {
        let adoptableApps = sortedAdoptableApps
        VStack(spacing: 0) {
            if adoptableApps.isEmpty {
                ContentUnavailableView(
                    "No adoptable apps",
                    systemImage: "shippingbox",
                    description: Text("Upkeep matches installed apps with Homebrew’s official cask catalog.")
                ).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .upkeepStateTransition()
            } else {
                List(selection: selectedAppID) {
                    ForEach(adoptableApps) { item in
                    StandardItemRow(isSelected: store.selectedApp?.id == item.app.id) {
                        AppIcon(url: item.app.url, size: 36)
                    } content: {
                        ItemIdentityView(
                            title: item.app.name,
                            detail: "Homebrew cask · \(item.caskToken) · May require password",
                            isRunning: store.isRunning(item.app),
                            prereleaseChannel: item.prereleaseChannel,
                            showsIntelWarning: item.app.needsAppleSiliconMigration
                        )
                    } accessories: {
                        VersionTransitionView(current: item.app.installedVersion, latest: item.caskVersion)
                        Button {
                            Task { await store.adopt(item) }
                        } label: {
                            WorkingActionLabel(
                                isWorking: store.isWorking(.homebrewAdoption(item.id)),
                                idleTitle: "Adopt",
                                workingTitle: "Adopting…",
                                phase: store.updatePhase(for: .homebrewAdoption(item.id))
                            )
                        }
                        .listRowPrimaryAction()
                        .disabled(store.isWorking(.homebrewAdoption(item.id)))
                    }
                    .tag(item.app.id)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("View Details") { store.selectedApp = item.app }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.app.url]) }
                    }
                    }
                }.upkeepContentList()
                    .upkeepStateTransition()
            }
        }
        .upkeepAnimated(for: adoptableApps.map(\.id))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ScanToolbarButton()
            }
        }
    }

    private var selectedAppID: Binding<String?> {
        Binding(
            get: {
                guard let selected = store.selectedApp,
                      store.filteredAdoptableApps.contains(where: { $0.app.id == selected.id }) else { return nil }
                return selected.id
            },
            set: { identifier in
                store.selectedApp = identifier.flatMap { id in
                    store.app(forID: id).flatMap { store.adoptableApp(for: $0) }?.app
                }
            }
        )
    }

    private var sortedAdoptableApps: [AdoptableApp] {
        store.filteredAdoptableApps.sorted { left, right in
            let leftHasUpdate = store.update(for: left.app) != nil
            let rightHasUpdate = store.update(for: right.app) != nil
            if leftHasUpdate != rightHasUpdate { return leftHasUpdate }
            return left.app.name.localizedStandardCompare(right.app.name) == .orderedAscending
        }
    }
}
