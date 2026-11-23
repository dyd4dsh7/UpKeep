import Foundation
import Testing
@testable import Upkeep

@Test func everyDeveloperManagerHasAnInstallAdapter() throws {
    for manager in DeveloperPackageManager.allCases {
        let package = adapterPackage(manager: manager)
        _ = try DeveloperPackageInstallAdapters.plan(for: package, version: package.latestVersion)
    }
}

@Test func everyDeveloperManagerHasAScanAdapter() {
    #expect(developerPackageScanAdapterManagers == Set(DeveloperPackageManager.allCases))
}

@Test func npmAdapterBuildsAnExplicitGlobalInstallCommand() throws {
    let package = adapterPackage(manager: .npm, name: "typescript")
    guard case let .command(executable, arguments, _) = try DeveloperPackageInstallAdapters.plan(
        for: package,
        version: "6.0.0"
    ) else {
        Issue.record("Expected an executable command plan")
        return
    }

    #expect(executable.path == "/usr/local/bin/npm")
    #expect(arguments == ["install", "-g", "typescript@6.0.0"])
}

@Test func npmUninstallAdapterBuildsAnExplicitGlobalCommand() throws {
    let package = adapterPackage(manager: .npm, name: "typescript")
    let plan = try DeveloperPackageUninstallAdapters.plan(for: package)

    #expect(plan.executable.path == "/usr/local/bin/npm")
    #expect(plan.arguments == ["uninstall", "-g", "typescript"])
}

@Test func nvmNodeUninstallAdapterUsesTheSelectedRuntimeVersion() throws {
    let package = DeveloperPackage(
        name: "Node.js",
        currentVersion: "24.15.0",
        latestVersion: "26.5.0",
        manager: .node,
        executablePath: "/Users/example/.nvm/versions/node/v24.15.0/bin/node"
    )
    let plan = try DeveloperPackageUninstallAdapters.plan(for: package)

    #expect(plan.executable.path == "/bin/zsh")
    #expect(plan.arguments.suffix(2) == ["/Users/example/.nvm", "24.15.0"])
}

@Test func toolWithUnknownOriginDoesNotOfferUninstall() {
    let package = DeveloperPackage(name: "Bun", currentVersion: "1.0.0", latestVersion: "2.0.0", manager: .bun,
                                   executablePath: "/nonexistent/upkeep/bin/bun")
    #expect(!DeveloperPackageUninstallAdapters.supports(package))
}

@Test func officialInstallerToolsMoveTheirFolderToTheTrash() throws {
    func plan(_ manager: DeveloperPackageManager, _ name: String, _ path: String) throws -> DeveloperPackageUninstallPlan.Action {
        try DeveloperPackageUninstallAdapters.plan(for: DeveloperPackage(
            name: name, currentVersion: "1.0.0", latestVersion: "2.0.0", manager: manager, executablePath: path)).action
    }
    #expect(try plan(.bun, "Bun", "/Users/example/.bun/bin/bun") == .trash(["/Users/example/.bun"]))
    #expect(try plan(.deno, "Deno", "/Users/example/.deno/bin/deno") == .trash(["/Users/example/.deno"]))
    #expect(try plan(.claudeCode, "Claude Code", "/Users/example/.local/bin/claude")
        == .trash(["/Users/example/.local/bin/claude", "/Users/example/.local/share/claude"]))
}

@Test func homebrewOwnedToolsUninstallWithBrew() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("UpkeepBrew-\(UUID().uuidString)/homebrew")
    let cellarBinary = root.appendingPathComponent("Cellar/deno/2.1.0/bin/deno")
    let link = root.appendingPathComponent("bin/deno")
    try FileManager.default.createDirectory(at: cellarBinary.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: cellarBinary)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: cellarBinary)
    defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
    let plan = try #require(DeveloperPackageUninstallAdapters.homebrewPlan(for: link.path))
    guard case let .command(brew, arguments) = plan.action else { Issue.record("Expected a brew command"); return }
    #expect(brew.path.hasSuffix("/homebrew/bin/brew"))
    #expect(arguments == ["uninstall", "deno"])
}

