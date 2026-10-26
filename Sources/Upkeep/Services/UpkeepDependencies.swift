import AppKit
import Foundation

protocol UpdateScanning: Sendable {
    func scan(settings: ScanSettings) async -> ScanReport
    func scan(settings: ScanSettings, progress: @escaping ScanProgressReporter) async -> ScanReport
    func scan(app: InstalledApp, settings: ScanSettings) async -> UpdateScanner.TargetedAppReport
    func homebrewInventory(includePrereleases: Bool) async throws -> [HomebrewPackage]
    func homebrewCatalog() async throws -> [CatalogCask]
    func macOS(scope: MacOSScanScope) async throws -> MacOSUpdateClient.Report
}

extension UpdateScanning {
    func macOS(scope: MacOSScanScope) async throws -> MacOSUpdateClient.Report { throw ScopedScanError.unavailable }
    func homebrewCatalog() async throws -> [CatalogCask] { throw ScopedScanError.unavailable }
    func homebrewInventory(includePrereleases: Bool) async throws -> [HomebrewPackage] {
        throw ScopedScanError.unavailable
    }
    func scan(settings: ScanSettings, progress: @escaping ScanProgressReporter) async -> ScanReport {
        await scan(settings: settings)
    }
}

enum ScopedScanError: LocalizedError {
    case unavailable
    var errorDescription: String? { "This scanner does not support a scoped source check." }
}

protocol ApplicationDiscovering: Sendable {
    func discover() async -> [InstalledApp]
    func discover(at url: URL) async -> InstalledApp?
}

struct LiveApplicationDiscovery: ApplicationDiscovering {
    func discover() async -> [InstalledApp] { await AppDiscovery.discover() }
    func discover(at url: URL) async -> InstalledApp? { await AppDiscovery.discover(at: url) }
}

protocol HomebrewScanning: Sendable {
    func inventory(includePrereleases: Bool) async throws -> [HomebrewPackage]
    func caskCatalog() async throws -> [CatalogCask]
    func adoptableApps(
        from apps: [InstalledApp],
        catalog: [CatalogCask],
        excluding packages: [HomebrewPackage]
    ) -> [AdoptableApp]
}

protocol MacOSUpdateScanning: Sendable {
    func scan(includeInstallers: Bool) async -> MacOSUpdateClient.Report
    func scan(scope: MacOSScanScope) async throws -> MacOSUpdateClient.Report
}

extension MacOSUpdateScanning {
    func scan(scope: MacOSScanScope) async throws -> MacOSUpdateClient.Report { throw ScopedScanError.unavailable }
}

protocol AppStoreUpdateChecking: Sendable {
    func update(for app: InstalledApp) async throws -> AvailableUpdate?
}

protocol SparkleUpdateChecking: Sendable {
    func update(for app: InstalledApp, includePrereleases: Bool) async throws -> AvailableUpdate?
}

protocol GitHubUpdateChecking: Sendable {
    func update(for app: InstalledApp, includePrereleases: Bool) async throws -> AvailableUpdate?
}

protocol MozillaUpdateChecking: Sendable {
    func update(for app: InstalledApp) async throws -> AvailableUpdate?
}

protocol HomebrewManaging: Sendable {
    func services() async throws -> [HomebrewService]
    func package(
        token: String,
        kind: HomebrewPackageKind,
        includePrereleases: Bool
    ) async throws -> HomebrewPackage?
    func upgrade(_ package: HomebrewPackage) async throws
    func adopt(_ item: AdoptableApp) async throws
    func installOrReplace(_ item: AdoptableApp) async throws
    func upgradeCask(token: String) async throws
}

extension HomebrewManaging {
    func services() async throws -> [HomebrewService] { throw ScopedScanError.unavailable }
}

typealias DeveloperScanProgressReporter = @Sendable (DeveloperPackageClient.Report, Set<DeveloperPackageManager>) async -> Void

protocol DeveloperPackageManaging: Sendable {
    func scan(enabledManagers: Set<DeveloperPackageManager>, includePrereleases: Bool,
              progress: @escaping DeveloperScanProgressReporter) async -> DeveloperPackageClient.Report
    func scan(
        enabledManagers: Set<DeveloperPackageManager>,
        includePrereleases: Bool
    ) async -> DeveloperPackageClient.Report
    func availableVersions(
        for package: DeveloperPackage,
        includePrereleases: Bool
    ) async -> [String]
    func install(_ package: DeveloperPackage, version: String) async throws
    func uninstall(_ package: DeveloperPackage) async throws
}

