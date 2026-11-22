import Foundation
import Testing
@testable import Upkeep

@MainActor
@Test func nvmMigrationReservesAllVersionsInItsRoot() async {
    let suite = "NVMMigrationReservations.\(UUID().uuidString)"
    let defaults = UserDefaults(testSuiteName: suite)!
    defer { defaults.removeTestDomain(forName: suite) }
    let store = UpkeepStore(settings: AppSettings(defaults: defaults))
    let node = DeveloperPackage(name: "Node.js", currentVersion: "18", latestVersion: "20", manager: .node,
                                executablePath: "/fixture/user/.nvm/versions/node/v18/bin/node")
    let cleanup = PackageCleanupTarget(kind: .npm,
                                      executablePath: "/fixture/user/.nvm/versions/node/v20/bin/npm")
    let migration = store.mutationTargets(for: .developer(node))
    let cache = store.mutationTargets(for: cleanup)
    #expect(migration.contains(.developerEnvironment("nvm-root:/fixture/user/.nvm")))
    #expect(cache.contains(.developerEnvironment("nvm-root:/fixture/user/.nvm")))
    await store.mutationCoordinator.withAccess(to: migration, otherwise: ()) {
        MutationContext.$owner.withValue(nil) {
            #expect(store.mutationCoordinator.isBusy(cache))
        }
    }
    #expect(!store.mutationCoordinator.isBusy(cache))
    let unrelated = PackageCleanupTarget(kind: .npm,
                                        executablePath: "/fixture/other/.nvm/versions/node/v20/bin/npm")
    #expect(!store.mutationTargets(for: unrelated).contains(.developerEnvironment("nvm-root:/fixture/user/.nvm")))
}

@MainActor
@Test func wrappersInDifferentDirectoriesReserveTheirSharedNodeRuntime() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let runtime = root.appendingPathComponent("runtime/node")
    let bins = [root.appendingPathComponent("npm/bin"), root.appendingPathComponent("pnpm/bin")]
    try FileManager.default.createDirectory(at: runtime.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: runtime)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtime.path)
    for bin in bins {
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("node"), withDestinationURL: runtime)
    }
    let npm = PackageCleanupTarget(kind: .npm, executablePath: bins[0].appendingPathComponent("npm").path)
    let pnpm = PackageCleanupTarget(kind: .pnpm, executablePath: bins[1].appendingPathComponent("pnpm").path)
    #expect(developerNodeRuntimePath(for: URL(fileURLWithPath: npm.executablePath)) == runtime.resolvingSymlinksInPath().path)
    #expect(developerNodeRuntimePath(for: URL(fileURLWithPath: pnpm.executablePath)) == runtime.resolvingSymlinksInPath().path)
    let suite = "NodeReservations.\(UUID().uuidString)"
    let defaults = UserDefaults(testSuiteName: suite)!
    defer { defaults.removeTestDomain(forName: suite) }
    let store = UpkeepStore(settings: AppSettings(defaults: defaults))
    #expect(!store.mutationTargets(for: npm).isDisjoint(with: store.mutationTargets(for: pnpm)))
    let other = bins[1].appendingPathComponent("node")
    try FileManager.default.removeItem(at: other)
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: other)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: other.path)
    #expect(store.mutationTargets(for: npm).isDisjoint(with: store.mutationTargets(for: pnpm)))
}

@MainActor
@Test(arguments: [DeveloperPackageManager.asdf, .mise, .volta, .fnm])
func managedNodeClientsAndCleanupReserveTheirRuntimeOwner(owner: DeveloperPackageManager) async throws {
    let suite = "NodeOwnerReservations-\(UUID())"
    let defaults = try #require(UserDefaults(testSuiteName: suite))
    defer { defaults.removeTestDomain(forName: suite) }
    let store = UpkeepStore(settings: AppSettings(defaults: defaults))
    let directory: String
    switch owner {
    case .asdf: directory = "/fixture/.asdf/shims"
    case .mise: directory = "/fixture/.local/share/mise/installs/node/20/bin"
    case .volta: directory = "/fixture/.volta/bin"
    case .fnm: directory = "/fixture/Library/Application Support/fnm/node-versions/v20/installation/bin"
    default: throw CancellationError()
    }
    let manager = DeveloperPackage(name: "node", currentVersion: "18", latestVersion: "20", manager: owner,
        executablePath: "/fixture/manager/bin/\(owner.assetName)", registryIdentifier: "node")
    let client = DeveloperPackage(name: "tool", currentVersion: "1", latestVersion: "2", manager: .npm,
        executablePath: "\(directory)/npm")
    let cleanup = PackageCleanupTarget(kind: .npm, executablePath: "\(directory)/npm")
    let ownerTargets = store.mutationTargets(for: .developer(manager))
    let clientTargets = store.mutationTargets(for: .developer(client))
    let cleanupTargets = store.mutationTargets(for: cleanup)
    #expect(ownerTargets.intersection(clientTargets) == [.packageEnvironment(owner.assetName)])
    #expect(ownerTargets.intersection(cleanupTargets) == [.packageEnvironment(owner.assetName)])
    await store.mutationCoordinator.withAccess(to: ownerTargets, otherwise: ()) {
        MutationContext.$owner.withValue(nil) {
            #expect(store.mutationCoordinator.isBusy(clientTargets))
            #expect(store.mutationCoordinator.isBusy(cleanupTargets))
        }
    }
    #expect(!store.mutationCoordinator.isBusy(clientTargets))
    #expect(!store.mutationCoordinator.isBusy(cleanupTargets))
}
