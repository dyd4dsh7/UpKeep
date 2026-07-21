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

    func nextDate(
        after lastCheck: Date,
        now: Date = Date(),
        dailyTimeMinutes: Int,
        calendar: Calendar = .current
    ) -> Date? {
        switch self {
        case .never:
            return nil
        case .hourly, .everySixHours:
            let interval = TimeInterval(rawValue)
            let elapsed = max(0, now.timeIntervalSince(lastCheck))
            let intervalsElapsed = floor(elapsed / interval) + 1
            return lastCheck.addingTimeInterval(intervalsElapsed * interval)
        case .daily:
            let clampedMinutes = min(max(dailyTimeMinutes, 0), (24 * 60) - 1)
            var components = DateComponents()
            components.hour = clampedMinutes / 60
            components.minute = clampedMinutes % 60
            return calendar.nextDate(
                after: now,
                matching: components,
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            )
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case sources = "Sources"
    case developer = "Developer"
    case changelog = "Changelog"
    case ignored = "Ignored"
    case about = "About"
    var id: Self { self }
}

enum UpdateExclusionMode: String, Codable, Sendable {
    case skipped = "Skipped"
    case ignored = "Ignored"
}

struct UpdateExclusion: Codable, Hashable, Identifiable, Sendable {
    var id: String { "\(key)|\(mode.rawValue)|\(version ?? "")" }
    let key: String
    let name: String
    let category: String
    let version: String?
    let mode: UpdateExclusionMode
}

struct ScanSettings: Sendable {
    let checkAppStore: Bool
    let checkSparkle: Bool
    let checkHomebrew: Bool
    let checkGitHub: Bool
    let checkMacOS: Bool
    let checkLocalModels: Bool
    let includePrereleaseUpdates: Bool
    let enabledDeveloperManagers: Set<DeveloperPackageManager>
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var checkOnLaunch: Bool { didSet { save(checkOnLaunch, "checkOnLaunch") } }
    @Published var refreshInterval: RefreshInterval { didSet { save(refreshInterval.rawValue, "refreshInterval") } }
    @Published var dailyRefreshTimeMinutes: Int { didSet { save(dailyRefreshTimeMinutes, "dailyRefreshTimeMinutes") } }
    @Published var showMenuBarItem: Bool { didSet { save(showMenuBarItem, "showMenuBarItem") } }
    @Published var showMenuBarCount: Bool { didSet { save(showMenuBarCount, "showMenuBarCount") } }
    @Published var showDockBadge: Bool { didSet { save(showDockBadge, "showDockBadge") } }
    @Published var notificationsEnabled: Bool { didSet { save(notificationsEnabled, "notificationsEnabled") } }
    @Published var showCurrentDeveloperPackages: Bool { didSet { save(showCurrentDeveloperPackages, "showCurrentDeveloperPackages") } }
    @Published var checkAppStore: Bool { didSet { save(checkAppStore, "checkAppStore") } }
    @Published var checkSparkle: Bool { didSet { save(checkSparkle, "checkSparkle") } }
    @Published var checkHomebrew: Bool { didSet { save(checkHomebrew, "checkHomebrew") } }
    @Published var checkGitHub: Bool { didSet { save(checkGitHub, "checkGitHub") } }
    @Published var checkMacOS: Bool { didSet { save(checkMacOS, "checkMacOS") } }
    @Published var checkLocalModels: Bool { didSet { save(checkLocalModels, "checkLocalModels") } }
    @Published var includePrereleaseUpdates: Bool { didSet { save(includePrereleaseUpdates, "includePrereleaseUpdates") } }
    @Published private(set) var enabledDeveloperManagers: Set<DeveloperPackageManager>
    @Published private(set) var updateExclusions: [UpdateExclusion]
    @Published var selectedSection: SettingsSection = .general
    @Published var confirmingPrereleaseUpdates = false

    init() {
        defaults.register(defaults: [
            "checkOnLaunch": true,
            "refreshInterval": RefreshInterval.everySixHours.rawValue,
            "dailyRefreshTimeMinutes": 9 * 60,
            "showMenuBarItem": true,
            "showMenuBarCount": true,
            "showDockBadge": true,
            "notificationsEnabled": false,
            "showCurrentDeveloperPackages": true,
            "checkAppStore": true,
            "checkSparkle": true,
            "checkHomebrew": true,
            "checkGitHub": true,
            "checkMacOS": true,
            "checkLocalModels": true,
            "includePrereleaseUpdates": false
        ])
        if !defaults.bool(forKey: "didRestoreSwiftUIMenuBarItem") {
            defaults.set(true, forKey: "showMenuBarItem")
            defaults.set(true, forKey: "didRestoreSwiftUIMenuBarItem")
        }
        checkOnLaunch = defaults.bool(forKey: "checkOnLaunch")
        refreshInterval = RefreshInterval(rawValue: defaults.integer(forKey: "refreshInterval")) ?? .everySixHours
        dailyRefreshTimeMinutes = defaults.integer(forKey: "dailyRefreshTimeMinutes")
        showMenuBarItem = defaults.bool(forKey: "showMenuBarItem")
        showMenuBarCount = defaults.bool(forKey: "showMenuBarCount")
        showDockBadge = defaults.bool(forKey: "showDockBadge")
        notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        showCurrentDeveloperPackages = defaults.bool(forKey: "showCurrentDeveloperPackages")
        checkAppStore = defaults.bool(forKey: "checkAppStore")
        checkSparkle = defaults.bool(forKey: "checkSparkle")
        checkHomebrew = defaults.bool(forKey: "checkHomebrew")
        checkGitHub = defaults.bool(forKey: "checkGitHub")
        checkMacOS = defaults.bool(forKey: "checkMacOS")
        checkLocalModels = defaults.bool(forKey: "checkLocalModels")
        includePrereleaseUpdates = defaults.bool(forKey: "includePrereleaseUpdates")
        let disabled = Set(defaults.stringArray(forKey: "disabledDeveloperManagers") ?? [])
        enabledDeveloperManagers = Set(DeveloperPackageManager.allCases.filter { !disabled.contains($0.rawValue) })
        updateExclusions = (defaults.data(forKey: "updateExclusions")
            .flatMap { try? JSONDecoder().decode([UpdateExclusion].self, from: $0) } ?? [])
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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

    func isExcluded(key: String, version: String) -> Bool {
        updateExclusions.contains {
            $0.key == key && ($0.mode == .ignored || ($0.mode == .skipped && $0.version == version))
        }
    }

    func exclusion(for key: String, version: String) -> UpdateExclusion? {
        updateExclusions.first {
            $0.key == key && ($0.mode == .ignored || ($0.mode == .skipped && $0.version == version))
        }
    }

    func ignoredExclusion(for key: String) -> UpdateExclusion? {
        updateExclusions.first { $0.key == key && $0.mode == .ignored }
    }

    func skip(key: String, name: String, category: String, version: String) {
        updateExclusions.removeAll { $0.key == key }
        updateExclusions.append(UpdateExclusion(
            key: key, name: name, category: category, version: version, mode: .skipped
        ))
        saveExclusions()
    }

    func ignore(key: String, name: String, category: String) {
        updateExclusions.removeAll { $0.key == key }
        updateExclusions.append(UpdateExclusion(
            key: key, name: name, category: category, version: nil, mode: .ignored
        ))
        saveExclusions()
    }

    func restore(_ exclusion: UpdateExclusion) {
        updateExclusions.removeAll { $0.id == exclusion.id }
        saveExclusions()
    }

    func restore(key: String) {
        updateExclusions.removeAll { $0.key == key }
        saveExclusions()
    }

    func restoreAllExclusions() {
        updateExclusions.removeAll()
        saveExclusions()
    }

    var scanSettings: ScanSettings {
        ScanSettings(
            checkAppStore: checkAppStore, checkSparkle: checkSparkle,
            checkHomebrew: checkHomebrew, checkGitHub: checkGitHub,
            checkMacOS: checkMacOS, checkLocalModels: checkLocalModels,
            includePrereleaseUpdates: includePrereleaseUpdates,
            enabledDeveloperManagers: enabledDeveloperManagers
        )
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    private func saveExclusions() {
        updateExclusions.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if let data = try? JSONEncoder().encode(updateExclusions) { defaults.set(data, forKey: "updateExclusions") }
    }
}
