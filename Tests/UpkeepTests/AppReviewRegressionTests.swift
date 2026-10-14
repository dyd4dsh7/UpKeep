import Foundation
import Testing
@testable import Upkeep

@MainActor
@Test(arguments: [false, true])
func appRefreshTracksFailedSourcesWithoutChangingOtherApps(fails: Bool) async {
    let app = reviewApp()
    let f = ReviewFixture(discoveredApp: app, scanner: ReviewScanner(failedSources: fails ? [.sparkle] : []))
    defer { f.cleanUp() }
    f.store.apps = [app]
    f.store.scanState.failedAppSources = [app.id: [.github], "other-app": [.github]]

    await f.store.refresh(app)
    #expect(f.store.scanState.failedAppSources[app.id] == (fails ? [.sparkle] : nil))
    #expect(f.store.scanState.failedAppSources["other-app"] == [.github])

    await f.store.scan()
    #expect(f.store.scanState.failedAppSources.isEmpty)
}

@MainActor
@Test func batchReservationsBlockIndividualInstallAndRestore() async throws {
    let installer = ReviewInstaller(pause: true)
    let f = ReviewFixture(installer: installer)
    defer { f.cleanUp() }
    let app = reviewApp()
    let update = reviewUpdate(app)
    f.store.apps = [app]; f.store.updates = [update]
    let batch = Task { await f.store.performBatchUpdates([.application(update)]) }
    let started = await eventually { await installer.calls == 1 }
    #expect(started)
    #expect(f.store.isUpdating(update))
    await f.store.performUpdate(update)
    let record = try await f.history.prepareAppBackup(app: app, toVersion: "1.1", kind: .app)
    await f.store.revert(record)
    #expect(await installer.calls == 1)
    #expect(await f.history.restores == 0)
    await installer.resume()
    #expect(await batch.value.updatedCount == 1)
    #expect(!f.store.isUpdating(update))
}

@MainActor
@Test func individualInstallBlocksBatchBeforeAnyAppIsQuit() async {
    let installer = ReviewInstaller(pause: true)
    let f = ReviewFixture(installer: installer)
    defer { f.cleanUp() }
    let app = reviewApp()
    let update = reviewUpdate(app)
    f.store.apps = [app]; f.store.updates = [update]
    let single = Task { await f.store.performUpdate(update) }
    #expect(await eventually { await installer.calls == 1 })
    let result = await f.store.performBatchUpdates([.application(update)])
    #expect(result.failedCount == 1)
    #expect(f.lifecycle.quitCalls.isEmpty)
    #expect(await installer.calls == 1)
    await installer.resume()
    await single.value
}

@MainActor
@Test func batchHistoryFailureKeepsBackupAndReportsInstalledWithWarning() async {
    let f = ReviewFixture(history: ReviewHistory(fail: true))
    defer { f.cleanUp() }
    let result = await f.store.performBatchUpdates([.application(reviewUpdate(reviewApp()))])
    #expect(await f.installer.calls == 1)
    #expect(await f.history.discarded == false)
    #expect(result.updatedCount == 1)
    #expect(result.failedCount == 0)
    #expect(result.results.first?.warning?.contains("history") == true)
}

@MainActor
@Test func restoreWaitsForQuitConfirmationAndReopensApp() async throws {
    let f = ReviewFixture()
    defer { f.cleanUp() }
    let app = reviewApp()
    f.store.apps = [app]
    f.lifecycle.running = [app]
    let record = try await f.history.prepareAppBackup(app: app, toVersion: "1.1", kind: .app)
    await f.store.revert(record)
    #expect(await f.history.restores == 0)
    let confirmation = try #require(f.store.pendingRunningAppConfirmation)
    #expect(confirmation.buttonTitle == "Quit and Restore")
    await f.store.confirmRunningAppUpdate(confirmation)
    #expect(f.lifecycle.quitCalls == [[app]])
    #expect(await f.history.restores == 1)
    #expect(f.opener.urls == [app.url])
}

