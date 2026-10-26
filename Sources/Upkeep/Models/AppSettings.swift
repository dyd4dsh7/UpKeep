import Foundation

enum ListDensity: String, CaseIterable, Identifiable, Sendable {
    case comfortable
    case compact

    var id: Self { self }
    var title: String { self == .comfortable ? "Comfortable" : "Compact" }
    var systemImage: String { self == .comfortable ? "rectangle.grid.1x2" : "list.bullet" }
    var detail: String {
        switch self {
        case .comfortable: "More breathing room for names, versions, and status."
        case .compact: "Fits more apps and packages on screen at once."
        }
    }
}

enum SidebarViewMode: String, CaseIterable, Identifiable, Sendable {
    case basic
    case advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .basic: "Basic"
        case .advanced: "Advanced"
        }
    }

    var detail: String {
        switch self {
        case .basic: "Focused navigation, stable updates, and essential controls."
        case .advanced: "Adds developer tools, diagnostics, prereleases, dependencies, and technical details."
        }
    }

    var systemImage: String {
        switch self {
        case .basic: "sidebar.left"
        case .advanced: "sidebar.squares.leading"
        }
    }
}

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
    case ignored = "Ignored"
    case diagnostics = "Diagnostics"
    case changelog = "Changelog"
    case about = "About"
    var id: Self { self }

    var requiresAdvancedView: Bool {
        self == .developer || self == .diagnostics
    }
}

enum SetupProfile: String, CaseIterable, Identifiable, Sendable {
    case applications
    case homebrew
    case advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .applications: "Applications only"
        case .homebrew: "Applications + Homebrew"
        case .advanced: "Advanced developer environment"
        }
    }

    var detail: String {
        switch self {
        case .applications: "App Store, Sparkle, GitHub, and stable macOS updates."
        case .homebrew: "Applications plus Homebrew apps and requested packages."
        case .advanced: "Applications, Homebrew, developer tools, package managers, and local AI models."
        }
    }

    var systemImage: String {
        switch self {
        case .applications: "macwindow"
        case .homebrew: "shippingbox"
        case .advanced: "terminal"
        }
    }
}

enum UpdateExclusionMode: String, Codable, Sendable {
    case skipped = "Skipped"
    case ignored = "Ignored"
}

enum UpdateExclusionDuration: String, CaseIterable, Identifiable, Codable, Sendable {
    case oneDay
    case twoDays
    case threeDays
    case fourDays
    case fiveDays
    case sixDays
    case oneWeek
    case oneMonth
    case threeMonths
    case sixMonths

    var id: Self { self }
    var title: String {
        switch self {
        case .oneDay: "1 Day"
        case .twoDays: "2 Days"
        case .threeDays: "3 Days"
        case .fourDays: "4 Days"
        case .fiveDays: "5 Days"
        case .sixDays: "6 Days"
        case .oneWeek: "1 Week"
        case .oneMonth: "1 Month"
        case .threeMonths: "3 Months"
        case .sixMonths: "6 Months"
        }
    }

    func expirationDate(from date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .oneDay: calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
        case .twoDays: calendar.date(byAdding: .day, value: 2, to: date) ?? date.addingTimeInterval(172_800)
        case .threeDays: calendar.date(byAdding: .day, value: 3, to: date) ?? date.addingTimeInterval(259_200)
        case .fourDays: calendar.date(byAdding: .day, value: 4, to: date) ?? date.addingTimeInterval(345_600)
        case .fiveDays: calendar.date(byAdding: .day, value: 5, to: date) ?? date.addingTimeInterval(432_000)
        case .sixDays: calendar.date(byAdding: .day, value: 6, to: date) ?? date.addingTimeInterval(518_400)
        case .oneWeek: calendar.date(byAdding: .day, value: 7, to: date) ?? date.addingTimeInterval(604_800)
        case .oneMonth: calendar.date(byAdding: .month, value: 1, to: date) ?? date.addingTimeInterval(2_592_000)
        case .threeMonths: calendar.date(byAdding: .month, value: 3, to: date) ?? date.addingTimeInterval(7_776_000)
        case .sixMonths: calendar.date(byAdding: .month, value: 6, to: date) ?? date.addingTimeInterval(15_552_000)
        }
    }
}

