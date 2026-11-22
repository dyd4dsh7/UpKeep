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

@Test func runtimeWithoutSafeRemovalDoesNotOfferUninstall() {
    let package = adapterPackage(manager: .bun, name: "Bun")
    #expect(!DeveloperPackageUninstallAdapters.supports(package))
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
