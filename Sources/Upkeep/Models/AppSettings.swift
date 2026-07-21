import Foundation

enum RefreshInterval: Int, CaseIterable, Identifiable, Sendable {
    case never = 0
    case hourly = 3600
    case everySixHours = 21600
    case daily = 86400

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .never: "Never"
        case .hourly: "Every hour"
        case .everySixHours: "Every 6 hours"
        case .daily: "Daily"
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case sources = "Sources"
    case developer = "Developer"
    case about = "About"
    var id: Self { self }
}

struct ScanSettings: Sendable {
    let checkAppStore: Bool
    let checkSparkle: Bool
    let checkHomebrew: Bool
    let checkGitHub: Bool
    let checkMacOS: Bool
    let includeBetas: Bool
    let enabledDeveloperManagers: Set<DeveloperPackageManager>
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var checkOnLaunch: Bool { didSet { save(checkOnLaunch, "checkOnLaunch") } }
    @Published var refreshInterval: RefreshInterval { didSet { save(refreshInterval.rawValue, "refreshInterval") } }
    @Published var showMenuBarItem: Bool { didSet { save(showMenuBarItem, "showMenuBarItem") } }
    @Published var showMenuBarCount: Bool { didSet { save(showMenuBarCount, "showMenuBarCount") } }
    @Published var notificationsEnabled: Bool { didSet { save(notificationsEnabled, "notificationsEnabled") } }
    @Published var showCurrentDeveloperPackages: Bool { didSet { save(showCurrentDeveloperPackages, "showCurrentDeveloperPackages") } }
    @Published var includePrereleaseVersions: Bool { didSet { save(includePrereleaseVersions, "includePrereleaseVersions") } }
    @Published var checkAppStore: Bool { didSet { save(checkAppStore, "checkAppStore") } }
    @Published var checkSparkle: Bool { didSet { save(checkSparkle, "checkSparkle") } }
    @Published var checkHomebrew: Bool { didSet { save(checkHomebrew, "checkHomebrew") } }
    @Published var checkGitHub: Bool { didSet { save(checkGitHub, "checkGitHub") } }
    @Published var checkMacOS: Bool { didSet { save(checkMacOS, "checkMacOS") } }
    @Published var includeBetas: Bool { didSet { save(includeBetas, "includeBetas") } }
    @Published private(set) var enabledDeveloperManagers: Set<DeveloperPackageManager>
    @Published var selectedSection: SettingsSection = .general

    init() {
        defaults.register(defaults: [
            "checkOnLaunch": true,
            "refreshInterval": RefreshInterval.everySixHours.rawValue,
            "showMenuBarItem": true,
            "showMenuBarCount": true,
            "notificationsEnabled": false,
            "showCurrentDeveloperPackages": true,
            "includePrereleaseVersions": false,
            "checkAppStore": true,
            "checkSparkle": true,
            "checkHomebrew": true,
            "checkGitHub": true,
            "checkMacOS": true,
            "includeBetas": true
        ])
        checkOnLaunch = defaults.bool(forKey: "checkOnLaunch")
        refreshInterval = RefreshInterval(rawValue: defaults.integer(forKey: "refreshInterval")) ?? .everySixHours
        showMenuBarItem = defaults.bool(forKey: "showMenuBarItem")
        showMenuBarCount = defaults.bool(forKey: "showMenuBarCount")
        notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        showCurrentDeveloperPackages = defaults.bool(forKey: "showCurrentDeveloperPackages")
        includePrereleaseVersions = defaults.bool(forKey: "includePrereleaseVersions")
        checkAppStore = defaults.bool(forKey: "checkAppStore")
        checkSparkle = defaults.bool(forKey: "checkSparkle")
        checkHomebrew = defaults.bool(forKey: "checkHomebrew")
        checkGitHub = defaults.bool(forKey: "checkGitHub")
        checkMacOS = defaults.bool(forKey: "checkMacOS")
        includeBetas = defaults.bool(forKey: "includeBetas")
        let disabled = Set(defaults.stringArray(forKey: "disabledDeveloperManagers") ?? [])
        enabledDeveloperManagers = Set(DeveloperPackageManager.allCases.filter { !disabled.contains($0.rawValue) })
    }

    func isManagerEnabled(_ manager: DeveloperPackageManager) -> Bool {
        enabledDeveloperManagers.contains(manager)
    }

    func setManager(_ manager: DeveloperPackageManager, enabled: Bool) {
        if enabled { enabledDeveloperManagers.insert(manager) }
        else { enabledDeveloperManagers.remove(manager) }
        objectWillChange.send()
        let disabled = DeveloperPackageManager.allCases.filter { !enabledDeveloperManagers.contains($0) }.map(\.rawValue)
        defaults.set(disabled, forKey: "disabledDeveloperManagers")
    }

    var scanSettings: ScanSettings {
        ScanSettings(
            checkAppStore: checkAppStore, checkSparkle: checkSparkle,
            checkHomebrew: checkHomebrew, checkGitHub: checkGitHub,
            checkMacOS: checkMacOS, includeBetas: includeBetas,
            enabledDeveloperManagers: enabledDeveloperManagers
        )
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }
}
