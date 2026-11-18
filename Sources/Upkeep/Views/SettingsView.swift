import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @UpkeepStoreReference private var store

    var body: some View {
        HStack(spacing: 0) {
            settingsNavigation
                .frame(width: 186)
            Divider()
            VStack(spacing: 0) {
                WorkspaceSummary(
                    title: settings.selectedSection.rawValue,
                    detail: description(for: settings.selectedSection),
                    systemImage: icon(for: settings.selectedSection)
                )
                settingsContent(for: settings.selectedSection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(settings.selectedSection)
            }
        }
        .frame(width: 830, height: 600)
        .upkeepWorkspaceAppearance()
        .onChange(of: visibleSettingsSections, initial: true) { _, sections in
            if !sections.contains(settings.selectedSection) {
                settings.selectedSection = .general
            }
        }
        .alert("Check for prerelease updates?", isPresented: $settings.confirmingPrereleaseUpdates) {
            Button("Cancel", role: .cancel) {}
            Button("Include Prereleases", role: .destructive) {
                settings.includePrereleaseUpdates = true
                Task { await store.scan() }
            }
        } message: {
            Text("Upkeep will look for beta, preview, and other prerelease builds across enabled sources. These builds can be unstable and may cause data loss.")
        }
    }

    private var settingsNavigation: some View {
        VStack(alignment: .leading, spacing: 9) {
            WorkspaceSectionLabel(title: "Settings")
                .padding(.horizontal, 13)
                .padding(.top, 16)
            List(selection: settingsSelection) {
                Section {
                    ForEach(visibleSettingsSections.filter { [.general, .sources, .developer, .ignored].contains($0) }) {
                        settingsLink($0)
                    }
                } header: {
                    WorkspaceSectionLabel(title: "Preferences")
                }
                Section {
                    ForEach(visibleSettingsSections.filter { [.diagnostics, .changelog, .about].contains($0) }) {
                        settingsLink($0)
                    }
                } header: {
                    WorkspaceSectionLabel(title: "App & support")
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .accessibilityLabel("Settings sections")
        }
        .padding(.horizontal, 8)
        .background(.regularMaterial)
    }

    private func settingsLink(_ section: SettingsSection) -> some View {
        Label(section.rawValue, systemImage: icon(for: section))
            .tag(section)
    }

    private func description(for section: SettingsSection) -> String {
        switch section {
        case .general: "Navigation, appearance, and automatic checks."
        case .sources: "Choose where Upkeep looks for releases."
        case .developer: "Choose which package managers Upkeep checks."
        case .ignored: "Manage skipped versions and ignored software."
        case .diagnostics: "Inspect update checks and export the local log."
        case .changelog: "Browse release notes by version."
        case .about: versionText
        }
    }

    private var settingsSelection: Binding<SettingsSection?> {
        Binding(get: { settings.selectedSection }, set: { section in
            if let section { settings.selectedSection = section }
        })
    }

    @ViewBuilder private func settingsContent(for section: SettingsSection) -> some View {
        switch section {
        case .general: general
        case .sources: sources
        case .developer: developer
        case .diagnostics: DiagnosticsSettingsView()
        case .changelog: changelog
        case .ignored: ignored
        case .about: about
        }
    }

    private var general: some View {
        Form {
            Section {
                SettingsOptionRow(title: "Navigation", systemImage: "sidebar.left") {
                    Picker("Navigation", selection: $settings.sidebarViewMode) {
                        ForEach(SidebarViewMode.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }
                SettingsOptionRow(title: "List density", systemImage: "line.3.horizontal") {
                    Picker("List density", selection: $settings.listDensity) {
                        ForEach(ListDensity.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text(settings.sidebarViewMode.detail)
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
                    title: "Automatically check CVEs",
                    detail: "Check installed software after launch, scheduled, and manual inventory refreshes using OSV, Homebrew, and NVD.",
                    systemImage: "shield.lefthalf.filled"
                ) {
                    Toggle("Automatically check CVEs", isOn: Binding(
                        get: { settings.automaticallyCheckCVEs },
                        set: { store.setAutomaticCVEChecking($0) }
                    )).labelsHidden()
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
                    .upkeepStateTransition()
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
        .upkeepAnimated(for: settings.refreshInterval)
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
                    "GitHub Releases", "Releases for apps linked to GitHub.",
                    "chevron.left.forwardslash.chevron.right", $settings.checkGitHub
                )
            } header: {
                Text("Application Sources")
            }
            Section {
                sourceToggle(
                    "Homebrew", "Installed apps and requested packages.",
                    "shippingbox", $settings.checkHomebrew
                )
                if settings.sidebarViewMode == .advanced {
                    sourceToggle(
                        "Local AI models", "Installed model revisions from upstream registries.",
                        "brain.head.profile", $settings.checkLocalModels
                    )
                }
                sourceToggle(
                    "macOS updates",
                    settings.sidebarViewMode == .advanced
                        ? "Software updates and full installers."
                        : "Stable software updates.",
                    "apple.logo", $settings.checkMacOS
                )
            } header: {
                Text("System and Package Sources")
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
            SourceHealthView(settings: settings)
        }
        .formStyle(.grouped)
    }

    private var changelog: some View {
        ChangelogView()
    }

    private var visibleSettingsSections: [SettingsSection] {
        SettingsSection.allCases.filter {
            settings.sidebarViewMode == .advanced || !$0.requiresAdvancedView
        }
    }

    private var ignored: some View {
        let ignored = settings.updateExclusions.filter { $0.mode == .ignored }
        let skipped = settings.updateExclusions.filter { $0.mode == .skipped }
        return Group {
            if ignored.isEmpty && skipped.isEmpty {
                WorkspaceEmptyState(
                    "Nothing skipped or ignored", systemImage: "eye",
                    description: Text("Use an update’s options to skip a version or ignore future releases.")
                )
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text(WorkspaceSummary.count(settings.updateExclusions.count, "exclusion", "exclusions"))
                            .font(.callout.weight(.medium))
                        Spacer()
                        Button("Restore All Updates", systemImage: "arrow.uturn.backward") {
                            store.restoreAllExclusions()
                        }
                    }
                    .padding(.horizontal, UpkeepLayout.pageInset)
                    .padding(.vertical, 12)
                    Divider()
                    List {
                        exclusionSection("Skipped versions", items: skipped)
                        exclusionSection("Ignored software", items: ignored)
                    }
                    .upkeepContentList()
                }
            }
        }
    }

    @ViewBuilder private func exclusionSection(_ title: String, items: [UpdateExclusion]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { exclusion in
                    StandardItemRow {
                        WorkspaceGlyph(systemImage: exclusion.mode == .ignored ? "eye.slash" : "forward.end", size: 34)
                    } content: {
                        ItemIdentityView(title: exclusion.name, detail: exclusionDescription(exclusion))
                    } accessories: {
                        Button("Restore") { store.restore(exclusion) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityLabel("Restore updates for \(exclusion.name)")
                    }
                }
            } header: {
                WorkspaceSectionLabel(title: title, count: items.count)
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

    @UpkeepState private var managerSearch = ""

    private var developer: some View {
        let query = managerSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let managers = DeveloperPackageManager.allCases.filter { query.isEmpty || $0.rawValue.localizedCaseInsensitiveContains(query) }
        let detected = Set(store.installedDeveloperManagers)
        return Form {
            Section("Inventory") {
                SettingsOptionRow(
                    title: "Show current packages",
                    detail: "Include packages that don’t need updates.",
                    systemImage: "checkmark.circle"
                ) {
                    Toggle("Show current packages", isOn: $settings.showCurrentDeveloperPackages)
                        .labelsHidden()
                }
            }
            Section("Package Managers") {
                TextField("Find a package manager", text: $managerSearch)
                    .textFieldStyle(.roundedBorder)
                if managers.isEmpty {
                    Text("No managers match your search.").foregroundStyle(.secondary)
                }
                ForEach(managers) { manager in
                    DeveloperManagerSettingsRow(
                        manager: manager,
                        detected: detected.contains(manager),
                        isEnabled: Binding(
                            get: { settings.isManagerEnabled(manager) },
                            set: { settings.setManager(manager, enabled: $0) }
                        )
                    )
                }
            }
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 17) {
                    AppBrandIcon(size: 76)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Upkeep")
                            .font(.title.weight(.semibold))
                        Text("Manage updates for apps, packages, AI models, and macOS.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                LabeledContent("Developer") {
                    VStack(alignment: .trailing, spacing: 5) {
                        Text("Hayden Thorn")
                        Link("haydenthorn.com", destination: URL(string: "https://haydenthorn.com")!)
                    }
                }
            }
            .padding(22)
            .upkeepSurface()
            .padding(UpkeepLayout.pageInset)
        }
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
    let detected: Bool
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            PackageManagerIcon(manager: manager, size: 30)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(manager.rawValue).fontWeight(.medium)
                if detected {
                    Text("Detected in inventory").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 16)
            Toggle(manager.rawValue, isOn: $isEnabled)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}
