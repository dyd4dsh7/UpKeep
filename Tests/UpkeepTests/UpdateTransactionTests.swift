import Foundation
import Testing
@testable import Upkeep

@MainActor
@Test func updatedApplicationsAreReopenedAtTheirInstalledPaths() async throws {
    let defaultsName = "UpdateRelaunchTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: defaultsName))
    defer { defaults.removePersistentDomain(forName: defaultsName) }
    let app = InstalledApp(
        name: "Example",
        bundleIdentifier: "com.example.relaunch",
        installedVersion: "1.0.0",
        buildVersion: nil,
        url: URL(fileURLWithPath: "/Applications/Example.app"),
        sparkleFeedURL: nil,
        githubRepository: nil,
        hasAppStoreReceipt: false
    )
    let opener = RecordingTransactionExternalOpener()
    let recorder = TransactionRecorder()
    let store = UpkeepStore(
        settings: AppSettings(defaults: defaults),
        dependencies: UpkeepDependencies(
            scanner: TransactionScanner(recorder: recorder),
            applicationDiscovery: TransactionDiscovery(app: app),
            homebrew: TransactionHomebrew(recorder: recorder),
            developerPackages: TransactionDeveloperPackages(),
            localModels: TransactionLocalModels(),
            history: TransactionHistory(recorder: recorder),
            externalOpener: opener
        )
    )

    store.reopenApplications([app])

    #expect(opener.openedURLs == [app.url])
    #expect(store.errorMessage == nil)
}

@MainActor
@Test func applicationUpdateTransactionBacksUpExecutesRecordsRescansAndRestores() async throws {
    let recorder = TransactionRecorder()
    let scanner = TransactionScanner(recorder: recorder)
    let homebrew = TransactionHomebrew(recorder: recorder)
    let history = TransactionHistory(recorder: recorder)
    let defaultsName = "UpdateTransactionTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: defaultsName))
    defer { defaults.removePersistentDomain(forName: defaultsName) }

    let app = InstalledApp(
        name: "Example",
        bundleIdentifier: "com.example.transaction",
        installedVersion: "1.0.0",
        buildVersion: nil,
        url: URL(fileURLWithPath: "/Applications/Example.app"),
        sparkleFeedURL: nil,
        githubRepository: nil,
        hasAppStoreReceipt: false
    )
    let package = HomebrewPackage(
        token: "example",
        displayName: "Example",
        description: nil,
        homepage: nil,
        license: nil,
        installedVersion: "1.0.0",
        currentVersion: "1.1.0",
        kind: .cask,
        isOutdated: true,
        isDependency: false,
        dependencies: []
    )
    let update = AvailableUpdate(
        app: app,
        availableVersion: "1.1.0",
        source: .homebrew,
        releaseNotes: nil,
        actionURL: nil,
        homebrewToken: package.token
    )
    let dependencies = UpkeepDependencies(
        scanner: scanner,
        applicationDiscovery: TransactionDiscovery(app: app, installedVersion: "1.1.0"),
        homebrew: homebrew,
        developerPackages: TransactionDeveloperPackages(),
        localModels: TransactionLocalModels(),
        history: history,
        externalOpener: TransactionExternalOpener()
    )
    let store = UpkeepStore(
        settings: AppSettings(defaults: defaults),
        dependencies: dependencies
    )
    store.apps = [app]
    store.updates = [update]
    store.homebrewPackages = [package]

    await store.performUpdate(update)
    let authorization = try #require(store.pendingHomebrewAuthorizationConfirmation)
    #expect(authorization.itemName == app.name)
    #expect(await recorder.events().isEmpty)
    await store.confirmHomebrewAuthorization(authorization)

    let savedRecord = try #require(await history.records().first)
    #expect(await recorder.events() == ["backup", "upgrade", "history"])
    #expect(store.errorMessage == nil)
    #expect(store.updateHistory == [savedRecord])

    await store.revert(savedRecord)

    #expect(await recorder.events() == [
        "backup", "upgrade", "history", "restore", "scan"
    ])
    #expect(!store.isWorking(.historyRestore(savedRecord.id)))
}

