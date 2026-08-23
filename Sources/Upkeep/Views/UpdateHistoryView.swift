import SwiftUI

private struct HistoryDay: Identifiable {
    let day: Date
    let records: [UpdateRecord]

    var id: Date { day }
}

private struct HistorySnapshot {
    let records: [UpdateRecord]
    let days: [HistoryDay]
    let availableKinds: [UpdateRecordKind]

    init(records: [UpdateRecord], kind: UpdateRecordKind?, calendar: Calendar = .current) {
        let filtered = kind.map { selected in records.filter { $0.kind == selected } } ?? records
        self.records = filtered
        days = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
            .map { HistoryDay(day: $0.key, records: $0.value) }
            .sorted { $0.day > $1.day }
        availableKinds = Array(Set(records.map(\.kind)))
            .sorted { $0.rawValue.localizedStandardCompare($1.rawValue) == .orderedAscending }
    }
}

struct UpdateHistoryView: View {
    @EnvironmentObject private var store: UpkeepStore
    @State private var kindFilter: UpdateRecordKind?

    var body: some View {
        let snapshot = HistorySnapshot(records: store.updateHistory, kind: kindFilter)
        VStack(spacing: 0) {
            if snapshot.records.isEmpty {
                ContentUnavailableView(
                    kindFilter == nil ? "No update history" : "No matching updates",
                    systemImage: kindFilter == nil ? "clock" : "line.3.horizontal.decrease.circle",
                    description: Text(kindFilter == nil
                        ? "Upkeep creates a recovery record before supported updates."
                        : "Choose another update type to see its history.")
                ).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .upkeepStateTransition()
            } else {
                List {
                    ForEach(snapshot.days) { group in
                        Section(dayTitle(group.day)) {
                            ForEach(group.records) { record in
                                historyRow(record)
                            }
                        }
                    }
                }.listStyle(.inset)
                    .upkeepStateTransition()
            }
        }
        .upkeepAnimated(for: snapshot.records.map(\.id))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        kindFilter = nil
                    } label: {
                        MenuSelectionLabel(title: "All Updates", isSelected: kindFilter == nil)
                    }
                    Divider()
                    ForEach(snapshot.availableKinds, id: \.self) { kind in
                        Button {
                            kindFilter = kind
                        } label: {
                            MenuSelectionLabel(title: kind.rawValue, isSelected: kindFilter == kind)
                        }
                    }
                } label: {
                    ListControlLabel(systemImage: "line.3.horizontal.decrease", isActive: kindFilter != nil)
                }
                .menuIndicator(.hidden)
                .toolbarControlLabel("Filter update history")
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

    @ViewBuilder
    private func historyRow(_ record: UpdateRecord) -> some View {
        StandardItemRow {
            Image(systemName: icon(for: record.kind))
                .font(.title3)
                .foregroundStyle(color(for: record.kind))
        } content: {
            ItemIdentityView(
                title: record.name,
                detail: record.kind.rawValue + " · " + record.date.formatted(date: .omitted, time: .shortened)
            )
        } accessories: {
            VersionTransitionView(current: record.fromVersion, latest: record.toVersion)
            recoveryControl(for: record)
        }
        .help(record.recoveryNote ?? "Updated with Upkeep")
    }

    @ViewBuilder
    private func recoveryControl(for record: UpdateRecord) -> some View {
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
            .frame(width: 128, alignment: .trailing)
            .disabled(store.isWorking(.historyRestore(record.id)))
        } else if record.backupPath != nil {
            ItemStatusView(title: "Backup expired", systemImage: "clock.badge.exclamationmark")
        } else if record.kind == .macOS {
            Button("Recovery Options") { store.openMacOSRecoveryHelp() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(width: 128, alignment: .trailing)
        } else {
            ItemStatusView(title: "Manual", systemImage: "wrench.and.screwdriver")
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .long, time: .omitted)
    }

    private func icon(for kind: UpdateRecordKind) -> String {
        switch kind { case .app: "app.fill"; case .homebrew: "shippingbox.fill"; case .macOS: "apple.logo"; case .developer: "chevron.left.forwardslash.chevron.right"; case .model: "brain.head.profile.fill" }
    }
    private func color(for kind: UpdateRecordKind) -> Color {
        switch kind { case .app: .blue; case .homebrew: .orange; case .macOS: .primary; case .developer: .purple; case .model: .indigo }
    }
}