@MainActor
@Test func restoreDoesNotTouchFilesWhenAppRefusesToQuit() async throws {
    let f = ReviewFixture()
    defer { f.cleanUp() }
    let app = reviewApp()
    f.store.apps = [app]; f.lifecycle.running = [app]; f.lifecycle.failQuit = true
    let record = try await f.history.prepareAppBackup(app: app, toVersion: "1.1", kind: .app)
    await f.store.revert(record)
    await f.store.confirmRunningAppUpdate(try #require(f.store.pendingRunningAppConfirmation))
    #expect(await f.history.restores == 0)
    #expect(f.store.errorMessage != nil)
}

@MainActor
@Test func selfUpdatesRemainExternalInIndividualAndBatchFlows() async {
    let app = reviewApp(identifier: InstalledApp.upkeepBundleIdentifier)
    let f = ReviewFixture(discoveredApp: app)
    defer { f.cleanUp() }
    f.lifecycle.running = [app]
    let update = reviewUpdate(app)
    #expect(!update.canInstallDirectly)
    #expect(!BatchUpdateItem.application(update).isRecommendedByDefault)
    await f.store.performUpdate(update)
    let batch = await f.store.performBatchUpdates([.application(update)])
    #expect(batch.openedCount == 1)
    #expect(f.store.pendingRunningAppConfirmation == nil)
    #expect(f.lifecycle.quitCalls.isEmpty)
    #expect(await f.installer.calls == 0)
    #expect(f.opener.urls.allSatisfy { $0 == update.externalActionURL })
    #expect(f.opener.urls.count == 2)
}

@MainActor
@Test func allManagerRefreshRetainsPackagesForFailedExecutable() async {
    let old = reviewPackage("old", executable: "/fixture/old/npm")
    let fresh = reviewPackage("fresh", executable: "/fixture/new/npm")
    let report = DeveloperPackageClient.Report(
        packages: [fresh], installedManagers: [.npm], warnings: ["old executable failed"],
        failedManagers: [], failedExecutablePaths: [old.executablePath]
    )
    let f = ReviewFixture(developerReport: report)
    defer { f.cleanUp() }
    f.store.developerPackages = [old]
    await f.store.scanDeveloperPackages(manager: nil)
    #expect(Set(f.store.developerPackages.map(\.id)) == Set([old.id, fresh.id]))
}

@MainActor
@Test func targetedRefreshDropsInstalledVersionsButKeepsUninstalledBuildsOnFailure() async {
    let f = ReviewFixture(discoveredApp: reviewApp(version: "1.1", build: "11"))
    defer { f.cleanUp() }
    let app = reviewApp()
    f.store.apps = [app]; f.store.updates = [reviewUpdate(app)]
    await f.store.refresh(app)
    #expect(f.store.updates.isEmpty)
    let buildUpdate = reviewUpdate(reviewApp(version: "1.1", build: "11"), version: "1.1", build: "12")
    f.store.updates = [buildUpdate]
    await f.store.refresh(buildUpdate.app)
    #expect(f.store.updates.first?.primaryCandidate.availableBuildVersion == "12")
}

@MainActor
@Test func modelUpdatesImmediatelyRefreshHistoryAndSurfacePersistenceFailure() async {
    let f = ReviewFixture(models: RuntimeScopedReviewModels(fails: false))
    defer { f.cleanUp() }
    await f.store.updateLocalModel(reviewModel())
    #expect(f.store.updateHistory.count == 1)
    #expect(f.store.updateHistory.first?.kind == .model)
    let failed = ReviewFixture(history: ReviewHistory(fail: true), models: RuntimeScopedReviewModels(fails: false))
    defer { failed.cleanUp() }
    await failed.store.updateLocalModel(reviewModel())
    #expect(failed.store.errorMessage?.contains("history") == true)
}

@MainActor
@Test func externalBatchActionsVerifyTheInstalledBundleAndClearCompletedUpdates() async {
    let app = reviewApp()
    let updated = reviewApp(version: "1.1", build: "11")
    let f = ReviewFixture(discoveredApp: updated)
    defer { f.cleanUp() }
    let update = AvailableUpdate(app: app, availableVersion: "1.1", source: .github, releaseNotes: nil,
                                 actionURL: URL(string: "https://example.invalid/releases"), homebrewToken: nil)
    f.store.apps = [app]; f.store.updates = [update]
    let result = await f.store.performBatchUpdates([.application(update)])
    #expect(result.openedCount == 1)
    #expect(f.store.externalUpdateVerification(for: app) != nil)
    #expect(await eventually { f.store.externalUpdateVerification(for: app)?.state == .completed })
    #expect(f.store.updates.isEmpty)
}

@MainActor
@Test func reviewAndExecutionUseTheSameRunningAppListForDirectUpdates() async {
    let f = ReviewFixture()
    defer { f.cleanUp() }
    let app = reviewApp()
    f.lifecycle.running = [app]
    f.store.runningBundleIdentifiers = [app.bundleIdentifier!]
    let items: [BatchUpdateItem] = [.application(reviewUpdate(app))]
    #expect(f.store.runningAppsForBatch(items) == [app])
    #expect(await f.store.performBatchUpdates(items).updatedCount == 1)
    #expect(f.lifecycle.quitCalls == [[app]])
    #expect(f.opener.urls == [app.url])
}

@MainActor
@Test func buildOnlySparkleReleaseSurvivesDetectionValidationSelectionAndExclusion() throws {
    let app = reviewApp()
    let feed = Data("""
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
    <enclosure url="https://example.invalid/update.zip" sparkle:shortVersionString="1.0" sparkle:version="11" />
    </item></channel></rss>
    """.utf8)
    let url = URL(string: "https://example.invalid/feed.xml")!
    let item = try #require(SparkleFeedParser(data: feed, baseURL: url).parse())
    #expect(item.isNewer(than: app))
    let update = item.availableUpdate(for: app, fallbackURL: url)
    #expect(update.primaryCandidate.availableBuildVersion == "11")
    try DirectAppInstaller.validateVersion(version: "1.0", build: "11", update: update)
    #expect(throws: (any Error).self) { try DirectAppInstaller.validateVersion(version: "1.0", build: "10", update: update) }
    #expect(throws: (any Error).self) { try DirectAppInstaller.validateVersion(version: "garbage", build: "11", update: update) }
    #expect(update.selecting(update.primaryCandidate).exclusionVersion == update.exclusionVersion)
    #expect(!update.primaryCandidate.isInstalled(in: app))
    #expect(update.primaryCandidate.isInstalled(in: reviewApp(build: "11")))
    let f = ReviewFixture()
    defer { f.cleanUp() }
    f.store.skip(update)
    #expect(f.store.isExcluded(update))
    #expect(!f.store.isExcluded(reviewUpdate(app, version: "1.0", build: "12")))
    let buildNumberOnly = AvailableUpdate(app: app, availableVersion: "11", source: .sparkle, releaseNotes: nil,
                                         actionURL: url, homebrewToken: nil, availableBuildVersion: "11", usesBuildVersionOnly: true)
    try DirectAppInstaller.validateVersion(version: "1.0", build: "11", update: buildNumberOnly)
}

@Test func modelTagsRequireExplicitReleaseChannelWords() {
    for value in ["e2b", "7b", "Q4_K_M", "Q8_0", "instruct", "70b-instruct"] {
        #expect(ModelReleaseChannel.detect(in: value) == nil)
    }
    #expect(ModelReleaseChannel.detect(in: "7b-beta") == .beta)
    #expect(ModelReleaseChannel.detect(in: "preview-Q4_K_M") == .preview)
}

@MainActor
@Test func scanPresentationDistinguishesUncheckedDisabledFailedPartialAndComplete() async {
    let f = ReviewFixture()
    defer { f.cleanUp() }
    f.settings.checkMacOS = true
    #expect(f.store.macOSCheckState == .notChecked)
    #expect(f.store.updateCheckState == .notChecked)
    f.store.isScanning = true
    #expect(f.store.macOSCheckState == .checking)
    f.store.isScanning = false
    f.store.scanState.macOSStatus = .failed
    #expect(f.store.macOSCheckState == .failed)
    f.store.scanState.macOSStatus = .succeeded
    #expect(f.store.macOSCheckState == .complete)
    f.settings.checkMacOS = false
    #expect(f.store.macOSCheckState == .disabled)
    let failed = reviewScanReport(macOS: .failed)
    #expect(UpdateCheckState.completed(report: failed, settings: f.settings.scanSettings) == .failed)
    let partial = reviewScanReport(macOS: .failed, homebrew: .succeeded)
    #expect(UpdateCheckState.completed(report: partial, settings: f.settings.scanSettings) == .partial)
    #expect(UpdateCheckState.completed(report: .empty, settings: f.settings.scanSettings) == .complete)
}

@Test func combinedUpdatePlanDeduplicatesCasksWithoutHidingSameNamedFormulae() {
    let app = reviewApp()
    let update = AvailableUpdate(app: app, availableVersion: "1.1", source: .homebrew,
                                 releaseNotes: nil, actionURL: nil, homebrewToken: "fixture")
    let packages = [HomebrewPackageKind.cask, .formula].map { kind in
        HomebrewPackage(token: "fixture", displayName: "Fixture", description: nil, homepage: nil, license: nil,
                        installedVersion: "1.0", currentVersion: "1.1", kind: kind, isOutdated: true,
                        isDependency: false, dependencies: [])
    }
    let plan = UpdatePlan(applicationUpdates: [update], homebrewUpdates: packages, macOSUpdates: [], developerUpdates: [], modelUpdates: [])
    #expect(plan.unrepresentedHomebrewUpdates.map(\.kind) == [.formula])
    #expect(plan.batchItems.count == 2)
    #expect(plan.primaryUpdateCount == 2)
}

private func reviewApp(version: String = "1.0", build: String = "10", identifier: String = "test.upkeep.review") -> InstalledApp {
    InstalledApp(name: "Review Fixture", bundleIdentifier: identifier, installedVersion: version, buildVersion: build,
                 url: URL(fileURLWithPath: "/fixture/Review.app"), sparkleFeedURL: URL(string: "https://example.invalid/feed"),
                 githubRepository: nil, hasAppStoreReceipt: false)
}

private func reviewUpdate(_ app: InstalledApp, version: String = "1.1", build: String? = nil) -> AvailableUpdate {
    AvailableUpdate(app: app, availableVersion: version, source: .sparkle, releaseNotes: nil,
                    actionURL: URL(string: "https://example.invalid/app.zip"), homebrewToken: nil, availableBuildVersion: build)
}

private func reviewPackage(_ name: String, executable: String) -> DeveloperPackage {
    DeveloperPackage(name: name, currentVersion: "1.0", latestVersion: "1.1", manager: .npm, executablePath: executable)
}

private func reviewModel() -> LocalLLMModel {
    LocalLLMModel(id: "fixture", name: "fixture", variant: "e2b", runtime: .ollama, installedRevision: "old",
                  latestRevision: "new", sizeBytes: nil, modifiedAt: nil, homepage: nil, executablePath: "/fixture/ollama",
                  updateReference: "fixture", isOutdated: true)
}

private func reviewScanReport(macOS: ScanStatus, homebrew: ScanStatus = .disabled) -> ScanReport {
    ScanReport(apps: [], updates: [], checkedAt: Date(), warnings: [.init(source: .macOS, message: "offline")],
               failedAppSources: [:], homebrewInventoryStatus: homebrew, homebrewCatalogStatus: .disabled,
               macOSUpdatesStatus: macOS, macOSInstallersStatus: .disabled, failedDeveloperManagers: [], failedDeveloperExecutablePaths: [],
               localModelsStatus: .disabled, failedLocalModelIDs: [], failedLocalModelRuntimes: [], homebrewPackages: [],
               adoptableApps: [], macOSUpdates: [], developerPackages: [], installedDeveloperManagers: [], localModels: [])
}

@MainActor
private func eventually(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<1_000 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return false
}

private enum ReviewError: Error { case historyWrite, quit }
private struct ReviewScanner: UpdateScanning {
    var failedSources: Set<UpdateSource> = [.sparkle]
    var onScan: (@Sendable () async -> Void)?
    var updates: [AvailableUpdate] = []
    func scan(settings: ScanSettings) async -> ScanReport {
        await onScan?()
        return .empty
    }
    func scan(app: InstalledApp, settings: ScanSettings) async -> UpdateScanner.TargetedAppReport {
        .init(updates: updates, failedSources: failedSources, warnings: [])
    }
}
private struct ReviewDiscovery: ApplicationDiscovering {
    let app: InstalledApp
    var onDiscover: (@Sendable () async -> Void)? = nil
    func discover() async -> [InstalledApp] { [app] }
    func discover(at url: URL) async -> InstalledApp? {
        await onDiscover?()
        return app
    }
}
private struct ReviewBrew: HomebrewManaging {
    var servicesFail = false
    func services() async throws -> [HomebrewService] {
        if servicesFail { throw ScopedScanError.unavailable }
        return []
    }
    func package(token: String, kind: HomebrewPackageKind, includePrereleases: Bool) async throws -> HomebrewPackage? { nil }
    func upgrade(_ package: HomebrewPackage) async throws {}
    func adopt(_ item: AdoptableApp) async throws {}
    func installOrReplace(_ item: AdoptableApp) async throws {}
    func upgradeCask(token: String) async throws {}
}

@MainActor
@Test(arguments: [false, true]) func serviceRefreshRetainsPriorInventoryOnlyOnFailure(fails: Bool) async {
    let f = ReviewFixture(homebrew: ReviewBrew(servicesFail: fails))
    defer { f.cleanUp() }
    let previous = HomebrewService(name: "redis", status: "started", user: "fixture", file: nil, exitCode: 0)
    let lastSuccess = Date(timeIntervalSince1970: 100)
    f.store.library.homebrewServices = [previous]
    f.store.library.homebrewServicesSucceededAt = lastSuccess
    await f.store.scanHomebrewServices()
    #expect(f.store.library.homebrewServices == (fails ? [previous] : []))
    #expect(f.store.library.homebrewServicesCheckedAt != nil)
    #expect((f.store.library.homebrewServicesFailure != nil) == fails)
    #expect(!f.store.library.isCheckingHomebrewServices)
    #expect(fails ? f.store.library.homebrewServicesSucceededAt == lastSuccess
        : f.store.library.homebrewServicesSucceededAt != lastSuccess)
}
private struct ReviewDeveloper: DeveloperPackageManaging {
    let report: DeveloperPackageClient.Report
    func scan(enabledManagers: Set<DeveloperPackageManager>, includePrereleases: Bool) async -> DeveloperPackageClient.Report { report }
    func availableVersions(for package: DeveloperPackage, includePrereleases: Bool) async -> [String] { [package.latestVersion] }
    func install(_ package: DeveloperPackage, version: String) async throws {}
}
private struct ReviewModels: LocalModelManaging {
    func scan() async -> LocalModelClient.Report { .empty }
    func update(_ model: LocalLLMModel) async throws {}
}
private actor ReviewHistory: UpdateHistoryManaging {
    let fail: Bool
    let failBackup: Bool
    var saved: [UpdateRecord] = []
    var discarded = false
    var restores = 0
    init(fail: Bool = false, failBackup: Bool = false) { self.fail = fail; self.failBackup = failBackup }
    func records() async -> [UpdateRecord] { saved }
    func prepareAppBackup(app: InstalledApp, toVersion: String, kind: UpdateRecordKind) async throws -> UpdateRecord {
        if failBackup { throw ReviewError.historyWrite }
        return .init(id: UUID(), date: Date(), name: app.name, fromVersion: app.installedVersion, toVersion: toVersion,
              kind: kind, originalAppPath: app.url.path, backupPath: "/fixture/backup.app", recoveryNote: nil)
    }
    func add(_ record: UpdateRecord) async throws { if fail { throw ReviewError.historyWrite }; saved.append(record) }
    func discardBackup(for record: UpdateRecord) async { discarded = true }
    func addMacOSPlan(update: MacOSUpdate) async throws {}
    func revert(_ record: UpdateRecord) async throws { restores += 1 }
}
private actor ReviewInstaller: DirectAppInstalling {
    var calls = 0
    var continuation: CheckedContinuation<Void, Never>?
    let pause: Bool
    var released = false
    init(pause: Bool = false) { self.pause = pause }
    func install(update: AvailableUpdate) async throws {
        calls += 1
        if pause && calls == 1 && !released { await withCheckedContinuation { continuation = $0 } }
    }
    func resume() { released = true; continuation?.resume(); continuation = nil }
}
@MainActor private final class ReviewOpener: ExternalOpening {
    var urls: [URL] = []
    func open(_ url: URL) -> Bool { urls.append(url); return true }
}
@MainActor private final class ReviewLifecycle: ApplicationLifecycleManaging {
    var running: [InstalledApp] = []
    var quitCalls: [[InstalledApp]] = []
    var failQuit = false
    func runningApplications() -> RunningApplications {
        .init(identifiers: Set(running.compactMap(\.bundleIdentifier)), paths: Set(running.map { $0.url.path }))
    }
    func quit(_ apps: [InstalledApp]) async throws {
        quitCalls.append(apps)
        if failQuit { throw ReviewError.quit }
        running.removeAll { apps.contains($0) }
    }
}
@MainActor private final class ReviewFixture {
    let suite = "Upkeep.AppReviewTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let settings: AppSettings
    let history: ReviewHistory
    let installer: ReviewInstaller
    let lifecycle = ReviewLifecycle()
    let opener = ReviewOpener()
    let store: UpkeepStore
    init(history: ReviewHistory = ReviewHistory(), installer: ReviewInstaller = ReviewInstaller(),
         discoveredApp: InstalledApp = reviewApp(version: "1.1", build: "11"), developerReport: DeveloperPackageClient.Report = .empty,
         scanner: any UpdateScanning = ReviewScanner(), developer: (any DeveloperPackageManaging)? = nil, models: (any LocalModelManaging)? = nil, progressInstaller: (any DirectAppInstalling)? = nil,
         discovery: (any ApplicationDiscovering)? = nil, homebrew: any HomebrewManaging = ReviewBrew()) {
        defaults = UserDefaults(suiteName: suite)!
        settings = AppSettings(defaults: defaults)
        self.history = history; self.installer = installer
        store = UpkeepStore(settings: settings, dependencies: UpkeepDependencies(
            scanner: scanner, applicationDiscovery: discovery ?? ReviewDiscovery(app: discoveredApp), homebrew: homebrew,
            developerPackages: developer ?? ReviewDeveloper(report: developerReport), localModels: models ?? ReviewModels(), history: history,
            externalOpener: opener, directAppInstaller: progressInstaller ?? installer, applicationLifecycle: lifecycle,
            externalVerificationInterval: .milliseconds(1)
        ))
    }
    func cleanUp() { defaults.removePersistentDomain(forName: suite) }
}

@MainActor
@Test(arguments: [false, true], [false, true])
func updateButtonTracksDirectInstallStagesAndClearsAfterCompletion(fails: Bool, batch: Bool) async {
    let probe = ReviewProgressProbe()
    let app = reviewApp()
    let update = reviewUpdate(app)
    let operation = OperationID.applicationUpdate(update.id)
    let f = ReviewFixture(
        scanner: ReviewScanner(onScan: {
            await probe.observe(.refreshing, operation: operation)
        }),
        progressInstaller: ReviewProgressInstaller(fails: fails, observe: { phase in
            await probe.observe(phase, operation: operation)
        }),
        discovery: ReviewDiscovery(app: fails ? app : reviewApp(version: "1.1", build: "11"), onDiscover: {
            await probe.observe(.refreshing, operation: operation)
        })
    )
    defer { f.cleanUp() }
    probe.store = f.store
    f.store.apps = [app]
    f.store.updates = [update]

    if batch {
        let result = await f.store.performBatchUpdates([.application(update)])
        #expect(result.failedCount == (fails ? 1 : 0))
    } else {
        await f.store.performUpdate(update)
    }

    #expect(probe.observed == [.downloading, .preparing, .installing, .refreshing])
    #expect(f.store.updatePhase(for: operation) == nil)
    #expect(!f.store.isUpdating(update))
    #expect(f.store.updateExecutionState.activities.isEmpty)
    #expect(await f.history.discarded == fails)
}

@MainActor private final class ReviewProgressProbe {
    var store: UpkeepStore?
    var observed: [UpdatePhase] = []
    func observe(_ expected: UpdatePhase, operation: OperationID) {
        #expect(store?.updatePhase(for: operation) == expected)
        MutationContext.$owner.withValue(nil) {
            #expect(store?.isWorking(operation) == true)
        }
        observed.append(expected)
    }
}

@MainActor
@Test func completedAppOperationRetainsItsCommandLog() async {
    let f = ReviewFixture(progressInstaller: ReviewLoggingInstaller())
    defer { f.cleanUp() }
    let app = reviewApp()
    let update = reviewUpdate(app)
    f.store.apps = [app]
    f.store.updates = [update]
    await f.store.performUpdate(update)
    #expect(f.store.updateExecutionState.completedOperations.first?.commandLog.contains("fixture-install-output") == true)
    #expect(f.store.updateExecutionState.completedOperations.first?.result == .verified)
}

private struct ReviewLoggingInstaller: DirectAppInstalling {
    func install(update: AvailableUpdate) async throws {
        _ = try await CommandRunner.run(URL(fileURLWithPath: "/bin/echo"), ["fixture-install-output"])
    }
}

private struct ReviewProgressInstaller: DirectAppInstalling {
    let fails: Bool
    let observe: @Sendable (UpdatePhase) async -> Void
    func install(update: AvailableUpdate) async throws {
        try await install(update: update, progress: { _ in })
    }
    func install(update: AvailableUpdate, progress: @escaping UpdateProgressReporter) async throws {
        for phase: UpdatePhase in [.downloading, .preparing, .installing] {
            await progress(phase)
            await observe(phase)
        }
        if fails { throw ReviewError.historyWrite }
    }
}

