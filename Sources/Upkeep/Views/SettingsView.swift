import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: UpkeepStore

    var body: some View {
        TabView(selection: $settings.selectedSection) {
            ForEach(visibleSettingsSections) { section in
                settingsContent(for: section)
                    .tabItem {
                        Label(section.rawValue, systemImage: icon(for: section))
                    }
                    .tag(section)
            }
        }
        .frame(width: 860, height: 620)
        .onChange(of: settings.sidebarViewMode) { _, mode in
            if mode == .basic, settings.selectedSection.requiresAdvancedView {
                settings.selectedSection = .general
            }
        }
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

    @ViewBuilder private func settingsContent(for section: SettingsSection) -> some View {
        switch section {
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
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    appearanceHeading("Navigation")
                    HStack(spacing: 10) {
                        ForEach(SidebarViewMode.allCases) { mode in
                            AppearanceOptionButton(
                                title: mode.title,
                                detail: mode.detail,
                                systemImage: mode.systemImage,
                                isSelected: settings.sidebarViewMode == mode
                            ) {
                                settings.sidebarViewMode = mode
                            }
                        }
                    }

                    Divider()

                    appearanceHeading("List Density")
                    HStack(spacing: 10) {
                        ForEach(ListDensity.allCases) { density in
                            AppearanceOptionButton(
                                title: density.title,
                                detail: density.detail,
                                systemImage: density.systemImage,
                                isSelected: settings.listDensity == density
                            ) {
                                settings.listDensity = density
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Appearance")
            }
            Section {
                SettingsOptionRow(
                    title: "Check when Upkeep opens",
                    systemImage: "arrow.clockwise.circle"
                ) {
                    Toggle("Check when Upkeep opens", isOn: $settings.checkOnLaunch)
                        .labelsHidden()
                }

                SettingsOptionRow(
                    title: "Background checks",
                    detail: backgroundCheckDetail,
                    systemImage: "clock.arrow.circlepath"
                ) {
                    Picker("Background checks", selection: $settings.refreshInterval) {
                        ForEach(RefreshInterval.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    .onChange(of: settings.refreshInterval) { _, _ in store.scheduleNextRefresh() }
                }

                if settings.refreshInterval == .daily {
                    SettingsOptionRow(
                        title: "Daily check time",
                        systemImage: "calendar.badge.clock"
                    ) {
                        DatePicker(
                            "Daily check time",
                            selection: dailyRefreshTime,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .onChange(of: settings.dailyRefreshTimeMinutes) { _, _ in store.scheduleNextRefresh() }
                    }
                }

                SettingsOptionRow(
                    title: "Notify when update count changes",
                    systemImage: "bell.badge"
                ) {
                    Toggle("Update notifications", isOn: $settings.notificationsEnabled)
                        .labelsHidden()
                }
                    .onChange(of: settings.notificationsEnabled) { _, enabled in
                        if enabled { Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) } }
                    }
            } header: {
                Text("Automatic Checking")
            }
            Section {
                SettingsOptionRow(
                    title: "Show Upkeep in the menu bar",
                    systemImage: "menubar.rectangle"
                ) {
                    Toggle("Menu bar item", isOn: $settings.showMenuBarItem)
                        .labelsHidden()
                }
                SettingsOptionRow(
                    title: "Show update count in menu bar",
                    systemImage: "number.circle"
                ) {
                    Toggle("Menu bar count", isOn: $settings.showMenuBarCount)
                        .labelsHidden()
                }
                    .disabled(!settings.showMenuBarItem)
                SettingsOptionRow(
                    title: "Show update count on Dock icon",
                    systemImage: "dock.rectangle"
                ) {
                    Toggle("Dock badge", isOn: $settings.showDockBadge)
                        .labelsHidden()
                }
            } header: {
                Text("Menu Bar and Dock")
            }
        }
        .formStyle(.grouped)
    }

    private var sources: some View {
        Form {
            Section {
                sourceToggle(
                    "Mac App Store", "Installed app updates from Apple.",
                    "bag", $settings.checkAppStore
                )
                sourceToggle(
                    "Sparkle", "In-app update feeds published by developers.",
                    "sparkles", $settings.checkSparkle
                )
                sourceToggle(
                    "Homebrew", "Installed apps and requested packages.",
                    "shippingbox", $settings.checkHomebrew
                )
                sourceToggle(
                    "GitHub Releases", "Releases for apps linked to GitHub.",
                    "chevron.left.forwardslash.chevron.right", $settings.checkGitHub
                )
                if settings.sidebarViewMode == .advanced {
                    sourceToggle(
                        "Local AI models", "Installed model revisions from upstream registries.",
                        "brain.head.profile", $settings.checkLocalModels
                    )
                }
            } header: {
                Text("Application Sources")
            }
            if settings.sidebarViewMode == .advanced {
                Section {
                    SettingsOptionRow(
                        title: "Include prereleases",
                        detail: "Alpha, beta, preview, release-candidate, and nightly builds.",
                        systemImage: "testtube.2",
                        tint: .purple
                    ) {
                        Toggle("Include prereleases", isOn: Binding(
                            get: { settings.includePrereleaseUpdates },
                            set: { enabled in
                                if enabled { settings.confirmingPrereleaseUpdates = true }
                                else {
                                    settings.includePrereleaseUpdates = false
                                    Task { await store.scan() }
                                }
                            }
                        ))
                        .labelsHidden()
                    }
                    Label(
                        "Prerelease software may be unstable, incompatible, or unsafe for important data.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)
                } header: {
                    Text("Prerelease Updates")
                }
            }
            if settings.checkHomebrew {
                Section {
                    SettingsOptionRow(
                        title: appManagementPermissionTitle,
                        detail: appManagementPermissionDetail,
                        systemImage: appManagementPermissionImage,
                        tint: appManagementPermissionColor
                    ) {
                        HStack(spacing: 8) {
                            if store.appManagementPermissionCheck?.status == .denied {
                                Button("Open Settings") {
                                    store.openAppManagementSettings()
                                }
                            }
                            Button {
                                Task { await store.checkAppManagementPermission() }
                            } label: {
                                if isCheckingAppManagementPermission {
                                    HStack(spacing: 6) {
                                        ProgressView().controlSize(.small)
                                        Text("Checking…")
                                    }
                                } else {
                                    Text(store.appManagementPermissionCheck == nil ? "Check Access" : "Check Again")
                                }
                            }
                            .disabled(
                                isCheckingAppManagementPermission
                                    || store.homebrewPermissionCheckApps.isEmpty
                            )
                        }
                    }
                } header: {
                    Text("App Management")
                } footer: {
                    Text("macOS App Management controls whether Upkeep can update or delete other apps. The check opens one eligible app file for modification but does not write, truncate, or change it.")
                }
            }
            Section {
                sourceToggle(
                    "macOS updates",
                    settings.sidebarViewMode == .advanced
                        ? "Software updates and full installers."
                        : "Stable software updates.",
                    "apple.logo", $settings.checkMacOS
                )
            } header: {
                Text("macOS")
            }
        }
        .formStyle(.grouped)
    }

    private var changelog: some View {
        ChangelogView(compact: true)
    }

    private var visibleSettingsSections: [SettingsSection] {
        SettingsSection.allCases.filter {
            settings.sidebarViewMode == .advanced || !$0.requiresAdvancedView
        }
    }

    private var diagnostics: some View {
        VStack(spacing: 0) {
            Form {
                Section("Latest Activity") {
                    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
                        GridRow {
                            diagnosticSummary("Entries", "\(store.diagnosticEntries.count)", "list.bullet.rectangle")
                            diagnosticSummary("Warnings", "\(diagnosticWarningCount)", "exclamationmark.triangle.fill")
                        }
                        GridRow {
                            diagnosticSummary("Errors", "\(diagnosticErrorCount)", "xmark.octagon.fill")
                            diagnosticSummary("Latest scan", latestScanDuration, "clock")
                        }
                    }
                }
                Section("Filter") {
                    TextField("Search diagnostics", text: $store.diagnostics.diagnosticsSearchText)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Picker("Level", selection: $store.diagnostics.diagnosticsLevelFilter) {
                            ForEach(DiagnosticLevelFilter.allCases) { Text($0.title).tag($0) }
                        }
                        Picker("Category", selection: $store.diagnostics.diagnosticsCategoryFilter) {
                            Text("All Categories").tag(nil as DiagnosticCategory?)
                            ForEach(DiagnosticCategory.allCases) { category in
                                Label(category.shortTitle, systemImage: category.systemImage)
                                    .tag(Optional(category))
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(height: 255)

            HStack(spacing: 8) {
                Label("Private paths and secrets are redacted", systemImage: "hand.raised")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { store.refreshDiagnostics() } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                Button { store.exportDiagnostics() } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                Button("Clear", role: .destructive) { store.clearDiagnostics() }
                    .disabled(store.diagnosticEntries.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            if filteredDiagnostics.isEmpty {
                ContentUnavailableView(
                    store.diagnosticsSearchText.isEmpty ? "No diagnostics yet" : "No matching diagnostics",
                    systemImage: "stethoscope",
                    description: Text(store.diagnosticsSearchText.isEmpty ? "Run an update check to populate this log." : "Try a different search or level.")
                )
            } else {
                List(filteredDiagnostics) { entry in
                    DiagnosticRow(entry: entry)
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
                    DeveloperManagerSettingsRow(
                        manager: manager,
                        isEnabled: Binding(
                            get: { settings.isManagerEnabled(manager) },
                            set: { settings.setManager(manager, enabled: $0) }
                        )
                    )
                }
            }
            Section {
                SettingsOptionRow(
                    title: "Show packages that are already current",
                    systemImage: "checkmark.circle"
                ) {
                    Toggle("Show current packages", isOn: $settings.showCurrentDeveloperPackages)
                        .labelsHidden()
                }
            } header: {
                Text("Display and Versions")
            } footer: {
                Text("Prerelease package versions are controlled by the global option in Sources.")
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

    private var backgroundCheckDetail: String {
        guard settings.refreshInterval != .never else {
            return "Automatic checks are disabled. You can still scan manually."
        }
        guard let nextCheck = store.nextScheduledCheck else {
            return "Schedule update checks while Upkeep is running."
        }
        return "Next check: \(nextCheck.formatted(.dateTime.weekday(.abbreviated).hour().minute()))."
    }

    private var appManagementPermissionTitle: String {
        if isCheckingAppManagementPermission { return "Checking App Management access" }
        return switch store.appManagementPermissionCheck?.status {
        case .allowed: "App Management is allowed"
        case .denied: "App Management access is needed"
        case .unavailable: "App Management could not be checked"
        case nil: "Check App Management access"
        }
    }

    private var appManagementPermissionDetail: String {
        if store.homebrewPermissionCheckApps.isEmpty {
            return "No eligible Homebrew-managed app is available for a safe access check."
        }
        return store.appManagementPermissionCheck?.detail
            ?? "Verify that macOS allows Upkeep to modify applications managed through Homebrew."
    }

    private var appManagementPermissionImage: String {
        if isCheckingAppManagementPermission { return "arrow.triangle.2.circlepath" }
        return switch store.appManagementPermissionCheck?.status {
        case .allowed: "checkmark.shield.fill"
        case .denied: "lock.shield.fill"
        case .unavailable: "exclamationmark.shield.fill"
        case nil: "lock.shield"
        }
    }

    private var appManagementPermissionColor: Color {
        switch store.appManagementPermissionCheck?.status {
        case .allowed: .green
        case .denied: .orange
        case .unavailable: .red
        case nil: .accentColor
        }
    }

    private var isCheckingAppManagementPermission: Bool {
        store.isWorking(.appManagementPermissionCheck)
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

    private func diagnosticSummary(_ title: String, _ value: String, _ systemImage: String) -> some View {
        LabeledContent {
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        } label: {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func sourceToggle(
        _ title: String,
        _ detail: String,
        _ icon: String,
        _ binding: Binding<Bool>
    ) -> some View {
        SettingsOptionRow(title: title, detail: detail, systemImage: icon) {
            Toggle(title, isOn: binding)
                .labelsHidden()
        }
    }

    private func appearanceHeading(_ title: String) -> some View {
        Text(title)
            .font(.headline)
    }
}

private struct SettingsOptionRow<Control: View>: View {
    let title: String
    let detail: String?
    let systemImage: String
    let tint: Color
    let control: Control

    init(
        title: String,
        detail: String? = nil,
        systemImage: String,
        tint: Color = .accentColor,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.tint = tint
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            control
        }
        .padding(.vertical, 4)
    }
}

private struct DeveloperManagerSettingsRow: View {
    let manager: DeveloperPackageManager
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            PackageManagerIcon(manager: manager, size: 30)
                .frame(width: 30, height: 30)
            Text(manager.rawValue)
                .fontWeight(.medium)
            Spacer(minLength: 16)
            Toggle(manager.rawValue, isOn: $isEnabled)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

private struct AppearanceOptionButton: View {
    let title: String
    let detail: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 11)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.16),
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                        columns: [GridItem(.adaptive(minimum: 132), spacing: 7, alignment: .leading)],
                        alignment: .leading,
                        spacing: 7
                    ) {
                        ForEach(orderedMetadata, id: \.key) { pair in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pair.key)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                Text(diagnosticDisplayValue(pair.value, key: pair.key))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(pair.key == "Error" ? .red : .secondary)
                                    .lineLimit(2)
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
