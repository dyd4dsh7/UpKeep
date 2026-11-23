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
    @UpkeepStoreReference private var store
    @UpkeepState private var kindFilter: UpdateRecordKind?
    @UpkeepState private var selectedRecordID: UUID?
    @UpkeepState private var showingStorage = false

    var body: some View {
        let snapshot = HistorySnapshot(records: store.updateHistory, kind: kindFilter)
        VStack(spacing: 0) {
            if snapshot.records.isEmpty {
                WorkspaceEmptyState(
                    kindFilter == nil ? "No history yet" : "No matching history",
                    systemImage: kindFilter == nil ? "clock" : "line.3.horizontal.decrease.circle",
                    description: Text(kindFilter == nil
                        ? "Updates and uninstalls made with Upkeep appear here, with a way to restore them where possible."
                        : "Choose another type to see its history.")
                ).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .upkeepStateTransition()
            } else {
                historyList(snapshot)
                    .upkeepStateTransition()
            }
        }
        .upkeepAnimated(for: snapshot.records.map(\.id))
        .safeAreaInset(edge: .top, spacing: 0) {
            WorkspaceSummary(title: "Update History",
                detail: "\(WorkspaceSummary.count(snapshot.records.count, "record", "records")) · \(kindFilter?.rawValue ?? "All update types")",
                systemImage: "clock.arrow.circlepath")
        }
        .toolbar {
            ToolbarItem {
                Button("Recovery Storage", systemImage: "externaldrive") {
                    showingStorage = true
                }
            }
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
        .sheet(isPresented: $showingStorage) {
            RecoveryStorageSheet()
        }
        .confirmationDialog(
            "Restore \(store.pendingRevert?.name ?? "this app")?",
            isPresented: Binding(get: { store.pendingRevert != nil }, set: { if !$0 { store.pendingRevert = nil } }),
            titleVisibility: .visible
        ) {
            if let record = store.pendingRevert {
                Button("Restore version \(record.fromVersionLabel)", role: .destructive) {
                    store.pendingRevert = nil
                    Task { await store.revert(record) }
                }
            }
            Button("Cancel", role: .cancel) { store.pendingRevert = nil }
        } message: {
            Text("Upkeep verifies the backup before replacing the current app. If the app is open, Upkeep will ask you to quit it. The replaced copy moves to Trash after the restore succeeds.")
        }
    }

    private var revealedRecordID: UUID? {
        guard case let .history(id) = store.navigation.inventoryReveal else { return nil }
        return id
    }

    private func historyList(_ snapshot: HistorySnapshot) -> some View {
        ScrollViewReader { proxy in
            List(selection: $selectedRecordID) {
                ForEach(snapshot.days) { group in
                    Section(dayTitle(group.day)) {
                        ForEach(group.records) { record in
                            historyRow(record)
                                .tag(record.id)
                                .id(record.id)
                        }
                    }
                }
            }
            .upkeepContentList()
            .onChange(of: revealedRecordID, initial: true) { _, id in
                guard let id, snapshot.records.contains(where: { $0.id == id }) else { return }
                selectedRecordID = id
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func historyRow(_ record: UpdateRecord) -> some View {
        StandardItemRow(isSelected: selectedRecordID == record.id) {
            WorkspaceGlyph(systemImage: record.kind.systemImage, size: 34)
        } content: {
            ItemIdentityView(
                title: record.name,
                detail: [record.kind.rawValue, record.isUninstall ? "Uninstalled" : nil,
                         record.date.formatted(date: .omitted, time: .shortened)]
                    .compactMap { $0 }.joined(separator: " · ")
            )
        } accessories: {
            if record.isUninstall {
                Text(record.fromVersionLabel)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                VersionTransitionView(current: record.fromVersionLabel, latest: record.toVersionLabel)
            }
            recoveryControl(for: record)
        }
        .help(record.recoveryNote ?? (record.isUninstall ? "Uninstalled with Upkeep" : "Updated with Upkeep"))
    }

    @ViewBuilder
    private func recoveryControl(for record: UpdateRecord) -> some View {
        if record.isUninstall {
            uninstallControl(for: record)
        } else if record.canRevertDirectly {
            Button { store.pendingRevert = record } label: {
                WorkingActionLabel(
                    isWorking: store.isWorking(.historyRestore(record.id)),
                    idleTitle: "Restore…",
                    workingTitle: "Restoring…"
                )
            }
            .listRowPrimaryAction()
            .disabled(store.isWorking(.historyRestore(record.id)))
        } else if record.backupPath != nil {
            ItemStatusView(title: "Backup expired", systemImage: "clock.badge.exclamationmark")
        } else if record.kind == .macOS {
            Button("Recovery Options") { store.openMacOSRecoveryHelp() }
                .listRowPrimaryAction()
        } else {
            ItemStatusView(title: "Manual", systemImage: "wrench.and.screwdriver")
        }
    }

    @ViewBuilder
    private func uninstallControl(for record: UpdateRecord) -> some View {
        if record.canPutBack {
            Button { Task { await store.putBack(record) } } label: {
                WorkingActionLabel(
                    isWorking: store.isWorking(.historyRestore(record.id)),
                    idleTitle: "Put Back",
                    workingTitle: "Putting Back…"
                )
            }
            .listRowPrimaryAction()
            .disabled(store.isWorking(.historyRestore(record.id)))
            .help("Move \(record.name) back from the Trash to where it was")
        } else if record.isBackInPlace {
            ItemStatusView(title: "Back in place", systemImage: "checkmark.circle")
        } else if record.trashedItems != nil {
            ItemStatusView(title: "Not in Trash", systemImage: "trash.slash")
        } else {
            ItemStatusView(title: "Uninstalled", systemImage: "trash")
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .long, time: .omitted)
    }
}
