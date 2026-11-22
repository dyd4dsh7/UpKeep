import Foundation
import Testing
@testable import Upkeep

@MainActor
@Test(arguments: [DeveloperPackageManager.python, .pipx])
func pythonClientsReserveUVManagedRuntimeAndCleanup(manager: DeveloperPackageManager) async throws {
    let suite = "PythonReservations-\(UUID())"
    let defaults = try #require(UserDefaults(testSuiteName: suite))
    defer { defaults.removeTestDomain(forName: suite) }
    let store = UpkeepStore(settings: AppSettings(defaults: defaults))
    let package = DeveloperPackage(name: "tool", currentVersion: "1", latestVersion: "2", manager: manager,
        executablePath: "/fixture/python-client/bin/\(manager.assetName)")
    let runtime = DeveloperPackage(name: "Python", currentVersion: "3.12", latestVersion: "3.13", manager: .uv,
        executablePath: "/fixture/uv/bin/uv", registryIdentifier: "python:3.12")
    let cleanup = PackageCleanupTarget(kind: .uv, executablePath: "/fixture/another-wrapper/uv")
    let clientTargets = store.mutationTargets(for: .developer(package))
    let runtimeTargets = store.mutationTargets(for: .developer(runtime))
    let cleanupTargets = store.mutationTargets(for: cleanup)
    #expect(clientTargets.intersection(runtimeTargets) == [.packageEnvironment("python-runtime")])
    #expect(clientTargets.intersection(cleanupTargets) == [.packageEnvironment("python-runtime")])
    await store.mutationCoordinator.withAccess(to: clientTargets, otherwise: ()) {
        MutationContext.$owner.withValue(nil) {
            #expect(store.mutationCoordinator.isBusy(runtimeTargets))
            #expect(store.mutationCoordinator.isBusy(cleanupTargets))
        }
    }
    #expect(!store.mutationCoordinator.isBusy(runtimeTargets))
    #expect(!store.mutationCoordinator.isBusy(cleanupTargets))
    let ruby = DeveloperPackage(name: "gem", currentVersion: "1", latestVersion: "2", manager: .rubyGems,
        executablePath: "/fixture/ruby/bin/gem")
    #expect(clientTargets.isDisjoint(with: store.mutationTargets(for: .developer(ruby))))
}