protocol PackageCleanupManaging: Sendable {
    func scan(_ target: PackageCleanupTarget) async throws -> PackageCleanupEstimate
    func cleanup(_ target: PackageCleanupTarget) async throws -> PackageCleanupResult
}

extension DeveloperPackageManaging {
    func scan(enabledManagers: Set<DeveloperPackageManager>, includePrereleases: Bool,
              progress: @escaping DeveloperScanProgressReporter) async -> DeveloperPackageClient.Report {
        let report = await scan(enabledManagers: enabledManagers, includePrereleases: includePrereleases)
        await progress(report, enabledManagers)
        return report
    }
    func uninstall(_ package: DeveloperPackage) async throws {
        throw DeveloperPackageUninstallAdapters.AdapterError.unsupportedPackage(package.name)
    }
}

typealias LocalModelScanProgressReporter = @Sendable (LocalModelClient.Report, Set<LocalModelRuntime>) async -> Void

protocol LocalModelManaging: Sendable {
    func scan() async -> LocalModelClient.Report
    func scan(progress: @escaping LocalModelScanProgressReporter) async -> LocalModelClient.Report
    func scan(runtime: LocalModelRuntime) async -> LocalModelClient.Report
    func update(_ model: LocalLLMModel) async throws
}

extension LocalModelManaging {
    func scan(progress: @escaping LocalModelScanProgressReporter) async -> LocalModelClient.Report {
        let report = await scan()
        await progress(report, Set(LocalModelRuntime.allCases))
        return report
    }
    func scan(runtime: LocalModelRuntime) async -> LocalModelClient.Report {
        let report = await scan()
        let models = report.models.filter { $0.runtime == runtime }
        let warnings = report.warnings.filter {
            guard let owners = report.warningRuntimes[$0], !owners.isEmpty else { return true }
            return owners.contains(runtime)
        }
        let owners = report.warningRuntimes.reduce(into: [String: Set<LocalModelRuntime>]()) { result, entry in
            let checked = entry.value.intersection([runtime])
            if !checked.isEmpty { result[entry.key] = checked }
        }
        return LocalModelClient.Report(models: models, warnings: warnings,
            failedModelIDs: report.failedModelIDs.intersection(Set(models.map(\.id))),
            failedRuntimes: report.failedRuntimes.intersection([runtime]), warningRuntimes: owners)
    }
}

protocol UpdateHistoryManaging: Sendable {
    func records() async -> [UpdateRecord]
    func maintainStorage() async
    func recoveryStorage() async -> RecoveryStorage?
    func prepareAppBackup(app: InstalledApp, toVersion: String, kind: UpdateRecordKind) async throws -> UpdateRecord
    func add(_ record: UpdateRecord) async throws
    func discardBackup(for record: UpdateRecord) async
    func addMacOSPlan(update: MacOSUpdate) async throws
    func revert(_ record: UpdateRecord) async throws
}

extension UpdateHistoryManaging {
    func maintainStorage() async {}
    func recoveryStorage() async -> RecoveryStorage? { nil }
}

@MainActor
protocol ExternalOpening: Sendable {
    func open(_ url: URL) -> Bool
}

struct WorkspaceExternalOpener: ExternalOpening {
    func open(_ url: URL) -> Bool { NSWorkspace.shared.open(url) }
}