@MainActor
@Test func applicationUpdateShowsProgressWhilePreparingItsRollbackBackup() async throws {
    let recorder = TransactionRecorder()
    let history = PausingTransactionHistory()
    let defaultsName = "UpdateProgressTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: defaultsName))
    defer { defaults.removePersistentDomain(forName: defaultsName) }

    let app = InstalledApp(
        name: "Adobe Example",
        bundleIdentifier: "com.adobe.example",
        installedVersion: "1.0.0",
        buildVersion: nil,
        url: URL(fileURLWithPath: "/Applications/Adobe Example.app"),
        sparkleFeedURL: nil,
        githubRepository: nil,
        hasAppStoreReceipt: false
    )
    let package = HomebrewPackage(
        token: "adobe-example",
        displayName: "Adobe Example",
        description: nil,
        homepage: nil,
        license: nil,
        installedVersion: "1.0.0",
        currentVersion: "1.1.0",
        kind: .cask,
        isOutdated: true,
        isDependency: false,
        dependencies: []
    )
    let update = AvailableUpdate(
        app: app,
        availableVersion: package.currentVersion,
        source: .homebrew,
        releaseNotes: nil,
        actionURL: nil,
        homebrewToken: package.token
    )
    let store = UpkeepStore(
        settings: AppSettings(defaults: defaults),
        dependencies: UpkeepDependencies(
            scanner: TransactionScanner(recorder: recorder),
            applicationDiscovery: TransactionDiscovery(app: app),
            homebrew: TransactionHomebrew(recorder: recorder),
            developerPackages: TransactionDeveloperPackages(),
            localModels: TransactionLocalModels(),
            history: history,
            externalOpener: TransactionExternalOpener()
        )
    )
    store.apps = [app]
    store.updates = [update]
    store.homebrewPackages = [package]

    await store.performUpdate(update)
    let authorization = try #require(store.pendingHomebrewAuthorizationConfirmation)
    #expect(store.updatePhase(for: .applicationUpdate(update.id)) == .confirmation)
    #expect(store.updatePhase(for: .homebrewPackage(package.id)) == .confirmation)
    store.pendingHomebrewAuthorizationConfirmation = nil
    #expect(store.updatePhase(for: .applicationUpdate(update.id)) == nil)
    let updateTask = Task { await store.confirmHomebrewAuthorization(authorization) }
    await history.waitUntilBackupStarts()

    #expect(store.isUpdating(update))
    #expect(store.isWorking(.applicationUpdate(update.id)))
    #expect(store.isWorking(.homebrewPackage(package.id)))
    #expect(store.updatePhase(for: .applicationUpdate(update.id)) == .backingUp)
    #expect(store.updatePhase(for: .homebrewPackage(package.id)) == .backingUp)

    await history.resumeBackup()
    await updateTask.value

    #expect(!store.isUpdating(update))
    #expect(!store.isWorking(.homebrewPackage(package.id)))
    #expect(store.updatePhase(for: .applicationUpdate(update.id)) == nil)
    #expect(store.updateExecutionState.activities.isEmpty)
}

@MainActor
@Test func homebrewAdoptionShowsProgressAfterAuthorizationUntilCommandCompletes() async throws {
    let homebrew = PausingAdoptionHomebrew()
    let defaultsName = "AdoptionProgressTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: defaultsName))
    defer { defaults.removePersistentDomain(forName: defaultsName) }

    let app = InstalledApp(
        name: "Adoptable Example",
        bundleIdentifier: "com.example.adoptable",
        installedVersion: "1.0.0",
        buildVersion: nil,
        url: URL(fileURLWithPath: "/Applications/Adoptable Example.app"),
        sparkleFeedURL: nil,
        githubRepository: nil,
        hasAppStoreReceipt: false
    )
    let item = AdoptableApp(app: app, caskToken: "adoptable-example", caskVersion: "1.0.0")
    let recorder = TransactionRecorder()
    let store = UpkeepStore(
        settings: AppSettings(defaults: defaults),
        dependencies: UpkeepDependencies(
            scanner: TransactionScanner(recorder: recorder),
            applicationDiscovery: TransactionDiscovery(app: app),
            homebrew: homebrew,
            developerPackages: TransactionDeveloperPackages(),
            localModels: TransactionLocalModels(),
            history: TransactionHistory(recorder: recorder),
            externalOpener: TransactionExternalOpener()
        )
    )
    store.apps = [app]
    store.adoptableApps = [item]

    await store.adopt(item)
    let authorization = try #require(store.pendingHomebrewAuthorizationConfirmation)
    let adoptionTask = Task { await store.confirmHomebrewAuthorization(authorization) }
    await homebrew.waitUntilAdoptionStarts()

    #expect(store.pendingHomebrewAuthorizationConfirmation == nil)
    #expect(store.isWorking(.homebrewAdoption(item.id)))
    #expect(store.updatePhase(for: .homebrewAdoption(item.id)) == .adopting)

    await homebrew.resumeAdoption()
    await adoptionTask.value

    #expect(!store.isWorking(.homebrewAdoption(item.id)))
    #expect(store.updateExecutionState.activities.isEmpty)
}

private actor TransactionRecorder {
    private var values: [String] = []
    func append(_ value: String) { values.append(value) }
    func events() -> [String] { values }
}

private struct TransactionScanner: UpdateScanning {
    let recorder: TransactionRecorder

    func scan(settings: ScanSettings) async -> ScanReport {
        await recorder.append("scan")
        return .empty
    }

