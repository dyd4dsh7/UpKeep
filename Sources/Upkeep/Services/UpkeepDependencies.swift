import AppKit
import Foundation

protocol UpdateScanning: Sendable {
    func scan(settings: ScanSettings) async -> ScanReport
    func scan(app: InstalledApp, settings: ScanSettings) async -> UpdateScanner.TargetedAppReport
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

protocol DeveloperPackageManaging: Sendable {
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

extension DeveloperPackageManaging {
    func uninstall(_ package: DeveloperPackage) async throws {
        throw DeveloperPackageUninstallAdapters.AdapterError.unsupportedPackage(package.name)
    }
}

protocol LocalModelManaging: Sendable {
    func scan() async -> LocalModelClient.Report
    func update(_ model: LocalLLMModel) async throws
}

protocol UpdateHistoryManaging: Sendable {
    func records() async -> [UpdateRecord]
    func prepareAppBackup(app: InstalledApp, toVersion: String, kind: UpdateRecordKind) async throws -> UpdateRecord
    func add(_ record: UpdateRecord) async throws
    func discardBackup(for record: UpdateRecord) async
    func addMacOSPlan(update: MacOSUpdate) async throws
    func revert(_ record: UpdateRecord) async throws
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
extension DeveloperPackageClient: DeveloperPackageManaging {}
extension LocalModelClient: LocalModelManaging {}
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
    let localModels: any LocalModelManaging
    let history: any UpdateHistoryManaging
    let externalOpener: any ExternalOpening
    let directAppInstaller: any DirectAppInstalling

    init(
        scanner: any UpdateScanning,
        applicationDiscovery: any ApplicationDiscovering = LiveApplicationDiscovery(),
        homebrew: any HomebrewManaging,
        developerPackages: any DeveloperPackageManaging,
        localModels: any LocalModelManaging,
        history: any UpdateHistoryManaging = UpdateHistoryStore.shared,
        externalOpener: any ExternalOpening = WorkspaceExternalOpener(),
        directAppInstaller: any DirectAppInstalling = DirectAppInstaller()
    ) {
        self.scanner = scanner
        self.applicationDiscovery = applicationDiscovery
        self.homebrew = homebrew
        self.developerPackages = developerPackages
        self.localModels = localModels
        self.history = history
        self.externalOpener = externalOpener
        self.directAppInstaller = directAppInstaller
    }

    static let live = UpkeepDependencies(
        scanner: UpdateScanner(dependencies: .live),
        applicationDiscovery: LiveApplicationDiscovery(),
        homebrew: HomebrewClient(),
        developerPackages: DeveloperPackageClient(),
        localModels: LocalModelClient(),
        history: UpdateHistoryStore.shared,
        externalOpener: WorkspaceExternalOpener(),
        directAppInstaller: DirectAppInstaller()
    )
}