struct UpdateExclusion: Codable, Hashable, Identifiable, Sendable {
    var id: String { "\(key)|\(mode.rawValue)|\(version ?? "")" }
    let key: String
    let name: String
    let category: String
    let version: String?
    let mode: UpdateExclusionMode
    let expiresAt: Date?

    var isTemporary: Bool { expiresAt != nil }
    func isActive(at date: Date = Date()) -> Bool { expiresAt.map { $0 > date } ?? true }
}

struct ScanSettings: Sendable {
    var appSourceFilter: Set<UpdateSource>? = nil
    let checkAppStore: Bool
    let checkSparkle: Bool
    let checkHomebrew: Bool
    let checkGitHub: Bool
    let checkMacOS: Bool
    let checkLocalModels: Bool
    let includePrereleaseUpdates: Bool
    let enabledDeveloperManagers: Set<DeveloperPackageManager>
    let includeAdvancedSources: Bool
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var automaticallyCheckCVEs: Bool { didSet { save(automaticallyCheckCVEs, "automaticallyCheckCVEs") } }
    @Published var checkOnLaunch: Bool { didSet { save(checkOnLaunch, "checkOnLaunch") } }
    @Published var refreshInterval: RefreshInterval { didSet { save(refreshInterval.rawValue, "refreshInterval") } }
    @Published var dailyRefreshTimeMinutes: Int { didSet { save(dailyRefreshTimeMinutes, "dailyRefreshTimeMinutes") } }
    @Published var showMenuBarItem: Bool { didSet { save(showMenuBarItem, "showMenuBarItem") } }
    @Published var showMenuBarCount: Bool { didSet { save(showMenuBarCount, "showMenuBarCount") } }
    @Published var showDockBadge: Bool { didSet { save(showDockBadge, "showDockBadge") } }
    @Published var notificationsEnabled: Bool { didSet { save(notificationsEnabled, "notificationsEnabled") } }
    @Published var listDensity: ListDensity { didSet { save(listDensity.rawValue, "listDensity") } }
    @Published var sidebarViewMode: SidebarViewMode { didSet { save(sidebarViewMode.rawValue, "sidebarViewMode") } }
    @Published var showCurrentDeveloperPackages: Bool { didSet { save(showCurrentDeveloperPackages, "showCurrentDeveloperPackages") } }
    @Published var checkAppStore: Bool { didSet { save(checkAppStore, "checkAppStore") } }
    @Published var checkSparkle: Bool { didSet { save(checkSparkle, "checkSparkle") } }
    @Published var checkHomebrew: Bool { didSet { save(checkHomebrew, "checkHomebrew") } }
    @Published var checkGitHub: Bool { didSet { save(checkGitHub, "checkGitHub") } }
    @Published var checkMacOS: Bool { didSet { save(checkMacOS, "checkMacOS") } }
    @Published var checkLocalModels: Bool { didSet { save(checkLocalModels, "checkLocalModels") } }
    @Published var includePrereleaseUpdates: Bool { didSet { save(includePrereleaseUpdates, "includePrereleaseUpdates") } }
    @Published private(set) var hasCompletedSetup: Bool
    @Published var lastCompletedScanDate: Date? {
        didSet {
            if let lastCompletedScanDate { save(lastCompletedScanDate, "lastCompletedScanDate") }
            else { defaults.removeObject(forKey: "lastCompletedScanDate") }
        }
    }
    @Published private(set) var enabledDeveloperManagers: Set<DeveloperPackageManager>
    @Published private(set) var updateExclusions: [UpdateExclusion]
    @Published private(set) var ignoredHomebrewAdoptionKeys: Set<String>
    @Published private(set) var itemLastCheckedDates: [String: Date]
    @Published private(set) var sourceCheckFreshness: [String: CheckFreshness]
    @Published private(set) var customGitHubRepositories: [String: String]
    @Published var selectedSection: SettingsSection = .general
    @Published var confirmingPrereleaseUpdates = false
    private var exclusionExpiryTask: Task<Void, Never>?
    private(set) var exclusionCacheRevision: UInt64 = 0
    private(set) var nextExclusionExpiration: Date?
    private var exclusionsByKey: [String: [UpdateExclusion]] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "checkOnLaunch": true,
            "automaticallyCheckCVEs": true,
            "refreshInterval": RefreshInterval.everySixHours.rawValue,
            "dailyRefreshTimeMinutes": 9 * 60,
            "showMenuBarItem": true,
            "showMenuBarCount": true,
            "showDockBadge": true,
            "notificationsEnabled": false,
            "listDensity": ListDensity.comfortable.rawValue,
            "sidebarViewMode": SidebarViewMode.basic.rawValue,
            "showCurrentDeveloperPackages": true,
            "checkAppStore": true,
            "checkSparkle": true,
            "checkHomebrew": true,
            "checkGitHub": true,
            "checkMacOS": true,
            "checkLocalModels": true,
            "includePrereleaseUpdates": false
        ])
        let completedSetup = defaults.object(forKey: "hasCompletedSetup") != nil
            ? defaults.bool(forKey: "hasCompletedSetup")
            : (defaults.object(forKey: "lastCompletedScanDate") != nil)
        hasCompletedSetup = completedSetup
        if !defaults.bool(forKey: "didRestoreSwiftUIMenuBarItem") {
            defaults.set(true, forKey: "showMenuBarItem")
            defaults.set(true, forKey: "didRestoreSwiftUIMenuBarItem")
        }
        automaticallyCheckCVEs = defaults.bool(forKey: "automaticallyCheckCVEs")
        checkOnLaunch = defaults.bool(forKey: "checkOnLaunch")
        refreshInterval = RefreshInterval(rawValue: defaults.integer(forKey: "refreshInterval")) ?? .everySixHours
        dailyRefreshTimeMinutes = defaults.integer(forKey: "dailyRefreshTimeMinutes")
        showMenuBarItem = defaults.bool(forKey: "showMenuBarItem")
        showMenuBarCount = defaults.bool(forKey: "showMenuBarCount")
        showDockBadge = defaults.bool(forKey: "showDockBadge")
        notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        listDensity = ListDensity(rawValue: defaults.string(forKey: "listDensity") ?? "") ?? .comfortable
        sidebarViewMode = SidebarViewMode(rawValue: defaults.string(forKey: "sidebarViewMode") ?? "") ?? .basic
        showCurrentDeveloperPackages = defaults.bool(forKey: "showCurrentDeveloperPackages")
        checkAppStore = defaults.bool(forKey: "checkAppStore")
        checkSparkle = defaults.bool(forKey: "checkSparkle")
        checkHomebrew = defaults.bool(forKey: "checkHomebrew")
        checkGitHub = defaults.bool(forKey: "checkGitHub")
        checkMacOS = defaults.bool(forKey: "checkMacOS")
        checkLocalModels = defaults.bool(forKey: "checkLocalModels")
        includePrereleaseUpdates = defaults.bool(forKey: "includePrereleaseUpdates")
        lastCompletedScanDate = defaults.object(forKey: "lastCompletedScanDate") as? Date
        sourceCheckFreshness = defaults.data(forKey: "sourceCheckFreshness")
            .flatMap { try? JSONDecoder().decode([String: CheckFreshness].self, from: $0) } ?? [:]
        let disabled = Set(defaults.stringArray(forKey: "disabledDeveloperManagers") ?? [])
        enabledDeveloperManagers = completedSetup
            ? Set(DeveloperPackageManager.allCases.filter { !disabled.contains($0.rawValue) })
            : []
        updateExclusions = (defaults.data(forKey: "updateExclusions")
            .flatMap { try? JSONDecoder().decode([UpdateExclusion].self, from: $0) } ?? [])
            .filter { $0.isActive() }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        ignoredHomebrewAdoptionKeys = Set(defaults.stringArray(forKey: "ignoredHomebrewAdoptionKeys") ?? [])
        itemLastCheckedDates = defaults.data(forKey: "itemLastCheckedDates")
            .flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } ?? [:]
        customGitHubRepositories = defaults.dictionary(forKey: "customGitHubRepositories")
            as? [String: String] ?? [:]
        saveExclusions()
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

    func completeSetup(_ profile: SetupProfile, sidebarViewMode: SidebarViewMode = .basic) {
        self.sidebarViewMode = sidebarViewMode
        checkAppStore = true
        checkSparkle = true
        checkGitHub = true
        checkMacOS = true
        includePrereleaseUpdates = false

        switch profile {
        case .applications:
            checkHomebrew = false
            checkLocalModels = false
            setEnabledManagers([])
        case .homebrew:
            checkHomebrew = true
            checkLocalModels = false
            setEnabledManagers([])
        case .advanced:
            checkHomebrew = true
            checkLocalModels = true
            setEnabledManagers(Set(DeveloperPackageManager.allCases))
        }

        hasCompletedSetup = true
        defaults.set(true, forKey: "hasCompletedSetup")
    }

    private func setEnabledManagers(_ managers: Set<DeveloperPackageManager>) {
        enabledDeveloperManagers = managers
        let disabled = DeveloperPackageManager.allCases
            .filter { !managers.contains($0) }
            .map(\.rawValue)
        defaults.set(disabled, forKey: "disabledDeveloperManagers")
    }

    func isExcluded(key: String, version: String) -> Bool {
        exclusion(for: key, version: version) != nil
    }

    func exclusion(for key: String, version: String) -> UpdateExclusion? {
        exclusionsByKey[key]?.first {
            $0.isActive() && ($0.mode == .ignored || ($0.mode == .skipped && $0.version == version))
        }
    }

    func ignoredExclusion(for key: String) -> UpdateExclusion? {
        exclusionsByKey[key]?.first { $0.mode == .ignored && $0.isActive() }
    }

    func skip(
        key: String,
        name: String,
        category: String,
        version: String,
        duration: UpdateExclusionDuration? = nil,
        now: Date = Date()
    ) {
        updateExclusions.removeAll { $0.key == key }
        updateExclusions.append(UpdateExclusion(
            key: key, name: name, category: category, version: version, mode: .skipped,
            expiresAt: duration?.expirationDate(from: now)
        ))
        saveExclusions()
    }

    func ignore(
        key: String,
        name: String,
        category: String,
        duration: UpdateExclusionDuration? = nil,
        now: Date = Date()
    ) {
        updateExclusions.removeAll { $0.key == key }
        updateExclusions.append(UpdateExclusion(
            key: key, name: name, category: category, version: nil, mode: .ignored,
            expiresAt: duration?.expirationDate(from: now)
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

    func isHomebrewAdoptionIgnored(key: String) -> Bool {
        ignoredHomebrewAdoptionKeys.contains(key)
    }

    func setHomebrewAdoptionIgnored(_ ignored: Bool, key: String) {
        if ignored { ignoredHomebrewAdoptionKeys.insert(key) }
        else { ignoredHomebrewAdoptionKeys.remove(key) }
        defaults.set(ignoredHomebrewAdoptionKeys.sorted(), forKey: "ignoredHomebrewAdoptionKeys")
    }

    func lastChecked(for key: String) -> Date? {
        itemLastCheckedDates[key]
    }

    func recordCheck(for key: String, at date: Date = Date()) {
        recordChecks(for: [key], at: date)
    }

    func recordSourceAttempt(_ key: String, at date: Date, failure: String? = nil) {
        recordSourceAttempts([key: failure ?? ""], at: date)
    }

    /// Empty values denote success. Persist once per source group, not once per app.
    func recordSourceAttempts(_ attempts: [String: String], at date: Date) {
        var freshness = sourceCheckFreshness
        for (key, failure) in attempts {
            freshness[key] = CheckFreshness(lastAttempt: date,
                lastSuccess: failure.isEmpty ? date : freshness[key]?.lastSuccess,
                failure: failure.isEmpty ? nil : failure)
        }
        sourceCheckFreshness = freshness
        if let data = try? JSONEncoder().encode(sourceCheckFreshness) {
            defaults.set(data, forKey: "sourceCheckFreshness")
        }
    }

    func recordChecks(for keys: [String], at date: Date = Date()) {
        for key in keys { itemLastCheckedDates[key] = date }
        if let data = try? JSONEncoder().encode(itemLastCheckedDates) {
            defaults.set(data, forKey: "itemLastCheckedDates")
        }
    }

    func githubRepository(for bundleIdentifier: String?) -> String? {
        guard let key = bundleIdentifier?.lowercased() else { return nil }
        return customGitHubRepositories[key]
    }

    func setGitHubRepository(_ repository: String?, for bundleIdentifier: String) {
        let key = bundleIdentifier.lowercased()
        if let repository, !repository.isEmpty {
            customGitHubRepositories[key] = repository
        } else {
            customGitHubRepositories.removeValue(forKey: key)
        }
        defaults.set(customGitHubRepositories, forKey: "customGitHubRepositories")
    }

    func migrateExclusion(from legacyKey: String, to key: String) {
        guard legacyKey != key,
              let legacy = updateExclusions.first(where: { $0.key == legacyKey })
        else { return }

        if updateExclusions.contains(where: { $0.key == key }) {
            updateExclusions.removeAll { $0.key == legacyKey }
        } else {
            updateExclusions.removeAll { $0.key == legacyKey }
            updateExclusions.append(UpdateExclusion(
                key: key,
                name: legacy.name,
                category: legacy.category,
                version: legacy.version,
                mode: legacy.mode,
                expiresAt: legacy.expiresAt
            ))
        }
        saveExclusions()
    }

    var scanSettings: ScanSettings {
        let includeAdvancedSources = sidebarViewMode == .advanced
        return ScanSettings(
            checkAppStore: checkAppStore, checkSparkle: checkSparkle,
            checkHomebrew: checkHomebrew, checkGitHub: checkGitHub,
            checkMacOS: checkMacOS,
            checkLocalModels: includeAdvancedSources && checkLocalModels,
            includePrereleaseUpdates: includeAdvancedSources && includePrereleaseUpdates,
            enabledDeveloperManagers: includeAdvancedSources ? enabledDeveloperManagers : [],
            includeAdvancedSources: includeAdvancedSources
        )
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    private func saveExclusions() {
        updateExclusions.removeAll { !$0.isActive() }
        updateExclusions.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        // Every exclusion mutation passes through here. Grouping preserves first-match
        // ordering for older persisted data with duplicate keys; reads still check expiry.
        exclusionsByKey = Dictionary(grouping: updateExclusions, by: \.key)
        exclusionCacheRevision &+= 1
        nextExclusionExpiration = updateExclusions.compactMap(\.expiresAt).min()
        if let data = try? JSONEncoder().encode(updateExclusions) { defaults.set(data, forKey: "updateExclusions") }
        scheduleExclusionExpiry()
    }

    private func scheduleExclusionExpiry() {
        exclusionExpiryTask?.cancel()
        guard let expiration = updateExclusions.compactMap(\.expiresAt).min() else {
            exclusionExpiryTask = nil
            return
        }
        exclusionExpiryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, expiration.timeIntervalSinceNow))) }
            catch { return }
            guard !Task.isCancelled, let self else { return }
            self.updateExclusions.removeAll { !$0.isActive() }
            self.saveExclusions()
        }
    }
}
