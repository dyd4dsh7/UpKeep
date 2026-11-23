import Foundation
@testable import Upkeep

/// Unit-test data and clients remain available in optimized builds. All external
/// clients are injected; updates and other mutations are rejected.
enum CVEStoreFixture {
    static let app = InstalledApp(name: "Fixture Editor", bundleIdentifier: "test.upkeep.fixture.editor",
        installedVersion: "1.0", buildVersion: "10", url: URL(fileURLWithPath: "/fixture/Editor.app"),
        sparkleFeedURL: URL(string: "https://example.invalid/feed"), githubRepository: nil, hasAppStoreReceipt: false)
    static var update: AvailableUpdate {
        AvailableUpdate(app: app, availableVersion: "2.0", source: .sparkle, releaseNotes: "Fixture release notes.",
            actionURL: URL(string: "https://example.invalid/editor.zip"), homebrewToken: nil)
    }
    static let cvePackages = [
        DeveloperPackage(name: "fixture-vulnerable-tool", currentVersion: "1.0.0", latestVersion: "2.0.0", manager: .npm, executablePath: "/fixture/npm"),
        DeveloperPackage(name: "fixture-current-tool", currentVersion: "2.0.0", latestVersion: "2.0.0", manager: .npm, executablePath: "/fixture/npm"),
        DeveloperPackage(name: "Fixture runtime", currentVersion: "1.0.0", latestVersion: "1.0.0", manager: .node, executablePath: "/fixture/node")
    ]
    static var cveClient: CVEClient {
        CVEClient { request in
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            let response = body.contains("fixture-vulnerable-tool")
                ? #"{"vulns":[{"id":"GHSA-fixture-example","aliases":["CVE-2026-0000"],"summary":"Offline UI fixture advisory. Review the publisher advisory before updating.","severity":[{"type":"CVSS_V3","score":"CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H"}],"affected":[{"package":{"name":"fixture-vulnerable-tool","ecosystem":"npm"},"ranges":[{"type":"SEMVER","events":[{"introduced":"0"},{"fixed":"1.0.1"},{"introduced":"2.0.0"},{"fixed":"2.0.2"}]}]}]}]}"#
                : "{}"
            return (Data(response.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }
    static var cveInventoryClient: CVEInventoryClient {
        let transport: CVEClient.Transport = { request in
            let json: String
            if request.url?.host == "formulae.brew.sh" {
                json = #"{"advisories":{"zip":[{"id":"BREW-fixture","upstream":["CVE-2026-0001"],"summary":"Offline formula advisory fixture","affected":[{"package":{"name":"zip","ecosystem":"Homebrew"},"ranges":[{"type":"ECOSYSTEM","events":[{"introduced":"0"},{"fixed":"1.0_2"}]}]}]}]}}"#
            } else {
                json = #"{"startIndex":0,"resultsPerPage":2000,"totalResults":1,"vulnerabilities":[{"cve":{"id":"CVE-2026-0002","metrics":{"cvssMetricV31":[{"cvssData":{"baseScore":8.1,"baseSeverity":"HIGH"}}]},"descriptions":[{"lang":"en","value":"Offline app advisory fixture; review applicability."}]}}]}"#
            }
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        return CVEInventoryClient(developer: cveClient, nvd: NVDCVEClient(transport: transport, pace: {}), transport: transport)
    }
    static let cveApp = InstalledApp(name: "Fixture Firefox", bundleIdentifier: "org.mozilla.firefox",
        installedVersion: "100.0", buildVersion: nil, url: URL(fileURLWithPath: "/fixture/Firefox.app"),
        sparkleFeedURL: nil, githubRepository: nil, hasAppStoreReceipt: false)
    static var cveUpdate: AvailableUpdate {
        AvailableUpdate(app: cveApp, availableVersion: "101.0", source: .github,
            releaseNotes: "Offline CVE update fixture", actionURL: nil, homebrewToken: nil)
    }
    static let cveFormula = HomebrewPackage(token: "zip", displayName: "zip", description: nil,
        homepage: nil, license: nil, installedVersion: "1.0_1", currentVersion: "1.0_2", kind: .formula,
        isOutdated: true, isDependency: false, dependencies: [], tap: "homebrew/core")
    @MainActor static func makeStore(
        settings: AppSettings,
        includeCVEInventory: Bool = false,
        appUninstaller: any AppUninstalling = AppUninstaller(),
        appDataLibrary: URL = AppDataLocator.defaultLibrary,
        unattendedConditions: any UnattendedConditionsChecking = ReadyForUnattendedUpdates(),
        homebrew: (any HomebrewManaging)? = nil,
        appStoreUpdater: any AppStoreUpdating = MasAppStoreUpdater(),
        packageReleaseNotes: any PackageReleaseNotesProviding = PackageReleaseNotesClient(fetch: { _ in nil }),
        makeCVEClient: (@MainActor @Sendable () -> CVEInventoryClient)? = nil
    ) -> UpkeepStore {
        let services = CVEStoreFixtureServices(includeCVEInventory: includeCVEInventory)
        let store = UpkeepStore(settings: settings, dependencies: UpkeepDependencies(
            scanner: services, applicationDiscovery: services, homebrew: homebrew ?? services,
            developerPackages: services, packageCleanup: services, localModels: services,
            history: services, externalOpener: services, directAppInstaller: services,
            applicationLifecycle: services, appUninstaller: appUninstaller,
            itemDescriber: OfflineItemDescriber(), descriptionCacheURL: nil, appDataLibrary: appDataLibrary,
            unattendedConditions: unattendedConditions, appStoreUpdater: appStoreUpdater,
            packageReleaseNotes: packageReleaseNotes,
            makeCVEClient: makeCVEClient ?? { CVEStoreFixture.cveInventoryClient }))
        store.apps = services.apps
        store.updates = services.updates
        if includeCVEInventory {
            store.homebrewPackages = [cveFormula]
            store.developerPackages = cvePackages
            store.installedDeveloperManagers = [.npm, .node]
            store.selection = .cveChecker
        }
        return store
    }
}

struct ReadyForUnattendedUpdates: UnattendedConditionsChecking {
    var reason: String?
    func reasonToWait() async -> String? { reason }
}

private enum CVEStoreFixtureError: LocalizedError {
    case mutationBlocked
    var errorDescription: String? { "External actions are disabled in the CVE test fixture." }
}

private struct CVEStoreFixtureServices: UpdateScanning, ApplicationDiscovering,
    HomebrewManaging, DeveloperPackageManaging, PackageCleanupManaging,
    LocalModelManaging, UpdateHistoryManaging, ExternalOpening, DirectAppInstalling,
    ApplicationLifecycleManaging {
    let includeCVEInventory: Bool
    var apps: [InstalledApp] {
        includeCVEInventory ? [CVEStoreFixture.app, CVEStoreFixture.cveApp] : [CVEStoreFixture.app]
    }
    var updates: [AvailableUpdate] {
        includeCVEInventory ? [CVEStoreFixture.update, CVEStoreFixture.cveUpdate] : [CVEStoreFixture.update]
    }
    func scan(settings: ScanSettings) async -> ScanReport {
        ScanReport(apps: apps, updates: updates, checkedAt: Date(), warnings: [],
            failedAppSources: [:], homebrewInventoryStatus: .succeeded, homebrewCatalogStatus: .disabled,
            macOSUpdatesStatus: .disabled, macOSInstallersStatus: .disabled, failedDeveloperManagers: [],
            failedDeveloperExecutablePaths: [], localModelsStatus: .disabled, failedLocalModelIDs: [],
            failedLocalModelRuntimes: [], homebrewPackages: includeCVEInventory ? [CVEStoreFixture.cveFormula] : [],
            adoptableApps: [], macOSUpdates: [],
            developerPackages: includeCVEInventory ? CVEStoreFixture.cvePackages : [],
            installedDeveloperManagers: includeCVEInventory ? [.npm, .node] : [], localModels: [])
    }
    func scan(app: InstalledApp, settings: ScanSettings) async -> UpdateScanner.TargetedAppReport {
        .init(updates: updates.filter { $0.app.id == app.id }, failedSources: [], warnings: [])
    }
    func discover() async -> [InstalledApp] { apps }
    func discover(at url: URL) async -> InstalledApp? { apps.first { $0.url == url } }
    func package(token: String, kind: HomebrewPackageKind, includePrereleases: Bool) async throws -> HomebrewPackage? { nil }
    func upgrade(_ package: HomebrewPackage) async throws { throw CVEStoreFixtureError.mutationBlocked }
    func adopt(_ item: AdoptableApp) async throws { throw CVEStoreFixtureError.mutationBlocked }
    func installOrReplace(_ item: AdoptableApp) async throws { throw CVEStoreFixtureError.mutationBlocked }
    func upgradeCask(token: String) async throws { throw CVEStoreFixtureError.mutationBlocked }
    func scan(enabledManagers: Set<DeveloperPackageManager>, includePrereleases: Bool) async -> DeveloperPackageClient.Report { .empty }
    func availableVersions(for package: DeveloperPackage, includePrereleases: Bool) async -> [String] { [] }
    func install(_ package: DeveloperPackage, version: String) async throws { throw CVEStoreFixtureError.mutationBlocked }
    func scan(_ target: PackageCleanupTarget) async throws -> PackageCleanupEstimate { throw CVEStoreFixtureError.mutationBlocked }
    func cleanup(_ target: PackageCleanupTarget) async throws -> PackageCleanupResult { throw CVEStoreFixtureError.mutationBlocked }
    func scan() async -> LocalModelClient.Report { .empty }
    func update(_ model: LocalLLMModel) async throws { throw CVEStoreFixtureError.mutationBlocked }
    func records() async -> [UpdateRecord] { [] }
    func prepareAppBackup(app: InstalledApp, toVersion: String, kind: UpdateRecordKind) async throws -> UpdateRecord {
        throw CVEStoreFixtureError.mutationBlocked
    }
    func add(_ record: UpdateRecord) async throws { throw CVEStoreFixtureError.mutationBlocked }
    func discardBackup(for record: UpdateRecord) async {}
    func addMacOSPlan(update: MacOSUpdate) async throws { throw CVEStoreFixtureError.mutationBlocked }
    func revert(_ record: UpdateRecord) async throws { throw CVEStoreFixtureError.mutationBlocked }
    @MainActor func open(_ url: URL) -> Bool { false }
    func install(update: AvailableUpdate) async throws { throw CVEStoreFixtureError.mutationBlocked }
    @MainActor func runningApplications() -> RunningApplications { .init(identifiers: [], paths: []) }
    @MainActor func quit(_ apps: [InstalledApp]) async throws { throw CVEStoreFixtureError.mutationBlocked }
}
