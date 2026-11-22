import Combine
import Foundation
import Observation
import SwiftUI
import Testing
@testable import Upkeep

private final class ObservationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var events = 0
    func record() { lock.withLock { events += 1 } }
    var count: Int { lock.withLock { events } }
}

@MainActor
@Test func featureObservationIgnoresUnrelatedInventoryAndProgress() {
    let library = UpkeepLibraryState()
    let scan = UpkeepScanState(lastChecked: nil)
    let probe = ObservationProbe()
    withObservationTracking {
        _ = library.developerPackages
    } onChange: { probe.record() }
    library.localModels = [LocalLLMModel(id: "fixture", name: "Fixture", variant: nil,
        runtime: .ollama, installedRevision: "one", latestRevision: "two",
        sizeBytes: 1, modifiedAt: nil, homepage: nil, executablePath: "/not-executed/ollama",
        updateReference: "fixture", isOutdated: true)]
    library.apps = [InstalledApp(name: "Fixture", bundleIdentifier: "test.scoped",
        installedVersion: "1", buildVersion: nil, url: URL(fileURLWithPath: "/fixture.app"),
        sparkleFeedURL: nil, githubRepository: nil, hasAppStoreReceipt: false)]
    scan.progress = ScanProgress(completed: 1, total: 5, lastSource: .sparkle)
    #expect(probe.count == 0)
    library.developerPackages = [DeveloperPackage(name: "fixture", currentVersion: "1",
        latestVersion: "2", manager: .npm, executablePath: "/not-executed/npm")]
    #expect(probe.count == 1)
}

@MainActor
@Test func applicationLookupObservationTracksItsLookupRatherThanWholeLibrary() {
    let suite = "ScopedObservation.\(UUID())"
    let defaults = UserDefaults(testSuiteName: suite)!
    defer { defaults.removeTestDomain(forName: suite) }
    let store = UpkeepStore(settings: AppSettings(defaults: defaults))
    let app = InstalledApp(name: "Fixture", bundleIdentifier: "test.observation",
        installedVersion: "1", buildVersion: nil, url: URL(fileURLWithPath: "/fixture.app"),
        sparkleFeedURL: nil, githubRepository: nil, hasAppStoreReceipt: false)
    let probe = ObservationProbe()
    withObservationTracking {
        _ = store.update(for: app)
    } onChange: { probe.record() }
    store.library.developerPackages = [DeveloperPackage(name: "fixture", currentVersion: "1",
        latestVersion: "2", manager: .npm, executablePath: "/not-executed/npm")]
    store.scanState.firstResultSeconds = 0.1
    store.updateExecutionState.begin(.localModel("fixture"), targets: [], phase: .updating, label: "Fixture")
    #expect(probe.count == 0)
    store.library.updates = [AvailableUpdate(app: app, availableVersion: "2", source: .sparkle,
        releaseNotes: nil, actionURL: nil, homebrewToken: nil)]
    #expect(probe.count == 1)
    #expect(store.update(for: app)?.availableVersion == "2")
}

@MainActor
@Test func nativeNestedBindingWritesObservableNavigationState() {
    let suite = "ScopedBinding.\(UUID())"
    let defaults = UserDefaults(testSuiteName: suite)!
    defer { defaults.removeTestDomain(forName: suite) }
    let store = UpkeepStore(settings: AppSettings(defaults: defaults))
    let probe = ObservationProbe()
    withObservationTracking { _ = store.navigation.selectedLocalModelID }
        onChange: { probe.record() }
    let projection = ObservedObject(wrappedValue: store).projectedValue
    projection.navigation.selectedLocalModelID.wrappedValue = "fixture-model"
    #expect(store.navigation.selectedLocalModelID == "fixture-model")
    #expect(probe.count == 1)
}

@MainActor
@Test func scopedBusyObservationAndLegacyPublisherBothSeeReservations() async {
    let coordinator = MutationCoordinator()
    let targets: Set<MutationTarget> = [.packageEnvironment("homebrew")]
    let observation = ObservationProbe()
    let legacy = ObservationProbe()
    let subscription = coordinator.objectWillChange.sink { legacy.record() }
    defer { subscription.cancel() }
    withObservationTracking { _ = coordinator.isBusy(targets) }
        onChange: { observation.record() }
    _ = await coordinator.withAccess(to: targets, otherwise: false) {
        #expect(observation.count == 1)
        #expect(legacy.count == 1)
        #expect(MutationContext.$owner.withValue(UUID()) { coordinator.isBusy(targets) })
        return true
    }
    #expect(legacy.count == 2)
    #expect(!coordinator.isBusy(targets))
}

@MainActor
@Test func nestedMutationOwnershipSurvivesSuspensionAndReleasesReservations() async {
    let coordinator = MutationCoordinator()
    let targets: Set<MutationTarget> = [.packageEnvironment("fixture")]
    #expect(MutationContext.owner == nil)

    let completed = await coordinator.withAccess(to: targets, otherwise: false) {
        let owner = MutationContext.owner
        #expect(owner != nil)
        await Task.yield()
        #expect(MutationContext.owner == owner)

        let nested = await coordinator.withAccess(to: targets, otherwise: false) {
            await Task.yield()
            #expect(MutationContext.owner == owner)
            return true
        }
        #expect(nested)
        #expect(MutationContext.owner == owner)
        // Finishing a nested step must not release its parent's reservation.
        #expect(MutationContext.$owner.withValue(UUID()) { coordinator.isBusy(targets) })
        return true
    }

    #expect(completed)
    #expect(MutationContext.owner == nil)
    #expect(!coordinator.isBusy(targets))
}

@MainActor
@Test func sceneCommandReadsTrackRequiredChildStateWithoutRootSubscription() {
    let suite = "ScopedScene.\(UUID())"
    let defaults = UserDefaults(testSuiteName: suite)!
    defer { defaults.removeTestDomain(forName: suite) }
    let store = UpkeepStore(settings: AppSettings(defaults: defaults))
    let probe = ObservationProbe()
    withObservationTracking {
        _ = store.totalUpdateCount
        _ = store.availableBatchUpdateItems.count
        _ = store.isScanning
    } onChange: { probe.record() }
    store.diagnostics.diagnosticsSearchText = "fixture"
    store.scanState.firstResultSeconds = 0.1
    #expect(probe.count == 0)
    store.scanState.isScanning = true
    #expect(probe.count == 1)
    #expect(store.isScanning)
}

@MainActor
@Test func exclusionsKeepSettingsNotificationsForReferenceConsumers() {
    let suite = "ScopedSettings.\(UUID())"
    let defaults = UserDefaults(testSuiteName: suite)!
    defer { defaults.removeTestDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    let store = UpkeepStore(settings: settings)
    let probe = ObservationProbe()
    let subscription = settings.objectWillChange.sink { probe.record() }
    defer { subscription.cancel() }
    let app = InstalledApp(name: "Fixture", bundleIdentifier: "test.scoped-settings",
        installedVersion: "1", buildVersion: nil, url: URL(fileURLWithPath: "/fixture.app"),
        sparkleFeedURL: nil, githubRepository: nil, hasAppStoreReceipt: false)
    store.ignore(app)
    #expect(store.ignoredExclusion(for: app) != nil)
    #expect(probe.count > 0)
    let beforeRestore = probe.count
    store.restore(app: app)
    #expect(store.ignoredExclusion(for: app) == nil)
    #expect(probe.count > beforeRestore)
}
