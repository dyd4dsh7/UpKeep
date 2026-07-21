import AppKit
import Foundation
import UserNotifications

enum HomebrewFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case updates = "Updates"
    case requested = "Requested"
    case dependencies = "Dependencies"
    case casks = "Casks"
    var id: Self { self }
}

@MainActor
final class UpkeepStore: ObservableObject {
    let settings: AppSettings
    @Published var apps: [InstalledApp] = []
    @Published var updates: [AvailableUpdate] = []
    @Published var homebrewPackages: [HomebrewPackage] = []
    @Published var adoptableApps: [AdoptableApp] = []
    @Published var macOSUpdates: [MacOSUpdate] = []
    @Published var updateHistory: [UpdateRecord] = []
    @Published var developerPackages: [DeveloperPackage] = []
    @Published var developerManagerFilter = "all"
    @Published var installedDeveloperManagers: [DeveloperPackageManager] = []
    @Published var localModels: [LocalLLMModel] = []
    @Published var selection: SidebarDestination = .updates
    @Published var homebrewFilter: HomebrewFilter = .all
    @Published var selectedPackageID: String?
    @Published var selectedDeveloperPackageID: String?
    @Published var selectedDeveloperVersion = ""
    @Published var selectedLocalModelID: String?
    @Published var availableDeveloperVersions: [String] = []
    @Published var isLoadingDeveloperVersions = false
    @Published var selectedApp: InstalledApp?
    @Published var searchText = ""
    @Published var isScanning = false
    @Published var lastChecked: Date?
    @Published var errorMessage: String?
    @Published var workingIDs = Set<String>()
    @Published var pendingRevert: UpdateRecord?
    private var periodicTask: Task<Void, Never>?
    private var didStart = false
    private let startedAt = Date()
    private var versionCache: [String: [String]] = [:]

    init(settings: AppSettings = AppSettings()) { self.settings = settings }

    var visibleUpdates: [AvailableUpdate] { updates.filter { !isExcluded($0) } }
    var filteredUpdates: [AvailableUpdate] { matching(visibleUpdates, name: { $0.app.name }) }
    var filteredApps: [InstalledApp] { matching(apps, name: \InstalledApp.name) }
    var filteredAdoptableApps: [AdoptableApp] { matching(adoptableApps, name: { $0.app.name }) }
    var outdatedPackageCount: Int { homebrewPackages.count { $0.isOutdated && !isExcluded($0) } }
    var outdatedDeveloperPackageCount: Int { developerPackages.count { $0.isOutdated && !isExcluded($0) } }
    var outdatedLocalModelCount: Int { localModels.count { $0.isOutdated && !isExcluded($0) } }
    var totalUpdateCount: Int {
        visibleUpdates.count + outdatedPackageCount + macOSUpdates.count(where: { !$0.isFullInstaller }) + outdatedDeveloperPackageCount + outdatedLocalModelCount
    }
    var filteredDeveloperPackages: [DeveloperPackage] {
        matching(developerPackages.filter {
            (settings.showCurrentDeveloperPackages || $0.isOutdated) &&
            (developerManagerFilter == "all" || $0.manager.rawValue == developerManagerFilter)
        }, name: { $0.name })
    }

    var visibleOutdatedLocalModels: [LocalLLMModel] {
        localModels.filter { $0.isOutdated && !isExcluded($0) }
    }

    var filteredHomebrewPackages: [HomebrewPackage] {
        let scoped = homebrewPackages.filter { package in
            switch homebrewFilter {
            case .all: true
            case .updates: package.isOutdated && !isExcluded(package)
            case .requested: !package.isDependency
            case .dependencies: package.isDependency
            case .casks: package.kind == .cask
            }
        }
        return matching(scoped, name: { $0.displayName })
    }

    func apps(for destination: SidebarDestination) -> [InstalledApp] {
        apps.filter { app in
            switch destination {
            case .allApps: true
            case .appStore: app.hasAppStoreReceipt
            case .sparkle: app.sparkleFeedURL != nil
            case .homebrewApps: homebrewPackage(for: app) != nil
            case .github: app.githubRepository != nil && app.sparkleFeedURL == nil
            case .noSource: source(for: app) == nil
            default: false
            }
        }
    }

