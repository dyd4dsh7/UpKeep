import SwiftUI

struct DiagnosticsSettingsView: View {
    @UpkeepStoreReference private var store
    @UpkeepState private var confirmingClear = false

    var body: some View {
        let snapshot = DiagnosticSnapshot(
            entries: store.diagnosticEntries,
            searchText: store.diagnosticsSearchText,
            levelFilter: store.diagnosticsLevelFilter,
            categoryFilter: store.diagnosticsCategoryFilter
        )
        VStack(spacing: 0) {
            summary(snapshot)
            filters(snapshot)
            Divider()
            if snapshot.entries.isEmpty {
                WorkspaceEmptyState(
                    title: store.diagnosticEntries.isEmpty ? "No diagnostics yet" : "No matching entries",
                    systemImage: "stethoscope",
                    description: Text(store.diagnosticEntries.isEmpty
                        ? "Run an update check to record activity here."
                        : "Change your search or filters to see more entries.")
                ) {
                    if hasFilters {
                        Button("Reset Filters", action: resetFilters)
                            .buttonStyle(.bordered)
                    }
                }
            } else {
                List(snapshot.entries) { entry in
                    DiagnosticRow(entry: entry)
                }
                .upkeepContentList()
            }

            WorkspaceDialogFooter {
                Label("Private paths and secrets are redacted", systemImage: "hand.raised")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reload", systemImage: "arrow.clockwise") { store.refreshDiagnostics() }
                Button("Export…", systemImage: "square.and.arrow.up") { store.exportDiagnostics() }
                    .disabled(store.diagnosticEntries.isEmpty)
                Button("Clear…", role: .destructive) { confirmingClear = true }
                    .disabled(store.diagnosticEntries.isEmpty)
            }
        }
        .onAppear { store.refreshDiagnostics() }
        .confirmationDialog("Clear the diagnostics log?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear Log", role: .destructive) { store.clearDiagnostics() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all recorded diagnostic entries from this Mac.")
        }
    }

    private func summary(_ snapshot: DiagnosticSnapshot) -> some View {
        HStack(spacing: 0) {
            metric("Log entries", store.diagnosticEntries.count.formatted())
            Divider().padding(.vertical, 11)
            metric("Scan warnings", snapshot.warningCount.formatted())
            Divider().padding(.vertical, 11)
            metric("Scan errors", snapshot.errorCount.formatted())
            Divider().padding(.vertical, 11)
            metric("Latest scan", snapshot.latestScanDuration)
        }
        .frame(height: 62)
        .upkeepSurface()
        .padding(.horizontal, UpkeepLayout.pageInset)
        .padding(.top, 14)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 13)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private func filters(_ snapshot: DiagnosticSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                TextField("Search diagnostics", text: $store.diagnostics.diagnosticsSearchText)
                    .textFieldStyle(.roundedBorder)
                Picker("Level", selection: $store.diagnostics.diagnosticsLevelFilter) {
                    ForEach(DiagnosticLevelFilter.allCases) {
                        Text($0 == .all ? "All Levels" : $0.title).tag($0)
                    }
                }
                .labelsHidden()
                .fixedSize()
                Picker("Category", selection: $store.diagnostics.diagnosticsCategoryFilter) {
                    Text("All Categories").tag(nil as DiagnosticCategory?)
                    ForEach(DiagnosticCategory.allCases) {
                        Label($0.shortTitle, systemImage: $0.systemImage).tag(Optional($0))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            if hasFilters {
                HStack {
                    Text(WorkspaceSummary.count(snapshot.entries.count, "match", "matches"))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset Filters", action: resetFilters).buttonStyle(.link)
                }
            }
        }
        .padding(.horizontal, UpkeepLayout.pageInset)
        .padding(.vertical, 12)
    }

    private var hasFilters: Bool {
        !store.diagnosticsSearchText.isEmpty || store.diagnosticsLevelFilter != .all || store.diagnosticsCategoryFilter != nil
    }

    private func resetFilters() {
        store.diagnosticsSearchText = ""
        store.diagnosticsLevelFilter = .all
        store.diagnosticsCategoryFilter = nil
    }
}

private struct DiagnosticSnapshot {
    let entries: [DiagnosticEntry]
    let warningCount: Int
    let errorCount: Int
    let latestScanDuration: String