    func scan(app: InstalledApp, settings: ScanSettings) async -> UpdateScanner.TargetedAppReport {
        .empty
    }
}

private struct TransactionDiscovery: ApplicationDiscovering {
    let app: InstalledApp
    var installedVersion: String? = nil
    func discover() async -> [InstalledApp] { [app] }
    func discover(at url: URL) async -> InstalledApp? {
        guard let installedVersion else { return app }
        return InstalledApp(name: app.name, bundleIdentifier: app.bundleIdentifier, installedVersion: installedVersion,
            buildVersion: app.buildVersion, url: app.url, sparkleFeedURL: app.sparkleFeedURL,
            githubRepository: app.githubRepository, hasAppStoreReceipt: app.hasAppStoreReceipt)
    }
}

private struct TransactionHomebrew: HomebrewManaging {
    let recorder: TransactionRecorder

    func package(token: String, kind: HomebrewPackageKind, includePrereleases: Bool) async throws -> HomebrewPackage? { nil }
    func upgrade(_ package: HomebrewPackage) async throws { await recorder.append("upgrade") }
    func adopt(_ item: AdoptableApp) async throws { await recorder.append("adopt") }
    func installOrReplace(_ item: AdoptableApp) async throws { await recorder.append("replace") }
    func upgradeCask(token: String) async throws { await recorder.append("upgrade-cask") }
}

