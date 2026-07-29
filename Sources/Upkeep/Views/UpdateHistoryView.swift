import SwiftUI

struct UpdateHistoryView: View {
    @EnvironmentObject private var store: UpkeepStore

    var body: some View {
        VStack(spacing: 0) {
            if store.updateHistory.isEmpty {
                ContentUnavailableView(
                    "No update history",
                    systemImage: "clock",
                    description: Text("Upkeep creates a recovery record before supported updates.")
                ).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.updateHistory) { record in
                    StandardItemRow {
                        Image(systemName: icon(for: record.kind)).font(.title3).foregroundStyle(color(for: record.kind))
                    } content: {
                        ItemIdentityView(
                            title: record.name,
                            detail: record.kind.rawValue + " · " + (record.recoveryNote ?? "Updated with Upkeep")
                        )
                    } accessories: {
                        VersionTransitionView(current: record.fromVersion, latest: record.toVersion)
                        Text(record.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary).frame(width: 120, alignment: .trailing)
                        if record.canRevertDirectly {
                            Button { store.pendingRevert = record } label: {
                                WorkingActionLabel(
                                    isWorking: store.isWorking(.historyRestore(record.id)),
                                    idleTitle: "Revert",
                                    workingTitle: "Restoring…"
                                )
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(store.isWorking(.historyRestore(record.id)))
                        } else if record.backupPath != nil {
                            Text("Backup expired").font(.caption).foregroundStyle(.secondary)
                        } else if record.kind == .macOS {
                            Button("Recovery Options") { store.openMacOSRecoveryHelp() }.controlSize(.small)
                        } else {
                            Text("Manual recovery").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.listStyle(.inset)
            }
        }
        .confirmationDialog(
            "Revert \(store.pendingRevert?.name ?? "this app")?",
            isPresented: Binding(get: { store.pendingRevert != nil }, set: { if !$0 { store.pendingRevert = nil } }),
            titleVisibility: .visible
        ) {
            if let record = store.pendingRevert {
                Button("Restore version \(record.fromVersion)", role: .destructive) {
                    store.pendingRevert = nil
                    Task { await store.revert(record) }
                }
            }
            Button("Cancel", role: .cancel) { store.pendingRevert = nil }
        } message: {
            Text("The current app will be moved to Trash and Upkeep’s pre-update backup will be restored.")
        }
    }

    private func icon(for kind: UpdateRecordKind) -> String {
        switch kind { case .app: "app.fill"; case .homebrew: "shippingbox.fill"; case .macOS: "apple.logo"; case .developer: "chevron.left.forwardslash.chevron.right"; case .model: "brain.head.profile.fill" }
    }
    private func color(for kind: UpdateRecordKind) -> Color {
        switch kind { case .app: .blue; case .homebrew: .orange; case .macOS: .primary; case .developer: .purple; case .model: .indigo }
    }
}
