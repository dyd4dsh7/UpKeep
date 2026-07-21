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
                                Text(exclusion.mode == .ignored
                                     ? "\(exclusion.category) · All future updates ignored"
                                     : "\(exclusion.category) · Version \(exclusion.version ?? "") skipped")
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
        case .changelog: "list.bullet.rectangle"
        case .ignored: "eye.slash"
        case .about: "info.circle"
        }
    }

    private func sourceToggle(_ title: String, _ icon: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) { Label(title, systemImage: icon) }
    }
}
