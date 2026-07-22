import AppKit
import SwiftUI

struct AdoptableView: View {
    @EnvironmentObject private var store: UpkeepStore

    var body: some View {
        VStack(spacing: 0) {
            if store.filteredAdoptableApps.isEmpty {
                ContentUnavailableView(
                    "No adoptable apps",
                    systemImage: "shippingbox",
                    description: Text("Upkeep matches installed apps with Homebrew’s official cask catalog.")
                ).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: selectedAppID) {
                    ForEach(sortedAdoptableApps) { item in
                    StandardItemRow {
                        AppIcon(url: item.app.url, size: 36)
                    } content: {
                        ItemIdentityView(
                            title: item.app.name,
                            detail: "Homebrew cask · \(item.caskToken)",
                            isRunning: store.isRunning(item.app),
                            prereleaseChannel: item.prereleaseChannel
                        )
                    } accessories: {
                        VersionTransitionView(current: item.app.installedVersion, latest: item.caskVersion)
                        Button {
                            Task { await store.adopt(item) }
                        } label: {
                            if store.workingIDs.contains(item.id) { ProgressView().controlSize(.small) }
                            else { Text("Adopt") }
                        }
                        .listRowPrimaryAction()
                        .disabled(store.workingIDs.contains(item.id))
                    }
                    .tag(item.app.id)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("View Details") { store.selectedApp = item.app }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.app.url]) }
                    }
                    }
                }.listStyle(.inset)
            }
        }
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
                    store.filteredAdoptableApps.first { $0.app.id == id }?.app
                }
            }
        )
    }

    private var sortedAdoptableApps: [AdoptableApp] {
        store.filteredAdoptableApps.sorted { left, right in
            let leftHasUpdate = store.updates.contains { $0.app.id == left.app.id }
            let rightHasUpdate = store.updates.contains { $0.app.id == right.app.id }
            if leftHasUpdate != rightHasUpdate { return leftHasUpdate }
            return left.app.name.localizedStandardCompare(right.app.name) == .orderedAscending
        }
    }
}
