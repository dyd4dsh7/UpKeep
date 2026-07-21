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
            .padding(.horizontal, 20).padding(.bottom, 12)

            if availableUpdates.isEmpty && installers.isEmpty {
                ContentUnavailableView(
                    "Your Mac is up to date",
                    systemImage: "checkmark.seal.fill",
                    description: Text("Enable a beta channel with Beta Updates if you want prerelease builds.")
                ).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !availableUpdates.isEmpty {
                        Section("Available Updates") {
                            ForEach(availableUpdates) { update in systemRow(update) }
                        }
                    }
                    if !installers.isEmpty {
                        Section {
                            ForEach(installers) { update in systemRow(update) }
                        } header: {
                            Text("Full macOS Installers")
                        } footer: {
                            Text("Installers offered by Apple for clean installs, upgrades, and recovery media.")
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var availableUpdates: [MacOSUpdate] { store.macOSUpdates.filter { !$0.isFullInstaller } }
    private var installers: [MacOSUpdate] { store.macOSUpdates.filter(\.isFullInstaller) }

    private func systemRow(_ update: MacOSUpdate) -> some View {
        StandardItemRow {
            Image(systemName: update.isFullInstaller ? "internaldrive" : "apple.logo")
                .font(.title2).foregroundStyle(update.isBeta ? .purple : .blue)
        } content: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(update.title).fontWeight(.semibold).lineLimit(1)
                    if update.isBeta { Text("BETA").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2).background(.purple.opacity(0.12), in: Capsule()).foregroundStyle(.purple) }
                }
                Text((update.isFullInstaller ? "Full installer" : "System update") + (update.size.map { " · \($0)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } accessories: {
            Text(update.version)
                .font(.caption.monospacedDigit()).fontWeight(.semibold)
                .frame(width: 128, alignment: .trailing)
            Button(update.isFullInstaller ? "View in Software Update" : "Prepare Update") {
                Task { await store.prepareMacOSUpdate(update) }
            }.buttonStyle(.bordered).controlSize(.small)
        }
    }
}
