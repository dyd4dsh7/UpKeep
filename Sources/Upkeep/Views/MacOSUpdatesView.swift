import SwiftUI

struct MacOSUpdatesView: View {
    @EnvironmentObject private var store: UpkeepStore

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(
                title: "macOS Updates",
                subtitle: availableUpdates.isEmpty ? "No system updates available" : "\(availableUpdates.count) system updates available",
                systemImage: "apple.logo"
            )
            HStack {
                Label("Stable and beta updates come directly from Apple", systemImage: "checkmark.shield")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Beta Updates…") { store.openBetaSettings() }
                    .help("Choose a beta channel in Apple’s Software Update settings")
                Button("Check Again") { Task { await store.scan() } }.buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 22).padding(.vertical, 12).background(.bar)
            .overlay(alignment: .bottom) { Divider() }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if availableUpdates.isEmpty {
                        ContentUnavailableView(
                            "Your Mac is up to date",
                            systemImage: "checkmark.seal.fill",
                            description: Text("Enable a beta channel with Beta Updates if you want prerelease builds.")
                        ).frame(maxWidth: .infinity).padding(.vertical, 35)
                    } else {
                        sectionTitle("Available Updates")
                        ForEach(availableUpdates) { update in systemRow(update) }
                    }

                    if !installers.isEmpty {
                        sectionTitle("Full macOS Installers")
                        Text("Installers offered by Apple for clean installs, upgrades, and recovery media.")
                            .font(.callout).foregroundStyle(.secondary)
                        ForEach(installers) { update in systemRow(update) }
                    }
                }.padding(22)
            }
        }
    }

    private var availableUpdates: [MacOSUpdate] { store.macOSUpdates.filter { !$0.isFullInstaller } }
    private var installers: [MacOSUpdate] { store.macOSUpdates.filter(\.isFullInstaller) }

    private func sectionTitle(_ title: String) -> some View { Text(title).font(.title2.bold()) }

    private func systemRow(_ update: MacOSUpdate) -> some View {
        HStack(spacing: 15) {
            Image(systemName: update.isFullInstaller ? "internaldrive" : "apple.logo")
                .font(.title2).foregroundStyle(update.isBeta ? .purple : .blue).frame(width: 38)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(update.title).font(.headline)
                    if update.isBeta { Text("BETA").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2).background(.purple.opacity(0.12), in: Capsule()).foregroundStyle(.purple) }
                }
                Text("Version \(update.version)" + (update.size.map { " · \($0)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(update.isFullInstaller ? "View in Software Update" : "Prepare Update") {
                Task { await store.prepareMacOSUpdate(update) }
            }.buttonStyle(.borderedProminent)
        }
        .padding(16).background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)) }
    }
}
