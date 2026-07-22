import SwiftUI

struct MacOSUpdatesView: View {
    @EnvironmentObject private var store: UpkeepStore

    var body: some View {
        VStack(spacing: 0) {
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
        .toolbar {
            ToolbarItemGroup(placement: .secondaryAction) {
                Button("Beta Updates…") { store.openBetaSettings() }
                    .help("Choose a beta channel in Apple’s Software Update settings")
                Button { Task { await store.scan() } } label: {
                    Label("Check Again", systemImage: "arrow.clockwise")
                }
                .help("Check Apple Software Update")
                .disabled(store.isScanning)
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
            ItemIdentityView(
                title: update.title,
                detail: (update.isFullInstaller ? "Full installer" : "System update") + (update.size.map { " · \($0)" } ?? ""),
                prereleaseChannel: update.prereleaseChannel
            )
        } accessories: {
            ItemStatusView(
                title: update.isFullInstaller ? "Installer" : "Available",
                systemImage: update.isFullInstaller ? "internaldrive" : "arrow.down.circle.fill",
                color: update.isBeta ? .purple : .accentColor
            )
            InstalledVersionView(version: update.version)
            Button(update.isFullInstaller ? "View in Software Update" : "Prepare Update") {
                Task { await store.prepareMacOSUpdate(update) }
            }.buttonStyle(.bordered).controlSize(.small).frame(width: 150)
        }
    }
}
