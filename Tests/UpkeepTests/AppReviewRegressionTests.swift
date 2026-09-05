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
    let f = ReviewFixture()
    defer { f.cleanUp() }
    await f.store.updateLocalModel(reviewModel())
    #expect(f.store.updateHistory.count == 1)
    #expect(f.store.updateHistory.first?.kind == .model)
    let failed = ReviewFixture(history: ReviewHistory(fail: true))
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
    func scan(settings: ScanSettings) async -> ScanReport {
        await onScan?()
        return .empty
    }
    func scan(app: InstalledApp, settings: ScanSettings) async -> UpdateScanner.TargetedAppReport {
        .init(updates: [], failedSources: failedSources, warnings: [])
    }
}
private struct ReviewDiscovery: ApplicationDiscovering {
    let app: InstalledApp
    func discover() async -> [InstalledApp] { [app] }
    func discover(at url: URL) async -> InstalledApp? { app }
}
private struct ReviewBrew: HomebrewManaging {
    func package(token: String, kind: HomebrewPackageKind, includePrereleases: Bool) async throws -> HomebrewPackage? { nil }
    func upgrade(_ package: HomebrewPackage) async throws {}
    func adopt(_ item: AdoptableApp) async throws {}
    func installOrReplace(_ item: AdoptableApp) async throws {}
    func upgradeCask(token: String) async throws {}
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
         discoveredApp: InstalledApp = reviewApp(), developerReport: DeveloperPackageClient.Report = .empty,
         scanner: ReviewScanner = ReviewScanner(), developer: (any DeveloperPackageManaging)? = nil, models: (any LocalModelManaging)? = nil, progressInstaller: (any DirectAppInstalling)? = nil) {
        defaults = UserDefaults(suiteName: suite)!
        settings = AppSettings(defaults: defaults)
        self.history = history; self.installer = installer
        store = UpkeepStore(settings: settings, dependencies: UpkeepDependencies(
            scanner: scanner, applicationDiscovery: ReviewDiscovery(app: discoveredApp), homebrew: ReviewBrew(),
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

    #expect(probe.observed == (fails
        ? [.downloading, .preparing, .installing]
        : [.downloading, .preparing, .installing, .refreshing]))
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
