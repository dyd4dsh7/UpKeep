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
                    HStack(spacing: 14) {
                        AppIcon(url: item.app.url, size: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.app.name).fontWeight(.medium)
                            Text("\(item.app.installedVersion) · Homebrew cask: \(item.caskToken)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.caskVersion).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Button {
                            Task { await store.adopt(item) }
                        } label: {
                            if store.workingIDs.contains(item.id) { ProgressView().controlSize(.small) }
                            else { Text("Adopt") }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.workingIDs.contains(item.id))
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6).contentShape(Rectangle())
                    .onTapGesture { store.selectedApp = item.app }
                }.listStyle(.inset)
            }
        }
    }
}