private actor PausingAdoptionHomebrew: HomebrewManaging {
    private var didStartAdoption = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var adoptionContinuation: CheckedContinuation<Void, Never>?

    func waitUntilAdoptionStarts() async {
        if didStartAdoption { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func resumeAdoption() {
        adoptionContinuation?.resume()
        adoptionContinuation = nil
    }

    func inventory(includePrereleases: Bool) async throws -> [HomebrewPackage] { [] }
    func caskCatalog() async throws -> [CatalogCask] { [] }
    func adoptableApps(
        from apps: [InstalledApp],
        catalog: [CatalogCask],
        excluding packages: [HomebrewPackage]
    ) -> [AdoptableApp] { [] }
    func package(
        token: String,
        kind: HomebrewPackageKind,
        includePrereleases: Bool
    ) async throws -> HomebrewPackage? { nil }
    func upgrade(_ package: HomebrewPackage) async throws {}
    func adopt(_ item: AdoptableApp) async throws {
        didStartAdoption = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { adoptionContinuation = $0 }
    }
    func installOrReplace(_ item: AdoptableApp) async throws {}
    func upgradeCask(token: String) async throws {}
}

private actor TransactionHistory: UpdateHistoryManaging {
    let recorder: TransactionRecorder
    private var storedRecords: [UpdateRecord] = []

    init(recorder: TransactionRecorder) {
        self.recorder = recorder
    }

    func records() -> [UpdateRecord] { storedRecords }

    func prepareAppBackup(
        app: InstalledApp,
        toVersion: String,
        kind: UpdateRecordKind
    ) async throws -> UpdateRecord {
        await recorder.append("backup")
        return UpdateRecord(
            id: UUID(),
            date: Date(),
            name: app.name,
            fromVersion: app.installedVersion,
            toVersion: toVersion,
            kind: kind,
            originalAppPath: app.url.path,
            backupPath: "/tmp/upkeep-transaction-backup/Example.app",
            recoveryNote: nil
        )
    }

    func add(_ record: UpdateRecord) async throws {
        storedRecords.insert(record, at: 0)
        await recorder.append("history")
    }

    func discardBackup(for record: UpdateRecord) async {}
    func addMacOSPlan(update: MacOSUpdate) async throws {}

    func revert(_ record: UpdateRecord) async throws {
        await recorder.append("restore")
    }
}

private actor PausingTransactionHistory: UpdateHistoryManaging {
    private var didStartBackup = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var backupContinuation: CheckedContinuation<Void, Never>?
    private var storedRecords: [UpdateRecord] = []

    func waitUntilBackupStarts() async {
        if didStartBackup { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func resumeBackup() {
        backupContinuation?.resume()
        backupContinuation = nil
    }

    func records() -> [UpdateRecord] { storedRecords }

    func prepareAppBackup(
        app: InstalledApp,
        toVersion: String,
        kind: UpdateRecordKind
    ) async throws -> UpdateRecord {
        didStartBackup = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { backupContinuation = $0 }
        return UpdateRecord(
            id: UUID(),
            date: Date(),
            name: app.name,
            fromVersion: app.installedVersion,
            toVersion: toVersion,
            kind: kind,
            originalAppPath: app.url.path,
            backupPath: "/tmp/upkeep-progress-backup/Adobe Example.app",
            recoveryNote: nil
        )
    }

    func add(_ record: UpdateRecord) async throws { storedRecords.insert(record, at: 0) }
    func discardBackup(for record: UpdateRecord) async {}
    func addMacOSPlan(update: MacOSUpdate) async throws {}
    func revert(_ record: UpdateRecord) async throws {}
}

private struct TransactionDeveloperPackages: DeveloperPackageManaging {
    func scan(enabledManagers: Set<DeveloperPackageManager>, includePrereleases: Bool) async -> DeveloperPackageClient.Report { .empty }
    func availableVersions(for package: DeveloperPackage, includePrereleases: Bool) async -> [String] { [] }
    func install(_ package: DeveloperPackage, version: String) async throws {}
}

private struct TransactionLocalModels: LocalModelManaging {
    func scan() async -> LocalModelClient.Report { .empty }
    func update(_ model: LocalLLMModel) async throws {}
}

@MainActor
private struct TransactionExternalOpener: ExternalOpening {
    func open(_ url: URL) -> Bool { true }
}

@MainActor
private final class RecordingTransactionExternalOpener: ExternalOpening {
    private(set) var openedURLs: [URL] = []

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return true
    }
}

@MainActor
@Test(arguments: ["updated", "outdated", "failed", "partial"], ["individual", "batch", "all"])
func formulaUpdateVerifiesItsTokenWithoutScanningUnrelatedSources(result: String, mode: String) async throws {
    let suite = "FormulaUpdateVerification.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let recorder = TransactionRecorder()
    let package = HomebrewPackage(
        token: "gh", displayName: "gh", description: nil, homepage: nil, license: nil,
        installedVersion: "1.0", currentVersion: "2.0", kind: .formula,
        isOutdated: true, isDependency: false, dependencies: []
    )
    let store = UpkeepStore(settings: AppSettings(defaults: defaults), dependencies: UpkeepDependencies(
        scanner: TransactionScanner(recorder: recorder),
        applicationDiscovery: TransactionDiscovery(app: InstalledApp(
            name: "Example", bundleIdentifier: "test.example", installedVersion: "1.0",
            buildVersion: nil, url: URL(fileURLWithPath: "/Applications/Example.app"),
            sparkleFeedURL: nil, githubRepository: nil, hasAppStoreReceipt: false
        )),
        homebrew: FormulaVerificationHomebrew(result: result, recorder: recorder),
        developerPackages: TransactionDeveloperPackages(), localModels: TransactionLocalModels(),
        history: TransactionHistory(recorder: recorder), externalOpener: TransactionExternalOpener()
    ))
    store.homebrewPackages = [package]
    switch mode {
    case "batch":
        let summary = await store.performBatchUpdates([.homebrew(package)])
        #expect(summary.results.first?.outcome == (result == "updated" ? .updated : .failed))
    case "all": await store.updateAllPackages()
    default: await store.updatePackage(package)
    }
    #expect(await recorder.events() == ((result == "updated" || result == "partial") ? ["upgrade", "verify", "history"] : ["upgrade", "verify"]))
    #expect(store.totalUpdateCount == ((result == "updated" || result == "partial") ? 0 : 1))
    #expect(store.homebrewPackages.first?.installedVersion == ((result == "updated" || result == "partial") ? "2.0" : "1.0"))
    #expect(!store.isWorking(.homebrewPackage(package.id)))
    #expect(store.updatePhase(for: .homebrewPackage(package.id)) == nil)
    #expect(store.updateHistory.count == ((result == "updated" || result == "partial") ? 1 : 0))
    if result == "updated" || result == "partial" {
        #expect(store.updateHistory.first?.toVersion == "2.0")
    }
    if result == "partial" {
        #expect(store.errorMessage?.contains("download failed") == true)
    } else if result == "failed" {
        #expect(store.errorMessage?.contains("Could not refresh gh") == true)
    } else {
        #expect((store.errorMessage == nil) == (result == "updated"))
    }
}

private struct FormulaVerificationHomebrew: HomebrewManaging {
    let result: String
    let recorder: TransactionRecorder
    func package(token: String, kind: HomebrewPackageKind, includePrereleases: Bool) async throws -> HomebrewPackage? {
        await recorder.append("verify")
        if result == "failed" { throw URLError(.cannotConnectToHost) }
        return HomebrewPackage(
            token: token, displayName: token, description: nil, homepage: nil, license: nil,
            installedVersion: (result == "updated" || result == "partial") ? "2.0" : "1.0", currentVersion: "2.0",
            kind: kind, isOutdated: result != "updated" && result != "partial", isDependency: false, dependencies: []
        )
    }
    func upgrade(_ package: HomebrewPackage) async throws {
        await recorder.append("upgrade")
        if result == "partial" { throw HomebrewClient.BrewError.failed("download failed") }
    }
    func adopt(_ item: AdoptableApp) async throws {}
    func installOrReplace(_ item: AdoptableApp) async throws {}
    func upgradeCask(token: String) async throws {}
}
