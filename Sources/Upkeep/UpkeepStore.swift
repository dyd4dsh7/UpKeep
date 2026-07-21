import AppKit
import Foundation
import UniformTypeIdentifiers
import UserNotifications

enum HomebrewFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case updates = "Updates"
    case requested = "Requested"
    case dependencies = "Dependencies"
    case casks = "Casks"
    case unmapped = "Unmapped"
    var id: Self { self }
}

enum AppListFilter: String, CaseIterable, Identifiable {
    case all = "All Apps"
    case updates = "Updates"
    case warnings = "Warnings"
    case unmapped = "Unmapped"
    var id: Self { self }
}

enum AppSortOrder: String, CaseIterable, Identifiable {
    case recommended = "Recommended"
    case name = "Name"
    case source = "Update Source"
    case installedVersion = "Installed Version"
    case availableVersion = "Available Version"
    case installDate = "Install Date"
    case recentlyUpdated = "Recently Updated"
    case warningSeverity = "Warning Severity"
    var id: Self { self }
}

enum HomebrewSortOrder: String, CaseIterable, Identifiable {
    case recommended = "Recommended"
    case name = "Name"
    case installedVersion = "Installed Version"
    case availableVersion = "Available Version"
    case kind = "Package Type"
    var id: Self { self }
}

enum UpdateListFilter: String, CaseIterable, Identifiable {
    case all = "All Updates"
    case applications = "Applications"
    case homebrew = "Homebrew"
    case macOS = "macOS"
    case developer = "Developer"
    case models = "AI Models"
    case warnings = "Warnings"
    var id: Self { self }
}

enum UpdateSortOrder: String, CaseIterable, Identifiable {
    case recommended = "Recommended"
    case name = "Name"
    case source = "Source"
    case installedVersion = "Installed Version"
    case availableVersion = "Available Version"
    case installDate = "Install Date"
    case recentlyUpdated = "Recently Updated"
    var id: Self { self }
}

enum UpdateInspectorSelection: Equatable {
    case homebrew(String)
    case developer(String)
    case model(String)

    var listID: String {
        switch self {
        case let .homebrew(id): "homebrew:\(id)"
        case let .developer(id): "developer:\(id)"
        case let .model(id): "model:\(id)"
        }
    }
}

struct RunningAppConfirmation: Identifiable {
    enum Action {
        case update(AvailableUpdate)
        case package(HomebrewPackage)
        case adopt(AdoptableApp)
        case updateAdoptable(AdoptableApp)
        case allPackages
    }

    let id = UUID()
    let apps: [InstalledApp]
    let action: Action

    var title: String { apps.count == 1 ? "Quit \(apps[0].name) and Continue?" : "Quit Running Apps and Continue?" }
    var message: String {
        let names = apps.map(\.name).formatted()
        return "\(names) \(apps.count == 1 ? "is" : "are") currently running. Upkeep must quit \(apps.count == 1 ? "it" : "them") before Homebrew changes the application files."
    }
    var buttonTitle: String {
        switch action {
        case .adopt: "Quit and Adopt"
        case .allPackages: "Quit Apps and Update"
        default: "Quit and Update"
        }
    }
}

private enum RunningAppUpdateError: LocalizedError {
    case couldNotQuit([String])

    var errorDescription: String? {
        switch self {
        case let .couldNotQuit(names):
            return "Could not quit \(names.formatted()). Quit \(names.count == 1 ? "the app" : "these apps") manually, then try the update again."
        }
    }
}

private enum BatchUpdateError: LocalizedError {
    case couldNotOpen(String)