    func source(for app: InstalledApp) -> UpdateSource? {
        if app.hasAppStoreReceipt { return .appStore }
        if homebrewPackage(for: app) != nil { return .homebrew }
        if app.sparkleFeedURL != nil { return .sparkle }
        if app.githubRepository != nil { return .github }
        return nil
    }

    func count(for destination: SidebarDestination) -> Int {
        switch destination {
        case .updates: totalUpdateCount
        case .allApps: apps.count
        case .adoptable: adoptableApps.count
        case .homebrewPackages: homebrewPackages.count
        case .macOSUpdates: macOSUpdates.count
        case .history: updateHistory.count
        case .developerPackages: developerPackages.count
        case .localModels: localModels.count
        default: apps(for: destination).count
        }
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil
        let previousCount = totalUpdateCount
        let report = await UpdateScanner().scan(settings: settings.scanSettings)
        apps = report.apps
        updates = report.updates
        homebrewPackages = report.homebrewPackages
        adoptableApps = report.adoptableApps
        macOSUpdates = report.macOSUpdates
        updateHistory = await UpdateHistoryStore.shared.records()
        developerPackages = report.developerPackages
        installedDeveloperManagers = report.installedDeveloperManagers
        localModels = report.localModels
        if developerManagerFilter != "all", !installedDeveloperManagers.contains(where: { $0.rawValue == developerManagerFilter }) {
            developerManagerFilter = "all"
        }
        lastChecked = report.checkedAt
        if selectedPackageID == nil { selectedPackageID = filteredHomebrewPackages.first?.id }
        if selectedDeveloperPackageID == nil || !developerPackages.contains(where: { $0.id == selectedDeveloperPackageID }) {
            selectedDeveloperPackageID = developerPackages.first?.id
            selectedDeveloperVersion = developerPackages.first?.latestVersion ?? ""
        }
        if selectedLocalModelID == nil || !localModels.contains(where: { $0.id == selectedLocalModelID }) {
            selectedLocalModelID = localModels.first?.id
        }
        isScanning = false
        notifyIfNeeded(previousCount: previousCount)
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        if settings.checkOnLaunch { await scan() }
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard let self, self.settings.refreshInterval != .never else { continue }
                let elapsed = Date().timeIntervalSince(self.lastChecked ?? self.startedAt)
                if elapsed >= Double(self.settings.refreshInterval.rawValue) { await self.scan() }
            }
        }
    }

    func scanDeveloperPackages(manager: DeveloperPackageManager?) async {
        let identifier = "developer-scan-\(manager?.rawValue ?? "all")"
        guard !workingIDs.contains(identifier) else { return }
        workingIDs.insert(identifier)
        defer { workingIDs.remove(identifier) }
        let managers = manager.map { Set([$0]) } ?? settings.enabledDeveloperManagers
        let report = await DeveloperPackageClient().scan(enabledManagers: managers)
        if let manager {
            developerPackages.removeAll { $0.manager == manager }
            developerPackages.append(contentsOf: report.packages)
            developerPackages.sort { $0.manager.rawValue == $1.manager.rawValue ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.manager.rawValue < $1.manager.rawValue }
            if !installedDeveloperManagers.contains(manager), report.installedManagers.contains(manager) { installedDeveloperManagers.append(manager) }
            versionCache = versionCache.filter { !$0.key.hasPrefix("\(manager.rawValue):") }
        } else {
            developerPackages = report.packages
            installedDeveloperManagers = report.installedManagers
            versionCache.removeAll()
        }
        lastChecked = Date()
        if let package = selectedDeveloperPackage { await loadAvailableVersions(for: package, force: true) }
    }

    func loadAvailableVersions(for package: DeveloperPackage, force: Bool = false) async {
        selectedDeveloperVersion = package.latestVersion
        if !force, let cached = versionCache[package.id] {
            availableDeveloperVersions = cached
            return
        }
        isLoadingDeveloperVersions = true
        availableDeveloperVersions = [package.latestVersion]
        let versions = await DeveloperPackageClient().availableVersions(
            for: package, includePrereleases: settings.includePrereleaseVersions
        )
        versionCache[package.id] = versions
        if selectedDeveloperPackageID == package.id {
            availableDeveloperVersions = versions
            selectedDeveloperVersion = versions.first ?? package.latestVersion
            isLoadingDeveloperVersions = false
        }
    }

    func performUpdate(_ update: AvailableUpdate) async {
        guard !workingIDs.contains(update.id) else { return }
        if let token = update.homebrewToken {
            if let package = homebrewPackages.first(where: { $0.kind == .cask && $0.token == token }) {
                await updatePackage(package)
            } else if let item = adoptableApps.first(where: { $0.caskToken == token && $0.app.id == update.app.id }) {
                await updateAdoptableApp(item)
            } else {
                let succeeded = await perform(id: update.id) { try await HomebrewClient().upgradeCask(token: token) }
                if succeeded { await scan() }
            }
        } else if let actionURL = update.actionURL {
            NSWorkspace.shared.open(actionURL)
        }
    }

    func updatePackage(_ package: HomebrewPackage) async {
        let record = await recoveryRecord(for: package)
        if package.kind == .cask, matchingApp(for: package) != nil, record == nil { return }
        let succeeded = await perform(id: package.id) { try await HomebrewClient().upgrade(package) }
        if succeeded {
            if let record { try? await UpdateHistoryStore.shared.add(record) }
            await scan()
        }
    }

    func updateAllPackages() async {
        guard !workingIDs.contains("homebrew-all") else { return }
        workingIDs.insert("homebrew-all")
        defer { workingIDs.remove("homebrew-all") }
        for package in homebrewPackages where package.isOutdated && !isExcluded(package) {
            let record = await recoveryRecord(for: package)
            if package.kind == .cask, matchingApp(for: package) != nil, record == nil { break }
            do {
                try await HomebrewClient().upgrade(package)
                if let record { try? await UpdateHistoryStore.shared.add(record) }
            } catch {
                errorMessage = error.localizedDescription
                break
            }
        }
        await scan()
    }

    func adopt(_ item: AdoptableApp) async {
        let succeeded = await perform(id: item.id) { try await HomebrewClient().adopt(item) }
        if succeeded { await scan() }
    }

    func updateAdoptableApp(_ item: AdoptableApp) async {
        let record: UpdateRecord
        do {
            record = try await UpdateHistoryStore.shared.prepareAppBackup(
                app: item.app, toVersion: item.caskVersion, kind: .homebrew
            )
        } catch {
            errorMessage = "Could not create a rollback backup: \(error.localizedDescription)"
            return
        }
        let succeeded = await perform(id: item.id) { try await HomebrewClient().installOrReplace(item) }
        if succeeded {
            try? await UpdateHistoryStore.shared.add(record)
            await scan()
        }
    }

    func updateDeveloperPackage(_ package: DeveloperPackage) async {
        await installDeveloperPackage(package, version: package.latestVersion)
    }

    func installDeveloperPackage(_ package: DeveloperPackage, version: String) async {
        let selectedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedVersion.isEmpty else {
            errorMessage = "Enter a version to install."
            return
        }
        let succeeded = await perform(id: package.id) {
            try await DeveloperPackageClient().install(package, version: selectedVersion)
        }
        if succeeded {
            let record = UpdateRecord(
                id: UUID(), date: Date(), name: package.name,
                fromVersion: package.currentVersion, toVersion: selectedVersion,
                kind: .developer, originalAppPath: nil, backupPath: nil,
                recoveryNote: "Package-manager updates do not have a universal rollback mechanism. Reinstall the previous version with \(package.manager.rawValue) if needed."
            )
            try? await UpdateHistoryStore.shared.add(record)
            await scan()
        }
    }

    func scanLocalModels() async {
        let identifier = "local-model-scan"
        guard !workingIDs.contains(identifier) else { return }
        workingIDs.insert(identifier)
        defer { workingIDs.remove(identifier) }
        localModels = await LocalModelClient().scan()
        if selectedLocalModelID == nil || !localModels.contains(where: { $0.id == selectedLocalModelID }) {
            selectedLocalModelID = localModels.first?.id
        }
        lastChecked = Date()
    }

    func updateLocalModel(_ model: LocalLLMModel) async {
        let succeeded = await perform(id: model.id) { try await LocalModelClient().update(model) }
        if succeeded {
            let record = UpdateRecord(
                id: UUID(), date: Date(), name: model.name,
                fromVersion: model.installedRevision, toVersion: model.latestRevision,
                kind: .model, originalAppPath: nil, backupPath: nil,
                recoveryNote: "Model files are managed by \(model.runtime.rawValue). Download the earlier model revision again if rollback is required."
            )
            try? await UpdateHistoryStore.shared.add(record)
            await scanLocalModels()
        }
    }

    func isExcluded(_ update: AvailableUpdate) -> Bool {
        settings.isExcluded(key: exclusionKey(for: update.app), version: update.availableVersion)
    }

    func isExcluded(_ package: HomebrewPackage) -> Bool {
        settings.isExcluded(key: exclusionKey(for: package), version: package.currentVersion)
    }

    func isExcluded(_ package: DeveloperPackage) -> Bool {
        settings.isExcluded(key: exclusionKey(for: package), version: package.latestVersion)
    }

    func isExcluded(_ model: LocalLLMModel) -> Bool {
        settings.isExcluded(key: exclusionKey(for: model), version: model.latestRevision)
    }

    func exclusion(for app: InstalledApp, version: String) -> UpdateExclusion? {
        settings.exclusion(for: exclusionKey(for: app), version: version)
    }

    func exclusion(for package: HomebrewPackage) -> UpdateExclusion? {
        settings.exclusion(for: exclusionKey(for: package), version: package.currentVersion)
    }

    func exclusion(for package: DeveloperPackage) -> UpdateExclusion? {
        settings.exclusion(for: exclusionKey(for: package), version: package.latestVersion)
    }

    func exclusion(for model: LocalLLMModel) -> UpdateExclusion? {
        settings.exclusion(for: exclusionKey(for: model), version: model.latestRevision)
    }

    func ignoredExclusion(for app: InstalledApp) -> UpdateExclusion? {
        settings.ignoredExclusion(for: exclusionKey(for: app))
    }

    func skip(_ update: AvailableUpdate) {
        exclude(.skipped, key: exclusionKey(for: update.app), name: update.app.name, category: "App", version: update.availableVersion)
    }

    func ignore(_ app: InstalledApp) {
        exclude(.ignored, key: exclusionKey(for: app), name: app.name, category: "App", version: nil)
    }

    func skip(_ package: HomebrewPackage) {
        exclude(.skipped, key: exclusionKey(for: package), name: package.displayName, category: "Homebrew", version: package.currentVersion)
    }

    func ignore(_ package: HomebrewPackage) {
        exclude(.ignored, key: exclusionKey(for: package), name: package.displayName, category: "Homebrew", version: nil)
    }

    func skip(_ package: DeveloperPackage) {
        exclude(.skipped, key: exclusionKey(for: package), name: package.name, category: package.manager.rawValue, version: package.latestVersion)
    }

    func ignore(_ package: DeveloperPackage) {
        exclude(.ignored, key: exclusionKey(for: package), name: package.name, category: package.manager.rawValue, version: nil)
    }

    func skip(_ model: LocalLLMModel) {
        exclude(.skipped, key: exclusionKey(for: model), name: model.name, category: model.runtime.rawValue, version: model.latestRevision)
    }

    func ignore(_ model: LocalLLMModel) {
        exclude(.ignored, key: exclusionKey(for: model), name: model.name, category: model.runtime.rawValue, version: nil)
    }

    func restore(_ exclusion: UpdateExclusion) {
        settings.restore(exclusion)
        objectWillChange.send()
    }

    func restore(app: InstalledApp) {
        settings.restore(key: exclusionKey(for: app))
        objectWillChange.send()
    }

    func restoreAllExclusions() {
        settings.restoreAllExclusions()
        objectWillChange.send()
    }

    func prepareMacOSUpdate(_ update: MacOSUpdate) async {
        do {
            try await UpdateHistoryStore.shared.addMacOSPlan(update: update)
            updateHistory = await UpdateHistoryStore.shared.records()
            MacOSUpdateClient().openSoftwareUpdateSettings()
        } catch { errorMessage = error.localizedDescription }
    }

    func openBetaSettings() { MacOSUpdateClient().openSoftwareUpdateSettings() }

    func revert(_ record: UpdateRecord) async {
        let succeeded = await perform(id: record.id.uuidString) {
            try await UpdateHistoryStore.shared.revert(record)
        }
        if succeeded { await scan() }
    }

    func openMacOSRecoveryHelp() {
        if let url = URL(string: "https://support.apple.com/102551") { NSWorkspace.shared.open(url) }
    }

    func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    }

    var selectedDeveloperPackage: DeveloperPackage? {
        guard let id = selectedDeveloperPackageID else { return nil }
        return developerPackages.first { $0.id == id }
    }

    private func notifyIfNeeded(previousCount: Int) {
        guard settings.notificationsEnabled, totalUpdateCount > 0, totalUpdateCount != previousCount else { return }
        let content = UNMutableNotificationContent()
        content.title = "Upkeep found updates"
        content.body = "\(totalUpdateCount) update\(totalUpdateCount == 1 ? " is" : "s are") available."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "upkeep-updates", content: content, trigger: nil))
    }

    private func exclude(_ mode: UpdateExclusionMode, key: String, name: String, category: String, version: String?) {
        if mode == .skipped, let version { settings.skip(key: key, name: name, category: category, version: version) }
        else { settings.ignore(key: key, name: name, category: category) }
        objectWillChange.send()
    }

    private func exclusionKey(for app: InstalledApp) -> String { "app|\(app.id)" }
    private func exclusionKey(for package: HomebrewPackage) -> String { "homebrew|\(package.id)" }
    private func exclusionKey(for package: DeveloperPackage) -> String { "developer|\(package.id)" }
    private func exclusionKey(for model: LocalLLMModel) -> String { "model|\(model.id)" }

    private func perform(id: String, operation: () async throws -> Void) async -> Bool {
        guard !workingIDs.contains(id) else { return false }
        workingIDs.insert(id)
        errorMessage = nil
        defer { workingIDs.remove(id) }
        do { try await operation(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }

    private func recoveryRecord(for package: HomebrewPackage) async -> UpdateRecord? {
        if package.kind == .cask, let app = matchingApp(for: package) {
            do {
                return try await UpdateHistoryStore.shared.prepareAppBackup(
                    app: app, toVersion: package.currentVersion, kind: .homebrew
                )
            } catch {
                errorMessage = "Could not create a rollback backup: \(error.localizedDescription)"
                return nil
            }
        }
        return UpdateRecord(
            id: UUID(), date: Date(), name: package.displayName,
            fromVersion: package.installedVersion, toVersion: package.currentVersion,
            kind: .homebrew, originalAppPath: nil, backupPath: nil,
            recoveryNote: "Homebrew formula versions cannot always be rolled back automatically. Restore from Time Machine or install a versioned formula when available."
        )
    }

    private func matchingApp(for package: HomebrewPackage) -> InstalledApp? {
        let packageName = normalize(package.displayName)
        let token = normalize(package.token)
        return apps.first { normalize($0.name) == packageName || normalize($0.name) == token }
    }

    private func homebrewPackage(for app: InstalledApp) -> HomebrewPackage? {
        let name = normalize(app.name)
        return homebrewPackages.first { $0.kind == .cask && (normalize($0.displayName) == name || normalize($0.token) == name) }
    }

    private func matching<T>(_ values: [T], name: (T) -> String) -> [T] {
        searchText.isEmpty ? values : values.filter { name($0).localizedCaseInsensitiveContains(searchText) }
    }

    private func normalize(_ value: String) -> String { value.lowercased().filter(\.isLetter) }
}
