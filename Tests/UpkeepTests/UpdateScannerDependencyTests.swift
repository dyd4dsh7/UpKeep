import Foundation
import Testing
@testable import Upkeep

@Test func updateScannerUsesInjectedApplicationSourceClients() async {
    let app = InstalledApp(
        name: "Injected",
        bundleIdentifier: "com.example.injected",
        installedVersion: "1.0.0",
        buildVersion: nil,
        url: URL(fileURLWithPath: "/Applications/Injected.app"),
        sparkleFeedURL: URL(string: "https://example.com/appcast.xml"),
        githubRepository: "example/injected",
        hasAppStoreReceipt: true
    )
    let calls = ScannerCallRecorder()
    let scanner = UpdateScanner(dependencies: UpdateScannerDependencies(
        applicationDiscovery: ScannerDiscovery(app: app),
        homebrew: ScannerHomebrew(),
        macOS: ScannerMacOS(),
        developerPackages: ScannerDeveloperPackages(),
        localModels: ScannerLocalModels(),
        appStore: ScannerAppStore(calls: calls),
        sparkle: ScannerSparkle(calls: calls),
        github: ScannerGitHub(calls: calls),
        mozilla: ScannerMozilla(calls: calls)
    ))
    let report = await scanner.scan(settings: ScanSettings(
        checkAppStore: true,
        checkSparkle: true,
        checkHomebrew: false,
        checkGitHub: true,
        checkMacOS: false,
        checkLocalModels: false,
        includePrereleaseUpdates: false,
        enabledDeveloperManagers: [],
        includeAdvancedSources: false
    ))

    #expect(await calls.values() == Set([UpdateSource.appStore]))
    #expect(report.updates.count == 1)
    #expect(report.updates[0].candidates.map(\.source) == [.appStore])
}

@Test func directDeveloperAppsUseDeclaredDeveloperSources() async {
    let app = InstalledApp(
        name: "Direct",
        bundleIdentifier: "com.example.direct",
        installedVersion: "1.0.0",
        buildVersion: nil,
        url: URL(fileURLWithPath: "/Applications/Direct.app"),
        sparkleFeedURL: URL(string: "https://example.com/appcast.xml"),
        githubRepository: "example/direct",
        hasAppStoreReceipt: false
    )
    let calls = ScannerCallRecorder()
    let scanner = UpdateScanner(dependencies: UpdateScannerDependencies(
        applicationDiscovery: ScannerDiscovery(app: app),
        homebrew: ScannerHomebrew(),
        macOS: ScannerMacOS(),
        developerPackages: ScannerDeveloperPackages(),
        localModels: ScannerLocalModels(),
        appStore: ScannerAppStore(calls: calls),
        sparkle: ScannerSparkle(calls: calls),
        github: ScannerGitHub(calls: calls),
        mozilla: ScannerMozilla(calls: calls)
    ))

    _ = await scanner.scan(settings: ScanSettings(
        checkAppStore: true,
        checkSparkle: true,
        checkHomebrew: false,
        checkGitHub: true,
        checkMacOS: false,
        checkLocalModels: false,
        includePrereleaseUpdates: false,
        enabledDeveloperManagers: [],
        includeAdvancedSources: false
    ))

    #expect(await calls.values() == Set([UpdateSource.sparkle, .github]))
}

@Test func firefoxUsesMozillaSourceWithoutDisablingGitHubForOtherApps() async {
    let app = InstalledApp(
        name: "Firefox",
        bundleIdentifier: "org.mozilla.firefox",
        installedVersion: "152.0.6",
        buildVersion: nil,
        url: URL(fileURLWithPath: "/Applications/Firefox.app"),
        sparkleFeedURL: nil,
        githubRepository: nil,
        hasAppStoreReceipt: false,
        mozillaUpdateChannel: .release
    )
    let calls = ScannerCallRecorder()
    let scanner = UpdateScanner(dependencies: UpdateScannerDependencies(
        applicationDiscovery: ScannerDiscovery(app: app),
        homebrew: ScannerHomebrew(),
        macOS: ScannerMacOS(),
        developerPackages: ScannerDeveloperPackages(),
        localModels: ScannerLocalModels(),
        appStore: ScannerAppStore(calls: calls),
        sparkle: ScannerSparkle(calls: calls),
        github: ScannerGitHub(calls: calls),
        mozilla: ScannerMozilla(calls: calls)
    ))

    _ = await scanner.scan(settings: ScanSettings(
        checkAppStore: true,
        checkSparkle: true,
        checkHomebrew: false,
        checkGitHub: true,
        checkMacOS: false,
        checkLocalModels: false,
        includePrereleaseUpdates: false,
        enabledDeveloperManagers: [],
        includeAdvancedSources: false
    ))

    #expect(await calls.values() == Set([UpdateSource.developer]))
}

private actor ScannerCallRecorder {
    private var calls = Set<UpdateSource>()
    func record(_ source: UpdateSource) { calls.insert(source) }
    func values() -> Set<UpdateSource> { calls }
}

