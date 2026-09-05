import SwiftUI

private struct MacOSUpdateGroups {
    let updates: [MacOSUpdate]
    let installers: [MacOSUpdate]

    init(_ items: [MacOSUpdate]) {
        var updates: [MacOSUpdate] = []
        var installers: [MacOSUpdate] = []
        updates.reserveCapacity(items.count)
        installers.reserveCapacity(items.count)
        for item in items {
            if item.isFullInstaller {
                installers.append(item)
            } else {
                updates.append(item)
            }
        }
        self.updates = updates
        self.installers = installers
    }

    var isEmpty: Bool { updates.isEmpty && installers.isEmpty }
    var identity: [String] { (updates + installers).map(\.id) }
}

struct MacOSUpdatesView: View {
    @EnvironmentObject private var store: UpkeepStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        let groups = MacOSUpdateGroups(store.macOSUpdates.filter {
            settings.sidebarViewMode == .advanced || !$0.isFullInstaller
        })
        VStack(spacing: 0) {
            if groups.isEmpty {
                ContentUnavailableView(
                    store.macOSCheckState == .complete ? "Your Mac is up to date" : store.macOSCheckState.title,
                    systemImage: store.macOSCheckState.symbol,
                    description: Text(store.macOSCheckState == .complete
                        ? "Upkeep will show new macOS updates here when Apple makes them available."
                        : store.macOSCheckState.detail)
                ).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .upkeepStateTransition()
            } else {
                List {
                    if !groups.updates.isEmpty {
                        Section("Available Updates") {
                            ForEach(groups.updates) { update in systemRow(update) }
                        }
                    }
                    if settings.sidebarViewMode == .advanced, !groups.installers.isEmpty {
                        Section {
                            ForEach(groups.installers) { update in systemRow(update) }
                        } header: {
                            Text("Full macOS Installers")
                        } footer: {
                            Text("Installers offered by Apple for clean installs, upgrades, and recovery media.")
                        }
                    }
                }
                .upkeepContentList()
                .upkeepStateTransition()
            }
        }
        .upkeepAnimated(for: groups.identity)
        .toolbar {
            if settings.sidebarViewMode == .advanced {
                ToolbarItem(placement: .primaryAction) {
                    Button("Beta Updates…") { store.openBetaSettings() }
                        .toolbarControlLabel("Choose macOS beta updates")
                }
                upkeepToolbarSpacer()
            }
            ToolbarItem(placement: .primaryAction) {
                AsyncToolbarButton(
                    title: "Check for macOS updates",
                    systemImage: "arrow.clockwise",
                    isWorking: store.isScanning,
                    action: store.scan
                )
            }
        }
    }

    private func systemRow(_ update: MacOSUpdate) -> some View {
        StandardItemRow {
            Image(systemName: update.isFullInstaller ? "internaldrive" : "apple.logo")
                .font(.title2).foregroundStyle(update.isBeta ? .purple : .blue)
        } content: {
            ItemIdentityView(
                title: update.title,
                detail: (update.isFullInstaller ? "Full installer" : "System update") + (formattedSize(update.size).map { " · \($0)" } ?? ""),
                prereleaseChannel: update.prereleaseChannel
            )
        } accessories: {
            InstalledVersionView(version: update.version)
            Button {
                Task { await store.prepareMacOSUpdate(update) }
            } label: {
                WorkingActionLabel(
                    isWorking: store.isWorking(.macOSUpdate(update.id)),
                    idleTitle: update.isFullInstaller ? "View in Software Update" : "Prepare Update",
                    workingTitle: "Opening…"
                )
            }
            .listRowPrimaryAction()
            .disabled(store.isWorking(.macOSUpdate(update.id)))
        }
    }

    private func formattedSize(_ value: String?) -> String? {
        guard let value else { return nil }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let units: [(suffix: String, multiplier: Double)] = [
            ("kib", 1_024),
            ("mib", 1_048_576),
            ("gib", 1_073_741_824),
            ("kb", 1_000),
            ("mb", 1_000_000),
            ("gb", 1_000_000_000)
        ]

        for unit in units where trimmed.lowercased().hasSuffix(unit.suffix) {
            let numberText = trimmed.dropLast(unit.suffix.count).trimmingCharacters(in: .whitespaces)
            guard let number = Double(numberText) else { continue }
            return ByteCountFormatter.string(
                fromByteCount: Int64(number * unit.multiplier),
                countStyle: .file
            )
        }

        return trimmed
    }
}