@MainActor
@Test func concurrentScanRequestsWaitForAFreshFollowup() async {
    let gate = ReviewScanGate()
    let f = ReviewFixture(scanner: ReviewScanner(onScan: { await gate.scan() }))
    defer { f.cleanUp() }
    let first = Task { await f.store.scan() }
    #expect(await eventually { await gate.calls == 1 })
    var completed = false
    let second = Task { await f.store.scan(); completed = true }
    await Task.yield()
    #expect(!completed)
    await gate.resume()
    await first.value
    await second.value
    #expect(await gate.calls == 2)
    #expect(completed)
    #expect(!f.store.isScanning)
}

private actor ReviewScanGate {
    var calls = 0
    var continuation: CheckedContinuation<Void, Never>?
    func scan() async {
        calls += 1
        if calls == 1 { await withCheckedContinuation { continuation = $0 } }
    }
    func resume() { continuation?.resume(); continuation = nil }
}

@MainActor
@Test func refreshingAnotherPackageDoesNotReplaceSelectedVersions() async {
    let f = ReviewFixture()
    defer { f.cleanUp() }
    let first = reviewPackage("first", executable: "/fixture/npm")
    let second = reviewPackage("second", executable: "/fixture/npm")
    f.store.developerPackages = [first, second]
    f.store.selectedDeveloperPackageID = second.id
    f.store.availableDeveloperVersions = ["9.0"]
    f.store.selectedDeveloperVersion = "9.0"
    await f.store.refresh(first)
    #expect(f.store.availableDeveloperVersions == ["9.0"])
    #expect(f.store.selectedDeveloperVersion == "9.0")
}

@MainActor
@Test func supersededVersionRequestCannotOverwriteNewerResults() async {
    let developer = ReviewVersionGate()
    let f = ReviewFixture(developer: developer)
    defer { f.cleanUp() }
    let package = reviewPackage("first", executable: "/fixture/npm")
    f.store.developerPackages = [package]
    f.store.selectedDeveloperPackageID = package.id
    let first = Task { await f.store.loadAvailableVersions(for: package, force: true) }
    #expect(await eventually { await developer.calls == 1 })
    await f.store.loadAvailableVersions(for: package, force: true)
    await developer.resume()
    await first.value
    #expect(f.store.availableDeveloperVersions == ["3.0"])
    #expect(!f.store.isLoadingDeveloperVersions)
}

@MainActor
@Test func cancelledVersionRequestClearsLoadingState() async {
    let developer = ReviewVersionGate()
    let f = ReviewFixture(developer: developer)
    defer { f.cleanUp() }
    let package = reviewPackage("first", executable: "/fixture/npm")
    f.store.selectedDeveloperPackageID = package.id
    let request = Task { await f.store.loadAvailableVersions(for: package, force: true) }
    #expect(await eventually { await developer.calls == 1 })
    request.cancel()
    await developer.resume()
    await request.value
    #expect(!f.store.isLoadingDeveloperVersions)
}

private actor ReviewVersionGate: DeveloperPackageManaging {
    var calls = 0
    var continuation: CheckedContinuation<Void, Never>?
    func scan(enabledManagers: Set<DeveloperPackageManager>, includePrereleases: Bool) async -> DeveloperPackageClient.Report { .empty }
    func availableVersions(for package: DeveloperPackage, includePrereleases: Bool) async -> [String] {
        calls += 1
        if calls == 1 {
            await withCheckedContinuation { continuation = $0 }
            return ["2.0"]
        }
        return ["3.0"]
    }
    func resume() { continuation?.resume(); continuation = nil }
    func install(_ package: DeveloperPackage, version: String) async throws {}
}

