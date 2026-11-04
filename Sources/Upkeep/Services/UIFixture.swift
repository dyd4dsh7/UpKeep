#if DEBUG
import Foundation

/// Explicit debug-only fixture launch. Every external mutation is rejected.
enum UIFixture {
    enum OperationState: String { case completed, active, empty, longLog, services, servicesFailure, servicesRetained, servicesEmpty, cleanupUnavailable, cve }
    static var operationState: OperationState {
        let prefix = "--ui-fixture-state="
        return ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) })
            .flatMap { OperationState(rawValue: String($0.dropFirst(prefix.count))) } ?? .completed
    }
    static var enabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-fixture")
            || Bundle.main.bundleIdentifier?.hasPrefix("test.upkeep.ui-fixture.") == true
            || Bundle.main.bundleIdentifier == "test.upkeep.ui-fixture"
    }
    static let app = InstalledApp(name: "Fixture Editor", bundleIdentifier: "test.upkeep.fixture.editor",
        installedVersion: "1.0", buildVersion: "10", url: URL(fileURLWithPath: "/fixture/Editor.app"),
        sparkleFeedURL: URL(string: "https://example.invalid/feed"), githubRepository: nil, hasAppStoreReceipt: false)
    static var update: AvailableUpdate {
        AvailableUpdate(app: app, availableVersion: "2.0", source: .sparkle, releaseNotes: "Fixture release notes.",
            actionURL: URL(string: "https://example.invalid/editor.zip"), homebrewToken: nil)
    }
    static let package = HomebrewPackage(token: "fixture-server", displayName: "Fixture Server",
        description: "Offline service preview fixture", homepage: nil, license: nil,
        installedVersion: "1", currentVersion: "2", kind: .formula, isOutdated: true,
        isDependency: false, dependencies: [])
    static let developerPackage = DeveloperPackage(name: "fixture-tool", currentVersion: "1", latestVersion: "1",
        manager: .npm, executablePath: "/fixture/npm")
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
    @MainActor static func makeStore(settings: AppSettings, operationState: OperationState = .completed,
                                    makeCVEClient: (@MainActor @Sendable () -> CVEInventoryClient)? = nil) -> UpkeepStore {
        let services = UIFixtureServices(operationState: operationState)
        let store = UpkeepStore(settings: settings, dependencies: UpkeepDependencies(scanner: services,
            applicationDiscovery: services, homebrew: services, developerPackages: services,
            packageCleanup: services, localModels: services, history: services, externalOpener: services,
            directAppInstaller: services, applicationLifecycle: services, makeCVEClient: makeCVEClient ?? { UIFixture.cveInventoryClient }))
        store.apps = [app]
        store.updates = [update]
        if operationState == .cleanupUnavailable {
            store.developerPackages = [developerPackage]
            store.installedDeveloperManagers = [.npm]
        }
        if [.services, .servicesFailure, .servicesRetained, .servicesEmpty].contains(operationState) {
            store.homebrewPackages = [package]
            store.selectedPackageID = package.id
            store.selection = .homebrewPackages
        }
        if operationState == .servicesRetained {
            store.library.homebrewServices = [HomebrewService(name: package.token, status: "started", user: "fixture", file: nil, exitCode: 0)]
            store.library.homebrewServicesSucceededAt = Date().addingTimeInterval(-3600)
            store.library.homebrewServicesFailure = "Fixture service inventory is unavailable."
        }
        if operationState == .cve {
            store.apps = [app, cveApp]
            store.updates = [update, cveUpdate]
            store.homebrewPackages = [cveFormula]
            store.developerPackages = cvePackages
            store.installedDeveloperManagers = [.npm, .node]
            store.selection = .cveChecker
        }
        let operation = OperationID.applicationUpdate(app.id)
        if operationState != .empty {
            store.updateExecutionState.begin(operation, targets: [.applicationPath(app.url.path)],
                phase: .updating, label: app.name, at: Date().addingTimeInterval(-45))
            store.updateExecutionState.recordVerification(.verified, for: operation,
                commandError: "Fixture command reported an interrupted download.",
                verification: OperationVerificationDetail(requested: "2.0", observed: "1.5 (build 15)", targetReached: false))
            store.updateExecutionState.appendRedactedCommandLog(operationState == .longLog
                ? String(repeating: "Fixture output: " + String(repeating: "long-output-", count: 30) + "\n", count: 60)
                : "Command: fixture-install\nExit status: 1\nDownload interrupted.\n", for: operation)
            store.updateExecutionState.finish(operation)
        }
        if operationState == .active {
            store.updateExecutionState.activeOperations.insert(operation)
            store.updateExecutionState.begin(operation, targets: [.applicationPath(app.url.path)],
                phase: .downloading, label: app.name, at: Date().addingTimeInterval(-12))
        }
        return store
    }
}

