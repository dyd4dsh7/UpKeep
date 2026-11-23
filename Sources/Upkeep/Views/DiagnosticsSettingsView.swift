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
                List {
                    ForEach(snapshot.days, id: \.day) { group in
                        Section {
                            ForEach(group.entries) { entry in
                                DiagnosticRow(entry: entry)
                                    .listRowSeparator(.hidden)
                            }
                        } header: {
                            WorkspaceSectionLabel(title: group.title, count: group.entries.count)
                        }
                    }
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
        HStack(spacing: 10) {
            metric("Log entries", store.diagnosticEntries.count.formatted(), systemImage: "list.bullet.rectangle", tint: .secondary)
            metric("Warnings in last scan", snapshot.warningCount.formatted(), systemImage: "exclamationmark.triangle.fill",
                   tint: snapshot.warningCount > 0 ? .orange : .secondary)
            metric("Errors in last scan", snapshot.errorCount.formatted(), systemImage: "xmark.octagon.fill",
                   tint: snapshot.errorCount > 0 ? .red : .secondary)
            metric("Last scan took", snapshot.latestScanDuration, systemImage: "stopwatch", tint: .secondary)
        }
        .padding(.horizontal, UpkeepLayout.pageInset)
        .padding(.top, 16)
    }

    private func metric(_ title: String, _ value: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(tint)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint == .secondary ? Color.primary : tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .upkeepSurface(radius: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private func filters(_ snapshot: DiagnosticSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search messages and details", text: $store.diagnostics.diagnosticsSearchText)
                        .textFieldStyle(.plain)
                    if !store.diagnosticsSearchText.isEmpty {
                        Button {
                            store.diagnosticsSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
                Picker("Level", selection: $store.diagnostics.diagnosticsLevelFilter) {
                    ForEach(DiagnosticLevelFilter.allCases) {
                        Text($0 == .all ? "All" : $0.title).tag($0)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                Picker("Category", selection: $store.diagnostics.diagnosticsCategoryFilter) {
                    Text("All Categories").tag(nil as DiagnosticCategory?)
                    Divider()
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
                    Button("Reset Filters", action: resetFilters).buttonStyle(.link).font(.caption)
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
    struct Day {
        let day: Date
        let title: String
        let entries: [DiagnosticEntry]
    }

    let entries: [DiagnosticEntry]
    /// Entries grouped by calendar day, newest first, as the log is ordered.
    var days: [Day] {
        let calendar = Calendar.current
        var result: [Day] = []
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            if let last = result.last, last.day == day {
                result[result.count - 1] = Day(day: day, title: last.title, entries: last.entries + [entry])
            } else {
                let title = calendar.isDateInToday(day) ? "Today"
                    : calendar.isDateInYesterday(day) ? "Yesterday"
                    : day.formatted(.dateTime.weekday(.wide).day().month(.wide))
                result.append(Day(day: day, title: title, entries: [entry]))
            }
        }
        return result
    }
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
    @UpkeepState private var expanded: Bool?

    /// Warnings and errors open with their details; routine entries show a
    /// one-line summary until opened.
    private var isExpanded: Bool { expanded ?? (entry.level != .info) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            levelMarker
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.message)
                        .fontWeight(entry.level == .info ? .medium : .semibold)
                        .foregroundStyle(entry.level == .error ? Color.red : Color.primary)
                    categoryChip
                    Spacer(minLength: 8)
                    Text(entry.date, format: .dateTime.hour().minute().second())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    // Every row keeps the chevron's space so times line up.
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .opacity(entry.metadata.isEmpty ? 0 : 1)
                        .accessibilityHidden(true)
                }
                if !entry.metadata.isEmpty {
                    if isExpanded { details } else { summaryLine }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !entry.metadata.isEmpty else { return }
            withAnimation(.snappy(duration: 0.2)) { expanded = !isExpanded }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(entry.metadata.isEmpty ? [] : .isButton)
        .accessibilityHint(entry.metadata.isEmpty ? "" : (isExpanded ? "Hides details" : "Shows details"))
    }

    @ViewBuilder private var levelMarker: some View {
        switch entry.level {
        case .info:
            Circle().fill(Color.secondary.opacity(0.45)).frame(width: 7, height: 7)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .error:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }

    private var categoryChip: some View {
        Label(entry.category.shortTitle, systemImage: entry.category.systemImage)
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.7), in: Capsule())
            .fixedSize()
    }

    private var rowBackground: Color {
        switch entry.level {
        case .info: .clear
        case .warning: .orange.opacity(0.08)
        case .error: .red.opacity(0.08)
        }
    }

    private var summaryLine: some View {
        Text(orderedMetadata.prefix(4)
            .map { "\($0.key) \(diagnosticDisplayValue($0.value, key: $0.key))" }
            .joined(separator: "  ·  "))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var details: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 5) {
            ForEach(orderedMetadata, id: \.key) { pair in
                GridRow {
                    Text(pair.key)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.leading)
                        .frame(minWidth: 96, alignment: .leading)
                    Text(diagnosticDisplayValue(pair.value, key: pair.key))
                        .font(Self.monospacedKeys.contains(pair.key) ? .caption.monospaced() : .caption)
                        .foregroundStyle(pair.key == "Error" ? Color.red : Color.primary)
                        .lineLimit(pair.key == "Output" ? 8 : nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private static let monospacedKeys: Set<String> = ["Command", "Output", "Path", "Executable", "URL", "Error"]

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
