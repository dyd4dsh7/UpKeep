import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: UpkeepStore

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $settings.selectedSection) { section in
                Label(section.rawValue, systemImage: icon(for: section))
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 210)
        } detail: {
            selectedContent
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 780, height: 540)
        .alert("Include prerelease updates?", isPresented: $settings.confirmingPrereleaseUpdates) {
            Button("Cancel", role: .cancel) {}
            Button("Include Prereleases", role: .destructive) {
                settings.includePrereleaseUpdates = true
                Task { await store.scan() }
            }
        } message: {
            Text("Alpha, beta, preview, release-candidate, nightly, and other non-stable software may be unreliable, incompatible, or cause data loss. UpKeep will check every enabled app and package source for these releases.")
        }
    }

    @ViewBuilder private var selectedContent: some View {
        switch settings.selectedSection {
        case .general: general
        case .sources: sources
        case .developer: developer
        case .diagnostics: diagnostics
        case .changelog: changelog
        case .ignored: ignored
        case .about: about
        }
    }

    private var general: some View {
        Form {
            Section("Checking") {
                Toggle("Check for updates when Upkeep opens", isOn: $settings.checkOnLaunch)
                Picker("Background check", selection: $settings.refreshInterval) {
                    ForEach(RefreshInterval.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: settings.refreshInterval) { _, _ in store.scheduleNextRefresh() }
                if settings.refreshInterval == .daily {
                    DatePicker(
                        "Check at",
                        selection: dailyRefreshTime,
                        displayedComponents: .hourAndMinute
                    )
                    .onChange(of: settings.dailyRefreshTimeMinutes) { _, _ in store.scheduleNextRefresh() }
                }
                if let nextCheck = store.nextScheduledCheck, settings.refreshInterval != .never {
                    LabeledContent("Next check") {
                        Text(nextCheck, format: .dateTime.weekday(.abbreviated).hour().minute())
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Notify me when the available count changes", isOn: $settings.notificationsEnabled)
                    .onChange(of: settings.notificationsEnabled) { _, enabled in
                        if enabled { Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) } }
                    }
            }
            Section("Menu Bar") {
                Toggle("Show Upkeep in the menu bar", isOn: $settings.showMenuBarItem)
                Toggle("Show the available update count", isOn: $settings.showMenuBarCount)
                    .disabled(!settings.showMenuBarItem)
                Toggle("Show the available update count on the Dock icon", isOn: $settings.showDockBadge)
                Text("The Upkeep icon remains available for quick scans, Settings, and opening the main window.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Appearance") {
                Picker("List density", selection: $settings.listDensity) {
                    ForEach(ListDensity.allCases) { density in
                        Label(density.title, systemImage: density.systemImage).tag(density)
                    }
                }
                Text("Compact rows fit more apps and packages on screen without hiding status information.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var sources: some View {
        Form {
            Section("Application Sources") {
                sourceToggle("Mac App Store", "bag", $settings.checkAppStore)
                sourceToggle("Sparkle feeds", "sparkles", $settings.checkSparkle)
                sourceToggle("Homebrew apps and packages", "shippingbox", $settings.checkHomebrew)
                sourceToggle("GitHub Releases", "chevron.left.forwardslash.chevron.right", $settings.checkGitHub)
                sourceToggle("Local LLM models", "brain.head.profile", $settings.checkLocalModels)
                Text("Checks model files directly against upstream registries. Ollama and LM Studio can remain closed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Prerelease Updates") {
                Toggle("Include prerelease updates for all apps and packages", isOn: Binding(
                    get: { settings.includePrereleaseUpdates },
                    set: { enabled in
                        if enabled { settings.confirmingPrereleaseUpdates = true }
                        else {
                            settings.includePrereleaseUpdates = false
                            Task { await store.scan() }
                        }
                    }
                ))
                Label(
                    "Warning: prerelease software may be unstable, incompatible, or unsafe for important data.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
                Text("Applies to Sparkle, GitHub, Homebrew, developer packages, and macOS updates. Sources such as the Mac App Store only expose releases available through their public update service.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("macOS") {
                sourceToggle("Software Update and full installers", "apple.logo", $settings.checkMacOS)
            }
        }
        .formStyle(.grouped)
    }

    private var changelog: some View {
        ChangelogView(compact: true)
    }

    private var diagnostics: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Diagnostics").font(.title2.bold())
                        Text("Understand what Upkeep checked and why it reached each result.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { store.exportDiagnostics() } label: {
                        Label("Export…", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) { store.clearDiagnostics() } label: {
                        Label("Clear", systemImage: "trash")
                    }
                        .disabled(store.diagnosticEntries.isEmpty)
                }

                HStack(spacing: 8) {
                    DiagnosticMetric(
                        title: "Entries",
                        value: "\(store.diagnosticEntries.count)",
                        systemImage: "list.bullet.rectangle",
                        color: .blue
                    )
                    DiagnosticMetric(
                        title: "Warnings",
                        value: "\(diagnosticWarningCount)",
                        systemImage: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                    DiagnosticMetric(
                        title: "Errors",
                        value: "\(diagnosticErrorCount)",
                        systemImage: "xmark.octagon.fill",
                        color: .red
                    )
                    DiagnosticMetric(
                        title: "Latest Scan",
                        value: latestScanDuration,
                        systemImage: "clock",
                        color: .secondary
                    )
                }

                HStack {
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search entries", text: $store.diagnosticsSearchText)
                            .textFieldStyle(.plain)
                        if !store.diagnosticsSearchText.isEmpty {
                            Button { store.diagnosticsSearchText = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear diagnostics search")
                        }
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                    Picker("Level", selection: $store.diagnosticsLevelFilter) {
                        ForEach(DiagnosticLevelFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 105)

                    Picker("Category", selection: $store.diagnosticsCategoryFilter) {
                        Text("All Categories").tag(nil as DiagnosticCategory?)
                        ForEach(DiagnosticCategory.allCases) { category in
                            Label(category.shortTitle, systemImage: category.systemImage)
                                .tag(Optional(category))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 145)

                    Button { store.refreshDiagnostics() } label: { Image(systemName: "arrow.clockwise") }
                        .help("Reload diagnostics")
                }
                Label(
                    "Secrets and private paths are redacted. Exports include installed item names, so review them before sharing.",
                    systemImage: "hand.raised.fill"
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.bottom, 14)

            if filteredDiagnostics.isEmpty {
                ContentUnavailableView(
                    store.diagnosticsSearchText.isEmpty ? "No diagnostics yet" : "No matching diagnostics",
                    systemImage: "stethoscope",
                    description: Text(store.diagnosticsSearchText.isEmpty ? "Run an update check to populate this log." : "Try a different search or level.")
                )
            } else {
                List(filteredDiagnostics) { entry in
                    DiagnosticRow(entry: entry)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.inset)
            }
        }
        .onAppear { store.refreshDiagnostics() }
    }

    private var filteredDiagnostics: [DiagnosticEntry] {
        let query = store.diagnosticsSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.diagnosticEntries.filter { entry in
            let matchesLevel = store.diagnosticsLevelFilter.level.map { entry.level == $0 } ?? true
            let matchesCategory = store.diagnosticsCategoryFilter.map { entry.category == $0 } ?? true
            let searchable = ([entry.message, entry.category.rawValue] + entry.metadata.flatMap { [$0.key, $0.value] })
                .joined(separator: " ")
            return matchesLevel && matchesCategory
                && (query.isEmpty || searchable.localizedCaseInsensitiveContains(query))
        }
    }

    private var diagnosticWarningCount: Int {
        latestScanEntries.count { $0.level == .warning }
    }

    private var diagnosticErrorCount: Int {
        latestScanEntries.count { $0.level == .error }
    }

    private var latestScanDuration: String {
        let rawValue = store.diagnosticEntries.first {
            $0.category == .scan && $0.message == "Update scan completed"
        }?.metadata["Duration"] ?? "—"
        return diagnosticDisplayValue(rawValue, key: "Duration")
    }

    private var latestScanEntries: ArraySlice<DiagnosticEntry> {
        guard let completionIndex = store.diagnosticEntries.firstIndex(where: {
            $0.category == .scan && $0.message == "Update scan completed"
        }) else { return store.diagnosticEntries[...] }
        let remaining = store.diagnosticEntries[completionIndex...]
        guard let startIndex = remaining.firstIndex(where: {
            $0.category == .scan && $0.message == "Update scan started"
        }) else { return remaining }
        return store.diagnosticEntries[completionIndex...startIndex]
    }

    private var ignored: some View {
        Group {
            if settings.updateExclusions.isEmpty {
                ContentUnavailableView(
                    "Nothing skipped or ignored", systemImage: "eye",
                    description: Text("Use the More menu beside an update to skip one version or ignore future updates.")
                )
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("Skipped versions return automatically when a newer version is released.")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Restore All") { store.restoreAllExclusions() }
                    }.padding(.horizontal, 10).padding(.bottom, 10)
                    List(settings.updateExclusions) { exclusion in
                        StandardItemRow {
                            Image(systemName: exclusion.mode == .ignored ? "eye.slash.fill" : "forward.end.fill")
                                .foregroundStyle(exclusion.mode == .ignored ? .orange : .blue)
                        } content: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(exclusion.name).fontWeight(.semibold).lineLimit(1)
                                Text(exclusionDescription(exclusion))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } accessories: {
                            Button("Restore") { store.restore(exclusion) }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }.listStyle(.inset)
                }
            }
        }
    }

    private func exclusionDescription(_ exclusion: UpdateExclusion) -> String {
        let behavior = exclusion.mode == .ignored
            ? "All updates ignored"
            : "Version \(exclusion.version ?? "") skipped"
        guard let expiresAt = exclusion.expiresAt else {
            return exclusion.mode == .ignored
                ? "\(exclusion.category) · All future updates ignored"
                : "\(exclusion.category) · \(behavior)"
        }
        return "\(exclusion.category) · \(behavior) until \(expiresAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private var developer: some View {
        Form {
            Section("Package Managers") {
                ForEach(DeveloperPackageManager.allCases) { manager in
                    Toggle(isOn: Binding(
                        get: { settings.isManagerEnabled(manager) },
                        set: { settings.setManager(manager, enabled: $0) }
                    )) {
                        HStack { PackageManagerIcon(manager: manager, size: 24); Text(manager.rawValue) }
                    }
                }
            }
            Section("Display and Versions") {
                Toggle("Show packages that are already current", isOn: $settings.showCurrentDeveloperPackages)
                Text("Prerelease package versions are controlled by the global option in Sources.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        VStack(spacing: 14) {
            AppBrandIcon(size: 104)
            Text("Upkeep").font(.largeTitle.weight(.semibold))
            Text(versionText).foregroundStyle(.secondary)
            Text("Every app, package, and system update in one native macOS workspace.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 390)
            Divider().frame(width: 220).padding(.vertical, 4)
            VStack(spacing: 5) {
                Text("Developed by Hayden Thorn")
                Link("haydenthorn.com", destination: URL(string: "https://haydenthorn.com")!)
            }
            .font(.callout)
            Spacer()
        }.padding(.top, 28)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Version \(version) (\(build))"
    }

    private var dailyRefreshTime: Binding<Date> {
        Binding(
            get: {
                let minutes = settings.dailyRefreshTimeMinutes
                return Calendar.current.date(
                    bySettingHour: minutes / 60,
                    minute: minutes % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.dailyRefreshTimeMinutes = (components.hour ?? 9) * 60 + (components.minute ?? 0)
            }
        )
    }

    private func icon(for section: SettingsSection) -> String {
        switch section {
        case .general: "gearshape"
        case .sources: "dot.radiowaves.left.and.right"
        case .developer: "chevron.left.forwardslash.chevron.right"
        case .diagnostics: "stethoscope"
        case .changelog: "list.bullet.rectangle"
        case .ignored: "eye.slash"
        case .about: "info.circle"
        }
    }

    private func sourceToggle(_ title: String, _ icon: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) { Label(title, systemImage: icon) }
    }
}

private struct DiagnosticRow: View {
    let entry: DiagnosticEntry

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.12))
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 9) {
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
                        columns: [GridItem(.adaptive(minimum: 132), spacing: 7, alignment: .leading)],
                        alignment: .leading,
                        spacing: 7
                    ) {
                        ForEach(orderedMetadata, id: \.key) { pair in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pair.key.uppercased())
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                Text(diagnosticDisplayValue(pair.value, key: pair.key))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(pair.key == "Error" ? .red : .secondary)
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(11)
        .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
        .padding(.vertical, 3)
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

private struct DiagnosticMetric: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.headline.monospacedDigit()).lineLimit(1)
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
