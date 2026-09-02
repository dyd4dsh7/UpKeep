import Foundation
import Testing
@testable import Upkeep

@Test func architectureInspectorReadsThinAndUniversalMachOHeaders() {
    for littleEndian in [true, false] {
        #expect(AppArchitectureInspector.architectures(in: machO(cpu: 0x01000007, littleEndian: littleEndian)) == ["x86_64"])
        #expect(AppArchitectureInspector.architectures(in: machO(cpu: 0x0100000c, littleEndian: littleEndian)) == ["arm64"])
        for is64 in [true, false] {
            let header = universalMachO(littleEndian: littleEndian, is64: is64)
            #expect(AppArchitectureInspector.architectures(in: header) == ["x86_64", "arm64"])
        }
    }
}

@Test func architectureInspectorLeavesUnreadableOrMalformedExecutablesUnknown() {
    for data in [Data(), Data("#!/bin/sh\nopen example".utf8), Data([0xcf, 0xfa, 0xed, 0xfe]),
                 Data([0xca, 0xfe, 0xba, 0xbe, 0xff, 0xff, 0xff, 0xff]),
                 universalMachO(littleEndian: false, is64: false).prefix(30)] {
        #expect(AppArchitectureInspector.architectures(in: data).isEmpty)
    }
    #expect(AppArchitecture(architectures: ["cpu-123"]) == .unknown)
    #expect(AppArchitecture(architectures: ["x86_64", "cpu-123"]) == .unknown)
}

@Test func onlyIntelOnlyAppsOnAppleSiliconNeedMigration() {
    #expect(AppArchitecture(architectures: ["x86_64"]).needsMigration(onAppleSilicon: true))
    #expect(!AppArchitecture(architectures: ["x86_64"]).needsMigration(onAppleSilicon: false))
    #expect(!AppArchitecture(architectures: ["x86_64", "arm64"]).needsMigration(onAppleSilicon: true))
    #expect(!AppArchitecture(architectures: ["arm64"]).needsMigration(onAppleSilicon: true))
    #expect(!AppArchitecture(architectures: []).needsMigration(onAppleSilicon: true))
}

@Test func migrationVerificationRequiresNativeCodeAtTheSameAppIdentity() {
    let original = migrationApp(architectures: ["x86_64"])
    #expect(AppleSiliconVerification.result(original: original, installed: original) == .stillIntel)
    #expect(AppleSiliconVerification.result(original: original, installed: nil) == .missing)
    #expect(AppleSiliconVerification.result(original: original, installed: migrationApp(architectures: [])) == .unknown)
    #expect(AppleSiliconVerification.result(original: original, installed: migrationApp(architectures: ["arm64"], identifier: "other.app")) == .differentApp)
    for architectures in [["arm64"], ["arm64", "x86_64"]] {
        let replacement = migrationApp(architectures: architectures)
        #expect(original.installedVersion == replacement.installedVersion)
        #expect(AppleSiliconVerification.result(original: original, installed: replacement) == .native)
    }
    #expect(original.replacingGitHubRepository("example/new").architectures == ["x86_64"])
}

@Test func migrationSourcePreservesTheExistingUpdateManager() {
    for management in [AppUpdateManagement.appStore, .testFlight, .setapp, .steam, .microsoftAutoUpdate] {
        let app = migrationApp(architectures: ["x86_64"], management: management)
        #expect(AppleSiliconMigrationSource.resolve(app: app, homebrewToken: "example") == .updateManager)
    }
    let app = migrationApp(architectures: ["x86_64"])
    #expect(AppleSiliconMigrationSource.resolve(app: app, homebrewToken: "example") == .homebrew(URL(string: "https://formulae.brew.sh/cask/example")!))
    #expect(AppleSiliconMigrationSource.resolve(app: app, homebrewToken: nil) == .developerWebsite)
    #expect(AppleSiliconMigrationSource.resolve(app: app.replacingGitHubRepository("example/app"), homebrewToken: nil) == .releases(URL(string: "https://github.com/example/app/releases")!))
}

