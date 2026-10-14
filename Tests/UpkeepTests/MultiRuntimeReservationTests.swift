import Foundation
import Testing
@testable import Upkeep

@MainActor
@Test(arguments: [DeveloperPackageManager.asdf, .mise], ["python", "rust", "ruby"])
func runtimeManagerPluginReservesItsConsumerEnvironment(owner: DeveloperPackageManager, runtime: String) async throws {
    let suite = "MultiRuntimeReservations-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = UpkeepStore(settings: AppSettings(defaults: defaults))
    let consumer: DeveloperPackageManager = runtime == "python" ? .python : runtime == "rust" ? .cargo : .rubyGems
    let key = runtime == "python" ? "python-runtime" : runtime == "rust" ? "rust-toolchain" : "rubygems"
    let plugin = DeveloperPackage(name: "Runtime display name", currentVersion: "1", latestVersion: "2", manager: owner,
        executablePath: "/fixture/manager/\(owner.assetName)", registryIdentifier: runtime)
    let client = DeveloperPackage(name: "tool", currentVersion: "1", latestVersion: "2", manager: consumer,
        executablePath: "/fixture/consumer/\(consumer.assetName)")
    let ownerTargets = store.mutationTargets(for: .developer(plugin))
    let clientTargets = store.mutationTargets(for: .developer(client))
    #expect(ownerTargets.intersection(clientTargets) == [.packageEnvironment(key)])
    await store.mutationCoordinator.withAccess(to: ownerTargets, otherwise: ()) {
        MutationContext.$owner.withValue(nil) { #expect(store.mutationCoordinator.isBusy(clientTargets)) }
    }
    #expect(!store.mutationCoordinator.isBusy(clientTargets))
    let unrelatedPlugin = DeveloperPackage(name: "Go", currentVersion: "1", latestVersion: "2", manager: owner,
        executablePath: plugin.executablePath, registryIdentifier: "go")
    #expect(store.mutationTargets(for: .developer(unrelatedPlugin)).isDisjoint(with: clientTargets))
}