@Test func scannerPublishesEachDeveloperManagerBeforeItsScanReturns() async {
    let probe = DeveloperProgressProbe()
    let calls = ScannerCallRecorder()
    let app = InstalledApp(name: "Fixture", bundleIdentifier: "test.fixture", installedVersion: "1",
        buildVersion: nil, url: URL(fileURLWithPath: "/fixture.app"), sparkleFeedURL: nil,
        githubRepository: nil, hasAppStoreReceipt: false)
    let scanner = UpdateScanner(dependencies: UpdateScannerDependencies(
        applicationDiscovery: ScannerDiscovery(app: app), homebrew: ScannerHomebrew(),
        macOS: ScannerMacOS(), developerPackages: ProgressiveScannerDeveloperPackages(probe: probe),
        localModels: ScannerLocalModels(), appStore: ScannerAppStore(calls: calls),
        sparkle: ScannerSparkle(calls: calls), github: ScannerGitHub(calls: calls),
        mozilla: ScannerMozilla(calls: calls)))
    _ = await scanner.scan(settings: ScanSettings(checkAppStore: false, checkSparkle: false,
        checkHomebrew: false, checkGitHub: false, checkMacOS: false, checkLocalModels: false,
        includePrereleaseUpdates: false, enabledDeveloperManagers: [.npm, .pipx],
        includeAdvancedSources: false)) { event in
        if case let .developerPackages(_, managers) = event { await probe.record(managers) }
    }
    #expect(await probe.values() == [Set([.npm]), Set([.pipx])])
    #expect(await probe.publishedBeforeReturn)
}

@Test func combinedDeveloperReportsPreserveFailureScopesAndSharedWarningOwners() {
    let npm = DeveloperPackageClient.Report(packages: [], installedManagers: [.npm],
        warnings: ["Shared failure"], failedManagers: [], failedExecutablePaths: ["/node/npm"],
        warningManagers: ["Shared failure": [.npm]])
    let pipx = DeveloperPackageClient.Report(packages: [], installedManagers: [.pipx],
        warnings: ["Shared failure"], failedManagers: [.pipx], failedExecutablePaths: ["/python/pipx"],
        warningManagers: ["Shared failure": [.pipx]])
    let report = DeveloperPackageClient.combine([pipx, .empty, npm])
    #expect(Set(report.installedManagers) == [.npm, .pipx])
    #expect(report.failedManagers == [.pipx])
    #expect(report.failedExecutablePaths == ["/node/npm", "/python/pipx"])
    #expect(report.warningManagers["Shared failure"] == [.npm, .pipx])
}

private actor DeveloperProgressProbe {
    private var scopes: [Set<DeveloperPackageManager>] = []
    private(set) var publishedBeforeReturn = false
    func record(_ managers: Set<DeveloperPackageManager>) { scopes.append(managers) }
    func values() -> [Set<DeveloperPackageManager>] { scopes }
    func checkBeforeReturn() { publishedBeforeReturn = scopes == [Set([.npm]), Set([.pipx])] }
}

private struct ProgressiveScannerDeveloperPackages: DeveloperPackageManaging {
    let probe: DeveloperProgressProbe
    func scan(enabledManagers: Set<DeveloperPackageManager>, includePrereleases: Bool) async -> DeveloperPackageClient.Report {
        Issue.record("Scanner must request progressive developer results")
        return .empty
    }
    func scan(enabledManagers: Set<DeveloperPackageManager>, includePrereleases: Bool,
              progress: @escaping DeveloperScanProgressReporter) async -> DeveloperPackageClient.Report {
        await progress(.empty, [.npm])
        await progress(.empty, [.pipx])
        await probe.checkBeforeReturn()
        return .empty
    }
    func availableVersions(for package: DeveloperPackage, includePrereleases: Bool) async -> [String] { [] }
    func install(_ package: DeveloperPackage, version: String) async throws {}
}

private struct ScannerDiscovery: ApplicationDiscovering {
    let app: InstalledApp
    func discover() async -> [InstalledApp] { [app] }
    func discover(at url: URL) async -> InstalledApp? { app }
}

private struct ScannerAppStore: AppStoreUpdateChecking {
    let calls: ScannerCallRecorder
    func update(for app: InstalledApp) async throws -> AvailableUpdate? {
        await calls.record(.appStore)
        return AvailableUpdate(
            app: app, availableVersion: "1.1.0", source: .appStore,
            releaseNotes: nil, actionURL: URL(string: "macappstore://showUpdatesPage"),
            homebrewToken: nil
        )
    }
}

private struct ScannerSparkle: SparkleUpdateChecking {
    let calls: ScannerCallRecorder
    func update(for app: InstalledApp, includePrereleases: Bool) async throws -> AvailableUpdate? {
        await calls.record(.sparkle)
        return AvailableUpdate(
            app: app, availableVersion: "1.1.0", source: .sparkle,
            releaseNotes: nil, actionURL: app.sparkleFeedURL, homebrewToken: nil
        )
    }
}