    var errorDescription: String? {
        switch self {
        case let .couldNotOpen(source): "Could not open \(source)."
        }
    }
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
    @Published var appListFilter: AppListFilter = .all
    @Published var appSortOrder: AppSortOrder = .recommended
    @Published var appSortAscending = true
    @Published var homebrewSortOrder: HomebrewSortOrder = .recommended
    @Published var homebrewSortAscending = true
    @Published var updateListFilter: UpdateListFilter = .all
    @Published var updateSortOrder: UpdateSortOrder = .recommended
    @Published var updateSortAscending = true
    @Published var selectedPackageID: String?
    @Published var selectedDeveloperPackageID: String?
    @Published var selectedDeveloperVersion = ""
    @Published var selectedLocalModelID: String?
    @Published var availableDeveloperVersions: [String] = []
    @Published var isLoadingDeveloperVersions = false
    @Published var selectedApp: InstalledApp?
    @Published var updateInspectorSelection: UpdateInspectorSelection?
    @Published var searchText = ""
    @Published var isScanning = false
    @Published var lastChecked: Date?
    @Published private(set) var nextScheduledCheck: Date?
    @Published var errorMessage: String?
    @Published var scanWarnings: [ScanWarning] = []
    @Published var scanWarningsHidden = false
    @Published var workingIDs = Set<String>()
    @Published var pendingRevert: UpdateRecord?
    @Published var pendingRunningAppConfirmation: RunningAppConfirmation?
    @Published var isShowingBatchReview = false
    @Published private(set) var batchUpdateProgress: BatchUpdateProgress?
    @Published private(set) var runningBundleIdentifiers = Set<String>()
    @Published private(set) var runningApplicationPaths = Set<String>()
    @Published private(set) var diagnosticEntries = DiagnosticsStore.shared.entries()
    @Published var diagnosticsSearchText = ""
    @Published var diagnosticsLevelFilter = DiagnosticLevelFilter.all
    @Published var diagnosticsCategoryFilter: DiagnosticCategory?
    private var periodicTask: Task<Void, Never>?
    private var runningAppTask: Task<Void, Never>?
    private var didStart = false
    private let startedAt = Date()
    private var versionCache: [String: [String]] = [:]

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
        self.lastChecked = settings.lastCompletedScanDate
    }

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

    var availableBatchUpdateItems: [BatchUpdateItem] {
        let appUpdates = visibleUpdates
        let representedCaskTokens = Set(appUpdates.flatMap { $0.candidates.compactMap(\.homebrewToken) })
        let packages = homebrewPackages.filter {
            $0.isOutdated && !isExcluded($0) && !representedCaskTokens.contains($0.token)
        }
        return appUpdates.map(BatchUpdateItem.application)
            + packages.map(BatchUpdateItem.homebrew)
            + developerPackages.filter { $0.isOutdated && !isExcluded($0) }.map(BatchUpdateItem.developer)
            + visibleOutdatedLocalModels.map(BatchUpdateItem.model)
    }

    var filteredHomebrewPackages: [HomebrewPackage] {
        let scoped = homebrewPackages.filter { package in
            switch homebrewFilter {
            case .all: true
            case .updates: package.isOutdated && !isExcluded(package)
            case .requested: !package.isDependency
            case .dependencies: package.isDependency
            case .casks: package.kind == .cask
            case .unmapped: package.kind == .cask && matchingApp(for: package) == nil
            }
        }
        return matching(scoped, name: { $0.displayName })
    }

    func apps(for destination: SidebarDestination) -> [InstalledApp] {
        apps.filter { app in
            switch destination {
            case .allApps: true
            case .appStore: app.updateManagement == .appStore
            case .testFlight: app.updateManagement == .testFlight
            case .setapp: app.updateManagement == .setapp
            case .microsoftAutoUpdate: app.updateManagement == .microsoftAutoUpdate
            case .sparkle: app.sparkleFeedURL != nil
            case .homebrewApps: homebrewPackage(for: app) != nil
            case .github: app.githubRepository != nil
            case .noSource: sources(for: app).isEmpty && !app.updateManagement.isExternallyManaged
            default: false
            }
        }
    }

    func source(for app: InstalledApp) -> UpdateSource? {
        updates.first(where: { $0.app.id == app.id })?.source ?? sources(for: app).first
    }

    func sources(for app: InstalledApp) -> [UpdateSource] {
        var detected = Set<UpdateSource>()
        if let update = updates.first(where: { $0.app.id == app.id }) {
            detected.formUnion(update.candidates.map(\.source))
        }
        if app.updateManagement == .appStore { detected.insert(.appStore) }
        if homebrewPackage(for: app) != nil { detected.insert(.homebrew) }
        if app.sparkleFeedURL != nil { detected.insert(.sparkle) }
        if app.githubRepository != nil { detected.insert(.github) }
        let preferredOrder: [UpdateSource] = [.appStore, .homebrew, .sparkle, .github]
        let ordered = preferredOrder.filter(detected.contains)
        guard let primary = updates.first(where: { $0.app.id == app.id })?.source else { return ordered }
        return [primary] + ordered.filter { $0 != primary }
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
        for app in apps {
            settings.migrateExclusion(from: legacyExclusionKey(for: app), to: exclusionKey(for: app))
        }
        updates = mergedUpdates(from: report)
        switch report.homebrewInventoryStatus {
        case .disabled:
            homebrewPackages = []
            adoptableApps = []
        case .failed:
            break
        case .succeeded:
            homebrewPackages = report.homebrewPackages
            if report.homebrewCatalogStatus == .succeeded { adoptableApps = report.adoptableApps }
            else if report.homebrewCatalogStatus == .disabled { adoptableApps = [] }
        }
        macOSUpdates = mergedMacOSUpdates(from: report)
        updateHistory = await UpdateHistoryStore.shared.records()
        developerPackages = mergedDeveloperPackages(from: report)
        installedDeveloperManagers = report.installedDeveloperManagers
        localModels = mergedLocalModels(from: report)
        scanWarnings = report.warnings
        scanWarningsHidden = false
        if developerManagerFilter != "all", !installedDeveloperManagers.contains(where: { $0.rawValue == developerManagerFilter }) {
            developerManagerFilter = "all"
        }
        lastChecked = report.checkedAt
        settings.lastCompletedScanDate = report.checkedAt
        if selectedPackageID == nil { selectedPackageID = filteredHomebrewPackages.first?.id }
        if selectedDeveloperPackageID == nil || !developerPackages.contains(where: { $0.id == selectedDeveloperPackageID }) {
            selectedDeveloperPackageID = developerPackages.first?.id
            selectedDeveloperVersion = developerPackages.first?.latestVersion ?? ""
        }
        if selectedLocalModelID == nil || !localModels.contains(where: { $0.id == selectedLocalModelID }) {
            selectedLocalModelID = localModels.first?.id
        }
        isScanning = false
        refreshDiagnostics()
        notifyIfNeeded(previousCount: previousCount)
        if didStart { scheduleNextRefresh() }
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        refreshRunningApplications()
        runningAppTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refreshRunningApplications()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        if settings.checkOnLaunch { await scan() }
        scheduleNextRefresh()
    }

    func scheduleNextRefresh() {
        periodicTask?.cancel()
        let nextDate = settings.refreshInterval.nextDate(
            after: lastChecked ?? startedAt,
            dailyTimeMinutes: settings.dailyRefreshTimeMinutes
        )
        nextScheduledCheck = nextDate
        guard let nextDate else {
            periodicTask = nil
            return
        }
        periodicTask = Task { [weak self] in
            let delay = max(0, nextDate.timeIntervalSinceNow)
            do { try await Task.sleep(for: .seconds(delay)) }
            catch { return }
            guard !Task.isCancelled, let self else { return }
            await self.scan()
        }
    }

    func scanDeveloperPackages(manager: DeveloperPackageManager?) async {
        let identifier = "developer-scan-\(manager?.rawValue ?? "all")"
        guard !workingIDs.contains(identifier) else { return }
        workingIDs.insert(identifier)
        defer { workingIDs.remove(identifier) }
        let managers = manager.map { Set([$0]) } ?? settings.enabledDeveloperManagers
        let report = await DeveloperPackageClient().scan(
            enabledManagers: managers,
            includePrereleases: settings.includePrereleaseUpdates
        )
        let warnings = report.warnings.map { ScanWarning(source: .developerPackages, message: $0) }
        scanWarnings = (scanWarnings.filter { $0.source != .developerPackages } + warnings)
        scanWarningsHidden = false
        if let manager {
            guard !report.failedManagers.contains(manager) else { return }
            developerPackages.removeAll { $0.manager == manager }
            developerPackages.append(contentsOf: report.packages)
            developerPackages.sort { $0.manager.rawValue == $1.manager.rawValue ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.manager.rawValue < $1.manager.rawValue }
            if !installedDeveloperManagers.contains(manager), report.installedManagers.contains(manager) { installedDeveloperManagers.append(manager) }
            versionCache = versionCache.filter { !$0.key.hasPrefix("\(manager.rawValue):") }
        } else {
            let retained = developerPackages.filter { report.failedManagers.contains($0.manager) }
            developerPackages = (report.packages.filter { !report.failedManagers.contains($0.manager) } + retained).sorted(by: developerPackageOrder)
            installedDeveloperManagers = report.installedManagers
            versionCache.removeAll()
        }
        lastChecked = Date()
        settings.lastCompletedScanDate = lastChecked
        if let package = selectedDeveloperPackage { await loadAvailableVersions(for: package, force: true) }
    }

    func loadAvailableVersions(for package: DeveloperPackage, force: Bool = false) async {
        selectedDeveloperVersion = package.latestVersion
        let cacheKey = developerVersionCacheKey(for: package)
        if !force, let cached = versionCache[cacheKey] {
            availableDeveloperVersions = cached
            return
        }
        isLoadingDeveloperVersions = true
        availableDeveloperVersions = [package.latestVersion]
        let versions = await DeveloperPackageClient().availableVersions(
            for: package, includePrereleases: settings.includePrereleaseUpdates
        )
        versionCache[cacheKey] = versions
        if selectedDeveloperPackageID == package.id {
            availableDeveloperVersions = versions
            selectedDeveloperVersion = versions.contains(package.latestVersion)
                ? package.latestVersion
                : (versions.first ?? package.currentVersion)
            isLoadingDeveloperVersions = false
        }
    }

    private func developerVersionCacheKey(for package: DeveloperPackage) -> String {
        "\(package.id)|prereleases:\(settings.includePrereleaseUpdates)"
    }

    func performUpdate(_ update: AvailableUpdate) async {
        guard !workingIDs.contains(update.id) else { return }
        if update.homebrewToken != nil,
           queueRunningAppConfirmation(for: [update.app], action: .update(update)) { return }
        await performUpdateNow(update)
    }

    private func performUpdateNow(_ update: AvailableUpdate) async {
        if let token = update.homebrewToken {
            if let package = homebrewPackages.first(where: { $0.kind == .cask && $0.token == token }) {
                await updatePackageNow(package)
            } else if let item = adoptableApps.first(where: { $0.caskToken == token && $0.app.id == update.app.id }) {
                await updateAdoptableAppNow(item)
            } else {
                let record: UpdateRecord
                do {
                    record = try await UpdateHistoryStore.shared.prepareAppBackup(
                        app: update.app, toVersion: update.availableVersion, kind: .homebrew
                    )
                } catch {
                    errorMessage = "Could not create a rollback backup: \(error.localizedDescription)"
                    recordUpdateFailure(item: update.app.name, action: "Prepare rollback backup", error: error)
                    return
                }
                let succeeded = await perform(
                    id: update.id,
                    label: update.app.name,
                    metadata: updateDiagnosticMetadata(update)
                ) { try await HomebrewClient().upgradeCask(token: token) }
                if succeeded {
                    var historyError: Error?
                    do { try await UpdateHistoryStore.shared.add(record) }
                    catch { historyError = error }
                    await scan()
                    if let historyError { recordHistoryFailure(item: update.app.name, error: historyError) }
                    reconcileHomebrewUpdate(token: token, name: update.app.name)
                } else {
                    await UpdateHistoryStore.shared.discardBackup(for: record)
                }
            }
        } else if update.requiresInAppInstallation {
            let opened = NSWorkspace.shared.open(update.app.url)
            recordExternalUpdateAction(update, opened: opened)
        } else if let actionURL = update.actionURL {
            let opened = NSWorkspace.shared.open(actionURL)
            recordExternalUpdateAction(update, opened: opened)
        }
    }

    func updatePackage(_ package: HomebrewPackage) async {
        if package.kind == .cask,
           let app = matchingApp(for: package),
           queueRunningAppConfirmation(for: [app], action: .package(package)) { return }
        await updatePackageNow(package)
    }

    private func updatePackageNow(_ package: HomebrewPackage) async {
        let record = await recoveryRecord(for: package)
        if package.kind == .cask, matchingApp(for: package) != nil, record == nil { return }
        let succeeded = await perform(id: package.id, label: package.displayName, metadata: [
            "Source": "Homebrew",
            "From": package.installedVersion,
            "To": package.currentVersion
        ]) { try await HomebrewClient().upgrade(package) }
        if succeeded {
            var historyError: Error?
            if let record {
                do { try await UpdateHistoryStore.shared.add(record) }
                catch { historyError = error }
            }
            await scan()
            if let historyError { recordHistoryFailure(item: package.displayName, error: historyError) }
            reconcileHomebrewUpdate(token: package.token, name: package.displayName)
        } else if let record {
            await UpdateHistoryStore.shared.discardBackup(for: record)
        }
    }

    func updateAllPackages() async {
        let runningApps = homebrewPackages
            .filter { $0.isOutdated && !isExcluded($0) && $0.kind == .cask }
            .compactMap(matchingApp(for:))
        if queueRunningAppConfirmation(for: runningApps, action: .allPackages) { return }
        await updateAllPackagesNow()
    }

    private func updateAllPackagesNow() async {
        guard !workingIDs.contains("homebrew-all") else { return }
        let startedAt = Date()
        workingIDs.insert("homebrew-all")
        errorMessage = nil
        defer { workingIDs.remove("homebrew-all") }
        var failureMessage: String?
        let attempted = homebrewPackages.filter { $0.isOutdated && !isExcluded($0) }
        for package in attempted {
            let record = await recoveryRecord(for: package)
            if package.kind == .cask, matchingApp(for: package) != nil, record == nil { break }
            do {
                try await HomebrewClient().upgrade(package)
            } catch {
                if let record { await UpdateHistoryStore.shared.discardBackup(for: record) }
                failureMessage = error.localizedDescription
                break
            }
            if let record {
                do { try await UpdateHistoryStore.shared.add(record) }
                catch {
                    failureMessage = "\(package.displayName) was updated, but its rollback history could not be saved: \(error.localizedDescription)"
                    recordHistoryFailure(item: package.displayName, error: error)
                    break
                }
            }
        }
        await scan()
        if let failureMessage {
            errorMessage = failureMessage
        } else if scanWarnings.contains(where: { $0.source == .homebrew }) {
            errorMessage = "Homebrew finished, but Upkeep could not verify the result because Homebrew data did not refresh completely."
        } else {
            let remaining = attempted.filter { attemptedPackage in
                homebrewPackages.contains { $0.token == attemptedPackage.token && $0.kind == attemptedPackage.kind && $0.isOutdated }
            }
            if !remaining.isEmpty {
                errorMessage = "Homebrew finished, but \(remaining.map(\.displayName).joined(separator: ", ")) still report available updates."
            }
        }
        DiagnosticsStore.shared.record(
            errorMessage == nil ? .info : .error,
            category: .update,
            errorMessage == nil ? "Homebrew batch update completed" : "Homebrew batch update needs attention",
            metadata: [
                "Attempted": "\(attempted.count)",
                "Duration": diagnosticDuration(since: startedAt),
                "Result": errorMessage ?? "All attempted packages refreshed successfully"
            ]
        )
        refreshDiagnostics()
    }

    func adopt(_ item: AdoptableApp) async {
        if queueRunningAppConfirmation(for: [item.app], action: .adopt(item)) { return }
        await adoptNow(item)
    }

    private func adoptNow(_ item: AdoptableApp) async {
        let succeeded = await perform(id: item.id, label: item.app.name, metadata: [
            "Source": "Homebrew adoption",
            "Installed": item.app.installedVersion,
            "Catalog": item.caskVersion
        ]) { try await HomebrewClient().adopt(item) }
        if succeeded { await scan() }
    }

    func updateAdoptableApp(_ item: AdoptableApp) async {
        if queueRunningAppConfirmation(for: [item.app], action: .updateAdoptable(item)) { return }
        await updateAdoptableAppNow(item)
    }

    private func updateAdoptableAppNow(_ item: AdoptableApp) async {
        let record: UpdateRecord
        do {
            record = try await UpdateHistoryStore.shared.prepareAppBackup(
                app: item.app, toVersion: item.caskVersion, kind: .homebrew
            )
        } catch {
            errorMessage = "Could not create a rollback backup: \(error.localizedDescription)"
            recordUpdateFailure(item: item.app.name, action: "Prepare rollback backup", error: error)
            return
        }
        let succeeded = await perform(id: item.id, label: item.app.name, metadata: [
            "Source": "Homebrew adoption",
            "From": item.app.installedVersion,
            "To": item.caskVersion
        ]) { try await HomebrewClient().installOrReplace(item) }
        if succeeded {
            var historyError: Error?
            do { try await UpdateHistoryStore.shared.add(record) }
            catch { historyError = error }
            await scan()
            if let historyError { recordHistoryFailure(item: item.app.name, error: historyError) }
            reconcileHomebrewUpdate(token: item.caskToken, name: item.app.name)
        } else {
            await UpdateHistoryStore.shared.discardBackup(for: record)
        }
    }

    func isRunning(_ app: InstalledApp) -> Bool {
        if let bundleIdentifier = app.bundleIdentifier,
           runningBundleIdentifiers.contains(bundleIdentifier) { return true }
        return runningApplicationPaths.contains(canonicalPath(app.url))
    }

    func openUpdateManager(for app: InstalledApp) {
        let fileManager = FileManager.default
        let target: URL?
        switch app.updateManagement {
        case .testFlight:
            let installed = URL(fileURLWithPath: "/Applications/TestFlight.app")
            target = fileManager.fileExists(atPath: installed.path)
                ? installed
                : URL(string: "macappstore://apps.apple.com/app/testflight/id899247664")
        case .setapp:
            let installed = URL(fileURLWithPath: "/Applications/Setapp.app")
            target = fileManager.fileExists(atPath: installed.path)
                ? installed
                : URL(string: "https://setapp.com/apps")
        case .microsoftAutoUpdate:
            let installed = URL(fileURLWithPath: "/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app")
            target = fileManager.fileExists(atPath: installed.path) ? installed : app.url
        case .appStore:
            target = URL(string: "macappstore://showUpdatesPage")
        case .direct:
            target = app.url
        }
        guard let target, NSWorkspace.shared.open(target) else {
            errorMessage = "Could not open \(app.updateManagement.rawValue)."
            return
        }
    }

    func confirmRunningAppUpdate(_ confirmation: RunningAppConfirmation) async {
        pendingRunningAppConfirmation = nil
        do {
            try await quitRunningApplications(for: confirmation.apps)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        switch confirmation.action {
        case let .update(update): await performUpdateNow(update)
        case let .package(package): await updatePackageNow(package)
        case let .adopt(item): await adoptNow(item)
        case let .updateAdoptable(item): await updateAdoptableAppNow(item)
        case .allPackages: await updateAllPackagesNow()
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
        let succeeded = await perform(id: package.id, label: package.name, metadata: [
            "Source": package.manager.rawValue,
            "From": package.currentVersion,
            "To": selectedVersion
        ]) {
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
        let report = await LocalModelClient().scan()
        var merged = Dictionary(uniqueKeysWithValues: report.models.map { ($0.id, $0) })
        for previous in localModels where report.failedModelIDs.contains(previous.id) || report.failedRuntimes.contains(previous.runtime) {
            merged[previous.id] = previous
        }
        localModels = merged.values.sorted(by: localModelOrder)
        scanWarnings = scanWarnings.filter { $0.source != .localModels }
            + report.warnings.map { ScanWarning(source: .localModels, message: $0) }
        scanWarningsHidden = false
        if selectedLocalModelID == nil || !localModels.contains(where: { $0.id == selectedLocalModelID }) {
            selectedLocalModelID = localModels.first?.id
        }
        lastChecked = Date()
        settings.lastCompletedScanDate = lastChecked
    }

    func updateLocalModel(_ model: LocalLLMModel) async {
        let succeeded = await perform(id: model.id, label: model.name, metadata: [
            "Source": model.runtime.rawValue,
            "From": model.installedRevision,
            "To": model.latestRevision
        ]) { try await LocalModelClient().update(model) }
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

    func performBatchUpdates(_ items: [BatchUpdateItem]) async -> BatchUpdateSummary {
        let batchID = "unified-update-batch"
        guard !items.isEmpty, !workingIDs.contains(batchID) else { return BatchUpdateSummary(results: []) }
        workingIDs.insert(batchID)
        errorMessage = nil
        defer {
            workingIDs.remove(batchID)
            batchUpdateProgress = nil
        }

        let runningApps = batchRunningApps(for: items)
        if !runningApps.isEmpty { try? await quitRunningApplications(for: runningApps) }

        var results: [BatchUpdateResult] = []
        for (index, item) in items.enumerated() {
            batchUpdateProgress = BatchUpdateProgress(completed: index, total: items.count, itemName: item.name)
            if let app = batchApp(for: item), isRunning(app) {
                results.append(BatchUpdateResult(
                    item: item,
                    outcome: .failed,
                    detail: "\(app.name) could not be quit. Quit it manually and try again."
                ))
                continue
            }
            let result = await performBatchItem(item)
            results.append(result)
            DiagnosticsStore.shared.record(
                result.outcome == .failed ? .error : .info,
                category: .update,
                "Batch item \(result.outcome.rawValue.lowercased())",
                metadata: [
                    "Item": item.name,
                    "From": item.currentVersion,
                    "To": item.availableVersion,
                    "Detail": result.detail
                ]
            )
        }
        batchUpdateProgress = BatchUpdateProgress(completed: items.count, total: items.count, itemName: "Refreshing updates")

        if results.contains(where: { $0.outcome == .updated }) { await scan() }
        refreshDiagnostics()
        return BatchUpdateSummary(results: results)
    }

    private func performBatchItem(_ item: BatchUpdateItem) async -> BatchUpdateResult {
        let workID = "batch|\(item.id)"
        workingIDs.insert(workID)
        defer { workingIDs.remove(workID) }

        do {
            switch item {
            case let .application(update):
                guard let token = update.homebrewToken else {
                    let target = update.requiresInAppInstallation ? update.app.url : update.actionURL
                    guard let target, NSWorkspace.shared.open(target) else {
                        throw BatchUpdateError.couldNotOpen(update.source.rawValue)
                    }
                    return BatchUpdateResult(
                        item: item,
                        outcome: .opened,
                        detail: update.requiresInAppInstallation
                            ? "Opened \(update.app.name). Complete the update with its built-in updater."
                            : "Opened \(update.source.rawValue). Complete the update there."
                    )
                }
                if let package = homebrewPackages.first(where: { $0.kind == .cask && $0.token == token }) {
                    try await upgradeBatchPackage(package)
                } else if let adoptable = adoptableApps.first(where: { $0.caskToken == token && $0.app.id == update.app.id }) {
                    let record = try await UpdateHistoryStore.shared.prepareAppBackup(
                        app: adoptable.app, toVersion: adoptable.caskVersion, kind: .homebrew
                    )
                    do { try await HomebrewClient().installOrReplace(adoptable) }
                    catch {
                        await UpdateHistoryStore.shared.discardBackup(for: record)
                        throw error
                    }
                    try await UpdateHistoryStore.shared.add(record)
                } else {
                    let record = try await UpdateHistoryStore.shared.prepareAppBackup(
                        app: update.app, toVersion: update.availableVersion, kind: .homebrew
                    )
                    do { try await HomebrewClient().upgradeCask(token: token) }
                    catch {
                        await UpdateHistoryStore.shared.discardBackup(for: record)
                        throw error
                    }
                    try await UpdateHistoryStore.shared.add(record)
                }

            case let .homebrew(package):
                try await upgradeBatchPackage(package)

            case let .developer(package):
                try await DeveloperPackageClient().install(package, version: package.latestVersion)
                let record = UpdateRecord(
                    id: UUID(), date: Date(), name: package.name,
                    fromVersion: package.currentVersion, toVersion: package.latestVersion,
                    kind: .developer, originalAppPath: nil, backupPath: nil,
                    recoveryNote: "Package-manager updates do not have a universal rollback mechanism. Reinstall the previous version with \(package.manager.rawValue) if needed."
                )
                try? await UpdateHistoryStore.shared.add(record)

            case let .model(model):
                try await LocalModelClient().update(model)
                let record = UpdateRecord(
                    id: UUID(), date: Date(), name: model.name,
                    fromVersion: model.installedRevision, toVersion: model.latestRevision,
                    kind: .model, originalAppPath: nil, backupPath: nil,
                    recoveryNote: "Model files are managed by \(model.runtime.rawValue). Download the earlier model revision again if rollback is required."
                )
                try? await UpdateHistoryStore.shared.add(record)
            }
            return BatchUpdateResult(item: item, outcome: .updated, detail: "Updated to \(item.availableVersion).")
        } catch {
            return BatchUpdateResult(item: item, outcome: .failed, detail: error.localizedDescription)
        }
    }

    private func upgradeBatchPackage(_ package: HomebrewPackage) async throws {
        let record: UpdateRecord
        if package.kind == .cask, let app = matchingApp(for: package) {
            record = try await UpdateHistoryStore.shared.prepareAppBackup(
                app: app, toVersion: package.currentVersion, kind: .homebrew
            )
        } else {
            record = UpdateRecord(
                id: UUID(), date: Date(), name: package.displayName,
                fromVersion: package.installedVersion, toVersion: package.currentVersion,
                kind: .homebrew, originalAppPath: nil, backupPath: nil,
                recoveryNote: "Homebrew formula versions cannot always be rolled back automatically. Restore from Time Machine or install a versioned formula when available."
            )
        }
        do { try await HomebrewClient().upgrade(package) }
        catch {
            await UpdateHistoryStore.shared.discardBackup(for: record)
            throw error
        }
        try await UpdateHistoryStore.shared.add(record)
    }

    private func batchRunningApps(for items: [BatchUpdateItem]) -> [InstalledApp] {
        refreshRunningApplications()
        return Dictionary(uniqueKeysWithValues: items.compactMap(batchApp(for:)).filter(isRunning).map { ($0.id, $0) })
            .values
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func batchApp(for item: BatchUpdateItem) -> InstalledApp? {
        switch item {
        case let .application(update): return update.homebrewToken == nil ? nil : update.app
        case let .homebrew(package): return package.kind == .cask ? matchingApp(for: package) : nil
        case .developer, .model: return nil
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

    func skip(_ update: AvailableUpdate, duration: UpdateExclusionDuration? = nil) {
        exclude(.skipped, key: exclusionKey(for: update.app), name: update.app.name, category: "App", version: update.availableVersion, duration: duration)
    }

    func ignore(_ app: InstalledApp, duration: UpdateExclusionDuration? = nil) {
        exclude(.ignored, key: exclusionKey(for: app), name: app.name, category: "App", version: nil, duration: duration)
    }

    func skip(_ package: HomebrewPackage, duration: UpdateExclusionDuration? = nil) {
        exclude(.skipped, key: exclusionKey(for: package), name: package.displayName, category: "Homebrew", version: package.currentVersion, duration: duration)
    }

    func ignore(_ package: HomebrewPackage, duration: UpdateExclusionDuration? = nil) {
        exclude(.ignored, key: exclusionKey(for: package), name: package.displayName, category: "Homebrew", version: nil, duration: duration)
    }

    func skip(_ package: DeveloperPackage, duration: UpdateExclusionDuration? = nil) {
        exclude(.skipped, key: exclusionKey(for: package), name: package.name, category: package.manager.rawValue, version: package.latestVersion, duration: duration)
    }

    func ignore(_ package: DeveloperPackage, duration: UpdateExclusionDuration? = nil) {
        exclude(.ignored, key: exclusionKey(for: package), name: package.name, category: package.manager.rawValue, version: nil, duration: duration)
    }

    func skip(_ model: LocalLLMModel, duration: UpdateExclusionDuration? = nil) {
        exclude(.skipped, key: exclusionKey(for: model), name: model.name, category: model.runtime.rawValue, version: model.latestRevision, duration: duration)
    }

    func ignore(_ model: LocalLLMModel, duration: UpdateExclusionDuration? = nil) {
        exclude(.ignored, key: exclusionKey(for: model), name: model.name, category: model.runtime.rawValue, version: nil, duration: duration)
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
        let succeeded = await perform(id: record.id.uuidString, label: "Restore \(record.name)", metadata: [
            "From": record.toVersion,
            "To": record.fromVersion,
            "Source": "History"
        ]) {
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

    private func exclude(_ mode: UpdateExclusionMode, key: String, name: String, category: String, version: String?, duration: UpdateExclusionDuration?) {
        if mode == .skipped, let version { settings.skip(key: key, name: name, category: category, version: version, duration: duration) }
        else { settings.ignore(key: key, name: name, category: category, duration: duration) }
        objectWillChange.send()
    }

    private func exclusionKey(for app: InstalledApp) -> String { app.updateExclusionKey }
    private func legacyExclusionKey(for app: InstalledApp) -> String { "app|\(app.id)" }
    private func exclusionKey(for package: HomebrewPackage) -> String { "homebrew|\(package.id)" }
    private func exclusionKey(for package: DeveloperPackage) -> String { "developer|\(package.id)" }
    private func exclusionKey(for model: LocalLLMModel) -> String { "model|\(model.id)" }

    private func perform(
        id: String,
        label: String,
        metadata: [String: String] = [:],
        operation: () async throws -> Void
    ) async -> Bool {
        guard !workingIDs.contains(id) else { return false }
        let startedAt = Date()
        workingIDs.insert(id)
        errorMessage = nil
        defer { workingIDs.remove(id) }
        do {
            try await operation()
            DiagnosticsStore.shared.record(.info, category: .update, "Update action completed", metadata: metadata.merging([
                "Item": label,
                "Duration": diagnosticDuration(since: startedAt)
            ]) { _, new in new })
            refreshDiagnostics()
            return true
        } catch {
            errorMessage = error.localizedDescription
            DiagnosticsStore.shared.record(.error, category: .update, "Update action failed", metadata: metadata.merging([
                "Item": label,
                "Duration": diagnosticDuration(since: startedAt),
                "Error": error.localizedDescription
            ]) { _, new in new })
            refreshDiagnostics()
            return false
        }
    }

    func refreshDiagnostics() {
        diagnosticEntries = DiagnosticsStore.shared.entries()
    }

    func clearDiagnostics() {
        DiagnosticsStore.shared.clear()
        refreshDiagnostics()
    }

    func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.title = "Export Upkeep Diagnostics"
        panel.nameFieldStringValue = "Upkeep Diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DiagnosticsStore.shared.exportText().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "Could not export diagnostics: \(error.localizedDescription)"
        }
    }

    private func recordExternalUpdateAction(_ update: AvailableUpdate, opened: Bool) {
        DiagnosticsStore.shared.record(
            opened ? .info : .error,
            category: .update,
            opened ? "External update action opened" : "External update action could not open",
            metadata: [
                "Item": update.app.name,
                "Source": update.source.rawValue,
                "Installed": update.app.installedVersion,
                "Available": update.availableVersion
            ]
        )
        if !opened { errorMessage = "Could not open the update action for \(update.app.name)." }
        refreshDiagnostics()
    }

    private func updateDiagnosticMetadata(_ update: AvailableUpdate) -> [String: String] {
        [
            "Source": update.source.rawValue,
            "From": update.app.installedVersion,
            "To": update.availableVersion
        ]
    }

    private func recordUpdateFailure(item: String, action: String, error: Error) {
        DiagnosticsStore.shared.record(.error, category: .update, "Update preparation failed", metadata: [
            "Item": item,
            "Action": action,
            "Error": error.localizedDescription
        ])
        refreshDiagnostics()
    }

    private func recordHistoryFailure(item: String, error: Error) {
        errorMessage = "\(item) was updated, but its rollback history could not be saved: \(error.localizedDescription)"
        DiagnosticsStore.shared.record(.error, category: .update, "Rollback history could not be saved", metadata: [
            "Item": item,
            "Error": error.localizedDescription
        ])
        refreshDiagnostics()
    }

    private func recoveryRecord(for package: HomebrewPackage) async -> UpdateRecord? {
        if package.kind == .cask, let app = matchingApp(for: package) {
            do {
                return try await UpdateHistoryStore.shared.prepareAppBackup(
                    app: app, toVersion: package.currentVersion, kind: .homebrew
                )
            } catch {
                errorMessage = "Could not create a rollback backup: \(error.localizedDescription)"
                recordUpdateFailure(item: package.displayName, action: "Prepare rollback backup", error: error)
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

    func isUnmapped(_ package: HomebrewPackage) -> Bool {
        package.kind == .cask && matchingApp(for: package) == nil
    }

    func homebrewPackage(for app: InstalledApp) -> HomebrewPackage? {
        let name = normalize(app.name)
        return homebrewPackages.first { $0.kind == .cask && (normalize($0.displayName) == name || normalize($0.token) == name) }
    }

    func homebrewPackageApp(for package: HomebrewPackage) -> InstalledApp? {
        matchingApp(for: package)
    }

    private func queueRunningAppConfirmation(for apps: [InstalledApp], action: RunningAppConfirmation.Action) -> Bool {
        refreshRunningApplications()
        let runningApps = Dictionary(uniqueKeysWithValues: apps.filter(isRunning).map { ($0.id, $0) })
            .values
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !runningApps.isEmpty else { return false }
        pendingRunningAppConfirmation = RunningAppConfirmation(apps: runningApps, action: action)
        return true
    }

    private func refreshRunningApplications() {
        let runningApplications = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        let identifiers = Set(runningApplications.compactMap(\.bundleIdentifier))
        let paths = Set(runningApplications.compactMap(\.bundleURL).map(canonicalPath))
        if identifiers != runningBundleIdentifiers { runningBundleIdentifiers = identifiers }
        if paths != runningApplicationPaths { runningApplicationPaths = paths }
    }

    private func quitRunningApplications(for apps: [InstalledApp]) async throws {
        refreshRunningApplications()
        let identifiers = Set(apps.compactMap(\.bundleIdentifier))
        let paths = Set(apps.map { canonicalPath($0.url) })
        let targets = NSWorkspace.shared.runningApplications.filter { runningApplication in
            if let identifier = runningApplication.bundleIdentifier, identifiers.contains(identifier) { return true }
            if let url = runningApplication.bundleURL, paths.contains(canonicalPath(url)) { return true }
            return false
        }

        for target in targets where !target.isTerminated { target.terminate() }

        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(250))
            refreshRunningApplications()
            if apps.allSatisfy({ !isRunning($0) }) { return }
        }

        throw RunningAppUpdateError.couldNotQuit(apps.filter(isRunning).map(\.name))
    }

    private func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func matching<T>(_ values: [T], name: (T) -> String) -> [T] {
        searchText.isEmpty ? values : values.filter { name($0).localizedCaseInsensitiveContains(searchText) }
    }

    private func normalize(_ value: String) -> String { value.lowercased().filter(\.isLetter) }

    private func diagnosticDuration(since date: Date) -> String {
        String(format: "%.0f ms", Date().timeIntervalSince(date) * 1_000)
    }

    private func mergedUpdates(from report: ScanReport) -> [AvailableUpdate] {
        var merged = Dictionary(uniqueKeysWithValues: report.updates.map { ($0.id, $0) })
        let currentApps = Dictionary(uniqueKeysWithValues: report.apps.map { ($0.id, $0) })

        for previous in updates {
            guard let currentApp = currentApps[previous.id] else { continue }
            let failedSources = report.failedAppSources[previous.app.id] ?? []
            let retained = Self.retainableCandidates(
                in: previous, currentApp: currentApp, failedSources: failedSources
            )
            guard !retained.isEmpty else { continue }
            let retainedUpdate = AvailableUpdate(app: currentApp, candidates: retained)
            if let fresh = merged[previous.id] {
                merged[previous.id] = AvailableUpdate.merging([fresh, retainedUpdate])
            } else {
                merged[previous.id] = retainedUpdate
            }
        }

        if report.homebrewInventoryStatus == .failed {
            for previous in updates {
                guard let currentApp = currentApps[previous.id] else { continue }
                let retained = Self.retainableCandidates(
                    in: previous, currentApp: currentApp, failedSources: [.homebrew]
                ).filter { !$0.requiresHomebrewAdoption }
                guard !retained.isEmpty else { continue }
                let retainedUpdate = AvailableUpdate(app: currentApp, candidates: retained)
                if let fresh = merged[previous.id] {
                    merged[previous.id] = AvailableUpdate.merging([fresh, retainedUpdate])
                } else {
                    merged[previous.id] = retainedUpdate
                }
            }
        } else if report.homebrewCatalogStatus == .failed {
            for previous in updates {
                guard let currentApp = currentApps[previous.id] else { continue }
                let retained = Self.retainableCandidates(
                    in: previous, currentApp: currentApp, failedSources: [.homebrew]
                ).filter(\.requiresHomebrewAdoption)
                guard !retained.isEmpty else { continue }
                let retainedUpdate = AvailableUpdate(app: currentApp, candidates: retained)
                if let fresh = merged[previous.id] {
                    merged[previous.id] = AvailableUpdate.merging([fresh, retainedUpdate])
                } else {
                    merged[previous.id] = retainedUpdate
                }
            }
        }

        return merged.values.sorted { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending }
    }

    static func retainableCandidates(
        in previous: AvailableUpdate,
        currentApp: InstalledApp,
        failedSources: Set<UpdateSource>
    ) -> [UpdateCandidate] {
        previous.candidates.filter {
            failedSources.contains($0.source)
                && VersionComparator.isNewer($0.availableVersion, than: currentApp.installedVersion)
        }
    }

    private func mergedMacOSUpdates(from report: ScanReport) -> [MacOSUpdate] {
        let currentUpdates = report.macOSUpdates.filter { !$0.isFullInstaller }
        let currentInstallers = report.macOSUpdates.filter(\.isFullInstaller)
        let updatesPart: [MacOSUpdate] = report.macOSUpdatesStatus == .failed
            ? macOSUpdates.filter { !$0.isFullInstaller }
            : currentUpdates
        let installersPart: [MacOSUpdate] = report.macOSInstallersStatus == .failed
            ? macOSUpdates.filter(\.isFullInstaller)
            : currentInstallers
        return updatesPart + installersPart
    }

    private func mergedDeveloperPackages(from report: ScanReport) -> [DeveloperPackage] {
        let retained = developerPackages.filter { report.failedDeveloperManagers.contains($0.manager) }
        let fresh = report.developerPackages.filter { !report.failedDeveloperManagers.contains($0.manager) }
        return (fresh + retained).sorted(by: developerPackageOrder)
    }

    private func mergedLocalModels(from report: ScanReport) -> [LocalLLMModel] {
        guard report.localModelsStatus != .disabled else { return [] }
        var merged = Dictionary(uniqueKeysWithValues: report.localModels.map { ($0.id, $0) })
        for previous in localModels where report.failedLocalModelIDs.contains(previous.id)
            || report.failedLocalModelRuntimes.contains(previous.runtime) {
            merged[previous.id] = previous
        }
        return merged.values.sorted(by: localModelOrder)
    }

    private func developerPackageOrder(_ lhs: DeveloperPackage, _ rhs: DeveloperPackage) -> Bool {
        if lhs.manager != rhs.manager { return lhs.manager.rawValue < rhs.manager.rawValue }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private func localModelOrder(_ lhs: LocalLLMModel, _ rhs: LocalLLMModel) -> Bool {
        if lhs.runtime != rhs.runtime { return lhs.runtime.rawValue < rhs.runtime.rawValue }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private func reconcileHomebrewUpdate(token: String, name: String) {
        if let package = homebrewPackages.first(where: { $0.token == token }) {
            if package.isOutdated {
                errorMessage = "Homebrew completed the command, but \(name) still reports \(package.currentVersion) as available."
            }
            return
        }
        if scanWarnings.contains(where: { $0.source == .homebrew }) {
            errorMessage = "Homebrew completed the update for \(name), but Upkeep could not fully refresh Homebrew data. Check the scan warning and refresh again."
        }
    }
}
