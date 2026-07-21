import AppKit
import SwiftUI

struct AdoptableView: View {
    @EnvironmentObject private var store: UpkeepStore

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(
                title: "Adoptable",
                subtitle: "\(store.adoptableApps.count) apps can be managed by Homebrew",
                systemImage: "arrow.down.app.fill"
            )
            if store.filteredAdoptableApps.isEmpty {
                ContentUnavailableView(
                    "No adoptable apps",
                    systemImage: "shippingbox",
                    description: Text("Upkeep matches installed apps with Homebrew’s official cask catalog.")
                ).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.filteredAdoptableApps) { item in
                    StandardItemRow {
                        AppIcon(url: item.app.url, size: 36)
                    } content: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.app.name).fontWeight(.semibold).lineLimit(1)
                            Text("Homebrew cask · \(item.caskToken)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } accessories: {
                        VersionTransitionView(current: item.app.installedVersion, latest: item.caskVersion)
                        Button {
                            Task { await store.adopt(item) }
                        } label: {
                            if store.workingIDs.contains(item.id) { ProgressView().controlSize(.small) }
                            else { Text("Adopt") }
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(store.workingIDs.contains(item.id))
                        Menu {
                            Button("View Details") { store.selectedApp = item.app }
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.app.url]) }
                        } label: { MoreMenuIcon() }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { store.selectedApp = item.app }
                }.listStyle(.inset)
            }
        }
    }
}
