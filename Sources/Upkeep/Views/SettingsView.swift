import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 12) {
            Picker("Settings Section", selection: $settings.selectedSection) {
                ForEach(SettingsSection.allCases) { section in Text(section.rawValue).tag(section) }
            }
            .labelsHidden().pickerStyle(.segmented).frame(maxWidth: 470)
            Divider()
            selectedContent
        }
        .frame(width: 580, height: 430)
        .padding(16)
    }

    @ViewBuilder private var selectedContent: some View {
        switch settings.selectedSection {
        case .general: general
        case .sources: sources
        case .developer: developer
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
                Toggle("Notify me when the available count changes", isOn: $settings.notificationsEnabled)
                    .onChange(of: settings.notificationsEnabled) { _, enabled in
                        if enabled { Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) } }
                    }
            }
            Section("Menu Bar") {
                Toggle("Show the available update count", isOn: $settings.showMenuBarCount)
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
            }
            Section("macOS") {
                sourceToggle("Software Update and full installers", "apple.logo", $settings.checkMacOS)
                Toggle("Include beta and release-candidate updates", isOn: $settings.includeBetas)
                    .disabled(!settings.checkMacOS)
            }
        }
        .formStyle(.grouped)
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
                Toggle("Include prerelease versions in version menus", isOn: $settings.includePrereleaseVersions)
            }
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        VStack(spacing: 14) {
            AppBrandIcon(size: 104)
            Text("Upkeep").font(.largeTitle.bold())
            Text("Version 0.7.0").foregroundStyle(.secondary)
            Text("Every app, package, and system update in one native macOS workspace.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 390)
            Link("Private GitHub Repository", destination: URL(string: "https://github.com/dyd4dsh7/UpKeep")!)
            Spacer()
        }.padding(.top, 28)
    }

    private func sourceToggle(_ title: String, _ icon: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) { Label(title, systemImage: icon) }
    }
}
