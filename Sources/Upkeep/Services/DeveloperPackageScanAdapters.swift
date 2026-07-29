import Foundation

protocol DeveloperPackageScanAdapter: Sendable {
    var manager: DeveloperPackageManager { get }
    func scan(path: String, defaultNode: String?) async -> ManagerScanResult
}

private struct FunctionalDeveloperPackageScanAdapter: DeveloperPackageScanAdapter {
    let manager: DeveloperPackageManager
    let operation: @Sendable (String, String?) async -> ManagerScanResult

    func scan(path: String, defaultNode: String?) async -> ManagerScanResult {
        await operation(path, defaultNode)
    }
}

enum DeveloperPackageScanAdapters {
    static let managers = Set(adapters.keys)

    static func scan(
        manager: DeveloperPackageManager,
        path: String,
        defaultNode: String?
    ) async -> ManagerScanResult {
        guard let adapter = adapters[manager] else {
            return ManagerScanResult(
                manager: manager,
                packages: [],
                warning: "No scan adapter is registered for \(manager.rawValue).",
                executablePath: path
            )
        }
        let result = await adapter.scan(path: path, defaultNode: defaultNode)
        return ManagerScanResult(
            manager: result.manager,
            packages: result.packages,
            warning: result.warning,
            executablePath: path
        )
    }

    private static let adapters: [DeveloperPackageManager: any DeveloperPackageScanAdapter] = [
        .node: adapter(.node) { path, defaultNode in await scanNode(path, preferLatestMajor: path == defaultNode) },
        .bun: adapter(.bun) { path, _ in await scanBun(path) },
        .deno: adapter(.deno) { path, _ in await scanJavaScriptRuntime(.deno, name: "Deno", path: path, repository: "denoland/deno") },
        .npm: adapter(.npm) { path, _ in await scanNPM(path) },
        .pnpm: adapter(.pnpm) { path, _ in await scanPNPM(path) },
        .yarn: adapter(.yarn) { path, _ in await scanYarn(path) },
        .vsCode: adapter(.vsCode) { path, _ in await scanVSCodeExtensions(path) },
        .uv: adapter(.uv) { path, _ in await scanUVTools(path) },
        .pipx: adapter(.pipx) { path, _ in await scanPipxTools(path) },
        .python: adapter(.python) { path, _ in await scanPython(path) },
        .rubyGems: adapter(.rubyGems) { path, _ in await scanGems(path) },
        .rustup: adapter(.rustup) { path, _ in await scanRustup(path) },
        .cargo: adapter(.cargo) { path, _ in await scanCargo(path) },
        .githubCLI: adapter(.githubCLI) { path, _ in await scanGitHubCLIExtensions(path) },
        .go: adapter(.go) { path, _ in await scanGoTools(path) },
        .composer: adapter(.composer) { path, _ in await scanComposer(path) },
        .dotnet: adapter(.dotnet) { path, _ in await scanDotnetTools(path) },
        .macPorts: adapter(.macPorts) { path, _ in await scanMacPorts(path) },
        .nix: adapter(.nix) { path, _ in await scanNixProfile(path) },
        .mise: adapter(.mise) { path, _ in await scanMise(path) },
        .asdf: adapter(.asdf) { path, _ in await scanASDF(path) },
        .volta: adapter(.volta) { path, _ in await scanVolta(path) },
        .fnm: adapter(.fnm) { path, _ in await scanFNM(path) }
    ]

    private static func adapter(
        _ manager: DeveloperPackageManager,
        operation: @escaping @Sendable (String, String?) async -> ManagerScanResult
    ) -> any DeveloperPackageScanAdapter {
        FunctionalDeveloperPackageScanAdapter(manager: manager, operation: operation)
    }
}

let developerPackageScanAdapterManagers = DeveloperPackageScanAdapters.managers

func scanDeveloperTarget(
    manager: DeveloperPackageManager,
    path: String,
    defaultNode: String?
) async -> ManagerScanResult {
    await DeveloperPackageScanAdapters.scan(
        manager: manager,
        path: path,
        defaultNode: defaultNode
    )
}
