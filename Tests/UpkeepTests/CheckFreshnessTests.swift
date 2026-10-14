import Foundation
import Testing
@testable import Upkeep

@Test func partialDeveloperEnvironmentFailureRemainsVisibleWithoutReturnedPackages() {
    let warning = "npm inventory failed in one environment"
    let report = DeveloperPackageClient.Report(packages: [], installedManagers: [.npm, .uv],
        warnings: [warning], failedManagers: [], failedExecutablePaths: ["/fixture/node-18/bin/npm"],
        warningManagers: [warning: [.npm]])
    #expect(report.hasFailures(for: .npm))
    #expect(!report.hasFailures(for: .uv))
    #expect(report.scanWarnings.first?.itemNames == [DeveloperPackageManager.npm.rawValue])
}

@MainActor
@Test func partialDeveloperRetryRetainsFailedEnvironmentAndSuccessDateAcrossRestart() async throws {
    let suite = "PartialDeveloperFreshness.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    let baseline = Date(timeIntervalSince1970: 100)
    settings.lastCompletedScanDate = baseline
    let key = "developer|npm"
    settings.recordSourceAttempt(key, at: baseline)
    let failed = DeveloperPackage(name: "retained", currentVersion: "1", latestVersion: "2", manager: .npm,
                                  executablePath: "/fixture/failed/bin/npm")
    let fresh = DeveloperPackage(name: "fresh", currentVersion: "2", latestVersion: "2", manager: .npm,
                                 executablePath: "/fixture/success/bin/npm")
    let warning = "The other npm environment is unavailable"
    let report = DeveloperPackageClient.Report(packages: [fresh], installedManagers: [.npm], warnings: [warning],
        failedManagers: [], failedExecutablePaths: [failed.executablePath], warningManagers: [warning: [.npm]])
    let store = UpkeepStore(settings: settings, dependencies: UpkeepDependencies(
        scanner: FreshnessScanner(fails: false), homebrew: HomebrewClient(),
        developerPackages: PartialFreshnessManager(report: report), localModels: LocalModelClient(), history: TestUpdateHistory()))
    store.developerPackages = [failed]
    await store.scanDeveloperPackages(manager: .npm)
    #expect(store.developerPackages.contains(failed))
    #expect(store.developerPackages.contains(fresh))
    #expect(store.scanWarnings.contains { $0.source == .developerPackages && $0.itemNames.contains("npm") })
    let restored = AppSettings(defaults: defaults)
    let health = try #require(restored.sourceCheckFreshness[key])
    #expect(health.failure != nil)
    #expect(health.lastSuccess == baseline)
    #expect(health.lastAttempt > baseline)
    #expect(health.isRetained)
    #expect(restored.lastCompletedScanDate == baseline)
}

private struct PartialFreshnessManager: DeveloperPackageManaging {
    let report: DeveloperPackageClient.Report
    func scan(enabledManagers: Set<DeveloperPackageManager>, includePrereleases: Bool) async -> DeveloperPackageClient.Report { report }
    func availableVersions(for package: DeveloperPackage, includePrereleases: Bool) async -> [String] { [] }
    func install(_ package: DeveloperPackage, version: String) async throws { throw CancellationError() }
    func uninstall(_ package: DeveloperPackage) async throws { throw CancellationError() }
}

@MainActor
@Test func failedAttemptRetainsSuccessfulSourceDateAcrossRestart() {
    let suite = "CheckFreshness.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    let success = Date(timeIntervalSince1970: 100)
    let failed = Date(timeIntervalSince1970: 200)
    settings.recordSourceAttempt("app|example|Sparkle", at: success)
    settings.recordSourceAttempt("app|example|Sparkle", at: failed, failure: "Offline")
    let restored = AppSettings(defaults: defaults).sourceCheckFreshness["app|example|Sparkle"]
    #expect(restored?.lastAttempt == failed)
    #expect(restored?.lastSuccess == success)
    #expect(restored?.failure == "Offline")
    #expect(restored?.isRetained == true)
}

@MainActor
@Test(arguments: [true, false])
func targetedAppRefreshDoesNotAdvanceGlobalSchedule(fails: Bool) async {
    let suite = "TargetedFreshness.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let baseline = Date(timeIntervalSince1970: 1_725_000_000)
    let settings = AppSettings(defaults: defaults)
    settings.lastCompletedScanDate = baseline
    let app = InstalledApp(name: "Example", bundleIdentifier: "test.freshness", installedVersion: "1.0",
        buildVersion: nil, url: URL(fileURLWithPath: "/not-real/Example.app"),
        sparkleFeedURL: URL(string: "https://example.com/feed"), githubRepository: nil, hasAppStoreReceipt: false)
    let store = UpkeepStore(settings: settings, dependencies: UpkeepDependencies(
        scanner: FreshnessScanner(fails: fails), applicationDiscovery: FreshnessDiscovery(app: app),
        homebrew: HomebrewClient(), developerPackages: DeveloperPackageClient(), localModels: LocalModelClient(), history: TestUpdateHistory()))
    store.apps = [app]
    await store.refresh(app)
    let restored = AppSettings(defaults: defaults)
    #expect(restored.lastCompletedScanDate == baseline)
    #expect(store.lastChecked == baseline)
    #expect((settings.lastChecked(for: app.updateExclusionKey) != nil) == !fails)
    let freshness = settings.sourceCheckFreshness["app|\(app.id)|\(UpdateSource.sparkle.rawValue)"]
    #expect(freshness?.lastAttempt != nil)
    #expect((freshness?.lastSuccess != nil) == !fails)
    let restarted = UpkeepStore(settings: restored)
    #expect(restarted.lastChecked == baseline)
}