private enum UIFixtureError: LocalizedError {
    case mutationBlocked
    case serviceUnavailable
    var errorDescription: String? {
        switch self {
        case .mutationBlocked: "External actions are disabled in the UI fixture."
        case .serviceUnavailable: "Fixture service inventory is unavailable."
        }
    }
}

private struct UIFixtureServices: UpdateScanning, ApplicationDiscovering, HomebrewManaging,
    DeveloperPackageManaging, PackageCleanupManaging, LocalModelManaging, UpdateHistoryManaging,
    ExternalOpening, DirectAppInstalling, ApplicationLifecycleManaging {
    var operationState: UIFixture.OperationState = .completed
    func services() async throws -> [HomebrewService] {
        if [.servicesFailure, .servicesRetained].contains(operationState) { throw UIFixtureError.serviceUnavailable }
        if operationState == .servicesEmpty { return [] }
        return [HomebrewService(name: UIFixture.package.token, status: "started", user: "fixture", file: nil, exitCode: 0)]
    }
    func scan(settings: ScanSettings) async -> ScanReport {
        ScanReport(apps: operationState == .cve ? [UIFixture.app, UIFixture.cveApp] : [UIFixture.app], updates: operationState == .cve ? [UIFixture.update, UIFixture.cveUpdate] : [UIFixture.update], checkedAt: Date(), warnings: [],
            failedAppSources: [:], homebrewInventoryStatus: .succeeded, homebrewCatalogStatus: .disabled,
            macOSUpdatesStatus: .disabled, macOSInstallersStatus: .disabled, failedDeveloperManagers: [],
            failedDeveloperExecutablePaths: [], localModelsStatus: .disabled, failedLocalModelIDs: [],
            failedLocalModelRuntimes: [], homebrewPackages: operationState == .cve ? [UIFixture.cveFormula] : [UIFixture.package], adoptableApps: [], macOSUpdates: [],
            developerPackages: operationState == .cve ? UIFixture.cvePackages : (operationState == .cleanupUnavailable ? [UIFixture.developerPackage] : []),
            installedDeveloperManagers: operationState == .cve ? [.npm, .node] : (operationState == .cleanupUnavailable ? [.npm] : []), localModels: [])
    }
    func scan(app: InstalledApp, settings: ScanSettings) async -> UpdateScanner.TargetedAppReport {
        .init(updates: [UIFixture.update], failedSources: [], warnings: [])
    }
    func discover() async -> [InstalledApp] { [UIFixture.app] }
    func discover(at url: URL) async -> InstalledApp? { url == UIFixture.app.url ? UIFixture.app : nil }
    func package(token: String, kind: HomebrewPackageKind, includePrereleases: Bool) async throws -> HomebrewPackage? { nil }
    func upgrade(_ package: HomebrewPackage) async throws { throw UIFixtureError.mutationBlocked }
    func adopt(_ item: AdoptableApp) async throws { throw UIFixtureError.mutationBlocked }
    func installOrReplace(_ item: AdoptableApp) async throws { throw UIFixtureError.mutationBlocked }
    func upgradeCask(token: String) async throws { throw UIFixtureError.mutationBlocked }
    func scan(enabledManagers: Set<DeveloperPackageManager>, includePrereleases: Bool) async -> DeveloperPackageClient.Report { .empty }
    func availableVersions(for package: DeveloperPackage, includePrereleases: Bool) async -> [String] { [] }
    func install(_ package: DeveloperPackage, version: String) async throws { throw UIFixtureError.mutationBlocked }
    func scan(_ target: PackageCleanupTarget) async throws -> PackageCleanupEstimate {
        guard operationState == .cleanupUnavailable else { throw UIFixtureError.mutationBlocked }
        return PackageCleanupEstimate(target: target, bytes: 0, basis: .unavailable)
    }
    func cleanup(_ target: PackageCleanupTarget) async throws -> PackageCleanupResult { throw UIFixtureError.mutationBlocked }
    func scan() async -> LocalModelClient.Report { .empty }
    func update(_ model: LocalLLMModel) async throws { throw UIFixtureError.mutationBlocked }
    func records() async -> [UpdateRecord] { [] }
    func prepareAppBackup(app: InstalledApp, toVersion: String, kind: UpdateRecordKind) async throws -> UpdateRecord { throw UIFixtureError.mutationBlocked }
    func add(_ record: UpdateRecord) async throws { throw UIFixtureError.mutationBlocked }
    func discardBackup(for record: UpdateRecord) async {}
    func addMacOSPlan(update: MacOSUpdate) async throws { throw UIFixtureError.mutationBlocked }
    func revert(_ record: UpdateRecord) async throws { throw UIFixtureError.mutationBlocked }
    @MainActor func open(_ url: URL) -> Bool { false }
    func install(update: AvailableUpdate) async throws { throw UIFixtureError.mutationBlocked }
    @MainActor func runningApplications() -> RunningApplications { .init(identifiers: [], paths: []) }
    @MainActor func quit(_ apps: [InstalledApp]) async throws { throw UIFixtureError.mutationBlocked }
}
#endif