@MainActor
@Test func migrationRecheckRefreshesLibrarySelectionAndUpdatesWithoutANetworkScan() async throws {
    let original = migrationApp(architectures: ["x86_64"])
    let replacement = migrationApp(architectures: ["arm64"])
    let suite = "AppleSiliconMigration.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = UpkeepStore(settings: AppSettings(defaults: defaults), dependencies: UpkeepDependencies(
        scanner: UpkeepDependencies.live.scanner,
        applicationDiscovery: MigrationDiscovery(app: replacement),
        homebrew: UpkeepDependencies.live.homebrew,
        developerPackages: UpkeepDependencies.live.developerPackages,
        localModels: UpkeepDependencies.live.localModels,
        history: UpkeepDependencies.live.history
    ))
    store.apps = [original]
    store.selectedApp = original
    store.updates = [AvailableUpdate(app: original, availableVersion: "2.0", source: .github,
                                    releaseNotes: nil, actionURL: nil, homebrewToken: nil)]
    store.adoptableApps = [AdoptableApp(app: original, caskToken: "example", caskVersion: "2.0")]

    #expect(await store.verifyAppleSiliconMigration(original) == .native)
    #expect(store.apps.first?.architecture == .appleSilicon)
    #expect(store.selectedApp?.architecture == .appleSilicon)
    #expect(store.updates.first?.app.architecture == .appleSilicon)
    #expect(store.adoptableApps.first?.app.architecture == .appleSilicon)
    #expect(store.apps.first?.installedVersion == original.installedVersion)
}

@Test func discoveryRereadsArchitectureAfterSameVersionReplacement() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Upkeep-Architecture-\(UUID().uuidString).app")
    let macOS = root.appendingPathComponent("Contents/MacOS")
    try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let plist: [String: String] = ["CFBundleIdentifier": "example.app", "CFBundleExecutable": "Example", "CFBundleShortVersionString": "1.0"]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: root.appendingPathComponent("Contents/Info.plist"))
    let executable = macOS.appendingPathComponent("Example")
    try machO(cpu: 0x01000007).write(to: executable)
    let original = try #require(await AppDiscovery.discover(at: root))
    #expect(original.architecture == .intel)
    try machO(cpu: 0x0100000c).write(to: executable, options: .atomic)
    let replacement = try #require(await AppDiscovery.discover(at: root))
    #expect(replacement.architecture == .appleSilicon)
    #expect(AppleSiliconVerification.result(original: original, installed: replacement) == .native)
    try FileManager.default.removeItem(at: executable)
    #expect(await AppDiscovery.discover(at: root)?.architecture == .unknown)
}

private func migrationApp(architectures: [String], identifier: String = "example.app", management: AppUpdateManagement = .direct) -> InstalledApp {
    InstalledApp(name: "Example", bundleIdentifier: identifier, installedVersion: "1.0", buildVersion: nil,
                 url: URL(fileURLWithPath: "/Applications/Example.app"), sparkleFeedURL: nil,
                 githubRepository: nil, hasAppStoreReceipt: management == .appStore,
                 updateManagement: management, architectures: architectures)
}

private struct MigrationDiscovery: ApplicationDiscovering {
    let app: InstalledApp
    func discover() async -> [InstalledApp] { [app] }
    func discover(at url: URL) async -> InstalledApp? { app }
}

private func bytes(_ word: UInt32, littleEndian: Bool) -> [UInt8] {
    let result = [UInt8(truncatingIfNeeded: word >> 24), UInt8(truncatingIfNeeded: word >> 16),
                  UInt8(truncatingIfNeeded: word >> 8), UInt8(truncatingIfNeeded: word)]
    return littleEndian ? result.reversed() : result
}

private func machO(cpu: UInt32, littleEndian: Bool = true) -> Data {
    Data(bytes(0xfeedfacf, littleEndian: littleEndian) + bytes(cpu, littleEndian: littleEndian) + Array(repeating: 0, count: 24))
}

private func universalMachO(littleEndian: Bool, is64: Bool) -> Data {
    var data = Data(bytes(is64 ? 0xcafebabf : 0xcafebabe, littleEndian: littleEndian) + bytes(2, littleEndian: littleEndian))
    for cpu: UInt32 in [0x01000007, 0x0100000c] {
        data.append(contentsOf: bytes(cpu, littleEndian: littleEndian) + Array(repeating: 0, count: is64 ? 28 : 16))
    }
    return data
}
