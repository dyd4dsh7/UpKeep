import Foundation
import Testing
@testable import Upkeep

@MainActor
@Test func cargoAndRustupReserveSharedToolchainsAcrossExecutablePaths() async throws {
    let suite = "RustReservations-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = UpkeepStore(settings: AppSettings(defaults: defaults))
    let cargo = DeveloperPackage(name: "tool", currentVersion: "1", latestVersion: "2", manager: .cargo,
        executablePath: "/fixture/.rustup/toolchains/stable/bin/cargo")
    let rustup = DeveloperPackage(name: "stable", currentVersion: "1", latestVersion: "2", manager: .rustup,
        executablePath: "/fixture/.cargo/bin/rustup")
    let cargoTargets = store.mutationTargets(for: .developer(cargo))
    let rustupTargets = store.mutationTargets(for: .developer(rustup))
    #expect(cargoTargets.intersection(rustupTargets) == [.packageEnvironment("rust-toolchain")])
    await store.mutationCoordinator.withAccess(to: cargoTargets, otherwise: ()) {
        MutationContext.$owner.withValue(nil) {
            #expect(store.mutationCoordinator.isBusy(rustupTargets))
        }
    }
    #expect(!store.mutationCoordinator.isBusy(rustupTargets))
    let composer = DeveloperPackage(name: "tool", currentVersion: "1", latestVersion: "2", manager: .composer,
        executablePath: "/fixture/bin/composer")
    #expect(cargoTargets.isDisjoint(with: store.mutationTargets(for: .developer(composer))))
}
