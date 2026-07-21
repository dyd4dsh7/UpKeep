import AppKit
import Foundation

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
    @Published var apps: [InstalledApp] = []
    @Published var updates: [AvailableUpdate] = []
    @Published var homebrewPackages: [HomebrewPackage] = []
    @Published var adoptableApps: [AdoptableApp] = []
    @Published var macOSUpdates: [MacOSUpdate] = []
    @Published var updateHistory: [UpdateRecord] = []
    @Published var developerPackages: [DeveloperPackage] = []
    @Published var developerManagerFilter = "all"
    @Published var installedDeveloperManagers: [DeveloperPackageManager] = []
    @Published var selection: SidebarDestination = .updates
    @Published var homebrewFilter: HomebrewFilter = .all
    @Published var selectedPackageID: String?
    @Published var selectedDeveloperPackageID: String?
    @Published var selectedDeveloperVersion = ""
    @Published var selectedApp: InstalledApp?
    @Published var searchText = ""
    @Published var isScanning = false
    @Published var lastChecked: Date?
    @Published var errorMessage: String?
    @Published var workingIDs = Set<String>()
    @Published var pendingRevert: UpdateRecord?

    var filteredUpdates: [AvailableUpdate] { matching(updates, name: { $0.app.name }) }
    var filteredApps: [InstalledApp] { matching(apps, name: \InstalledApp.name) }
    var filteredAdoptableApps: [AdoptableApp] { matching(adoptableApps, name: { $0.app.name }) }
    var outdatedPackageCount: Int { homebrewPackages.count(where: \.isOutdated) }
    var outdatedDeveloperPackageCount: Int { developerPackages.count(where: \.isOutdated) }
    var filteredDeveloperPackages: [DeveloperPackage] {
        matching(developerPackages.filter { developerManagerFilter == "all" || $0.manager.rawValue == developerManagerFilter }, name: { $0.name })
    }

    var filteredHomebrewPackages: [HomebrewPackage] {
        let scoped = homebrewPackages.filter { package in
            switch homebrewFilter {
            case .all: true
            case .updates: package.isOutdated
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
        case .updates: updates.count + outdatedPackageCount + macOSUpdates.count(where: { !$0.isFullInstaller }) + outdatedDeveloperPackageCount
        case .allApps: apps.count
        case .adoptable: adoptableApps.count
        case .homebrewPackages: homebrewPackages.count
        case .macOSUpdates: macOSUpdates.count
        case .history: updateHistory.count
        case .developerPackages: developerPackages.count
        case .changelog: 0
        default: apps(for: destination).count
        }
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil
        let report = await UpdateScanner().scan()
        apps = report.apps
        updates = report.updates
        homebrewPackages = report.homebrewPackages
        adoptableApps = report.adoptableApps
        macOSUpdates = report.macOSUpdates
        updateHistory = await UpdateHistoryStore.shared.records()
        developerPackages = report.developerPackages
        installedDeveloperManagers = report.installedDeveloperManagers
        if developerManagerFilter != "all", !installedDeveloperManagers.contains(where: { $0.rawValue == developerManagerFilter }) {
            developerManagerFilter = "all"
        }
        lastChecked = report.checkedAt
        if selectedPackageID == nil { selectedPackageID = filteredHomebrewPackages.first?.id }
        if selectedDeveloperPackageID == nil || !developerPackages.contains(where: { $0.id == selectedDeveloperPackageID }) {
            selectedDeveloperPackageID = developerPackages.first?.id
            selectedDeveloperVersion = developerPackages.first?.latestVersion ?? ""
        }
        isScanning = false
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
        for package in homebrewPackages where package.isOutdated {
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