extension UpdateScanner: UpdateScanning {}
extension HomebrewClient: HomebrewManaging {}
extension DeveloperPackageClient: DeveloperPackageManaging {
    func scan(enabledManagers: Set<DeveloperPackageManager>, includePrereleases: Bool,
              progress: @escaping DeveloperScanProgressReporter) async -> Report {
        await scan(enabledManagers: enabledManagers, includePrereleases: includePrereleases, managerProgress: progress)
    }
}
extension PackageCleanupClient: PackageCleanupManaging {}
extension LocalModelClient: LocalModelManaging {
    func scan(progress: @escaping LocalModelScanProgressReporter) async -> Report {
        await scan(progress: Optional(progress))
    }
}
extension HomebrewClient: HomebrewScanning {
    func adoptableApps(
        from apps: [InstalledApp],
        catalog: [CatalogCask],
        excluding packages: [HomebrewPackage]
    ) -> [AdoptableApp] {
        Self.adoptableApps(from: apps, catalog: catalog, excluding: packages)
    }
}
extension MacOSUpdateClient: MacOSUpdateScanning {}
extension AppStoreClient: AppStoreUpdateChecking {}
extension SparkleClient: SparkleUpdateChecking {}
extension GitHubClient: GitHubUpdateChecking {}
extension MozillaUpdateClient: MozillaUpdateChecking {}
extension UpdateHistoryStore: UpdateHistoryManaging {}

struct UpdateScannerDependencies: Sendable {
    let applicationDiscovery: any ApplicationDiscovering
    let homebrew: any HomebrewScanning
    let macOS: any MacOSUpdateScanning
    let developerPackages: any DeveloperPackageManaging
    let localModels: any LocalModelManaging
    let appStore: any AppStoreUpdateChecking
    let sparkle: any SparkleUpdateChecking
    let github: any GitHubUpdateChecking
    let mozilla: any MozillaUpdateChecking

    static let live = UpdateScannerDependencies(
        applicationDiscovery: LiveApplicationDiscovery(),
        homebrew: HomebrewClient(),
        macOS: MacOSUpdateClient(),
        developerPackages: DeveloperPackageClient(),
        localModels: LocalModelClient(),
        appStore: AppStoreClient(),
        sparkle: SparkleClient(),
        github: GitHubClient(),
        mozilla: MozillaUpdateClient()
    )
}

struct UpkeepDependencies: Sendable {
    let scanner: any UpdateScanning
    let applicationDiscovery: any ApplicationDiscovering
    let homebrew: any HomebrewManaging
    let developerPackages: any DeveloperPackageManaging
    let packageCleanup: any PackageCleanupManaging
    let localModels: any LocalModelManaging
    let history: any UpdateHistoryManaging
    let externalOpener: any ExternalOpening
    let directAppInstaller: any DirectAppInstalling
    let applicationLifecycle: any ApplicationLifecycleManaging
    let externalVerificationInterval: Duration
    let makeCVEClient: (@MainActor @Sendable () -> CVEInventoryClient)?

    init(
        scanner: any UpdateScanning,
        applicationDiscovery: any ApplicationDiscovering = LiveApplicationDiscovery(),
        homebrew: any HomebrewManaging,
        developerPackages: any DeveloperPackageManaging,
        packageCleanup: any PackageCleanupManaging = PackageCleanupClient(),
        localModels: any LocalModelManaging,
        history: any UpdateHistoryManaging,
        externalOpener: any ExternalOpening = WorkspaceExternalOpener(),
        directAppInstaller: any DirectAppInstalling = DirectAppInstaller(),
        applicationLifecycle: any ApplicationLifecycleManaging = WorkspaceApplicationLifecycle(),
        externalVerificationInterval: Duration = .seconds(3),
        makeCVEClient: (@MainActor @Sendable () -> CVEInventoryClient)? = nil
    ) {
        self.scanner = scanner
        self.applicationDiscovery = applicationDiscovery
        self.homebrew = homebrew
        self.developerPackages = developerPackages
        self.packageCleanup = packageCleanup
        self.localModels = localModels
        self.history = history
        self.externalOpener = externalOpener
        self.directAppInstaller = directAppInstaller
        self.applicationLifecycle = applicationLifecycle
        self.externalVerificationInterval = externalVerificationInterval
        self.makeCVEClient = makeCVEClient
    }

    static let live = UpkeepDependencies(
        scanner: UpdateScanner(dependencies: .live),
        applicationDiscovery: LiveApplicationDiscovery(),
        homebrew: HomebrewClient(),
        developerPackages: DeveloperPackageClient(),
        packageCleanup: PackageCleanupClient(),
        localModels: LocalModelClient(),
        history: UpdateHistoryStore.shared,
        externalOpener: WorkspaceExternalOpener(),
        directAppInstaller: DirectAppInstaller(),
        makeCVEClient: { CVEInventoryClient() }
    )
}