    init(
        entries: [DiagnosticEntry],
        searchText: String,
        levelFilter: DiagnosticLevelFilter,
        categoryFilter: DiagnosticCategory?
    ) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.entries = entries.filter { entry in
            let matchesLevel = levelFilter.level.map { entry.level == $0 } ?? true
            let matchesCategory = categoryFilter.map { entry.category == $0 } ?? true
            guard matchesLevel && matchesCategory else { return false }
            guard !query.isEmpty else { return true }
            let searchable = ([entry.message, entry.category.rawValue]
                + entry.metadata.flatMap { [$0.key, $0.value] })
                .joined(separator: " ")
            return searchable.localizedCaseInsensitiveContains(query)
        }

        let completionIndex = entries.firstIndex(where: {
            $0.category == .scan && $0.message == "Update scan completed"
        })
        let latestScanEntries: ArraySlice<DiagnosticEntry>
        if let completionIndex {
            let remaining = entries[completionIndex...]
            if let startIndex = remaining.firstIndex(where: {
                $0.category == .scan && $0.message == "Update scan started"
            }) {
                latestScanEntries = entries[completionIndex...startIndex]
            } else {
                latestScanEntries = remaining
            }
        } else {
            latestScanEntries = entries[...]
        }
        warningCount = latestScanEntries.count { $0.level == .warning }
        errorCount = latestScanEntries.count { $0.level == .error }
        let duration = completionIndex.flatMap { entries[$0].metadata["Duration"] } ?? "—"
        latestScanDuration = diagnosticDisplayValue(duration, key: "Duration")
    }
}

private struct DiagnosticRow: View {
    let entry: DiagnosticEntry

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.message).fontWeight(.semibold)
                    Label(entry.category.shortTitle, systemImage: entry.category.systemImage)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                    Spacer()
                    Text(entry.date, format: .dateTime.hour().minute().second())
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if !entry.metadata.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 160), spacing: 9, alignment: .leading)],
                        alignment: .leading,
                        spacing: 9
                    ) {
                        ForEach(orderedMetadata, id: \.key) { pair in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pair.key)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                Text(diagnosticDisplayValue(pair.value, key: pair.key))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(pair.key == "Error" ? .red : .secondary)
                                    .lineLimit(3)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var orderedMetadata: [(key: String, value: String)] {
        let priority = [
            "Item", "Source", "Result", "Installed", "Available", "From", "To",
            "Duration", "Warnings", "Error", "Command", "Output"
        ]
        return entry.metadata.sorted { left, right in
            let leftIndex = priority.firstIndex(of: left.key) ?? priority.count
            let rightIndex = priority.firstIndex(of: right.key) ?? priority.count
            if leftIndex != rightIndex { return leftIndex < rightIndex }
            return left.key.localizedStandardCompare(right.key) == .orderedAscending
        }
    }

    private var icon: String {
        switch entry.level {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch entry.level {
        case .info: .blue
        case .warning: .orange
        case .error: .red
        }
    }
}

private func diagnosticDisplayValue(_ value: String, key: String) -> String {
    if key == "Duration",
       value.hasSuffix(" ms"),
       let milliseconds = Double(value.dropLast(3)),
       milliseconds >= 1_000 {
        return String(format: "%.1f s", milliseconds / 1_000)
    }
    if value == "true" { return "Enabled" }
    if value == "false" { return "Disabled" }
    if value == "completed" { return "Completed" }
    if value == "disabled" { return "Disabled" }
    if value == "failed" { return "Failed" }
    return value
}
