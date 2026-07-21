import SwiftUI

struct UpdateHistoryView: View {
    @EnvironmentObject private var store: UpkeepStore

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(
                title: "Update History",
                subtitle: "Backups and recovery options for updates made through Upkeep",
                systemImage: "clock.arrow.circlepath"
            )
            if store.updateHistory.isEmpty {
                ContentUnavailableView(
                    "No update history",
                    systemImage: "clock",
                    description: Text("Upkeep creates a recovery record before supported updates.")
                ).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.updateHistory) { record in
                    HStack(spacing: 14) {
                        Image(systemName: icon(for: record.kind)).font(.title2).foregroundStyle(color(for: record.kind)).frame(width: 34)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(record.name).fontWeight(.semibold); Text(record.kind.rawValue).font(.caption2.bold()).foregroundStyle(.secondary) }
                            Text("\(record.fromVersion) → \(record.toVersion) · \(record.date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                            if let note = record.recoveryNote { Text(note).font(.caption).foregroundStyle(.tertiary).lineLimit(2) }
                        }
                        Spacer()
                        if record.canRevertDirectly {
                            Button("Revert") { store.pendingRevert = record }.buttonStyle(.borderedProminent)
                        } else if record.kind == .macOS {
                            Button("Recovery Options") { store.openMacOSRecoveryHelp() }
                        } else {
                            Text("Manual recovery").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 7)
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
        switch kind { case .app: "app.fill"; case .homebrew: "shippingbox.fill"; case .macOS: "apple.logo"; case .developer: "chevron.left.forwardslash.chevron.right" }
    }
    private func color(for kind: UpdateRecordKind) -> Color {
        switch kind { case .app: .blue; case .homebrew: .orange; case .macOS: .primary; case .developer: .purple }
    }
}