private struct ScannerGitHub: GitHubUpdateChecking {
    let calls: ScannerCallRecorder
    func update(for app: InstalledApp, includePrereleases: Bool) async throws -> AvailableUpdate? {
        await calls.record(.github)
        return AvailableUpdate(
            app: app, availableVersion: "1.1.0", source: .github,
            releaseNotes: nil, actionURL: URL(string: "https://github.com/example/injected/releases"),
            homebrewToken: nil
        )
    }
}

private struct ScannerMozilla: MozillaUpdateChecking {
    let calls: ScannerCallRecorder
    func update(for app: InstalledApp) async throws -> AvailableUpdate? {
        await calls.record(.developer)
        return AvailableUpdate(
            app: app, availableVersion: "1.1.0", source: .developer,
            releaseNotes: nil, actionURL: nil, homebrewToken: nil,
            requiresInAppInstallation: true
        )
    }
}

private struct ScannerHomebrew: HomebrewScanning {
    func inventory(includePrereleases: Bool) async throws -> [HomebrewPackage] { [] }
    func caskCatalog() async throws -> [CatalogCask] { [] }
    func adoptableApps(from apps: [InstalledApp], catalog: [CatalogCask], excluding packages: [HomebrewPackage]) -> [AdoptableApp] { [] }
}

private struct ScannerMacOS: MacOSUpdateScanning {
    func scan(includeInstallers: Bool) async -> MacOSUpdateClient.Report { .empty }
}

private struct ScannerDeveloperPackages: DeveloperPackageManaging {
    func scan(enabledManagers: Set<DeveloperPackageManager>, includePrereleases: Bool) async -> DeveloperPackageClient.Report { .empty }
    func availableVersions(for package: DeveloperPackage, includePrereleases: Bool) async -> [String] { [] }
    func install(_ package: DeveloperPackage, version: String) async throws {}
}

private struct ScannerLocalModels: LocalModelManaging {
    func scan() async -> LocalModelClient.Report { .empty }
    func update(_ model: LocalLLMModel) async throws {}
}

@Test func fastSourcesPublishWhileHomebrewInventoryIsStillPending() async {
    let probe = ScanLatencyProbe()
    let calls = ScannerCallRecorder()
    let app = InstalledApp(name: "Fixture", bundleIdentifier: "test.fixture", installedVersion: "1",
        buildVersion: nil, url: URL(fileURLWithPath: "/fixture.app"),
        sparkleFeedURL: URL(string: "https://example.com/feed.xml"), githubRepository: nil,
        hasAppStoreReceipt: false)
    let scanner = UpdateScanner(dependencies: UpdateScannerDependencies(
        applicationDiscovery: ScannerDiscovery(app: app), homebrew: DelayedScannerHomebrew(probe: probe),
        macOS: ScannerMacOS(), developerPackages: ScannerDeveloperPackages(),
        localModels: ProgressiveScannerModels(), appStore: ScannerAppStore(calls: calls),
        sparkle: ScannerSparkle(calls: calls), github: ScannerGitHub(calls: calls),
        mozilla: ScannerMozilla(calls: calls)))
    let report = await scanner.scan(settings: ScanSettings(checkAppStore: false, checkSparkle: true,
        checkHomebrew: true, checkGitHub: false, checkMacOS: false, checkLocalModels: true,
        includePrereleaseUpdates: false, enabledDeveloperManagers: [.npm],
        includeAdvancedSources: false)) { event in
        switch event {
        case .appSource: await probe.record("app")
        case .developerPackages: await probe.record("developer")
        case let .localModels(_, runtimes):
            for runtime in runtimes { await probe.record(runtime.rawValue) }
        default: break
        }
    }
    #expect(await probe.earlySources == Set(["app", "developer", LocalModelRuntime.ollama.rawValue,
        LocalModelRuntime.lmStudio.rawValue]))
    #expect(report.updates.count == 1)
    #expect(await probe.homebrewFinished)
}

private actor ScanLatencyProbe {
    private(set) var homebrewFinished = false
    private(set) var earlySources = Set<String>()
    func record(_ source: String) { if !homebrewFinished { earlySources.insert(source) } }
    func finishHomebrew() { homebrewFinished = true }
}

private struct DelayedScannerHomebrew: HomebrewScanning {
    let probe: ScanLatencyProbe
    func inventory(includePrereleases: Bool) async throws -> [HomebrewPackage] {
        try await Task.sleep(for: .milliseconds(250))
        await probe.finishHomebrew()
        return []
    }
    func caskCatalog() async throws -> [CatalogCask] { [] }
    func adoptableApps(from apps: [InstalledApp], catalog: [CatalogCask], excluding packages: [HomebrewPackage]) -> [AdoptableApp] { [] }
}

private struct ProgressiveScannerModels: LocalModelManaging {
    func scan() async -> LocalModelClient.Report { .empty }
    func scan(progress: @escaping LocalModelScanProgressReporter) async -> LocalModelClient.Report {
        await progress(.empty, [.ollama])
        await progress(.empty, [.lmStudio])
        return .empty
    }
    func update(_ model: LocalLLMModel) async throws {}
}
