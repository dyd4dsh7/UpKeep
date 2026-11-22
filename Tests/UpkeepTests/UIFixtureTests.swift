#if DEBUG
import Foundation
import Testing
@testable import Upkeep

@MainActor
@Test func uiFixtureUpdateCannotMutateInstalledState() async {
    let suite = "test.upkeep.fixture-safety.\(UUID().uuidString)"
    let defaults = UserDefaults(testSuiteName: suite)!
    defer { defaults.removeTestDomain(forName: suite) }
    let store = UIFixture.makeStore(settings: AppSettings(defaults: defaults))
    await store.performUpdate(UIFixture.update)
    #expect(store.errorMessage?.contains("disabled in the UI fixture") == true)
    #expect(store.apps.first?.installedVersion == "1.0")
    #expect(store.updateHistory.isEmpty)
    await store.scan()
    #expect(store.apps.map(\.id) == [UIFixture.app.id])
    #expect(store.updates.first?.availableVersion == "2.0")
}
@MainActor
@Test func serviceUIFixtureUsesOnlyMockInventory() async {
    let suite = "test.upkeep.service-fixture.\(UUID().uuidString)"
    let defaults = UserDefaults(testSuiteName: suite)!
    defer { defaults.removeTestDomain(forName: suite) }
    let store = UIFixture.makeStore(settings: AppSettings(defaults: defaults), operationState: .services)
    #expect(store.selection == .homebrewPackages)
    #expect(store.selectedPackageID == UIFixture.package.id)
    await store.scan()
    #expect(store.homebrewPackages.map(\.id) == [UIFixture.package.id])
    await store.scanHomebrewServices()
    #expect(store.library.homebrewServices.map(\.name) == [UIFixture.package.token])
    #expect(store.library.homebrewServicesFailure == nil)
}
@MainActor
@Test(arguments: [UIFixture.OperationState.servicesFailure, .servicesRetained, .servicesEmpty])
func serviceFixtureFailureAndEmptyStatesRemainIsolated(state: UIFixture.OperationState) async {
    let suite = "test.upkeep.service-states.\(UUID().uuidString)"
    let defaults = UserDefaults(testSuiteName: suite)!
    defer { defaults.removeTestDomain(forName: suite) }
    let store = UIFixture.makeStore(settings: AppSettings(defaults: defaults), operationState: state)
    let lastSuccess = store.library.homebrewServicesSucceededAt
    await store.scanHomebrewServices()
    #expect((store.library.homebrewServicesFailure != nil) == (state != .servicesEmpty))
    #expect(store.library.homebrewServices.count == (state == .servicesRetained ? 1 : 0))
    if state != .servicesEmpty { #expect(store.library.homebrewServicesSucceededAt == lastSuccess) }
    else { #expect(store.library.homebrewServicesSucceededAt != nil) }
    #expect(store.selection == .homebrewPackages)
}
@MainActor
@Test func unavailableCleanupFixtureReviewsMockTargetAndBlocksCleanup() async throws {
    let suite = "test.upkeep.cleanup-fixture.\(UUID().uuidString)"
    let defaults = UserDefaults(testSuiteName: suite)!
    defer { defaults.removeTestDomain(forName: suite) }
    let store = UIFixture.makeStore(settings: AppSettings(defaults: defaults), operationState: .cleanupUnavailable)
    await store.scan()
    let target = try #require(store.packageCleanupTargets.first { $0.executablePath == "/fixture/npm" })
    let estimate = await store.scanCleanup(target)
    #expect(estimate?.basis == .unavailable)
    #expect(estimate?.shouldOfferCleanup == true)
    #expect(await store.cleanUp(target) == nil)
    #expect(store.errorMessage?.contains("disabled in the UI fixture") == true)
}
#endif