private struct FreshnessDiscovery: ApplicationDiscovering {
    let app: InstalledApp
    func discover() async -> [InstalledApp] { [app] }
    func discover(at url: URL) async -> InstalledApp? { app }
}
private struct FreshnessScanner: UpdateScanning {
    let fails: Bool
    func scan(settings: ScanSettings) async -> ScanReport { .empty }
    func scan(app: InstalledApp, settings: ScanSettings) async -> UpdateScanner.TargetedAppReport {
        fails ? .init(updates: [], failedSources: [.sparkle], warnings: [ScanWarning(source: .sparkle, message: "Offline")]) : .empty
    }
}

@MainActor
@Test func scopedSourceRetryPreservesOtherCandidatesAndTheirFreshness() async throws {
    let suite = "SourceRetry.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.checkSparkle = true
    settings.checkGitHub = true
    settings.checkHomebrew = false
    let app = InstalledApp(name: "Example", bundleIdentifier: "test.retry", installedVersion: "1.0",
        buildVersion: nil, url: URL(fileURLWithPath: "/not-real/Example.app"),
        sparkleFeedURL: URL(string: "https://example.com/feed"), githubRepository: "example/app", hasAppStoreReceipt: false)
    let scanner = RetryRecordingScanner()
    let store = UpkeepStore(settings: settings, dependencies: UpkeepDependencies(
        scanner: scanner, applicationDiscovery: FreshnessDiscovery(app: app), homebrew: HomebrewClient(),
        developerPackages: DeveloperPackageClient(), localModels: LocalModelClient(), history: TestUpdateHistory()))
    store.apps = [app]
    let github = AvailableUpdate(app: app, availableVersion: "3.0", source: .github,
        releaseNotes: nil, actionURL: nil, homebrewToken: nil)
    let sparkle = AvailableUpdate(app: app, availableVersion: "2.0", source: .sparkle,
        releaseNotes: nil, actionURL: nil, homebrewToken: nil)
    store.updates = [AvailableUpdate(app: app, candidates: github.candidates + sparkle.candidates)]
    let baseline = Date(timeIntervalSince1970: 100)
    let githubKey = "app|\(app.id)|GitHub"
    settings.recordSourceAttempt(githubKey, at: baseline)
    await store.refresh(app, sources: [.sparkle])
    #expect(await scanner.filters == [[.sparkle]])
    #expect(store.updates.first?.candidates.map(\.source) == [.github])
    #expect(settings.sourceCheckFreshness[githubKey]?.lastAttempt == baseline)
    #expect(settings.sourceCheckFreshness["app|\(app.id)|Sparkle"]?.lastSuccess != nil)
    #expect(settings.lastChecked(for: app.updateExclusionKey) == nil)
}

private actor RetryRecordingScanner: UpdateScanning {
    var filters: [Set<UpdateSource>] = []
    func scan(settings: ScanSettings) async -> ScanReport { .empty }
    func scan(app: InstalledApp, settings: ScanSettings) async -> UpdateScanner.TargetedAppReport {
        filters.append(settings.appSourceFilter ?? [])
        return .empty
    }
}

@MainActor
@Test func appFreshnessFailureDetailsDoNotBorrowAnotherAppsWarning() throws {
    let suite = "FreshnessAttribution.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    let store = UpkeepStore(settings: settings)
    let app = InstalledApp(name: "Target", bundleIdentifier: "test.target", installedVersion: "1",
        buildVersion: nil, url: URL(fileURLWithPath: "/fixture/Target.app"),
        sparkleFeedURL: URL(string: "https://example.com/feed"), githubRepository: nil, hasAppStoreReceipt: false)
    let other = ScanWarning(source: UpdateSource.sparkle.warningSource, itemNames: ["Other"], message: "Other feed is invalid")
    let owned = ScanWarning(source: UpdateSource.sparkle.warningSource, itemNames: ["Target"], message: "Target is offline")
    let key = "app|\(app.id)|\(UpdateSource.sparkle.rawValue)"
    store.recordAppSourceChecks(app: app, settings: settings.scanSettings, failed: [.sparkle], warnings: [other, owned], at: Date())
    #expect(settings.sourceCheckFreshness[key]?.failure?.contains("Target is offline") == true)
    #expect(settings.sourceCheckFreshness[key]?.failure?.contains("Other") == false)
    store.recordAppSourceChecks(app: app, settings: settings.scanSettings, failed: [.sparkle], warnings: [other], at: Date())
    #expect(settings.sourceCheckFreshness[key]?.failure == "This source could not be verified.")
    let duplicateName = ScanWarning(source: UpdateSource.sparkle.warningSource, itemNames: [app.name],
        itemNamesByID: ["another-app-id": app.name], message: "Duplicate name failed")
    let identified = ScanWarning(source: UpdateSource.sparkle.warningSource, itemNames: [app.name],
        itemNamesByID: [app.id: app.name], message: "Exact app failed")
    store.recordAppSourceChecks(app: app, settings: settings.scanSettings, failed: [.sparkle],
        warnings: [duplicateName, identified], at: Date())
    #expect(settings.sourceCheckFreshness[key]?.failure?.contains("Exact app failed") == true)
    store.recordAppSourceChecks(app: app, settings: settings.scanSettings, failed: [.sparkle],
        warnings: [duplicateName], at: Date())
    #expect(settings.sourceCheckFreshness[key]?.failure == "This source could not be verified.")
}