@Test func managerCommandsCoverPreviouslyUnsupportedPackages() throws {
    func arguments(_ package: DeveloperPackage) throws -> [String] {
        let plan = try DeveloperPackageUninstallAdapters.plan(for: package)
        guard case let .command(_, arguments) = plan.action else { return [] }
        return arguments
    }
    func package(_ manager: DeveloperPackageManager, _ name: String, version: String = "1.0.0",
                 identifier: String? = nil, path: String = "/x/tool") -> DeveloperPackage {
        DeveloperPackage(name: name, currentVersion: version, latestVersion: version, manager: manager,
                         executablePath: path, registryIdentifier: identifier)
    }
    #expect(try arguments(package(.npm, "npm")) == ["uninstall", "-g", "npm"])
    #expect(try arguments(package(.mise, "node", version: "22.1.0", identifier: "node")) == ["uninstall", "node@22.1.0"])
    #expect(try arguments(package(.asdf, "ruby", version: "3.3.0", identifier: "ruby")) == ["uninstall", "ruby", "3.3.0"])
    #expect(try arguments(package(.ghcup, "ghc", version: "9.6.6", identifier: "ghc")) == ["rm", "ghc", "9.6.6"])
    #expect(try arguments(package(.swiftly, "Swift 6.0", identifier: "6.0.3")) == ["uninstall", "6.0.3", "--assume-yes"])
    #expect(try arguments(package(.conda, "numpy", identifier: "numpy")) == ["remove", "-n", "base", "-y", "numpy"])
    #expect(!DeveloperPackageUninstallAdapters.supports(package(.conda, "conda", identifier: "conda")))
    #expect(try arguments(package(.pixi, "ripgrep", identifier: "ripgrep/ripgrep")) == ["global", "uninstall", "ripgrep"])
    let macPorts = try DeveloperPackageUninstallAdapters.plan(for: package(.macPorts, "wget", identifier: "wget", path: "/opt/local/bin/port"))
    #expect(macPorts.action == .administratorCommand(URL(fileURLWithPath: "/opt/local/bin/port"), ["uninstall", "wget"]))
    let simulator = try DeveloperPackageUninstallAdapters.plan(for: package(.xcodeSimulators, "iOS 18.2 Simulator",
        version: "22C150", identifier: "iOS", path: "/usr/bin/xcrun"))
    #expect(simulator.action == .simulatorRuntime(xcrun: "/usr/bin/xcrun", platform: "iOS", build: "22C150"))
}

@Test func simulatorRuntimeIdentifiersMatchPlatformAndBuild() {
    let json = Data("""
    {"A1": {"build": "22C150", "version": "18.2", "platformIdentifier": "com.apple.platform.iphonesimulator", "state": "Ready"},
     "B2": {"build": "22C150", "version": "11.2", "platformIdentifier": "com.apple.platform.watchsimulator", "state": "Ready"},
     "C3": {"build": "22B81", "version": "18.1", "platformIdentifier": "com.apple.platform.iphonesimulator", "state": "Ready"}}
    """.utf8)
    #expect(simulatorRuntimeIdentifiers(json, platform: "iOS", build: "22C150") == ["A1"])
}

@MainActor
@Test func storeUsesInjectedDeveloperPackageManagerForInstalls() async {
    let suiteName = "DeveloperPackageAdapterTests.\(UUID().uuidString)"
    let defaults = UserDefaults(testSuiteName: suiteName)!
    defer { defaults.removeTestDomain(forName: suiteName) }
    let manager = RecordingDeveloperPackageManager()
    let store = UpkeepStore(
        settings: AppSettings(defaults: defaults),
        dependencies: UpkeepDependencies(
            scanner: EmptyScanner(),
            homebrew: HomebrewClient(),
            developerPackages: manager,
            localModels: LocalModelClient(),
            history: TestUpdateHistory()
        )
    )
    let package = adapterPackage(manager: .npm, name: "typescript")

    await store.installDeveloperPackage(package, version: "6.0.0")

    #expect(await manager.installs == ["typescript@6.0.0"])
}

@MainActor
@Test func storeUsesInjectedDeveloperPackageManagerForUninstalls() async {
    let suiteName = "DeveloperPackageAdapterTests.Uninstall.\(UUID().uuidString)"
    let defaults = UserDefaults(testSuiteName: suiteName)!
    defer { defaults.removeTestDomain(forName: suiteName) }
    let manager = RecordingDeveloperPackageManager()
    let store = UpkeepStore(
        settings: AppSettings(defaults: defaults),
        dependencies: UpkeepDependencies(
            scanner: EmptyScanner(),
            homebrew: HomebrewClient(),
            developerPackages: manager,
            localModels: LocalModelClient(),
            history: TestUpdateHistory()
        )
    )
    let package = adapterPackage(manager: .npm, name: "typescript")

    await store.uninstallDeveloperPackage(package)

    #expect(await manager.uninstalls == ["typescript"])
}

private func adapterPackage(
    manager: DeveloperPackageManager,
    name: String? = nil
) -> DeveloperPackage {
    DeveloperPackage(
        name: name ?? manager.rawValue,
        currentVersion: "1.0.0",
        latestVersion: "2.0.0",
        manager: manager,
        executablePath: manager == .npm ? "/usr/local/bin/npm" : "/usr/local/bin/\(manager.assetName)",
        registryIdentifier: name,
        canUpdateAutomatically: true
    )
}

private struct EmptyScanner: UpdateScanning {
    func scan(settings: ScanSettings) async -> ScanReport { .empty }
    func scan(app: InstalledApp, settings: ScanSettings) async -> UpdateScanner.TargetedAppReport { .empty }
}

private actor RecordingDeveloperPackageManager: DeveloperPackageManaging {
    private(set) var installs: [String] = []
    private(set) var uninstalls: [String] = []

    func scan(
        enabledManagers: Set<DeveloperPackageManager>,
        includePrereleases: Bool
    ) async -> DeveloperPackageClient.Report { .empty }

    func availableVersions(
        for package: DeveloperPackage,
        includePrereleases: Bool
    ) async -> [String] { [package.latestVersion] }

    func install(_ package: DeveloperPackage, version: String) async throws {
        installs.append("\(package.name)@\(version)")
    }

    func uninstall(_ package: DeveloperPackage) async throws {
        uninstalls.append(package.name)
    }
}