@MainActor
@Test func homebrewBatchPreservesBackupFailureAcrossRescan() async throws {
    let f = ReviewFixture(history: ReviewHistory(failBackup: true))
    defer { f.cleanUp() }
    let app = reviewApp()
    f.store.apps = [app]
    f.store.homebrewPackages = [HomebrewPackage(
        token: "review-fixture", displayName: app.name, description: nil, homepage: nil, license: nil,
        installedVersion: "1.0", currentVersion: "1.1", kind: .cask, isOutdated: true,
        isDependency: false, dependencies: []
    )]
    await f.store.updateAllPackages()
    await f.store.confirmHomebrewAuthorization(try #require(f.store.pendingHomebrewAuthorizationConfirmation))
    #expect(f.store.errorMessage?.contains("backup") == true)
}

@MainActor
@Test func duplicateModelInventoryDoesNotCrashTargetedRefresh() async {
    let f = ReviewFixture(models: ReviewDuplicateModels())
    defer { f.cleanUp() }
    await f.store.scanLocalModels()
    #expect(f.store.localModels.count == 1)
}

private struct ReviewDuplicateModels: LocalModelManaging {
    func scan() async -> LocalModelClient.Report {
        .init(models: [reviewModel(), reviewModel()], warnings: [], failedModelIDs: [], failedRuntimes: [])
    }
    func update(_ model: LocalLLMModel) async throws {}
}

@Test func publisherDeclaredPrereleasesAreNeverRecommendedByDefault() {
    let update = AvailableUpdate(
        app: reviewApp(), availableVersion: "1.1", source: .sparkle, releaseNotes: nil,
        actionURL: URL(string: "https://example.invalid/app.zip"), homebrewToken: nil,
        sourcePrereleaseChannel: .beta
    )
    #expect(BatchUpdateItem.application(update).riskGroup == .prerelease)
    #expect(!BatchUpdateItem.application(update).isRecommendedByDefault)
}

@Test func emptyHomebrewCatalogVersionCannotCrashScan() {
    #expect(!UpdateScanner.caskIsNewer("", than: reviewApp()))
    #expect(!UpdateScanner.caskIsNewer(",", than: reviewApp()))
    #expect(UpdateScanner.caskIsNewer("1.1", than: reviewApp()))
}

@Test func newerInstalledAppSuppressesStaleHomebrewDowngrade() {
    let package = HomebrewPackage(
        token: "fixture", displayName: "Fixture", description: nil, homepage: nil, license: nil,
        installedVersion: "0.56.1", currentVersion: "0.56.2,100", kind: .cask, isOutdated: true,
        isDependency: false, dependencies: []
    )
    let reconciled = package.reconciled(with: reviewApp(version: "0.56.3"))
    #expect(!reconciled.isOutdated)
    #expect(reconciled.installedVersion == "0.56.3")
    #expect(package.reconciled(with: reviewApp(version: "0.56.1")).isOutdated)
}

@Test(arguments: ["1.1", "1.1,11", "1.1,12"])
func installedCaskReconcilesStaleReceiptWithoutHidingNewerBuild(target: String) {
    let installed = reviewApp(version: "1.1", build: "11")
    let package = HomebrewPackage(token: "fixture", displayName: installed.name, description: nil,
        homepage: nil, license: nil, installedVersion: "1.0", currentVersion: target,
        kind: .cask, isOutdated: true, isDependency: false, dependencies: [], versionScheme: 2)
    let candidate = AvailableUpdate(app: installed, availableVersion: target, source: .homebrew,
        releaseNotes: nil, actionURL: nil, homebrewToken: package.token).primaryCandidate
    let pending = target == "1.1,12"
    let reconciled = package.reconciled(with: installed)
    #expect(reconciled.isOutdated == pending)
    #expect(candidate.isNewer(than: installed) == pending)
    #expect(candidate.isInstalled(in: installed) == !pending)
    #expect(reconciled.versionScheme == 2)
    if !pending { #expect(reconciled.installedVersion == installed.installedVersion) }
}

@MainActor
@Test func refreshedInstalledAppRejectsStaleOffersAndRetainsNewerBuild() async {
    let original = reviewApp()
    let installed = reviewApp(version: "1.1", build: "11")
    let stale = reviewUpdate(original, version: "1.1")
    let newerBuild = reviewUpdate(original, version: "1.1", build: "12")
    let f = ReviewFixture(discoveredApp: installed,
        scanner: ReviewScanner(failedSources: [], updates: [stale, newerBuild]))
    defer { f.cleanUp() }
    f.store.apps = [original]
    f.store.updates = [stale]
    f.settings.checkHomebrew = false
    await f.store.refresh(original)
    #expect(f.store.updates.count == 1)
    #expect(f.store.updates.first?.app == installed)
    #expect(f.store.updates.first?.candidates == newerBuild.candidates)
}

@MainActor
@Test(arguments: ["1.1", "1.1,11"])
func refreshedCaskAtTargetLeavesUpdateListDespiteStaleReceipt(target: String) async {
    let original = reviewApp()
    let installed = reviewApp(version: "1.1", build: "11")
    let receipt = HomebrewPackage(token: "fixture", displayName: original.name, description: nil,
        homepage: nil, license: nil, installedVersion: "1.0", currentVersion: target,
        kind: .cask, isOutdated: true, isDependency: false, dependencies: [])
    let update = AvailableUpdate(app: original, availableVersion: target, source: .homebrew,
        releaseNotes: nil, actionURL: nil, homebrewToken: receipt.token)
    let f = ReviewFixture(discoveredApp: installed, scanner: ReviewScanner(failedSources: []),
        homebrew: ReceiptReviewBrew(observed: receipt))
    defer { f.cleanUp() }
    f.store.apps = [original]
    f.store.updates = [update]
    f.store.homebrewPackages = [receipt]
    await f.store.refresh(original)
    #expect(f.store.updates.isEmpty)
    #expect(f.store.visibleUpdates.isEmpty)
    #expect(f.store.totalUpdateCount == 0)
    #expect(f.store.availableBatchUpdateItems.isEmpty)
    #expect(f.store.homebrewPackages.first?.isOutdated == false)
    #expect(f.store.homebrewPackages.first?.installedVersion == installed.installedVersion)
}

@MainActor
@Test(arguments: [false, true])
func verifiedCaskBuildUpdateLeavesUpdateList(alreadyInstalled: Bool) async throws {
    let original = alreadyInstalled ? reviewApp(version: "1.1", build: "11") : reviewApp()
    let installed = reviewApp(version: "1.1", build: "11")
    let package = HomebrewPackage(token: "fixture", displayName: original.name, description: nil,
        homepage: nil, license: nil, installedVersion: "1.0", currentVersion: "1.1,11",
        kind: .cask, isOutdated: true, isDependency: false, dependencies: [])
    let update = AvailableUpdate(app: original, availableVersion: package.currentVersion, source: .homebrew,
        releaseNotes: nil, actionURL: nil, homebrewToken: package.token)
    let f = ReviewFixture(discoveredApp: installed)
    defer { f.cleanUp() }
    f.store.apps = [original]
    f.store.homebrewPackages = [package]
    f.store.updates = [update]
    await f.store.performUpdate(update)
    await f.store.confirmHomebrewAuthorization(try #require(f.store.pendingHomebrewAuthorizationConfirmation))
    #expect(f.store.updates.isEmpty)
    #expect(f.store.totalUpdateCount == 0)
    #expect(f.store.availableBatchUpdateItems.isEmpty)
    #expect(f.store.homebrewPackages.first?.isOutdated == false)
    #expect(f.store.updateHistory.count == (alreadyInstalled ? 0 : 1))
    #expect((f.store.errorMessage == nil) == !alreadyInstalled)
}

@MainActor
@Test func directVerificationClearsAnAlreadyInstalledOffer() async {
    let installed = reviewApp(version: "1.1", build: "11")
    let update = reviewUpdate(installed, version: "1.1", build: "11")
    let f = ReviewFixture(discoveredApp: installed)
    defer { f.cleanUp() }
    f.store.apps = [installed]
    f.store.updates = [update]
    await f.store.performUpdate(update)
    #expect(f.store.updates.isEmpty)
    #expect(f.store.totalUpdateCount == 0)
    #expect(f.store.updateHistory.isEmpty)
    #expect(f.store.errorMessage != nil)
}

@MainActor
@Test(arguments: [false, true])
func progressiveResultsAppearBeforeCompletionAndNewerTargetedResultsRemainOwned(targetFails: Bool) async {
    let app = reviewApp()
    let scanner = ProgressiveReviewScanner(app: app, targetFails: targetFails)
    let f = ReviewFixture(discoveredApp: reviewApp(version: "1.2"), scanner: scanner)
    defer { f.cleanUp() }
    f.settings.checkHomebrew = false
    let full = Task { await f.store.scan() }
    #expect(await eventually { await scanner.waiting })
    #expect(f.store.isScanning)
    #expect(f.store.updates.first?.availableVersion == "2.0")
    #expect(f.store.scanState.progress?.completed == 1)
    #expect(f.store.scanState.firstResultSeconds != nil)
    await f.store.refresh(app, sources: [.sparkle])
    let key = "app|\(app.id)|Sparkle"
    let targetedDate = f.settings.sourceCheckFreshness[key]?.lastAttempt
    #expect(f.store.updates.first?.availableVersion == (targetFails ? "2.0" : "3.0"))
    await scanner.resume()
    await full.value
    #expect(!f.store.isScanning)
    #expect(f.store.scanState.progress == nil)
    #expect(f.store.updates.first?.availableVersion == (targetFails ? "2.0" : "3.0"))
    #expect(f.settings.sourceCheckFreshness[key]?.lastAttempt == targetedDate)
    #expect(f.store.apps.first?.installedVersion == "1.2")
    #expect((f.store.scanState.failedAppSources[app.id]?.contains(.sparkle) == true) == targetFails)
    #expect((f.store.scanWarnings.contains { $0.source == .sparkle && $0.itemNames.contains(app.name) }) == targetFails)
    #expect(f.store.updateCheckState == (targetFails ? .partial : .complete))
    #expect(f.settings.lastChecked(for: app.updateExclusionKey) == nil)
}

@MainActor
@Test(arguments: [false, true])
func verifiedAppInstallationSurvivesOlderFullScan(commandFails: Bool) async {
    let app = reviewApp()
    let scanner = ProgressiveReviewScanner(app: app, targetFails: false)
    let f = ReviewFixture(discoveredApp: reviewApp(version: "2.0", build: "20"), scanner: scanner,
        progressInstaller: ReviewProgressInstaller(fails: commandFails, observe: { _ in }))
    defer { f.cleanUp() }
    let full = Task { await f.store.scan() }
    #expect(await eventually { await scanner.waiting })
    await f.store.performUpdate(reviewUpdate(app, version: "2.0"))
    #expect(f.store.apps.first?.installedVersion == "2.0")
    await scanner.resume()
    await full.value
    #expect(f.store.apps.first?.installedVersion == "2.0")
    #expect(f.store.apps.first?.buildVersion == "20")
    #expect(f.store.updates.isEmpty)
    #expect(f.store.updateHistory.first?.toVersion == "2.0")
    #expect(f.store.updateExecutionState.completedOperations.first?.result == .verified)
    #expect(f.store.updateExecutionState.completedOperations.first?.verification?.targetReached == true)
}

/// Offline store-publication timing: a slow optional source is represented by
/// holding the final report after the first application result is usable.
@MainActor
@Test func progressivePublicationBenchmark() async throws {
    guard ProcessInfo.processInfo.environment["UPKEEP_PROGRESS_BENCHMARK"] == "1" else { return }
    let clock = ContinuousClock()
    for sample in 0...7 {
        let scanner = ProgressiveReviewScanner(app: reviewApp(), targetFails: false)
        let fixture = ReviewFixture(scanner: scanner)
        fixture.settings.checkHomebrew = false
        let started = clock.now
        let scan = Task { await fixture.store.scan() }
        let reachedFirstResult = await eventually { await scanner.waiting }
        #expect(reachedFirstResult)
        let firstResult = fixture.store.scanState.firstResultSeconds
        #expect(firstResult != nil)
        #expect(fixture.store.isScanning)
        #expect(fixture.store.updates.first?.availableVersion == "2.0")
        let firstObserved = started.duration(to: clock.now)
        // This is a fixture delay, not measured network or package-manager work.
        try? await Task.sleep(for: .milliseconds(50))
        await scanner.resume()
        await scan.value
        let total = started.duration(to: clock.now)
        #expect(!fixture.store.isScanning)
        #expect(fixture.store.updates.first?.availableVersion == "2.0")
        #expect(firstObserved < total)
        #expect(fixture.store.scanState.firstResultSeconds == firstResult)
        print("PROGRESS_PUBLICATION_BENCHMARK sample=\(sample) first_recorded_seconds=\(firstResult ?? -1) first_observed=\(firstObserved) total=\(total) updates=\(fixture.store.updates.count) fixture_tail_ms=50")
        fixture.cleanUp()
    }
}

private actor ProgressiveReviewScanner: UpdateScanning {
    let app: InstalledApp
    var continuation: CheckedContinuation<Void, Never>?
    var waiting: Bool { continuation != nil }
    let targetFails: Bool
    init(app: InstalledApp, targetFails: Bool) { self.app = app; self.targetFails = targetFails }
    func resume() { continuation?.resume(); continuation = nil }
    func scan(settings: ScanSettings) async -> ScanReport {
        await scan(settings: settings, progress: { _ in })
    }
    func scan(settings: ScanSettings, progress: @escaping ScanProgressReporter) async -> ScanReport {
        let update = reviewUpdate(app, version: "2.0")
        await progress(.discovered([app]))
        await progress(.appSource(appID: app.id, source: .sparkle, update: update, warning: nil, completed: 1, total: 2))
        await withCheckedContinuation { continuation = $0 }
        await progress(.discovered([app]))
        await progress(.appSource(appID: app.id, source: .sparkle, update: update, warning: nil, completed: 2, total: 2))
        return ScanReport(apps: [app], updates: [update], checkedAt: Date(), warnings: [],
            failedAppSources: [:], homebrewInventoryStatus: .disabled, homebrewCatalogStatus: .disabled,
            macOSUpdatesStatus: .disabled, macOSInstallersStatus: .disabled, failedDeveloperManagers: [],
            failedDeveloperExecutablePaths: [], localModelsStatus: .disabled, failedLocalModelIDs: [],
            failedLocalModelRuntimes: [], homebrewPackages: [], adoptableApps: [], macOSUpdates: [],
            developerPackages: [], installedDeveloperManagers: [], localModels: [])
    }
    func scan(app: InstalledApp, settings: ScanSettings) async -> UpdateScanner.TargetedAppReport {
        targetFails
            ? .init(updates: [], failedSources: [.sparkle], warnings: [ScanWarning(source: .sparkle, itemNames: [app.name], message: "Targeted check offline")])
            : .init(updates: [reviewUpdate(app, version: "3.0")], failedSources: [], warnings: [])
    }
}

@MainActor
@Test func olderTargetedCheckCannotReviveResultsAfterNewerFullScan() async {
    let scanner = SupersededTargetReviewScanner()
    let f = ReviewFixture(scanner: scanner)
    defer { f.cleanUp() }
    let app = reviewApp()
    f.store.apps = [app]
    let target = Task { await f.store.refresh(app, sources: [.sparkle]) }
    #expect(await eventually { await scanner.waiting })
    await f.store.scan()
    #expect(f.store.apps.isEmpty)
    await scanner.resume()
    await target.value
    #expect(f.store.apps.isEmpty)
    #expect(f.store.updates.isEmpty)
    #expect(f.settings.sourceCheckFreshness["app|\(app.id)|Sparkle"] == nil)
}

private actor SupersededTargetReviewScanner: UpdateScanning {
    var continuation: CheckedContinuation<Void, Never>?
    var waiting: Bool { continuation != nil }
    func resume() { continuation?.resume(); continuation = nil }
    func scan(settings: ScanSettings) async -> ScanReport { .empty }
    func scan(app: InstalledApp, settings: ScanSettings) async -> UpdateScanner.TargetedAppReport {
        await withCheckedContinuation { continuation = $0 }
        return .init(updates: [reviewUpdate(app, version: "3.0")], failedSources: [], warnings: [])
    }
}

@MainActor
@Test(arguments: [false, true])
func modelRuntimeRetryPreservesOtherRuntimeResultsAndFreshness(fails: Bool) async throws {
    let client = RuntimeScopedReviewModels(fails: fails)
    let f = ReviewFixture(models: client)
    defer { f.cleanUp() }
    let model = reviewModel()
    let other = LocalLLMModel(id: "other", name: "Other", variant: nil, runtime: .lmStudio,
        installedRevision: "other-old", latestRevision: "other-new", sizeBytes: nil, modifiedAt: nil,
        homepage: nil, executablePath: "/fixture/lms", updateReference: "other", isOutdated: true)
    f.store.localModels = [model, other]
    let baseline = Date(timeIntervalSince1970: 100)
    f.settings.recordSourceAttempt("model.runtime|Ollama", at: baseline)
    f.settings.recordSourceAttempt("model.runtime|Ollama", at: baseline.addingTimeInterval(1), failure: "offline")
    f.settings.recordSourceAttempt("model|other", at: baseline, failure: "other offline")
    f.settings.recordSourceAttempt("model.runtime|LM Studio", at: baseline, failure: "other offline")
    let untouched = f.settings.sourceCheckFreshness["model.runtime|LM Studio"]
    let report = await f.store.scanLocalModels(runtime: .ollama)
    #expect(report != nil)
    #expect(await client.runtimes == [.ollama])
    #expect(await client.fullCalls == 0)
    #expect(f.store.localModels.first { $0.id == other.id } == other)
    #expect(f.store.localModels.first { $0.id == model.id }?.installedRevision == (fails ? "old" : "new"))
    #expect(f.settings.sourceCheckFreshness["model.runtime|LM Studio"] == untouched)
    #expect(f.settings.sourceCheckFreshness["model|other"]?.lastAttempt == baseline)
    let health = try #require(f.settings.sourceCheckFreshness["model.runtime|Ollama"])
    #expect((health.failure != nil) == fails)
    #expect(health.lastSuccess != nil)
    #expect(health.isRetained == fails)
}

private actor RuntimeScopedReviewModels: LocalModelManaging {
    let fails: Bool
    var runtimes: [LocalModelRuntime] = []
    var fullCalls = 0
    init(fails: Bool) { self.fails = fails }
    func scan() async -> LocalModelClient.Report { fullCalls += 1; return .empty }
    func scan(runtime: LocalModelRuntime) async -> LocalModelClient.Report {
        runtimes.append(runtime)
        let model = LocalLLMModel(id: "fixture", name: "fixture", variant: "e2b", runtime: runtime,
            installedRevision: "new", latestRevision: "new", sizeBytes: nil, modifiedAt: nil,
            homepage: nil, executablePath: "/fixture/ollama", updateReference: "fixture", isOutdated: false)
        return .init(models: fails ? [] : [model], warnings: fails ? ["offline"] : [],
            failedModelIDs: [], failedRuntimes: fails ? [runtime] : [])
    }
    func update(_ model: LocalLLMModel) async throws {}
}

@MainActor
@Test(arguments: ["updated", "unchanged", "partial", "unverified", "missing"], [false, true])
func modelMutationRecordsObservedRevisionAcrossCommandOutcomes(result: String, batch: Bool) async {
    let client = ModelMutationReviewClient(result: result)
    let f = ReviewFixture(models: client)
    defer { f.cleanUp() }
    let model = reviewModel()
    f.store.localModels = [model]
    if batch {
        let summary = await f.store.performBatchUpdates([.model(model)])
        #expect(summary.results.first?.outcome == (result == "updated" ? .updated : .failed))
        if result == "updated" { #expect(summary.results.first?.detail.contains("observed") == true) }
    } else { await f.store.updateLocalModel(model) }
    let changed = result == "updated" || result == "partial"
    #expect(f.store.updateHistory.count == (changed ? 1 : 0))
    if changed { #expect(f.store.updateHistory.first?.toVersion == "observed") }
    #expect((f.store.errorMessage == nil) == (result == "updated"))
    if result == "partial" { #expect(f.store.errorMessage?.contains("download failed") == true) }
    #expect(await client.fullCalls == 0)
    #expect(await client.runtimes == [.ollama])
    #expect(f.store.updateExecutionState.completedOperations.first?.result ==
        (changed ? .verified : result == "unchanged" ? .unchanged : .unverified))
    #expect((f.store.updateExecutionState.completedOperations.first?.commandError != nil) == (result == "partial"))
}

private actor ModelMutationReviewClient: LocalModelManaging {
    let result: String
    var fullCalls = 0
    var runtimes: [LocalModelRuntime] = []
    init(result: String) { self.result = result }
    func scan() async -> LocalModelClient.Report { fullCalls += 1; return .empty }
    func scan(runtime: LocalModelRuntime) async -> LocalModelClient.Report {
        runtimes.append(runtime)
        if result == "unverified" { return .init(models: [], warnings: ["offline"], failedModelIDs: [], failedRuntimes: [runtime]) }
        if result == "missing" { return .empty }
        let installed = result == "unchanged" ? "old" : "observed"
        let observed = LocalLLMModel(id: "fixture", name: "fixture", variant: "e2b", runtime: runtime,
            installedRevision: installed, latestRevision: "observed", sizeBytes: nil, modifiedAt: nil,
            homepage: nil, executablePath: "/fixture/ollama", updateReference: "fixture", isOutdated: result == "unchanged")
        return .init(models: [observed], warnings: [], failedModelIDs: [], failedRuntimes: [])
    }
    func update(_ model: LocalLLMModel) async throws {
        if result == "partial" { throw HomebrewClient.BrewError.failed("download failed") }
    }
}

@MainActor
@Test func modelRuntimeReservationsBlockOverlapsAndAllowIndependentRuntimes() async {
    let first = reviewModel()
    let sibling = LocalLLMModel(id: "sibling", name: "Sibling", variant: nil, runtime: .ollama,
        installedRevision: "old", latestRevision: "new", sizeBytes: nil, modifiedAt: nil,
        homepage: nil, executablePath: "/fixture/ollama", updateReference: "sibling", isOutdated: true)
    let independent = LocalLLMModel(id: "independent", name: "Independent", variant: nil, runtime: .lmStudio,
        installedRevision: "old", latestRevision: "new", sizeBytes: nil, modifiedAt: nil,
        homepage: nil, executablePath: "/fixture/lms", updateReference: "independent", isOutdated: true)
    let client = RuntimeReservationReviewModels(models: [first, sibling, independent])
    let f = ReviewFixture(models: client)
    defer { f.cleanUp() }
    f.store.localModels = [first, sibling, independent]
    let held = Task { await f.store.updateLocalModel(first) }
    #expect(await eventually { await client.waiting })
    #expect(f.store.isWorking(.localModel(sibling.id)))
    #expect(f.store.isWorking(.localModelRuntimeScan(.ollama)))
    #expect(!f.store.isWorking(.localModel(independent.id)))
    await f.store.updateLocalModel(sibling)
    #expect(await f.store.scanLocalModels(runtime: .ollama) == nil)
    #expect(await client.updated == [first.id])
    await f.store.updateLocalModel(independent)
    #expect(await client.updated == [first.id, independent.id])
    #expect(f.store.localModels.first { $0.id == independent.id }?.installedRevision == "new")
    await client.resume()
    await held.value
    #expect(!f.store.isWorking(.localModel(sibling.id)))
    #expect(f.store.localModels.first { $0.id == sibling.id }?.installedRevision == "old")
    #expect(f.store.updateHistory.count == 2)
}

private actor RuntimeReservationReviewModels: LocalModelManaging {
    let models: [LocalLLMModel]
    var updated: [String] = []
    var continuation: CheckedContinuation<Void, Never>?
    var waiting: Bool { continuation != nil }
    init(models: [LocalLLMModel]) { self.models = models }
    func resume() { continuation?.resume(); continuation = nil }
    func scan() async -> LocalModelClient.Report { .empty }
    func scan(runtime: LocalModelRuntime) async -> LocalModelClient.Report {
        let observed = models.filter { $0.runtime == runtime }.map { model in
            LocalLLMModel(id: model.id, name: model.name, variant: model.variant, runtime: runtime,
                installedRevision: updated.contains(model.id) ? "new" : "old", latestRevision: "new",
                sizeBytes: nil, modifiedAt: nil, homepage: nil, executablePath: model.executablePath,
                updateReference: model.updateReference, isOutdated: !updated.contains(model.id))
        }
        return .init(models: observed, warnings: [], failedModelIDs: [], failedRuntimes: [])
    }
    func update(_ model: LocalLLMModel) async throws {
        updated.append(model.id)
        if model.id == "fixture" { await withCheckedContinuation { continuation = $0 } }
    }
}

@MainActor
@Test(arguments: ["updated", "unchanged", "partial", "unverified", "unexpected"], [false, true])
func developerInstallRecordsObservedVersionAndVerifiesItsEnvironment(result: String, batch: Bool) async {
    let client = DeveloperMutationReviewClient(result: result)
    let f = ReviewFixture(developer: client)
    defer { f.cleanUp() }
    let package = reviewPackage("fixture", executable: "/fixture/npm")
    let independent = DeveloperPackage(name: "other", currentVersion: "1", latestVersion: "2", manager: .uv, executablePath: "/fixture/uv")
    f.store.developerPackages = [package, independent]
    if batch {
        let summary = await f.store.performBatchUpdates([.developer(package)])
        #expect(summary.results.first?.outcome == (result == "updated" ? .updated : .failed))
        if result == "updated" { #expect(summary.results.first?.detail.contains("1.1") == true) }
    } else { await f.store.installDeveloperPackage(package, version: "1.1") }
    #expect(await client.checkedManagers == [[.npm]])
    #expect(f.store.developerPackages.contains(independent))
    let changed = ["updated", "partial", "unexpected"].contains(result)
    #expect(f.store.updateHistory.count == (changed ? 1 : 0))
    if changed {
        #expect(f.store.updateHistory.first?.toVersion == (result == "unexpected" ? "1.2" : "1.1"))
    }
    #expect((f.store.errorMessage == nil) == (result == "updated"))
    if result == "partial" { #expect(f.store.errorMessage?.contains("download failed") == true) }
    if result == "unexpected" { #expect(f.store.errorMessage?.contains("requested version") == true) }
    if result != "unverified" {
        #expect(f.store.updateExecutionState.completedOperations.first?.verification?.requested == "1.1")
        #expect(f.store.updateExecutionState.completedOperations.first?.verification?.targetReached ==
            (result == "updated" || result == "partial"))
    } else {
        #expect(f.store.updateExecutionState.completedOperations.first?.verification == nil)
    }
    #expect(f.store.updateExecutionState.completedOperations.first?.result ==
        (changed ? .verified : result == "unchanged" ? .unchanged : .unverified))
    #expect((f.store.updateExecutionState.completedOperations.first?.commandError != nil) == (result == "partial"))
}

@MainActor
@Test func completedDeveloperOperationRechecksManagerWithoutRepeatingInstall() async {
    let client = DeveloperMutationReviewClient(result: "updated")
    let f = ReviewFixture(developer: client)
    defer { f.cleanUp() }
    let package = reviewPackage("fixture", executable: "/fixture/npm")
    f.store.developerPackages = [package]
    await f.store.installDeveloperPackage(package, version: "1.1")
    let operation = OperationID.developerPackage(package.id)
    #expect(f.store.canCheckOperation(operation))
    await f.store.checkCompletedOperation(operation)
    #expect(await client.checkedManagers == [[.npm], [.npm]])
    #expect(f.store.updateHistory.count == 1)
    #expect(f.store.updateExecutionState.completedOperations.count == 1)
    f.store.developerPackages = []
    #expect(!f.store.canCheckOperation(operation))
    await f.store.checkCompletedOperation(operation)
    #expect(await client.checkedManagers.count == 2)
}

@MainActor
@Test func operationRetryPreservesCaskAuthorizationAndRejectsSatisfiedTargets() async {
    let f = ReviewFixture()
    defer { f.cleanUp() }
    let package = HomebrewPackage(token: "retry-fixture", displayName: "Retry Fixture", description: nil,
        homepage: nil, license: nil, installedVersion: "1", currentVersion: "2", kind: .cask,
        isOutdated: true, isDependency: false, dependencies: [])
    let operation = OperationID.homebrewPackage(package.id)
    f.store.homebrewPackages = [package]
    #expect(f.store.canRetryOperation(operation))
    await f.store.retryCompletedOperation(operation)
    #expect(f.store.pendingHomebrewAuthorizationConfirmation?.itemName == package.displayName)
    #expect(f.store.updateHistory.isEmpty)
    #expect(f.store.updateExecutionState.activities.isEmpty)
    f.store.homebrewPackages = [HomebrewPackage(token: package.token, displayName: package.displayName,
        description: nil, homepage: nil, license: nil, installedVersion: "2", currentVersion: "2", kind: .cask,
        isOutdated: false, isDependency: false, dependencies: [])]
    f.store.pendingHomebrewAuthorizationConfirmation = nil
    #expect(!f.store.canRetryOperation(operation))
    await f.store.retryCompletedOperation(operation)
    #expect(f.store.pendingHomebrewAuthorizationConfirmation == nil)
}

private actor DeveloperMutationReviewClient: DeveloperPackageManaging {
    let result: String
    var checkedManagers: [Set<DeveloperPackageManager>] = []
    init(result: String) { self.result = result }
    func scan(enabledManagers: Set<DeveloperPackageManager>, includePrereleases: Bool) async -> DeveloperPackageClient.Report {
        checkedManagers.append(enabledManagers)
        let failed = result == "unverified"
        let version = result == "unexpected" ? "1.2" : result == "unchanged" ? "1.0" : "1.1"
        let observed = DeveloperPackage(name: "fixture", currentVersion: version, latestVersion: "1.2",
            manager: .npm, executablePath: "/fixture/npm")
        return .init(packages: failed ? [] : [observed], installedManagers: [.npm], warnings: failed ? ["offline"] : [],
            failedManagers: failed ? [.npm] : [], failedExecutablePaths: [])
    }
    func availableVersions(for package: DeveloperPackage, includePrereleases: Bool) async -> [String] { [] }
    func install(_ package: DeveloperPackage, version: String) async throws {
        if result == "partial" { throw HomebrewClient.BrewError.failed("download failed") }
    }
}

@MainActor
@Test(arguments: ["updated", "newer", "unchanged", "partial", "unverified"], ["individual", "batch", "all", "adoptable", "fallback", "batchAdoptable", "individualFallback"])
func caskVerificationUsesInstalledBundleAndProtectsUnverifiedRecovery(result: String, mode: String) async throws {
    let app = reviewApp()
    let observedVersion = result == "newer" ? "1.2" : "1.1"
    let successful = result == "updated" || result == "newer"
    let installed: InstalledApp? = result == "unverified" ? nil
        : result == "unchanged" ? app : reviewApp(version: observedVersion, build: "11")
    let history = ReviewHistory()
    let f = ReviewFixture(history: history, discovery: CaskReviewDiscovery(installed: installed),
        homebrew: CaskReviewBrew(partial: result == "partial"))
    defer { f.cleanUp() }
    let package = HomebrewPackage(token: "review-fixture", displayName: app.name, description: nil,
        homepage: nil, license: nil, installedVersion: "1.0", currentVersion: "1.1", kind: .cask,
        isOutdated: true, isDependency: false, dependencies: [])
    if mode == "all" { f.store.scanWarnings = [ScanWarning(source: .homebrew, message: "Cask catalog: offline")] }
    f.store.apps = [app]
    f.store.homebrewPackages = [package]
    #expect(f.store.homebrewPackageApp(for: package) != nil)
    if mode == "individualFallback" {
        f.store.homebrewPackages = []
        let update = AvailableUpdate(app: app, availableVersion: "1.1", source: .homebrew,
            releaseNotes: nil, actionURL: nil, homebrewToken: package.token)
        await f.store.performUpdate(update)
        await f.store.confirmHomebrewAuthorization(try #require(f.store.pendingHomebrewAuthorizationConfirmation))
    } else if mode == "fallback" || mode == "batchAdoptable" {
        f.store.homebrewPackages = []
        if mode == "batchAdoptable" {
            f.store.adoptableApps = [AdoptableApp(app: app, caskToken: package.token, caskVersion: package.currentVersion)]
        }
        let update = AvailableUpdate(app: app, availableVersion: "1.1", source: .homebrew,
            releaseNotes: nil, actionURL: nil, homebrewToken: package.token)
        let summary = await f.store.performBatchUpdates([.application(update)])
        #expect(summary.updatedCount == (successful ? 1 : 0))
        if successful { #expect(summary.results.first?.detail == "Updated to \(observedVersion).") }
    } else if mode == "batch" {
        let summary = await f.store.performBatchUpdates([.homebrew(package)])
        #expect(summary.updatedCount == (successful ? 1 : 0))
        if successful { #expect(summary.results.first?.detail == "Updated to \(observedVersion).") }
    } else {
        if mode == "all" { await f.store.updateAllPackages() }
        else if mode == "adoptable" {
            await f.store.updateAdoptableApp(AdoptableApp(app: app, caskToken: package.token, caskVersion: package.currentVersion))
        } else { await f.store.updatePackage(package) }
        let confirmation = try #require(f.store.pendingHomebrewAuthorizationConfirmation)
        await f.store.confirmHomebrewAuthorization(confirmation)
    }
    let changed = successful || result == "partial"
    #expect(f.store.updateHistory.count == (changed ? 1 : 0))
    if changed { #expect(f.store.updateHistory.first?.toVersion == observedVersion) }
    #expect(await history.discarded == (result == "unchanged"))
    #expect((f.store.errorMessage == nil) == successful)
    if result == "partial" { #expect(f.store.errorMessage?.contains("Installed 1.1") == true) }
    if result == "unverified" { #expect(f.store.errorMessage?.contains("backup was retained") == true) }
}

private struct CaskReviewDiscovery: ApplicationDiscovering {
    let installed: InstalledApp?
    func discover() async -> [InstalledApp] { installed.map { [$0] } ?? [] }
    func discover(at url: URL) async -> InstalledApp? { installed }
}
private struct CaskReviewBrew: HomebrewManaging {
    let partial: Bool
    func package(token: String, kind: HomebrewPackageKind, includePrereleases: Bool) async throws -> HomebrewPackage? { nil }
    func upgrade(_ package: HomebrewPackage) async throws {
        if partial { throw HomebrewClient.BrewError.failed("download failed") }
    }
    func adopt(_ item: AdoptableApp) async throws {}
    func installOrReplace(_ item: AdoptableApp) async throws {
        if partial { throw HomebrewClient.BrewError.failed("download failed") }
    }
    func upgradeCask(token: String) async throws {
        if partial { throw HomebrewClient.BrewError.failed("download failed") }
    }
}

@MainActor
@Test(arguments: ["registered", "unchanged", "partial", "unverified"])
func adoptionVerifiesHomebrewRegistrationWithoutInventingVersionHistory(result: String) async throws {
    let app = reviewApp()
    let item = AdoptableApp(app: app, caskToken: "review-fixture", caskVersion: "1.1")
    let f = ReviewFixture(homebrew: AdoptionReviewBrew(result: result))
    defer { f.cleanUp() }
    f.store.apps = [app]
    f.store.adoptableApps = [item]
    await f.store.adopt(item)
    await f.store.confirmHomebrewAuthorization(try #require(f.store.pendingHomebrewAuthorizationConfirmation))
    let registered = result == "registered" || result == "partial"
    #expect(f.store.homebrewPackages.count == (registered ? 1 : 0))
    #expect(f.store.adoptableApps.isEmpty == registered)
    #expect(f.store.updateHistory.isEmpty)
    #expect((f.store.errorMessage == nil) == (result == "registered"))
    #expect(f.store.updateExecutionState.completedOperations.first?.result == (registered ? .registered : .unverified))
    if result == "partial" { #expect(f.store.errorMessage?.contains("Homebrew registered") == true) }
}

@MainActor
@Test(arguments: ["registered", "partial"])
func verifiedAdoptionSurvivesOlderCatalogueScan(result: String) async throws {
    let item = AdoptableApp(app: reviewApp(), caskToken: "review-fixture", caskVersion: "1.1")
    let scanner = PausedAdoptionReviewScanner(item: item)
    let f = ReviewFixture(scanner: scanner, homebrew: AdoptionReviewBrew(result: result))
    defer { f.cleanUp() }
    let full = Task { await f.store.scan() }
    #expect(await eventually { await scanner.waiting })
    f.store.apps = [item.app]
    f.store.adoptableApps = [item]
    await f.store.adopt(item)
    await f.store.confirmHomebrewAuthorization(try #require(f.store.pendingHomebrewAuthorizationConfirmation))
    await scanner.resume()
    await full.value
    #expect(f.store.homebrewPackages.contains { $0.token == item.caskToken })
    #expect(f.store.adoptableApps.isEmpty)
    #expect(f.store.updateHistory.isEmpty)
}

private actor PausedAdoptionReviewScanner: UpdateScanning {
    let item: AdoptableApp
    var continuation: CheckedContinuation<Void, Never>?
    var waiting: Bool { continuation != nil }
    init(item: AdoptableApp) { self.item = item }
    func resume() { continuation?.resume(); continuation = nil }
    func scan(settings: ScanSettings) async -> ScanReport {
        await withCheckedContinuation { continuation = $0 }
        return ScanReport(apps: [item.app], updates: [], checkedAt: Date(), warnings: [],
            failedAppSources: [:], homebrewInventoryStatus: .succeeded, homebrewCatalogStatus: .succeeded,
            macOSUpdatesStatus: .disabled, macOSInstallersStatus: .disabled, failedDeveloperManagers: [],
            failedDeveloperExecutablePaths: [], localModelsStatus: .disabled, failedLocalModelIDs: [],
            failedLocalModelRuntimes: [], homebrewPackages: [], adoptableApps: [item], macOSUpdates: [],
            developerPackages: [], installedDeveloperManagers: [], localModels: [])
    }
    func scan(app: InstalledApp, settings: ScanSettings) async -> UpdateScanner.TargetedAppReport { .empty }
}

private struct AdoptionReviewBrew: HomebrewManaging {
    let result: String
    func package(token: String, kind: HomebrewPackageKind, includePrereleases: Bool) async throws -> HomebrewPackage? {
        if result == "unverified" { throw HomebrewClient.BrewError.failed("offline") }
        guard result != "unchanged" else { return nil }
        return HomebrewPackage(token: token, displayName: "Review Fixture", description: nil,
            homepage: nil, license: nil, installedVersion: "1.0", currentVersion: "1.1", kind: .cask,
            isOutdated: true, isDependency: false, dependencies: [])
    }
    func adopt(_ item: AdoptableApp) async throws {
        if result == "partial" { throw HomebrewClient.BrewError.failed("registration follow-up failed") }
    }
    func upgrade(_ package: HomebrewPackage) async throws {}
    func installOrReplace(_ item: AdoptableApp) async throws {}
    func upgradeCask(token: String) async throws {}
}

@Test func bundleVerificationDistinguishesUnchangedBuildUpdatesAndIncompleteTargets() {
    let original = reviewApp(version: "1.0", build: "10")
    #expect(AppInstallationVerification.evaluate(original: original, observed: nil, targetVersion: "1.1") == .unverified)
    #expect(AppInstallationVerification.evaluate(original: original,
        observed: reviewApp(version: "1.1", identifier: "another.app"), targetVersion: "1.1") == .unverified)
    #expect(AppInstallationVerification.evaluate(original: original,
        observed: reviewApp(version: ""), targetVersion: "1.1") == .unverified)
    #expect(AppInstallationVerification.evaluate(original: original, observed: original, targetVersion: "1.1") == .unchanged)
    #expect(AppInstallationVerification.evaluate(original: original, observed: reviewApp(version: "1.0", build: "11"),
        targetVersion: "1.0", targetBuild: "11") == .changed(targetReached: true))
    #expect(AppInstallationVerification.evaluate(original: original, observed: reviewApp(version: "1.0", build: "11"),
        targetVersion: "1.0", targetBuild: "12") == .changed(targetReached: false))
    #expect(AppInstallationVerification.evaluate(original: original, observed: reviewApp(version: "1.2", build: "12"),
        targetVersion: "1.1", targetBuild: "99") == .changed(targetReached: true))
    #expect(AppInstallationVerification.evaluate(original: original, observed: reviewApp(version: "0.9", build: "11"),
        targetVersion: "1.1") == .changed(targetReached: false))
}

@MainActor
@Test(arguments: ["updated", "unchanged", "partial", "unverified", "incomplete"], [false, true])
func individualDirectInstallVerifiesObservedBundle(result: String, batch: Bool) async {
    let app = reviewApp()
    let installed: InstalledApp? = result == "unverified" ? nil : result == "unchanged" ? app
        : reviewApp(version: "1.1", build: "11")
    let f = ReviewFixture(progressInstaller: ReviewProgressInstaller(fails: result == "partial", observe: { _ in }),
        discovery: CaskReviewDiscovery(installed: installed))
    defer { f.cleanUp() }
    f.store.apps = [app]
    let update = reviewUpdate(app, version: result == "incomplete" ? "1.2" : "1.1")
    if batch {
        let summary = await f.store.performBatchUpdates([.application(update)])
        #expect(summary.updatedCount == (result == "updated" ? 1 : 0))
    } else { await f.store.performUpdate(update) }
    let changed = result == "updated" || result == "partial" || result == "incomplete"
    #expect(f.store.updateHistory.count == (changed ? 1 : 0))
    if changed { #expect(f.store.updateHistory.first?.toVersion == installed?.installedVersion) }
    #expect(await f.history.discarded == (result == "unchanged"))
    #expect((f.store.errorMessage == nil) == (result == "updated"))
}

@Test func historyBuildVersionsRoundTripAndOldRecordsRemainReadable() throws {
    let record = UpdateRecord(id: UUID(), date: Date(), name: "Fixture", fromVersion: "1.0", toVersion: "1.0",
        kind: .app, originalAppPath: nil, backupPath: nil, recoveryNote: nil,
        fromBuildVersion: "10", toBuildVersion: "11")
    let data = try JSONEncoder().encode(record)
    #expect(try JSONDecoder().decode(UpdateRecord.self, from: data) == record)
    #expect(record.fromVersionLabel == "1.0 (build 10)")
    #expect(record.toVersionLabel == "1.0 (build 11)")
    var old = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    old.removeValue(forKey: "fromBuildVersion")
    old.removeValue(forKey: "toBuildVersion")
    let decoded = try JSONDecoder().decode(UpdateRecord.self, from: JSONSerialization.data(withJSONObject: old))
    #expect(decoded.fromBuildVersion == nil)
    #expect(decoded.toBuildVersion == nil)
    #expect(decoded.fromVersionLabel == "1.0")
}

@MainActor
@Test(arguments: ["registered", "unchanged", "unverified"])
func packageRefreshUpdatesSourceHealthWithoutAdvancingGlobalSchedule(result: String) async throws {
    let f = ReviewFixture(homebrew: AdoptionReviewBrew(result: result))
    defer { f.cleanUp() }
    let package = HomebrewPackage(token: "fixture", displayName: "Fixture", description: nil,
        homepage: nil, license: nil, installedVersion: "1.0", currentVersion: "1.1", kind: .cask,
        isOutdated: true, isDependency: false, dependencies: [])
    f.store.homebrewPackages = [package]
    let baseline = Date(timeIntervalSince1970: 100)
    let key = "homebrew|Cask|fixture"
    f.settings.lastCompletedScanDate = baseline
    f.settings.recordSourceAttempt(key, at: baseline, failure: "Previous failure")
    await f.store.refresh(package)
    let health = try #require(f.settings.sourceCheckFreshness[key])
    #expect(health.lastAttempt > baseline)
    #expect((health.lastSuccess != nil) == (result == "registered"))
    #expect((health.failure == nil) == (result == "registered"))
    #expect(f.settings.lastCompletedScanDate == baseline)
}

@MainActor
@Test(arguments: [false, true])
func scopedInventoryRetryRetainsFailuresAndDoesNotChangeGlobalSchedule(fails: Bool) async throws {
    let f = ReviewFixture(scanner: InventoryReviewScanner(fails: fails))
    defer { f.cleanUp() }
    let retained = HomebrewPackage(token: "retained", displayName: "Retained", description: nil,
        homepage: nil, license: nil, installedVersion: "1", currentVersion: "2", kind: .formula,
        isOutdated: true, isDependency: false, dependencies: [])
    f.store.homebrewPackages = [retained]
    let baseline = Date(timeIntervalSince1970: 100)
    f.settings.lastCompletedScanDate = baseline
    f.store.scanWarnings = [ScanWarning(source: .homebrew, message: "Installed packages: old"),
        ScanWarning(source: .homebrew, message: "Cask catalog: other failure")]
    await f.store.scanHomebrewInventory()
    #expect(f.store.homebrewPackages.isEmpty == !fails)
    let health = try #require(f.settings.sourceCheckFreshness["homebrew.inventory"])
    #expect((health.failure != nil) == fails)
    #expect((health.lastSuccess != nil) == !fails)
    #expect(f.settings.lastCompletedScanDate == baseline)
    #expect(f.store.scanWarnings.count == (fails ? 2 : 1))
    #expect(f.store.scanWarnings.contains { $0.message == "Cask catalog: other failure" })
}

private struct InventoryReviewScanner: UpdateScanning {
    let fails: Bool
    var packages: [HomebrewPackage] = []
    func macOS(scope: MacOSScanScope) async throws -> MacOSUpdateClient.Report {
        .init(updates: [], currentVersion: "", currentBuild: "", isRunningBeta: false,
            updatesSucceeded: !fails, installersSucceeded: !fails, warnings: fails ? ["offline"] : [])
    }
    func homebrewCatalog() async throws -> [CatalogCask] {
        if fails { throw HomebrewClient.BrewError.failed("offline") }
        return []
    }
    func homebrewInventory(includePrereleases: Bool) async throws -> [HomebrewPackage] {
        if fails { throw HomebrewClient.BrewError.failed("offline") }
        return packages
    }
    func scan(settings: ScanSettings) async -> ScanReport { .empty }
    func scan(app: InstalledApp, settings: ScanSettings) async -> UpdateScanner.TargetedAppReport { .empty }
}

@MainActor
@Test(arguments: [false, true])
func scopedCatalogRetryRetainsFailuresWithoutChangingInventory(fails: Bool) async throws {
    let f = ReviewFixture(scanner: InventoryReviewScanner(fails: fails))
    defer { f.cleanUp() }
    let app = reviewApp()
    let offer = AdoptableApp(app: app, caskToken: "fixture", caskVersion: "1.1")
    f.store.apps = [app]
    f.store.adoptableApps = [offer]
    let baseline = Date(timeIntervalSince1970: 100)
    f.settings.lastCompletedScanDate = baseline
    await f.store.scanHomebrewCatalog()
    #expect(f.store.adoptableApps.isEmpty == !fails)
    #expect(f.store.apps == [app])
    #expect(f.store.homebrewPackages.isEmpty)
    let health = try #require(f.settings.sourceCheckFreshness["homebrew.catalog"])
    #expect((health.failure != nil) == fails)
    #expect((health.lastSuccess != nil) == !fails)
    #expect(f.settings.lastCompletedScanDate == baseline)
}

@MainActor
@Test(arguments: [false, true], [MacOSScanScope.updates, .installers])
func scopedMacOSRetryPreservesOtherListAndFailedResults(fails: Bool, scope: MacOSScanScope) async throws {
    let f = ReviewFixture(scanner: InventoryReviewScanner(fails: fails))
    defer { f.cleanUp() }
    let existing = [false, true].map { installer in
        MacOSUpdate(label: installer ? "installer" : "update", title: "macOS", version: "27",
            size: nil, requiresRestart: true, isBeta: false, isFullInstaller: installer)
    }
    f.store.macOSUpdates = existing
    f.store.scanWarnings = [
        ScanWarning(source: .macOS, message: "Available updates: previous failure"),
        ScanWarning(source: .macOS, message: "Full installers: previous failure")
    ]
    let baseline = Date(timeIntervalSince1970: 100)
    f.settings.lastCompletedScanDate = baseline
    await f.store.scanMacOSSource(scope)
    #expect(f.store.macOSUpdates.count == (fails ? 2 : 1))
    if !fails { #expect(f.store.macOSUpdates.first?.isFullInstaller == (scope == .updates)) }
    let key = scope == .updates ? "macos.updates" : "macos.installers"
    let health = try #require(f.settings.sourceCheckFreshness[key])
    #expect((health.failure != nil) == fails)
    #expect((health.lastSuccess != nil) == !fails)
    #expect(f.settings.lastCompletedScanDate == baseline)
    let prefix = scope == .updates ? "Available updates:" : "Full installers:"
    #expect(f.store.scanWarnings.contains { $0.message.hasPrefix(prefix) } == fails)
    #expect(f.store.scanWarnings.count == (fails ? 2 : 1))
    if scope == .updates { #expect(f.store.scanState.macOSStatus == (fails ? .failed : .succeeded)) }
}

@MainActor
@Test(arguments: ["inventory", "catalog", "updates", "installers"], [false, true])
func newerFullScanSupersedesPausedAggregateRetry(source: String, fails: Bool) async {
    let scanner = PausedAggregateReviewScanner(fails: fails)
    let f = ReviewFixture(scanner: scanner)
    defer { f.cleanUp() }
    let retry = Task {
        switch source {
        case "inventory": await f.store.scanHomebrewInventory()
        case "catalog": await f.store.scanHomebrewCatalog()
        default: await f.store.scanMacOSSource(source == "updates" ? .updates : .installers)
        }
    }
    #expect(await eventually { await scanner.started })
    await f.store.scan()
    let key = source == "inventory" ? "homebrew.inventory" : source == "catalog" ? "homebrew.catalog" : "macos.\(source)"
    let newer = Date(timeIntervalSince1970: 123)
    f.settings.recordSourceAttempt(key, at: newer, failure: "Newer scan owns this state")
    let expected = f.settings.sourceCheckFreshness[key]
    await scanner.resume()
    await retry.value
    #expect(f.settings.sourceCheckFreshness[key] == expected)
    #expect(f.store.errorMessage == nil)
    #expect(f.store.homebrewPackages.isEmpty)
    #expect(f.store.adoptableApps.isEmpty)
    #expect(f.store.macOSUpdates.isEmpty)
}

private actor PausedAggregateReviewScanner: UpdateScanning {
    let fails: Bool
    var started = false
    var continuation: CheckedContinuation<Void, Never>?
    init(fails: Bool) { self.fails = fails }
    func pause() async throws {
        started = true
        await withCheckedContinuation { continuation = $0 }
        if fails { throw HomebrewClient.BrewError.failed("older failure") }
    }
    func resume() { continuation?.resume(); continuation = nil }
    func homebrewInventory(includePrereleases: Bool) async throws -> [HomebrewPackage] {
        try await pause()
        return [HomebrewPackage(token: "older", displayName: "Older", description: nil, homepage: nil,
            license: nil, installedVersion: "1", currentVersion: "2", kind: .formula,
            isOutdated: true, isDependency: false, dependencies: [])]
    }
    func homebrewCatalog() async throws -> [CatalogCask] { try await pause(); return [] }
    func macOS(scope: MacOSScanScope) async throws -> MacOSUpdateClient.Report { try await pause(); return .empty }
    func scan(settings: ScanSettings) async -> ScanReport { .empty }
    func scan(app: InstalledApp, settings: ScanSettings) async -> UpdateScanner.TargetedAppReport { .empty }
}

@MainActor
@Test(arguments: [false, true])
func inventoryRetryRebuildsCaskOffersWhilePreservingOtherSources(outdated: Bool) async {
    let app = reviewApp()
    let package = HomebrewPackage(token: "review-fixture", displayName: app.name, description: nil,
        homepage: nil, license: nil, installedVersion: "1.0", currentVersion: "1.1", kind: .cask,
        isOutdated: outdated, isDependency: false, dependencies: [])
    let f = ReviewFixture(scanner: InventoryReviewScanner(fails: false, packages: [package]))
    defer { f.cleanUp() }
    f.store.apps = [app]
    let old = AvailableUpdate(app: app, availableVersion: "9.0", source: .homebrew,
        releaseNotes: nil, actionURL: nil, homebrewToken: package.token)
    f.store.updates = [AvailableUpdate(app: app, candidates: old.candidates + reviewUpdate(app).candidates)]
    f.store.adoptableApps = [AdoptableApp(app: app, caskToken: package.token, caskVersion: "1.1")]
    await f.store.scanHomebrewInventory()
    let candidates = f.store.updates.first?.candidates ?? []
    #expect(candidates.contains { $0.source == .sparkle })
    #expect(candidates.contains { $0.source == .homebrew } == outdated)
    #expect(!candidates.contains { $0.availableVersion == "9.0" })
    #expect(f.store.adoptableApps.isEmpty)
}

@MainActor
@Test func homebrewInventoryProgressAppearsBeforeFullScanFinishes() async {
    let scanner = PausedInventoryProgressScanner()
    let f = ReviewFixture(scanner: scanner)
    defer { f.cleanUp() }
    let task = Task { await f.store.scan() }
    #expect(await eventually { await scanner.paused })
    #expect(f.store.isScanning)
    #expect(f.store.homebrewPackages.first?.token == "progressive")
    #expect(f.store.scanState.firstResultSeconds != nil)
    await scanner.resume()
    await task.value
    #expect(!f.store.isScanning)
}

@MainActor
@Test func verifiedFormulaReceiptSurvivesOlderInventoryScan() async {
    let scanner = PausedInventoryProgressScanner()
    let observed = HomebrewPackage(token: "progressive", displayName: "Progressive", description: nil,
        homepage: nil, license: nil, installedVersion: "2", currentVersion: "2", kind: .formula,
        isOutdated: false, isDependency: false, dependencies: [])
    let f = ReviewFixture(scanner: scanner, homebrew: ReceiptReviewBrew(observed: observed))
    defer { f.cleanUp() }
    let full = Task { await f.store.scan() }
    #expect(await eventually { await scanner.paused })
    guard let original = f.store.homebrewPackages.first else { Issue.record("Missing fixture package"); return }
    await f.store.updatePackage(original)
    await scanner.resume()
    await full.value
    #expect(f.store.homebrewPackages.first?.installedVersion == "2")
    #expect(f.store.homebrewPackages.first?.isOutdated == false)
    #expect(f.store.updateHistory.first?.toVersion == "2")
}

@MainActor
@Test(arguments: [false, true], [false, true])
func formulaRevisionReceiptPreservesActualVersionInSingleAndBatch(batch: Bool, commandFails: Bool) async {
    let original = HomebrewPackage(token: "revision-fixture", displayName: "Revision Fixture", description: nil,
        homepage: nil, license: nil, installedVersion: "1.2_3", currentVersion: "1.2_4", kind: .formula,
        isOutdated: true, isDependency: false, dependencies: [], versionScheme: 2)
    let observed = HomebrewPackage(token: original.token, displayName: original.displayName, description: nil,
        homepage: nil, license: nil, installedVersion: "1.2_4", currentVersion: "1.2_4", kind: .formula,
        isOutdated: false, isDependency: false, dependencies: [], versionScheme: 2)
    let f = ReviewFixture(homebrew: ReceiptReviewBrew(observed: observed, commandFails: commandFails))
    defer { f.cleanUp() }
    f.store.homebrewPackages = [original]
    #expect(original.isRevisionUpdate)
    if batch {
        let result = await f.store.performBatchUpdates([.homebrew(original)])
        #expect(result.updatedCount == (commandFails ? 0 : 1))
        #expect(result.failedCount == (commandFails ? 1 : 0))
    } else { await f.store.updatePackage(original) }
    #expect(f.store.homebrewPackages.first?.installedVersion == "1.2_4")
    #expect(f.store.homebrewPackages.first?.versionScheme == 2)
    #expect(f.store.updateHistory.first?.fromVersion == "1.2_3")
    #expect(f.store.updateHistory.first?.toVersion == "1.2_4")
}

private struct ReceiptReviewBrew: HomebrewManaging {
    let observed: HomebrewPackage
    var commandFails = false
    func package(token: String, kind: HomebrewPackageKind, includePrereleases: Bool) async throws -> HomebrewPackage? { observed }
    func upgrade(_ package: HomebrewPackage) async throws {
        if commandFails { throw HomebrewClient.BrewError.failed("Fixture command failed after changing the revision") }
    }
    func adopt(_ item: AdoptableApp) async throws {}
    func installOrReplace(_ item: AdoptableApp) async throws {}
    func upgradeCask(token: String) async throws {}
}

private actor PausedInventoryProgressScanner: UpdateScanning {
    var paused = false
    var continuation: CheckedContinuation<Void, Never>?
    func scan(settings: ScanSettings, progress: @escaping ScanProgressReporter) async -> ScanReport {
        let package = HomebrewPackage(token: "progressive", displayName: "Progressive", description: nil,
            homepage: nil, license: nil, installedVersion: "1", currentVersion: "2", kind: .formula,
            isOutdated: true, isDependency: false, dependencies: [])
        await progress(.homebrewInventory([package]))
        paused = true
        await withCheckedContinuation { continuation = $0 }
        await progress(.homebrewInventory([package]))
        return .empty
    }
    func resume() { continuation?.resume(); continuation = nil }
    func scan(settings: ScanSettings) async -> ScanReport { .empty }
    func scan(app: InstalledApp, settings: ScanSettings) async -> UpdateScanner.TargetedAppReport { .empty }
}

@MainActor
@Test(arguments: [false, true])
func macOSProgressAppearsEarlyAndRetainsFailedScope(updateFails: Bool) async {
    let scanner = PausedSystemProgressScanner(updateFails: updateFails)
    let f = ReviewFixture(scanner: scanner)
    defer { f.cleanUp() }
    f.store.macOSUpdates = [false, true].map { installer in
        MacOSUpdate(label: installer ? "old-installer" : "old-update", title: "macOS", version: "26",
            size: nil, requiresRestart: true, isBeta: false, isFullInstaller: installer)
    }
    let task = Task { await f.store.scan() }
    #expect(await eventually { await scanner.paused })
    #expect(f.store.isScanning)
    #expect(f.store.macOSUpdates.contains { $0.label == (updateFails ? "old-update" : "new-update") })
    #expect(f.store.macOSUpdates.contains { $0.label == (updateFails ? "new-installer" : "old-installer") })
    #expect(f.store.scanState.macOSStatus == (updateFails ? .failed : .succeeded))
    await scanner.resume()
    await task.value
}

private actor PausedSystemProgressScanner: UpdateScanning {
    let updateFails: Bool
    var paused = false
    var continuation: CheckedContinuation<Void, Never>?
    init(updateFails: Bool) { self.updateFails = updateFails }
    func scan(settings: ScanSettings, progress: @escaping ScanProgressReporter) async -> ScanReport {
        let entries = [false, true].map { installer in
            MacOSUpdate(label: installer ? "new-installer" : "new-update", title: "macOS", version: "27",
                size: nil, requiresRestart: true, isBeta: false, isFullInstaller: installer)
        }
        await progress(.macOS(.init(updates: entries, currentVersion: "", currentBuild: "", isRunningBeta: false,
            updatesSucceeded: !updateFails, installersSucceeded: updateFails, warnings: ["offline"]),
            includeInstallers: true, includePrereleases: false))
        paused = true
        await withCheckedContinuation { continuation = $0 }
        return .empty
    }
    func resume() { continuation?.resume(); continuation = nil }
    func scan(settings: ScanSettings) async -> ScanReport { .empty }
    func scan(app: InstalledApp, settings: ScanSettings) async -> UpdateScanner.TargetedAppReport { .empty }
}

@MainActor
@Test func developerProgressAppearsEarlyAndRetainsFailedEnvironment() async {
    let scanner = PausedDeveloperProgressScanner()
    let f = ReviewFixture(scanner: scanner)
    defer { f.cleanUp() }
    let retained = DeveloperPackage(name: "retained", currentVersion: "1", latestVersion: "2",
        manager: .pipx, executablePath: "/fixture/pipx")
    f.store.developerPackages = [retained]
    let task = Task { await f.store.scan() }
    #expect(await eventually { await scanner.paused })
    #expect(f.store.isScanning)
    #expect(f.store.developerPackages.contains { $0.name == "fresh" })
    #expect(f.store.developerPackages.contains { $0.id == retained.id })
    #expect(f.store.scanState.firstResultSeconds != nil)
    await scanner.resume()
    await task.value
}

private actor PausedDeveloperProgressScanner: UpdateScanning {
    var paused = false
    var continuation: CheckedContinuation<Void, Never>?
    func scan(settings: ScanSettings, progress: @escaping ScanProgressReporter) async -> ScanReport {
        let fresh = DeveloperPackage(name: "fresh", currentVersion: "2", latestVersion: "3",
            manager: .npm, executablePath: "/fixture/npm")
        await progress(.developerPackages(.init(packages: [fresh], installedManagers: [.npm, .pipx],
            warnings: ["offline"], failedManagers: [.pipx], failedExecutablePaths: []), managers: [.npm, .pipx]))
        paused = true
        await withCheckedContinuation { continuation = $0 }
        return .empty
    }
    func resume() { continuation?.resume(); continuation = nil }
    func scan(settings: ScanSettings) async -> ScanReport { .empty }
    func scan(app: InstalledApp, settings: ScanSettings) async -> UpdateScanner.TargetedAppReport { .empty }
}

@MainActor
@Test(arguments: [false, true]) func modelProgressAppearsEarlyAndRetainsFailedOrUncheckedRuntime(scoped: Bool) async {
    let scanner = PausedModelProgressScanner(scoped: scoped)
    let f = ReviewFixture(scanner: scanner)
    defer { f.cleanUp() }
    let retained = reviewModel()
    f.store.localModels = [retained]
    let task = Task { await f.store.scan() }
    #expect(await eventually { await scanner.paused })
    #expect(f.store.isScanning)
    #expect(f.store.localModels.contains { $0.id == "fresh" })
    #expect(f.store.localModels.contains { $0.id == retained.id })
    #expect(f.store.selectedLocalModelID != nil)
    #expect(f.store.scanState.firstResultSeconds != nil)
    await scanner.resume()
    await task.value
}

private actor PausedModelProgressScanner: UpdateScanning {
    let scoped: Bool
    init(scoped: Bool = false) { self.scoped = scoped }
    var paused = false
    var continuation: CheckedContinuation<Void, Never>?
    func scan(settings: ScanSettings, progress: @escaping ScanProgressReporter) async -> ScanReport {
        let fresh = LocalLLMModel(id: "fresh", name: "fresh", variant: "Q4", runtime: .lmStudio,
            installedRevision: "new", latestRevision: "newest", sizeBytes: nil, modifiedAt: nil,
            homepage: nil, executablePath: "/fixture/lms", updateReference: "fresh", isOutdated: true)
        await progress(.localModels(.init(models: [fresh], warnings: ["offline"],
            failedModelIDs: [], failedRuntimes: scoped ? [] : [.ollama]),
            runtimes: scoped ? [.lmStudio] : Set(LocalModelRuntime.allCases)))
        paused = true
        await withCheckedContinuation { continuation = $0 }
        return .empty
    }
    func resume() { continuation?.resume(); continuation = nil }
    func scan(settings: ScanSettings) async -> ScanReport { .empty }
    func scan(app: InstalledApp, settings: ScanSettings) async -> UpdateScanner.TargetedAppReport { .empty }
}

@MainActor
@Test func newerRuntimeCheckOwnsModelsAfterOlderFullScanCompletes() async {
    let scanner = PausedModelProgressScanner()
    let f = ReviewFixture(scanner: scanner, models: ReviewDuplicateModels())
    defer { f.cleanUp() }
    f.store.localModels = [reviewModel()]
    let full = Task { await f.store.scan() }
    #expect(await eventually { await scanner.paused })
    await f.store.scanLocalModels(runtime: .ollama)
    let key = "model.runtime|\(LocalModelRuntime.ollama.rawValue)"
    let freshness = f.settings.sourceCheckFreshness[key]
    await scanner.resume()
    await full.value
    #expect(f.store.localModels.contains { $0.id == reviewModel().id })
    #expect(f.settings.sourceCheckFreshness[key] == freshness)
}

@MainActor
@Test func newerManagerCheckOwnsPackagesAfterOlderFullScanCompletes() async {
    let scanner = PausedDeveloperProgressScanner()
    let package = reviewPackage("targeted", executable: "/fixture/npm")
    let f = ReviewFixture(developerReport: .init(packages: [package], installedManagers: [.npm],
        warnings: [], failedManagers: [], failedExecutablePaths: []), scanner: scanner)
    defer { f.cleanUp() }
    let full = Task { await f.store.scan() }
    #expect(await eventually { await scanner.paused })
    await f.store.scanDeveloperPackages(manager: .npm)
    let key = "developer|npm"
    let freshness = f.settings.sourceCheckFreshness[key]
    await scanner.resume()
    await full.value
    #expect(f.store.developerPackages == [package])
    #expect(f.store.installedDeveloperManagers.contains(.npm))
    #expect(f.settings.sourceCheckFreshness[key] == freshness)
}

@MainActor
@Test(arguments: ["updated", "partial"])
func verifiedDeveloperMutationOwnsResultsAfterOlderFullScan(result: String) async {
    let scanner = PausedDeveloperProgressScanner()
    let f = ReviewFixture(scanner: scanner, developer: DeveloperMutationReviewClient(result: result))
    defer { f.cleanUp() }
    let package = DeveloperPackage(name: "fixture", currentVersion: "1.0", latestVersion: "1.1",
        manager: .npm, executablePath: "/fixture/npm")
    let full = Task { await f.store.scan() }
    #expect(await eventually { await scanner.paused })
    f.store.developerPackages = [package]
    await f.store.installDeveloperPackage(package, version: "1.1")
    let freshness = f.settings.sourceCheckFreshness["developer|npm"]
    await scanner.resume()
    await full.value
    #expect(f.store.developerPackages.first { $0.id == package.id }?.currentVersion == "1.1")
    #expect(f.store.updateHistory.first?.toVersion == "1.1")
    #expect(f.settings.sourceCheckFreshness["developer|npm"] == freshness)
}

@MainActor
@Test(arguments: ["developer", "models"])
func failedNewerSourceCheckRetainsWarningAfterOlderFullScan(source: String) async {
    let scanner = PausedModelProgressScanner()
    let f = ReviewFixture(scanner: scanner, developer: DeveloperMutationReviewClient(result: "unverified"),
        models: ModelMutationReviewClient(result: "unverified"))
    defer { f.cleanUp() }
    let full = Task { await f.store.scan() }
    #expect(await eventually { await scanner.paused })
    if source == "developer" { await f.store.scanDeveloperPackages(manager: .npm) }
    else { await f.store.scanLocalModels(runtime: .ollama) }
    await scanner.resume()
    await full.value
    let warningSource: ScanWarningSource = source == "developer" ? .developerPackages : .localModels
    #expect(f.store.scanWarnings.contains { $0.source == warningSource })
    #expect(f.store.scanState.completedCheckState == .partial)
}

@Test func aggregateWarningsRetainExplicitManagerAndRuntimeAttribution() {
    let developer = DeveloperPackageClient.Report(packages: [], installedManagers: [], warnings: ["offline", "unknown"],
        failedManagers: [.npm, .pipx], failedExecutablePaths: [], warningManagers: ["offline": [.npm, .pipx]])
    #expect(Set(developer.scanWarnings.first?.itemNames ?? []) == Set(["npm", "pipx"]))
    #expect(developer.scanWarnings.last?.itemNames.isEmpty == true)
    let models = LocalModelClient.Report(models: [], warnings: ["offline"], failedModelIDs: [],
        failedRuntimes: [.ollama], warningRuntimes: ["offline": [.ollama]])
    #expect(models.scanWarnings.first?.itemNames == [LocalModelRuntime.ollama.rawValue])
    #expect(models.scanWarnings.first?.message == "offline")
}

@MainActor
@Test(arguments: [false, true])
func developerVersionRefreshRecordsLookupHealthWithoutMovingGlobalSchedule(fails: Bool) async throws {
    let f = ReviewFixture(developer: fails ? DeveloperMutationReviewClient(result: "unchanged") : ReviewDeveloper(report: .empty))
    defer { f.cleanUp() }
    let package = reviewPackage("fixture", executable: "/fixture/npm")
    f.store.developerPackages = [package]
    let baseline = Date(timeIntervalSince1970: 1_000_000)
    f.settings.lastCompletedScanDate = baseline
    let key = "developer.versions|\(package.id)"
    f.settings.recordSourceAttempt(key, at: baseline)
    await f.store.refresh(package)
    let restarted = AppSettings(defaults: f.defaults)
    let health = try #require(restarted.sourceCheckFreshness[key])
    #expect(health.lastAttempt > baseline)
    #expect((health.failure != nil) == fails)
    #expect(fails ? health.lastSuccess == baseline : health.lastSuccess == health.lastAttempt)
    #expect(restarted.lastCompletedScanDate == baseline)
    #expect(restarted.sourceCheckFreshness["developer|\(package.manager.rawValue)"] == nil)
}

private struct FullFreshnessReviewScanner: UpdateScanning {
    let app: InstalledApp
    let fails: Bool
    func scan(settings: ScanSettings) async -> ScanReport {
        ScanReport(apps: [app], updates: [], checkedAt: Date(), warnings: [],
            failedAppSources: fails ? [app.id: [.sparkle]] : [:], homebrewInventoryStatus: .disabled,
            homebrewCatalogStatus: .disabled, macOSUpdatesStatus: .disabled, macOSInstallersStatus: .disabled,
            failedDeveloperManagers: [], failedDeveloperExecutablePaths: [], localModelsStatus: .disabled,
            failedLocalModelIDs: [], failedLocalModelRuntimes: [], homebrewPackages: [], adoptableApps: [],
            macOSUpdates: [], developerPackages: [], installedDeveloperManagers: [], localModels: [])
    }
    func scan(app: InstalledApp, settings: ScanSettings) async -> UpdateScanner.TargetedAppReport { .empty }
}

@MainActor
@Test(arguments: [false, true], [false, true])
func fullScanNeverStampsFailedOrDisabledAppsAsVerified(fails: Bool, enabled: Bool) async throws {
    let app = reviewApp()
    let f = ReviewFixture(scanner: FullFreshnessReviewScanner(app: app, fails: fails))
    defer { f.cleanUp() }
    f.settings.checkSparkle = enabled
    let baseline = Date(timeIntervalSince1970: 1_000_000)
    f.settings.recordCheck(for: app.updateExclusionKey, at: baseline)
    let key = "app|\(app.id)|\(UpdateSource.sparkle.rawValue)"
    f.settings.recordSourceAttempt(key, at: baseline)
    await f.store.scan()
    let restarted = AppSettings(defaults: f.defaults)
    let verified = enabled && !fails
    #expect(verified ? restarted.lastChecked(for: app.updateExclusionKey)! > baseline
                     : restarted.lastChecked(for: app.updateExclusionKey) == baseline)
    let health = try #require(restarted.sourceCheckFreshness[key])
    #expect(verified ? health.lastSuccess! > baseline : health.lastSuccess == baseline)
    #expect(enabled ? health.lastAttempt > baseline : health.lastAttempt == baseline)
    #expect(restarted.lastCompletedScanDate != nil)
}

private actor InterruptedDirectReviewInstaller: DirectAppInstalling {
    private var continuation: CheckedContinuation<Void, Never>?
    var waiting: Bool { continuation != nil }
    func release() { continuation?.resume(); continuation = nil }
    func install(update: AvailableUpdate) async throws {
        await withCheckedContinuation { continuation = $0 }
        try Task.checkCancellation()
    }
}

@MainActor
@Test(arguments: [false, true])
func cancelledDirectMutationReconcilesObservedVersionWithoutReportingSuccess(batch: Bool) async throws {
    let installer = InterruptedDirectReviewInstaller()
    let original = reviewApp()
    let observed = reviewApp(version: "1.1", build: "11")
    let f = ReviewFixture(progressInstaller: installer, discovery: CaskReviewDiscovery(installed: observed))
    defer { f.cleanUp() }
    f.store.apps = [original]
    let update = reviewUpdate(original)
    let task = Task {
        if batch { return await f.store.performBatchUpdates([.application(update)]).updatedCount }
        await f.store.performUpdate(update)
        return 0
    }
    defer { task.cancel() }
    #expect(await eventually { await installer.waiting })
    task.cancel()
    await installer.release()
    #expect(await task.value == 0)
    #expect(f.store.updateHistory.count == 1)
    #expect(f.store.updateHistory.first?.toVersion == observed.installedVersion)
    #expect(f.store.errorMessage != nil)
    #expect(!f.store.isUpdating(update))
}
