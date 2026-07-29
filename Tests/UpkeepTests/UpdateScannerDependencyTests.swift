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
