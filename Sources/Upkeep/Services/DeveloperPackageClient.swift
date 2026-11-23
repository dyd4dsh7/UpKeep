import Foundation

struct DeveloperPackageClient: Sendable {
    struct Report: Sendable {
        let packages: [DeveloperPackage]
        let installedManagers: [DeveloperPackageManager]
        let warnings: [String]
        let failedManagers: Set<DeveloperPackageManager>
        let failedExecutablePaths: Set<String>
        var warningManagers: [String: Set<DeveloperPackageManager>] = [:]

        func hasFailures(for manager: DeveloperPackageManager) -> Bool {
            failedManagers.contains(manager)
                || packages.contains { $0.manager == manager && failedExecutablePaths.contains($0.executablePath) }
                || (!failedExecutablePaths.isEmpty && warningManagers.values.contains { $0.contains(manager) })
        }

        var scanWarnings: [ScanWarning] {
            warnings.map { ScanWarning(source: .developerPackages,
                itemNames: warningManagers[$0]?.map(\.rawValue) ?? [], message: $0) }
        }

        static let empty = Report(
            packages: [], installedManagers: [], warnings: [],
            failedManagers: [], failedExecutablePaths: []
        )
    }

    func scan(enabledManagers: Set<DeveloperPackageManager> = Set(DeveloperPackageManager.allCases),
              includePrereleases: Bool = false) async -> Report {
        await scan(enabledManagers: enabledManagers, includePrereleases: includePrereleases, managerProgress: nil)
    }

    func scan(
        enabledManagers: Set<DeveloperPackageManager> = Set(DeveloperPackageManager.allCases),
        includePrereleases: Bool = false,
        managerProgress: DeveloperScanProgressReporter?
    ) async -> Report {
        var tools: [(DeveloperPackageManager, String)] = []
        let defaultNode = nvmDefaultExecutable(named: "node")
        if enabledManagers.contains(.node) {
            tools.append(contentsOf: nvmExecutables(named: "node").map { (.node, $0) })
            if nvmExecutables(named: "node").isEmpty, let node = executable(named: "node", extra: []) {
                tools.append((.node, node))
            }
        }
        appendDetected(.bun, named: "bun", extra: [homePath(".bun/bin/bun")], enabledManagers: enabledManagers, to: &tools)
        appendDetected(.deno, named: "deno", extra: [homePath(".deno/bin/deno")], enabledManagers: enabledManagers, to: &tools)
        appendAllDetected(.npm, named: "npm", extra: nodeToolExecutables(named: "npm", defaultNode: defaultNode), enabledManagers: enabledManagers, to: &tools)
        appendAllDetected(.pnpm, named: "pnpm", extra: nodeToolExecutables(named: "pnpm", defaultNode: defaultNode), enabledManagers: enabledManagers, to: &tools)
        appendAllDetected(.yarn, named: "yarn", extra: nodeToolExecutables(named: "yarn", defaultNode: defaultNode), enabledManagers: enabledManagers, to: &tools)
        if enabledManagers.contains(.vsCode) {
            tools.append(contentsOf: editorCLIs().map { (.vsCode, $0) })
        }
        appendDetected(.uv, named: "uv", extra: [homePath(".local/bin/uv")], enabledManagers: enabledManagers, to: &tools)
        appendDetected(.pipx, named: "pipx", extra: [homePath(".local/bin/pipx")], enabledManagers: enabledManagers, to: &tools)
        appendDetected(.python, named: "python3", extra: ["/usr/bin/python3"], enabledManagers: enabledManagers, to: &tools)
        appendDetected(.rubyGems, named: "gem", extra: rubyGemExecutableCandidates(), enabledManagers: enabledManagers, to: &tools)
        appendDetected(.rustup, named: "rustup", extra: [homePath(".cargo/bin/rustup")], enabledManagers: enabledManagers, to: &tools)
        appendDetected(.cargo, named: "cargo", extra: [homePath(".cargo/bin/cargo")], enabledManagers: enabledManagers, to: &tools)
        appendDetected(.githubCLI, named: "gh", extra: [], enabledManagers: enabledManagers, to: &tools)
        appendDetected(.go, named: "go", extra: ["/usr/local/go/bin/go"], enabledManagers: enabledManagers, to: &tools)
        appendDetected(.composer, named: "composer", extra: [homePath(".composer/vendor/bin/composer")], enabledManagers: enabledManagers, to: &tools)
        appendDetected(.dotnet, named: "dotnet", extra: [homePath(".dotnet/dotnet")], enabledManagers: enabledManagers, to: &tools)
        appendDetected(.macPorts, named: "port", extra: ["/opt/local/bin/port"], enabledManagers: enabledManagers, to: &tools)
        appendDetected(.nix, named: "nix", extra: ["/nix/var/nix/profiles/default/bin/nix", "/run/current-system/sw/bin/nix"], enabledManagers: enabledManagers, to: &tools)
        appendDetected(.mise, named: "mise", extra: [homePath(".local/bin/mise")], enabledManagers: enabledManagers, to: &tools)
        appendDetected(.asdf, named: "asdf", extra: [homePath(".asdf/bin/asdf")], enabledManagers: enabledManagers, to: &tools)
        appendDetected(.volta, named: "volta", extra: [homePath(".volta/bin/volta")], enabledManagers: enabledManagers, to: &tools)
        appendDetected(.fnm, named: "fnm", extra: [homePath(".local/share/fnm/fnm")], enabledManagers: enabledManagers, to: &tools)
        appendDetected(.dockerImages, named: "docker", extra: ["/Applications/Docker.app/Contents/Resources/bin/docker"],
            enabledManagers: enabledManagers, to: &tools)
        appendDetected(.pixi, named: "pixi", extra: [homePath(".pixi/bin/pixi")], enabledManagers: enabledManagers, to: &tools)
        appendDetected(.krew, named: "kubectl-krew", extra: [homePath(".krew/bin/kubectl-krew")], enabledManagers: enabledManagers, to: &tools)
        appendDetected(.juliaup, named: "juliaup", extra: [homePath(".juliaup/bin/juliaup")], enabledManagers: enabledManagers, to: &tools)
        appendDetected(.opam, named: "opam", extra: [homePath(".local/bin/opam")], enabledManagers: enabledManagers, to: &tools)
        appendDetected(.dart, named: "dart", extra: [], enabledManagers: enabledManagers, to: &tools)
        appendDetected(.flutter, named: "flutter", extra: [
            homePath("flutter/bin/flutter"), homePath("development/flutter/bin/flutter"), "/opt/homebrew/share/flutter/bin/flutter"
        ], enabledManagers: enabledManagers, to: &tools)
        appendDetected(.ghcup, named: "ghcup", extra: [homePath(".ghcup/bin/ghcup")], enabledManagers: enabledManagers, to: &tools)
        appendDetected(.swiftly, named: "swiftly", extra: [homePath(".swiftly/bin/swiftly")], enabledManagers: enabledManagers, to: &tools)
        if enabledManagers.contains(.poetry) { tools.append(contentsOf: officialPoetryExecutables().map { (.poetry, $0) }) }
        if enabledManagers.contains(.conda) { tools.append(contentsOf: condaExecutables().map { (.conda, $0) }) }
        if enabledManagers.contains(.sdkman), let script = sdkmanInitScript() { tools.append((.sdkman, script)) }
        if enabledManagers.contains(.claudeCode), let launcher = claudeCodeNativeLauncher() { tools.append((.claudeCode, launcher)) }
        if enabledManagers.contains(.nvm), let script = nvmCheckoutScript() { tools.append((.nvm, script)) }
        if enabledManagers.contains(.pyenv), let pyenv = pyenvExecutable() { tools.append((.pyenv, pyenv)) }
        if enabledManagers.contains(.rbenv), let rbenv = rbenvExecutable() { tools.append((.rbenv, rbenv)) }
        if enabledManagers.contains(.googleCloud), let gcloud = googleCloudExecutable() { tools.append((.googleCloud, gcloud)) }
        appendDetected(.azureCLI, named: "az", extra: [], enabledManagers: enabledManagers, to: &tools)
        if enabledManagers.contains(.xcodeSimulators), let xcrun = xcodeSimulatorExecutable() { tools.append((.xcodeSimulators, xcrun)) }

        var seenTargets = Set<String>()
        tools = tools.filter { seenTargets.insert("\($0.0.rawValue):\($0.1)").inserted }

        let targets = Dictionary(grouping: tools, by: { $0.0 })
        let reports = await withTaskGroup(of: (DeveloperPackageManager, Report).self) { group in
            for manager in enabledManagers {
                let paths = targets[manager]?.map { $0.1 } ?? []
                group.addTask {
                    let results = await withTaskGroup(of: ManagerScanResult.self) { workers in
                        for path in paths {
                            workers.addTask { await scanDeveloperTarget(manager: manager, path: path, defaultNode: defaultNode) }
                        }
                        var values: [ManagerScanResult] = []
                        for await result in workers { values.append(result) }
                        return values
                    }
                    return (manager, await managerReport(results: results, manager: manager, includePrereleases: includePrereleases))
                }
            }
            var completed: [Report] = []
            for await (manager, report) in group {
                if let managerProgress { await managerProgress(report, [manager]) }
                completed.append(report)
            }
            return completed
        }
        return Self.combine(reports)
    }

    static func combine(_ reports: [Report]) -> Report {
        var warningManagers: [String: Set<DeveloperPackageManager>] = [:]
        for report in reports {
            for (warning, managers) in report.warningManagers { warningManagers[warning, default: []].formUnion(managers) }
        }
        return Report(packages: reports.flatMap(\.packages).sorted {
            if $0.manager != $1.manager { return $0.manager.rawValue < $1.manager.rawValue }
            let order = $0.name.localizedStandardCompare($1.name)
            if order != .orderedSame { return order == .orderedAscending }
            return ($0.installationContext ?? $0.executablePath).localizedStandardCompare($1.installationContext ?? $1.executablePath) == .orderedAscending
        }, installedManagers: Array(Set(reports.flatMap(\.installedManagers))).sorted { $0.rawValue < $1.rawValue },
        warnings: reports.flatMap(\.warnings), failedManagers: Set(reports.flatMap { $0.failedManagers }),
        failedExecutablePaths: Set(reports.flatMap { $0.failedExecutablePaths }), warningManagers: warningManagers)
    }

    private func managerReport(results: [ManagerScanResult], manager: DeveloperPackageManager,
                               includePrereleases: Bool) async -> Report {
        var packagesByID: [String: DeveloperPackage] = [:]
        for package in results.flatMap(\.packages) { packagesByID[package.id] = package }
        let stablePackages = packagesByID.values.sorted {
                if $0.manager != $1.manager { return $0.manager.rawValue < $1.manager.rawValue }
                let nameOrder = $0.name.localizedStandardCompare($1.name)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                return ($0.installationContext ?? $0.executablePath).localizedStandardCompare($1.installationContext ?? $1.executablePath) == .orderedAscending
        }
        let packages = includePrereleases
            ? await includingPrereleaseUpdates(in: stablePackages)
            : stablePackages
        var warningManagers: [String: Set<DeveloperPackageManager>] = [:]
        for result in results {
            if let warning = result.warning { warningManagers[warning, default: []].insert(result.manager) }
        }
        return Report(
            packages: packages,
            installedManagers: results.isEmpty ? [] : [manager],
            warnings: results.compactMap(\.warning),
            failedManagers: Set([manager].filter { manager in
                let managerResults = results.filter { $0.manager == manager }
                return !managerResults.isEmpty && managerResults.allSatisfy { $0.warning != nil && $0.packages.isEmpty }
            }),
            failedExecutablePaths: Set(results.compactMap { result in
                result.warning != nil ? result.executablePath : nil
            }),
            warningManagers: warningManagers
        )
    }

    private func includingPrereleaseUpdates(in packages: [DeveloperPackage]) async -> [DeveloperPackage] {
        let passthroughManagers: Set<DeveloperPackageManager> = [.node, .bun, .deno, .yarn, .dockerImages]
        let passthrough = packages.filter { passthroughManagers.contains($0.manager) }
        let grouped = Dictionary(grouping: packages.filter { !passthroughManagers.contains($0.manager) }) {
            "\($0.manager.rawValue):\($0.registryIdentifier ?? $0.name)"
        }
        let enrichedGroups = await withTaskGroup(of: [DeveloperPackage].self) { group in
            for values in grouped.values {
                group.addTask {
                    guard let representative = values.first else { return [] }
                    let versions = await availableVersions(for: representative, includePrereleases: true)
                    return values.map { package in
                        let latest = versions.first(where: {
                            VersionComparator.isNewer($0, than: package.currentVersion)
                        }) ?? package.latestVersion
                        return package.replacingLatestVersion(with: latest)
                    }
                }
            }
            var output: [DeveloperPackage] = []
            for await values in group { output.append(contentsOf: values) }
            return output
        }
        return (passthrough + enrichedGroups).sorted {
            if $0.manager != $1.manager { return $0.manager.rawValue < $1.manager.rawValue }
            let nameOrder = $0.name.localizedStandardCompare($1.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return ($0.installationContext ?? $0.executablePath).localizedStandardCompare($1.installationContext ?? $1.executablePath) == .orderedAscending
        }
    }

    func availableVersions(for package: DeveloperPackage, includePrereleases: Bool) async -> [String] {
        let discovered: [String]
        switch package.manager {
        case .node:
            discovered = await nodeReleaseVersions()
        case .bun:
            discovered = package.name == "Bun"
                ? await latestPublisherReleaseVersions(repository: "oven-sh/bun")
                : await npmRegistryVersions(package: package.registryIdentifier ?? package.name)
        case .deno:
            discovered = await latestPublisherReleaseVersions(repository: "denoland/deno")
        case .npm, .pnpm:
            let result = await captureDeveloperCommandAsync(
                URL(fileURLWithPath: package.executablePath),
                ["view", package.name, "versions", "--json"]
            )
            if result.status != 0 { discovered = [] }
            else if let values = try? JSONDecoder().decode([String].self, from: result.data) { discovered = values }
            else if let value = try? JSONDecoder().decode(String.self, from: result.data) { discovered = [value] }
            else { discovered = [] }
        case .uv where package.registryIdentifier?.hasPrefix("python:") == true:
            discovered = [package.currentVersion, package.latestVersion]
        case .uv, .pipx, .python:
            guard let encoded = (package.registryIdentifier ?? package.name).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "https://pypi.org/pypi/\(encoded)/json"),
                  let data = await registryData(from: url),
                  let response = try? JSONDecoder().decode(PyPIResponse.self, from: data)
            else { discovered = [] ; break }
            discovered = response.releases.compactMap { version, files in
                files.isEmpty ? nil : version
            }
        case .rubyGems:
            guard let encoded = package.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "https://rubygems.org/api/v1/versions/\(encoded).json"),
                  let data = await registryData(from: url),
                  let versions = try? JSONDecoder().decode([RubyGemVersion].self, from: data)
            else { discovered = [] ; break }
            discovered = versions.map(\.number)
        case .cargo:
            guard let encoded = package.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "https://crates.io/api/v1/crates/\(encoded)"),
                  let data = await registryData(from: url),
                  let response = try? JSONDecoder().decode(CrateVersionsResponse.self, from: data)
            else { discovered = [] ; break }
            discovered = response.versions.filter { !$0.yanked }.map(\.num)
        case .yarn:
            discovered = await npmRegistryVersions(package: package.name == "Yarn" ? "yarn" : (package.registryIdentifier ?? package.name))
        case .vsCode:
            if let gallery = EditorExtensionGallery.forEditorCLI(package.executablePath) {
                discovered = await visualStudioMarketplaceVersions(
                    extensionID: package.registryIdentifier ?? package.name, gallery: gallery)
            } else {
                discovered = []
            }
        case .rustup, .macPorts, .nix, .mise, .asdf, .volta, .fnm:
            discovered = [package.currentVersion, package.latestVersion]
        case .dockerImages:
            discovered = []
        case .dart:
            discovered = await pubDevVersions(package.registryIdentifier ?? package.name)
        case .pixi, .krew, .juliaup, .opam, .poetry, .flutter, .ghcup, .swiftly, .conda, .sdkman, .claudeCode, .nvm,
             .pyenv, .rbenv, .googleCloud, .azureCLI, .xcodeSimulators:
            discovered = [package.currentVersion, package.latestVersion]
        case .githubCLI:
            discovered = await latestPublisherReleaseVersions(repository: package.registryIdentifier ?? package.name)
        case .go where package.registryIdentifier == "go-runtime":
            discovered = [package.currentVersion, await latestGoReleaseVersion() ?? package.latestVersion]
        case .go:
            discovered = await goModuleVersions(module: package.registryIdentifier ?? package.name)
        case .composer:
            discovered = await composerPackageVersions(package.registryIdentifier ?? package.name)
        case .dotnet:
            discovered = await nugetPackageVersions(package.registryIdentifier ?? package.name)
        }

        return selectableDeveloperPackageVersions(
            discovered: discovered,
            package: package,
            includePrereleases: includePrereleases
        )
    }

    func install(_ package: DeveloperPackage, version: String) async throws {
        guard package.canUpdateAutomatically else {
            throw ClientError.failed("\(package.name) must be updated manually with \(package.manager.rawValue).")
        }
        switch try DeveloperPackageInstallAdapters.plan(for: package, version: version) {
        case .node:
            try await installNode(version: version, executablePath: package.executablePath)
        case let .command(executable, arguments, failureMessage):
            let result = await captureDeveloperCommandAsync(
                executable,
                arguments,
                qos: .userInitiated,
                purpose: .mutation
            )
            guard result.status == 0 else {
                let output = String(data: result.data, encoding: .utf8)
                throw ClientError.failed(output?.isEmpty == false ? output! : failureMessage)
            }
        }
    }

    func uninstall(_ package: DeveloperPackage) async throws {
        let plan = try DeveloperPackageUninstallAdapters.plan(for: package)
        switch plan.action {
        case let .command(executable, arguments):
            try await runUninstallCommand(executable, arguments, failureMessage: plan.failureMessage)
        case let .administratorCommand(executable, arguments):
            try await runAsAdministrator(executable, arguments, failureMessage: plan.failureMessage)
        case let .trash(paths):
            let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
            guard !existing.isEmpty else { throw ClientError.failed("\(package.name) was not found on disk.") }
            for path in existing {
                do { try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil) }
                catch { throw ClientError.failed("Could not move \(path) to the Trash: \(error.localizedDescription)") }
            }
        case let .simulatorRuntime(xcrun, platform, build):
            let xcrunURL = URL(fileURLWithPath: xcrun)
            let list = await captureDeveloperStandardOutput(xcrunURL, ["simctl", "runtime", "list", "-j"])
            guard list.status == 0 else { throw ClientError.failed(plan.failureMessage) }
            let identifiers = simulatorRuntimeIdentifiers(list.data, platform: platform, build: build)
            guard !identifiers.isEmpty else { throw ClientError.failed("No installed \(platform) simulator runtime has build \(build).") }
            for identifier in identifiers {
                try await runUninstallCommand(xcrunURL, ["simctl", "runtime", "delete", identifier],
                                              failureMessage: plan.failureMessage)
            }
        }
    }

    private func runUninstallCommand(_ executable: URL, _ arguments: [String], failureMessage: String) async throws {
        let result = await captureDeveloperCommandAsync(executable, arguments, qos: .userInitiated, purpose: .mutation)
        guard result.status == 0 else {
            let output = String(data: result.data, encoding: .utf8)
            throw ClientError.failed(output?.isEmpty == false ? output! : failureMessage)
        }
    }

    /// macOS shows its own password prompt; Upkeep never sees the password.
    private func runAsAdministrator(_ executable: URL, _ arguments: [String], failureMessage: String) async throws {
        let script = """
        on run argv
            set command to quoted form of (item 1 of argv)
            repeat with index from 2 to count of argv
                set command to command & " " & quoted form of (item index of argv)
            end repeat
            do shell script command with administrator privileges
        end run
        """
        let result: CommandRunner.Result
        do {
            result = try await CommandRunner.run(URL(fileURLWithPath: "/usr/bin/osascript"),
                                                 ["-e", script, executable.path] + arguments, timeout: 2_400)
        } catch { throw ClientError.failed(error.localizedDescription) }
        guard result.status == 0 else {
            let output = String(decoding: result.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if output.contains("-128") { throw ClientError.failed("Uninstall was cancelled.") }
            throw ClientError.failed(output.isEmpty ? failureMessage : output)
        }
    }

    enum ClientError: LocalizedError {
        case failed(String)
        var errorDescription: String? { if case let .failed(message) = self { return message }; return nil }
    }

    private func installNode(version: String, executablePath: String) async throws {
        guard let nvmDirectory = nvmDirectory(for: executablePath) else {
            throw ClientError.failed("Automatic Node.js updates currently require an NVM-managed installation.")
        }
        guard let currentVersion = nvmNodeVersion(for: executablePath) else {
            throw ClientError.failed("Upkeep could not determine the installed NVM Node.js version.")
        }
        let targetVersion = version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard currentVersion != targetVersion else { return }
        let arguments = nvmNodeUpdateArguments(
            nvmDirectory: nvmDirectory,
            currentVersion: currentVersion,
            targetVersion: targetVersion,
            isDefault: nvmDefaultExecutable(named: "node") == executablePath
        )
        let result = await captureDeveloperCommandAsync(
            URL(fileURLWithPath: "/bin/zsh"),
            arguments,
            qos: .userInitiated,
            purpose: .mutation
        )
        guard result.status == 0 else {
            let output = String(data: result.data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ClientError.failed(output?.isEmpty == false ? output! : "Node.js update failed.")
        }
    }
}

func selectableDeveloperPackageVersions(
    discovered: [String],
    package: DeveloperPackage,
    includePrereleases: Bool
) -> [String] {
    // A tag only pulls its current digest; digests have no version order.
    if package.manager.comparesExactVersions { return [package.latestVersion] }
    var allowed = includePrereleases
        ? discovered
        : discovered.filter { !VersionComparator.isPrerelease($0) }
    // Always preserve the installed version so an existing prerelease remains visible and identifiable.
    allowed.append(package.currentVersion)
    if includePrereleases || !VersionComparator.isPrerelease(package.latestVersion) {
        allowed.append(package.latestVersion)
    }
    return VersionComparator.sortedNewestFirst(Set(allowed))
}

struct ManagerScanResult: Sendable {
    let manager: DeveloperPackageManager
    let packages: [DeveloperPackage]
    let warning: String?
    let executablePath: String?

    init(
        manager: DeveloperPackageManager,
        packages: [DeveloperPackage],
        warning: String?,
        executablePath: String? = nil
    ) {
        self.manager = manager
        self.packages = packages
        self.warning = warning
        self.executablePath = executablePath
    }
}

func scanNode(_ path: String, preferLatestMajor: Bool) async -> ManagerScanResult {
    let installedResult = await captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["--version"])
    guard installedResult.status == 0,
          let installedOutput = String(data: installedResult.data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
          !installedOutput.isEmpty else {
        return failedManagerScan(.node, command: "version check", result: installedResult)
    }
    let installed = installedOutput.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    let releases = await nodeReleaseVersions()
    guard let latest = latestNodeRelease(in: releases, installed: installed, preferLatestMajor: preferLatestMajor) else {
        return ManagerScanResult(
            manager: .node,
            packages: [DeveloperPackage(
                name: "Node.js", currentVersion: installed, latestVersion: installed,
                manager: .node, executablePath: path,
                installationContext: nvmInstallationContext(for: path)
            )],
            warning: "Node.js release check failed: the official release index could not be read."
        )
    }
    return ManagerScanResult(
        manager: .node,
        packages: [DeveloperPackage(
            name: "Node.js", currentVersion: installed, latestVersion: latest,
            manager: .node, executablePath: path,
            installationContext: nvmInstallationContext(for: path)
        )],
        warning: nil
    )
}

func scanBun(_ path: String) async -> ManagerScanResult {
    let runtime = await scanJavaScriptRuntime(.bun, name: "Bun", path: path, repository: "oven-sh/bun")
    let manifest = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".bun/install/global/package.json")
    guard let data = try? Data(contentsOf: manifest),
          let root = try? JSONDecoder().decode(BunGlobalManifest.self, from: data) else { return runtime }
    let installed = (root.dependencies ?? [:]).merging(root.devDependencies ?? [:]) { current, _ in current }
    let globals = await packagesFromNPMRegistry(
        installed: installed,
        manager: .bun,
        executablePath: path,
        context: "Bun global"
    )
    return ManagerScanResult(manager: .bun, packages: runtime.packages + globals.packages, warning: joinedWarnings(runtime.warning, globals.warning))
}

func scanJavaScriptRuntime(
    _ manager: DeveloperPackageManager,
    name: String,
    path: String,
    repository: String
) async -> ManagerScanResult {
    let installedResult = await captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["--version"])
    guard installedResult.status == 0,
          let output = String(data: installedResult.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !output.isEmpty else {
        return failedManagerScan(manager, command: "version check", result: installedResult)
    }
    let installed = normalizedJavaScriptRuntimeVersion(output)
    guard let latest = await latestPublisherReleaseVersions(repository: repository).first else {
        return ManagerScanResult(
            manager: manager,
            packages: [DeveloperPackage(name: name, currentVersion: installed, latestVersion: installed, manager: manager, executablePath: path)],
            warning: "\(name) release check failed: the official release feed could not be read."
        )
    }
    return ManagerScanResult(
        manager: manager,
        packages: [DeveloperPackage(name: name, currentVersion: installed, latestVersion: latest, manager: manager, executablePath: path)],
        warning: nil
    )
}

func scanYarn(_ path: String) async -> ManagerScanResult {
    let installedResult = await captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["--version"])
    guard installedResult.status == 0,
          let output = String(data: installedResult.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !output.isEmpty else {
        return failedManagerScan(.yarn, command: "version check", result: installedResult)
    }
    guard let latest = await npmRegistryLatestVersion(package: "yarn") else {
        return ManagerScanResult(
            manager: .yarn,
            packages: [DeveloperPackage(name: "Yarn", currentVersion: output, latestVersion: output, manager: .yarn, executablePath: path)],
            warning: "Yarn release check failed: the npm registry could not be read."
        )
    }
    let managerPackage = DeveloperPackage(name: "Yarn", currentVersion: output, latestVersion: latest, manager: .yarn, executablePath: path, installationContext: nvmInstallationContext(for: path))
    let globalsResult = await captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["global", "list", "--json", "--depth=0"])
    let globals = DeveloperInventoryParsers.parseYarnGlobalPackages(globalsResult.data)
    let globalPackages = await packagesFromNPMRegistry(
        installed: globals,
        manager: .yarn,
        executablePath: path,
        context: nvmInstallationContext(for: path)
    )
    return ManagerScanResult(
        manager: .yarn,
        packages: [managerPackage] + globalPackages.packages,
        warning: joinedWarnings(
            globalsResult.status == 0 ? nil : commandWarning(.yarn, command: "global inventory", result: globalsResult),
            globalPackages.warning
        )
    )
}

func normalizedJavaScriptRuntimeVersion(_ value: String) -> String {
    let firstLine = value.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? value
    let lastToken = firstLine.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? firstLine
    return lastToken
        .replacingOccurrences(of: "bun-v", with: "")
        .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
}

func scanNPM(_ path: String) async -> ManagerScanResult {
    // `npm outdated` exits 1 when anything is outdated, so cache any result
    // that parses rather than requiring a zero exit status.
    let executable = URL(fileURLWithPath: path)
    let (installedResult, outdatedResult, _) = await DeveloperOutdatedCache.shared.inventoryAndOutdated(
        key: "npm|\(path)",
        inventory: { await captureDeveloperCommandAsync(executable, ["ls", "-g", "--depth=0", "--json"]) },
        outdated: { await captureDeveloperCommandAsync(executable, ["outdated", "-g", "--json"]) },
        isCacheable: { inventory, outdated in
            (try? JSONDecoder().decode(NPMList.self, from: inventory.data).dependencies) != nil
                && (try? JSONDecoder().decode([String: NPMOutdated].self, from: outdated.data)) != nil
        }
    )
    guard let installed = try? JSONDecoder().decode(NPMList.self, from: installedResult.data).dependencies else {
        return failedManagerScan(.npm, command: "inventory", result: installedResult)
    }
    let outdated = try? JSONDecoder().decode([String: NPMOutdated].self, from: outdatedResult.data)
    var latestNPM = outdated?["npm"]?.latest
    if let current = installed["npm"]?.version, let latest = latestNPM, latest != current {
        latestNPM = await newestNPMSupportingNode(nextTo: path, current: current, latest: latest)
    }
    let packages = installed.map { name, entry in
        DeveloperPackage(
            name: name, currentVersion: entry.version,
            latestVersion: (name == "npm" ? latestNPM : outdated?[name]?.latest) ?? entry.version,
            manager: .npm, executablePath: path, installationContext: nvmInstallationContext(for: path)
        )
    }
    return ManagerScanResult(
        manager: .npm,
        packages: packages,
        warning: outdated == nil && (outdatedResult.status != 0 || !outdatedResult.data.isEmpty)
            ? commandWarning(.npm, command: "outdated check", result: outdatedResult) : nil
    )
}

func scanPNPM(_ path: String) async -> ManagerScanResult {
    async let installedCommand = captureDeveloperCommandAsync(
        URL(fileURLWithPath: path), ["list", "-g", "--depth=0", "--json"]
    )
    async let outdatedCommand = captureDeveloperCommandAsync(
        URL(fileURLWithPath: path), ["outdated", "-g", "--format", "json"]
    )
    let (installedResult, outdatedResult) = await (installedCommand, outdatedCommand)
    guard let installed = parsePNPMInstalledPackages(installedResult.data) else {
        return failedManagerScan(.pnpm, command: "inventory", result: installedResult)
    }
    let outdated = try? JSONDecoder().decode([String: NPMOutdated].self, from: outdatedResult.data)
    let context = parsePNPMGlobalDirectory(installedResult.data).map { pnpmGlobalContext($0) }
        ?? nvmInstallationContext(for: path)
    let packages = installed.map { name, version in
        DeveloperPackage(
            name: name, currentVersion: version, latestVersion: outdated?[name]?.latest ?? version,
            manager: .pnpm, executablePath: path, installationContext: context
        )
    }
    return ManagerScanResult(
        manager: .pnpm,
        packages: packages,
        warning: outdated == nil && (outdatedResult.status != 0 || !outdatedResult.data.isEmpty)
            ? commandWarning(.pnpm, command: "outdated check", result: outdatedResult) : nil
    )
}

func scanPython(_ path: String) async -> ManagerScanResult {
    let executable = URL(fileURLWithPath: path)
    let (installedResult, outdatedResult, _) = await DeveloperOutdatedCache.shared.inventoryAndOutdated(
        key: "python|\(path)",
        inventory: {
            await captureDeveloperCommandAsync(executable, ["-m", "pip", "list", "--format=json", "--disable-pip-version-check"])
        },
        outdated: {
            await captureDeveloperCommandAsync(executable,
                ["-m", "pip", "list", "--outdated", "--format=json", "--disable-pip-version-check"])
        },
        isCacheable: { inventory, outdated in
            (try? JSONDecoder().decode([PipInstalled].self, from: inventory.data)) != nil
                && (try? JSONDecoder().decode([PipOutdated].self, from: outdated.data)) != nil
        }
    )
    guard let installed = try? JSONDecoder().decode([PipInstalled].self, from: installedResult.data) else {
        return failedManagerScan(.python, command: "inventory", result: installedResult)
    }
    let outdatedValues = try? JSONDecoder().decode([PipOutdated].self, from: outdatedResult.data)
    let outdated = Dictionary((outdatedValues ?? []).map { ($0.name.lowercased(), $0.latestVersion) }, uniquingKeysWith: { first, _ in first })
    let packages = installed.map {
        DeveloperPackage(name: $0.name, currentVersion: $0.version, latestVersion: outdated[$0.name.lowercased()] ?? $0.version, manager: .python, executablePath: path)
    }
    return ManagerScanResult(
        manager: .python,
        packages: packages,
        warning: outdatedValues == nil ? commandWarning(.python, command: "outdated check", result: outdatedResult) : nil
    )
}

func scanGems(_ path: String) async -> ManagerScanResult {
    let executable = URL(fileURLWithPath: path)
    let (installedResult, outdatedResult, _) = await DeveloperOutdatedCache.shared.inventoryAndOutdated(
        key: "rubygems|\(path)",
        inventory: { await captureDeveloperCommandAsync(executable, ["list", "--local"]) },
        outdated: { await captureDeveloperCommandAsync(executable, ["outdated"]) },
        isCacheable: { inventory, outdated in inventory.status == 0 && outdated.status == 0 }
    )
    guard installedResult.status == 0 else { return failedManagerScan(.rubyGems, command: "inventory", result: installedResult) }
    let installedOutput = String(data: installedResult.data, encoding: .utf8) ?? ""
    let outdatedOutput = String(data: outdatedResult.data, encoding: .utf8) ?? ""
    let packages = DeveloperInventoryParsers.parseGemInventory(installedOutput, outdatedOutput: outdatedOutput, executablePath: path)
    return ManagerScanResult(
        manager: .rubyGems,
        packages: packages,
        warning: outdatedResult.status == 0 ? nil : commandWarning(.rubyGems, command: "outdated check", result: outdatedResult)
    )
}


func scanCargo(_ path: String) async -> ManagerScanResult {
    let installedResult = await captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["install", "--list"])
    guard installedResult.status == 0 else { return failedManagerScan(.cargo, command: "inventory", result: installedResult) }
    let output = String(data: installedResult.data, encoding: .utf8) ?? ""
    let installed = output.split(separator: "\n").compactMap { line -> (String, String)? in
        guard !line.hasPrefix(" "), let colon = line.firstIndex(of: ":") else { return nil }
        let prefix = line[..<colon].split(separator: " "); guard prefix.count >= 2 else { return nil }
        return (String(prefix[0]), String(prefix[1]).trimmingCharacters(in: CharacterSet(charactersIn: "v")))
    }
    let results = await withTaskGroup(of: (DeveloperPackage, Bool).self) { group in
        for (name, current) in installed {
            group.addTask {
                guard let url = URL(string: "https://crates.io/api/v1/crates/\(name)"),
                      let data = await registryData(from: url),
                      let response = try? JSONDecoder().decode(CrateResponse.self, from: data)
                else { return (DeveloperPackage(name: name, currentVersion: current, latestVersion: current, manager: .cargo, executablePath: path), true) }
                return (DeveloperPackage(name: name, currentVersion: current, latestVersion: response.crate.maxVersion, manager: .cargo, executablePath: path), false)
            }
        }
        var values: [(DeveloperPackage, Bool)] = []
        for await value in group { values.append(value) }
        return values
    }
    let failureCount = results.count { $0.1 }
    return ManagerScanResult(
        manager: .cargo,
        packages: results.map { $0.0 },
        warning: failureCount == 0 ? nil : "Cargo: registry checks failed for \(failureCount) package\(failureCount == 1 ? "" : "s")."
    )
}

func scanVSCodeExtensions(_ path: String) async -> ManagerScanResult {
    let result = await captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["--list-extensions", "--show-versions"])
    guard result.status == 0 else { return failedManagerScan(.vsCode, command: "inventory", result: result) }
    let installed = DeveloperInventoryParsers.parseExtensionInventory(result.data)
    let context = editorName(for: path)
    guard let gallery = EditorExtensionGallery.forEditorCLI(path) else {
        return ManagerScanResult(manager: .vsCode, packages: [],
            warning: "\(context) has no extension gallery configured, so its extensions were not checked.")
    }
    // One gallery query covers every extension; per-extension requests
    // remain the fallback for anything the batch does not return.
    let batched = await visualStudioMarketplaceVersions(extensionIDs: installed.map(\.0), gallery: gallery)
    let values = await withTaskGroup(of: (DeveloperPackage, Bool).self) { group in
        for (identifier, version) in installed {
            group.addTask {
                let batchVersions = batched[identifier.lowercased()] ?? []
                let versions = batchVersions.isEmpty
                    ? await visualStudioMarketplaceVersions(extensionID: identifier, gallery: gallery)
                    : batchVersions
                return (DeveloperPackage(
                    name: identifier,
                    currentVersion: version,
                    latestVersion: latestStableVersion(in: versions) ?? version,
                    manager: .vsCode,
                    executablePath: path,
                    registryIdentifier: identifier,
                    installationContext: context
                ), versions.isEmpty)
            }
        }
        var output: [(DeveloperPackage, Bool)] = []
        for await value in group { output.append(value) }
        return output
    }
    let failures = values.count { $0.1 }
    return ManagerScanResult(
        manager: .vsCode,
        packages: values.map(\.0),
        warning: failures == 0 ? nil : "\(context): \(gallery.serviceURL.host ?? "gallery") checks failed for \(failures) extension\(failures == 1 ? "" : "s")."
    )
}

func scanUVTools(_ path: String) async -> ManagerScanResult {
    let result = await captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["tool", "list", "--show-version-specifiers"])
    guard result.status == 0 else { return failedManagerScan(.uv, command: "tool inventory", result: result) }
    async let toolScan = scanPyPIToolInventory(DeveloperInventoryParsers.parseSimpleToolList(result.data), manager: .uv, executablePath: path)
    async let runtimeScan = scanUVManagedPythons(path)
    let (tools, runtimes) = await (toolScan, runtimeScan)
    return ManagerScanResult(
        manager: .uv,
        packages: tools.packages + runtimes.packages,
        warning: joinedWarnings(tools.warning, runtimes.warning)
    )
}

private func scanUVManagedPythons(_ path: String) async -> ManagerScanResult {
    let root = ProcessInfo.processInfo.environment["UV_PYTHON_INSTALL_DIR"]
        .map(URL.init(fileURLWithPath:))
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/uv/python")
    let directories = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
    let installed = directories.compactMap { DeveloperInventoryParsers.parseUVPythonDirectoryName($0.lastPathComponent) }
    let values = await withTaskGroup(of: DeveloperPackage.self) { group in
        for runtime in installed {
            group.addTask {
                let result = await captureDeveloperCommandAsync(
                    URL(fileURLWithPath: path), ["python", "list", runtime.minor, "--managed-python"]
                )
                let latest = DeveloperInventoryParsers.parseUVPythonList(result.data, matchingMinor: runtime.minor).first ?? runtime.version
                return DeveloperPackage(
                    name: "\(runtime.implementation) Python \(runtime.minor)",
                    currentVersion: runtime.version,
                    latestVersion: latest,
                    manager: .uv,
                    executablePath: path,
                    registryIdentifier: "python:\(runtime.minor)",
                    installationContext: "uv-managed runtime"
                )
            }
        }
        var output: [DeveloperPackage] = []
        for await value in group { output.append(value) }
        return output
    }
    return ManagerScanResult(manager: .uv, packages: values, warning: nil)
}

func scanPipxTools(_ path: String) async -> ManagerScanResult {
    let result = await captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["list", "--json"])
    guard result.status == 0,
          let root = try? JSONDecoder().decode(PipxList.self, from: result.data) else {
        return failedManagerScan(.pipx, command: "tool inventory", result: result)
    }
    let installed = root.venvs.values.reduce(into: [String: String]()) { values, environment in
        guard let package = environment.metadata.mainPackage,
              let name = package.package,
              let version = package.packageVersion else { return }
        values[name] = version
    }
    return await scanPyPIToolInventory(installed, manager: .pipx, executablePath: path)
}

private func scanPyPIToolInventory(
    _ installed: [String: String],
    manager: DeveloperPackageManager,
    executablePath: String
) async -> ManagerScanResult {
    let values = await withTaskGroup(of: (DeveloperPackage, Bool).self) { group in
        for (name, version) in installed {
            group.addTask {
                let latest = await latestPyPIVersion(package: name)
                return (DeveloperPackage(
                    name: name, currentVersion: version, latestVersion: latest ?? version,
                    manager: manager, executablePath: executablePath, registryIdentifier: name
                ), latest == nil)
            }
        }
        var output: [(DeveloperPackage, Bool)] = []
        for await value in group { output.append(value) }
        return output
    }
    let failures = values.count { $0.1 }
    return ManagerScanResult(
        manager: manager,
        packages: values.map(\.0),
        warning: failures == 0 ? nil : "\(manager.rawValue): registry checks failed for \(failures) tool\(failures == 1 ? "" : "s")."
    )
}

func scanRustup(_ path: String) async -> ManagerScanResult {
    let result = await captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["check"])
    guard result.status == 0 else { return failedManagerScan(.rustup, command: "toolchain check", result: result) }
    let packages = DeveloperInventoryParsers.parseRustupCheck(result.data).filter { $0.name != "rustup" }.map { toolchain in
        DeveloperPackage(
            name: toolchain.name,
            currentVersion: toolchain.current,
            latestVersion: toolchain.latest,
            manager: .rustup,
            executablePath: path,
            registryIdentifier: toolchain.name
        )
    }
    return ManagerScanResult(manager: .rustup, packages: packages, warning: nil)
}

func scanGitHubCLIExtensions(_ path: String) async -> ManagerScanResult {
    let listResult = await captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["extension", "list"])
    guard listResult.status == 0 else { return failedManagerScan(.githubCLI, command: "extension inventory", result: listResult) }
    let installed = DeveloperInventoryParsers.parseGitHubExtensionList(listResult.data)
    let updatesResult = await captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["extension", "upgrade", "--all", "--dry-run"])
    let updates = DeveloperInventoryParsers.parseGitHubExtensionUpdates(updatesResult.data)
    let packages = installed.map { repository, version in
        DeveloperPackage(
            name: repository.split(separator: "/").last.map(String.init) ?? repository,
            currentVersion: version,
            latestVersion: updates[repository] ?? version,
            manager: .githubCLI,
            executablePath: path,
            registryIdentifier: repository
        )
    }
    return ManagerScanResult(
        manager: .githubCLI,
        packages: packages,
        warning: updatesResult.status == 0 ? nil : commandWarning(.githubCLI, command: "extension update check", result: updatesResult)
    )
}

struct DockerImageRow: Equatable, Sendable {
    let reference: DockerImageReference
    let digest: String
}

/// Reads `docker image ls --format '{{json .}}'` lines.
func parseDockerImageList(_ data: Data) -> [DockerImageRow] {
    struct Line: Decodable {
        let repository: String
        let tag: String
        let digest: String?
        enum CodingKeys: String, CodingKey { case repository = "Repository", tag = "Tag", digest = "Digest" }
    }
    var seen = Set<String>()
    return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { line in
        guard let row = try? JSONDecoder().decode(Line.self, from: Data(line.utf8)),
              let digest = row.digest, digest.hasPrefix("sha256:"),
              let reference = DockerImageReference.parse(repository: row.repository, tag: row.tag),
              seen.insert(reference.pullReference).inserted
        else { return nil }
        return DockerImageRow(reference: reference, digest: digest)
    }
}

/// A stopped Docker daemon is normal on a Mac, so it is not a failed check.
/// Docker Desktop that isn't running is not a failure; there is nothing to
/// list. Docker 28 and later word this "failed to connect to the docker API …
/// check if … the daemon is running" instead of "Cannot connect to the Docker
/// daemon".
func dockerDaemonIsUnavailable(_ output: Data) -> Bool {
    let text = String(decoding: output, as: UTF8.self).lowercased()
    return [
        "cannot connect to the docker daemon",
        "is the docker daemon running",
        "failed to connect to the docker api",
        "if the daemon is running",
        "error during connect"
    ].contains { text.contains($0) }
}

func scanDockerImages(_ path: String, registry: DockerImageRegistry = DockerImageRegistry()) async -> ManagerScanResult {
    let listResult = await captureDeveloperCommandAsync(
        URL(fileURLWithPath: path),
        ["image", "ls", "--digests", "--no-trunc", "--format", "{{json .}}"]
    )
    guard listResult.status == 0 else {
        if dockerDaemonIsUnavailable(listResult.data) {
            return ManagerScanResult(manager: .dockerImages, packages: [], warning: nil)
        }
        return failedManagerScan(.dockerImages, command: "image inventory", result: listResult)
    }
    var rows = parseDockerImageList(listResult.data)
    var listWarning: String?
    if rows.contains(where: { $0.reference.isDockerHub && $0.reference.repository.hasPrefix("library/") }) {
        let official: Set<String>
        do { official = try await registry.officialImageNames() } catch {
            official = []
            listWarning = "Docker Images could not load the official image list, so official images were not checked."
        }
        rows = rows.filter { row in
            guard row.reference.isDockerHub, row.reference.repository.hasPrefix("library/") else { return true }
            return official.contains(String(row.reference.repository.dropFirst("library/".count)))
        }
    }
    let checked = await withTaskGroup(of: (DockerImageRow, Result<DockerRegistryState, Error>).self) { group in
        var results: [(DockerImageRow, Result<DockerRegistryState, Error>)] = []
        var iterator = rows.makeIterator()
        func enqueue() {
            guard let row = iterator.next() else { return }
            group.addTask {
                do { return (row, .success(try await registry.state(of: row.reference, localDigest: row.digest))) }
                catch { return (row, .failure(error)) }
            }
        }
        for _ in 0..<4 { enqueue() }
        for await result in group {
            results.append(result)
            enqueue()
        }
        return results
    }
    var packages: [DeveloperPackage] = []
    var failures: [String] = []
    for (row, result) in checked {
        switch result {
        case .success(.notFromRegistry):
            continue
        case let .success(.checked(latest)):
            packages.append(DeveloperPackage(
                name: row.reference.pullReference,
                currentVersion: shortImageDigest(row.digest),
                latestVersion: shortImageDigest(latest),
                manager: .dockerImages,
                executablePath: path,
                registryIdentifier: row.reference.pullReference
            ))
        case .failure:
            failures.append(row.reference.pullReference)
        }
    }
    let warning = failures.isEmpty ? listWarning
        : "Docker Images registry checks failed for \(failures.count) image\(failures.count == 1 ? "" : "s")."
    return ManagerScanResult(manager: .dockerImages, packages: packages, warning: warning)
}

func shortImageDigest(_ digest: String) -> String {
    String(digest.replacingOccurrences(of: "sha256:", with: "").prefix(12))
}

func scanGoTools(_ path: String) async -> ManagerScanResult {
    async let environmentCommand = captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["env", "GOBIN", "GOPATH"])
    async let versionCommand = captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["version"])
    async let latestRelease = latestGoReleaseVersion()
    let (environment, versionResult, latestRuntime) = await (environmentCommand, versionCommand, latestRelease)
    guard environment.status == 0 else { return failedManagerScan(.go, command: "environment discovery", result: environment) }
    let lines = String(data: environment.data, encoding: .utf8)?.split(separator: "\n").map(String.init) ?? []
    let binDirectory = lines.first?.isEmpty == false ? lines[0] : "\(lines.dropFirst().first ?? homePath("go"))/bin"
    let urls = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: binDirectory), includingPropertiesForKeys: nil)) ?? []
    let installed = await withTaskGroup(of: GoInstalledTool?.self) { group in
        for url in urls where FileManager.default.isExecutableFile(atPath: url.path) {
            group.addTask {
                let result = await captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["version", "-m", url.path])
                return DeveloperInventoryParsers.parseGoBuildInfo(result.data)
            }
        }
        var output: [GoInstalledTool] = []
        for await value in group { if let value { output.append(value) } }
        return output
    }
    let values = await withTaskGroup(of: (DeveloperPackage, Bool).self) { group in
        for tool in installed {
            group.addTask {
                let versions = await goModuleVersions(module: tool.module)
                return (DeveloperPackage(
                    name: tool.command,
                    currentVersion: tool.version,
                    latestVersion: latestStableVersion(in: versions) ?? tool.version,
                    manager: .go,
                    executablePath: path,
                    registryIdentifier: tool.module
                ), versions.isEmpty)
            }
        }
        var output: [(DeveloperPackage, Bool)] = []
        for await value in group { output.append(value) }
        return output
    }
    var packages = values.map(\.0)
    if let currentRuntime = DeveloperInventoryParsers.parseGoRuntimeVersion(versionResult.data) {
        packages.append(DeveloperPackage(
            name: "Go", currentVersion: currentRuntime, latestVersion: latestRuntime ?? currentRuntime,
            manager: .go, executablePath: path, registryIdentifier: "go-runtime",
            installationContext: "Go runtime", canUpdateAutomatically: false
        ))
    }
    let failures = values.count { $0.1 }
    return ManagerScanResult(manager: .go, packages: packages, warning: failures == 0 ? nil : "Go: module checks failed for \(failures) tool\(failures == 1 ? "" : "s").")
}

func scanComposer(_ path: String) async -> ManagerScanResult {
    let result = await captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["global", "outdated", "--all", "--direct", "--format=json", "--no-interaction"])
    guard result.status == 0 || !result.data.isEmpty,
          let root = try? JSONDecoder().decode(ComposerOutdated.self, from: result.data) else {
        return failedManagerScan(.composer, command: "global package check", result: result)
    }
    let packages = root.installed.map {
        DeveloperPackage(
            name: $0.name, currentVersion: normalizedComposerVersion($0.version),
            latestVersion: normalizedComposerVersion($0.latest ?? $0.version),
            manager: .composer, executablePath: path, registryIdentifier: $0.name
        )
    }
    return ManagerScanResult(manager: .composer, packages: packages, warning: nil)
}

func scanDotnetTools(_ path: String) async -> ManagerScanResult {
    let result = await captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["tool", "list", "--global"])
    guard result.status == 0 else { return failedManagerScan(.dotnet, command: "global tool inventory", result: result) }
    let installed = DeveloperInventoryParsers.parseDotnetToolList(result.data)
    let values = await withTaskGroup(of: (DeveloperPackage, Bool).self) { group in
        for (identifier, version) in installed {
            group.addTask {
                let versions = await nugetPackageVersions(identifier)
                return (DeveloperPackage(
                    name: identifier, currentVersion: version, latestVersion: latestStableVersion(in: versions) ?? version,
                    manager: .dotnet, executablePath: path, registryIdentifier: identifier
                ), versions.isEmpty)
            }
        }
        var output: [(DeveloperPackage, Bool)] = []
        for await value in group { output.append(value) }
        return output
    }
    let failures = values.count { $0.1 }
    return ManagerScanResult(manager: .dotnet, packages: values.map(\.0), warning: failures == 0 ? nil : ".NET: NuGet checks failed for \(failures) tool\(failures == 1 ? "" : "s").")
}

func scanMacPorts(_ path: String) async -> ManagerScanResult {
    async let installedCommand = captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["installed", "requested"])
    async let outdatedCommand = captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["outdated"])
    let (installedResult, outdatedResult) = await (installedCommand, outdatedCommand)
    guard installedResult.status == 0 else { return failedManagerScan(.macPorts, command: "inventory", result: installedResult) }
    guard outdatedResult.status == 0 else { return failedManagerScan(.macPorts, command: "outdated check", result: outdatedResult) }
    let installed = DeveloperInventoryParsers.parseMacPortsInstalled(installedResult.data)
    let outdated = Dictionary(DeveloperInventoryParsers.parseMacPortsOutdated(outdatedResult.data).map { ($0.name, $0.latest) }, uniquingKeysWith: { first, _ in first })
    let packages = installed.map {
        DeveloperPackage(
            name: $0.name, currentVersion: $0.version, latestVersion: outdated[$0.name] ?? $0.version,
            manager: .macPorts, executablePath: path, registryIdentifier: $0.name,
            canUpdateAutomatically: false
        )
    }
    let prefix = URL(fileURLWithPath: path).deletingLastPathComponent().deletingLastPathComponent()
    return ManagerScanResult(
        manager: .macPorts, packages: packages,
        warning: macPortsIndexWarning(lastRefreshed: macPortsIndexDate(sources: prefix.appendingPathComponent("var/macports/sources")))
    )
}

/// `port outdated` compares against the local ports tree, which only
/// `sudo port selfupdate` (or `sync`) refreshes. Upkeep can't run that without
/// an administrator password, so it says when the tree is old.
let macPortsIndexMaximumAge: TimeInterval = 14 * 24 * 60 * 60

func macPortsIndexWarning(lastRefreshed: Date?, now: Date = Date()) -> String? {
    guard let lastRefreshed else { return nil }
    let age = now.timeIntervalSince(lastRefreshed)
    guard age > macPortsIndexMaximumAge else { return nil }
    let days = Int(age / (24 * 60 * 60))
    return "MacPorts' list of ports was last refreshed \(days) days ago, so newer versions may be missing. "
        + "Run `sudo port selfupdate` in Terminal to refresh it."
}

/// The newest `PortIndex` under MacPorts' sources folder. Each source tree
/// keeps one at its root (`rsync.macports.org/macports/release/tarballs/ports`),
/// so the search stops at the first `PortIndex` on each branch rather than
/// walking thousands of port folders.
func macPortsIndexDate(sources: URL, maximumDepth: Int = 6) -> Date? {
    let fileManager = FileManager.default
    var newest: Date?
    var queue: [(URL, Int)] = [(sources, 0)]
    while !queue.isEmpty {
        let (directory, depth) = queue.removeFirst()
        let index = directory.appendingPathComponent("PortIndex")
        if let date = (try? fileManager.attributesOfItem(atPath: index.path))?[.modificationDate] as? Date {
            newest = max(newest ?? date, date)
            continue
        }
        guard depth < maximumDepth,
              let children = try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
        else { continue }
        for child in children where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            queue.append((child, depth + 1))
        }
    }
    return newest
}

func scanNixProfile(_ path: String) async -> ManagerScanResult {
    async let listCommand = captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["profile", "list", "--json"])
    async let updateCommand = captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["profile", "upgrade", "--all", "--dry-run"])
    let (listResult, updateResult) = await (listCommand, updateCommand)
    guard listResult.status == 0 else { return failedManagerScan(.nix, command: "profile inventory", result: listResult) }
    guard updateResult.status == 0 else { return failedManagerScan(.nix, command: "profile update check", result: updateResult) }
    let updates = DeveloperInventoryParsers.parseNixDryRun(updateResult.data)
    let latestByName = Dictionary(updates.map { ($0.name, $0.latest) }, uniquingKeysWith: { first, _ in first })
    let packages = DeveloperInventoryParsers.parseNixProfileJSON(listResult.data).map {
        DeveloperPackage(
            name: $0.name, currentVersion: $0.version, latestVersion: latestByName[$0.name] ?? $0.version,
            manager: .nix, executablePath: path, registryIdentifier: $0.selector
        )
    }
    return ManagerScanResult(manager: .nix, packages: packages, warning: nil)
}

func scanMise(_ path: String) async -> ManagerScanResult {
    async let installedCommand = captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["ls", "--json", "--installed"])
    async let outdatedCommand = captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["outdated", "--json", "--inactive"])
    let (installedResult, outdatedResult) = await (installedCommand, outdatedCommand)
    guard installedResult.status == 0 else { return failedManagerScan(.mise, command: "tool inventory", result: installedResult) }
    guard outdatedResult.status == 0 else { return failedManagerScan(.mise, command: "tool update check", result: outdatedResult) }
    let outdated = Dictionary(DeveloperInventoryParsers.parseGenericOutdatedJSON(outdatedResult.data).map { ($0.name, $0.latest) }, uniquingKeysWith: { first, _ in first })
    let packages = DeveloperInventoryParsers.parseMiseInstalledJSON(installedResult.data).map {
        DeveloperPackage(
            name: $0.name, currentVersion: $0.version, latestVersion: outdated[$0.name] ?? $0.version,
            manager: .mise, executablePath: path, registryIdentifier: $0.name,
            installationContext: "mise \($0.version)"
        )
    }
    return ManagerScanResult(manager: .mise, packages: packages, warning: nil)
}

func scanASDF(_ path: String) async -> ManagerScanResult {
    let configURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tool-versions")
    let configData = (try? Data(contentsOf: configURL)) ?? Data()
    let installed = DeveloperInventoryParsers.parseASDFCurrent(configData)
    let values = await withTaskGroup(of: DeveloperPackage.self) { group in
        for (name, version) in installed {
            group.addTask {
                let latestResult = await captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["latest", name])
                let latest = String(data: latestResult.data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return DeveloperPackage(
                    name: name, currentVersion: version,
                    latestVersion: latest?.isEmpty == false ? latest! : version,
                    manager: .asdf, executablePath: path, registryIdentifier: name
                )
            }
        }
        var output: [DeveloperPackage] = []
        for await value in group { output.append(value) }
        return output
    }
    return ManagerScanResult(manager: .asdf, packages: values, warning: nil)
}

func scanVolta(_ path: String) async -> ManagerScanResult {
    let result = await captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["list", "--format", "plain", "--all"])
    guard result.status == 0 else { return failedManagerScan(.volta, command: "tool inventory", result: result) }
    let installed = DeveloperInventoryParsers.parseVoltaList(result.data)
    let nodeReleases = installed.keys.contains("node") ? await nodeReleaseVersions() : []
    let packages = await withTaskGroup(of: DeveloperPackage.self) { group in
        for (name, version) in installed {
            group.addTask {
                let latest: String
                if name == "node" {
                    latest = latestNodeRelease(in: nodeReleases, installed: version, preferLatestMajor: true) ?? version
                }
                else { latest = await npmRegistryLatestVersion(package: name) ?? version }
                return DeveloperPackage(
                    name: name, currentVersion: version, latestVersion: latest,
                    manager: .volta, executablePath: path, registryIdentifier: name
                )
            }
        }
        var output: [DeveloperPackage] = []
        for await value in group { output.append(value) }
        return output
    }
    return ManagerScanResult(manager: .volta, packages: packages, warning: nil)
}

func scanFNM(_ path: String) async -> ManagerScanResult {
    let result = await captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["list"])
    guard result.status == 0 else { return failedManagerScan(.fnm, command: "runtime inventory", result: result) }
    let installed = DeveloperInventoryParsers.parseFNMList(result.data)
    let releases = await nodeReleaseVersions()
    let packages = installed.map { version, isDefault in
        let latest = latestNodeRelease(in: releases, installed: version, preferLatestMajor: isDefault)
        return DeveloperPackage(
            name: "Node.js", currentVersion: version, latestVersion: latest ?? version,
            manager: .fnm, executablePath: path, registryIdentifier: "node",
            installationContext: "fnm \(version)"
        )
    }
    return ManagerScanResult(manager: .fnm, packages: packages, warning: releases.isEmpty ? "fnm: Node.js release index could not be read." : nil)
}

private func failedManagerScan(
    _ manager: DeveloperPackageManager,
    command: String,
    result: (data: Data, status: Int32)
) -> ManagerScanResult {
    ManagerScanResult(manager: manager, packages: [], warning: commandWarning(manager, command: command, result: result))
}

private func commandWarning(
    _ manager: DeveloperPackageManager,
    command: String,
    result: (data: Data, status: Int32)
) -> String {
    let output = String(data: result.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let detail = output?.isEmpty == false ? output! : "command exited with status \(result.status)"
    return "\(manager.rawValue) \(command) failed: \(detail)"
}

private func homePath(_ relativePath: String) -> String {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(relativePath).path
}

private func appendDetected(
    _ manager: DeveloperPackageManager,
    named name: String,
    extra: [String],
    enabledManagers: Set<DeveloperPackageManager>,
    to tools: inout [(DeveloperPackageManager, String)]
) {
    guard enabledManagers.contains(manager), let path = executable(named: name, extra: extra) else { return }
    tools.append((manager, path))
}

private func appendAllDetected(
    _ manager: DeveloperPackageManager,
    named name: String,
    extra: [String],
    enabledManagers: Set<DeveloperPackageManager>,
    to tools: inout [(DeveloperPackageManager, String)]
) {
    guard enabledManagers.contains(manager) else { return }
    for path in executableCandidates(named: name, extra: extra) { tools.append((manager, path)) }
}

private func executableCandidates(named name: String, extra: [String]) -> [String] {
    var seen = Set<String>()
    return (extra + ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"])
        .filter { FileManager.default.isExecutableFile(atPath: $0) && seen.insert($0).inserted }
}

/// VS Code and its forks, with each app's bundled CLI. Names and CLI paths
/// were read from the shipped apps. Windsurf was renamed Devin Desktop and
/// keeps its bundle ID, so both app names are listed.
private let editorApplications: [(app: String, cli: String, name: String)] = [
    ("Visual Studio Code.app", "code", "VS Code"),
    ("Visual Studio Code - Insiders.app", "code", "VS Code Insiders"),
    ("Cursor.app", "cursor", "Cursor"),
    ("VSCodium.app", "codium", "VSCodium"),
    ("VSCodium - Insiders.app", "codium-insiders", "VSCodium Insiders"),
    ("Windsurf.app", "windsurf", "Windsurf"),
    ("Devin.app", "devin-desktop", "Devin"),
    ("Devin - Next.app", "devin-desktop-next", "Devin Next")
]

private func editorCLIs() -> [String] {
    let candidates = editorApplications.flatMap { editor in
        let relative = "\(editor.app)/Contents/Resources/app/bin/\(editor.cli)"
        return ["/Applications/\(relative)", homePath("Applications/\(relative)")]
    }
    var seen = Set<String>()
    return candidates.filter { FileManager.default.isExecutableFile(atPath: $0) && seen.insert($0).inserted }
}

func editorName(for path: String) -> String {
    editorApplications.first { path.contains("/\($0.app)/") }?.name ?? "VS Code"
}

/// The extension gallery an editor installs from, read from its product.json.
/// VS Code forks use different galleries (Open VSX, Cursor's, Windsurf's) with
/// different versions, so checking the wrong one reports updates the editor
/// cannot install.
struct EditorExtensionGallery: Equatable, Sendable {
    let serviceURL: URL
    let itemURL: URL?

    static let visualStudioMarketplace = EditorExtensionGallery(
        serviceURL: URL(string: "https://marketplace.visualstudio.com/_apis/public/gallery")!,
        itemURL: URL(string: "https://marketplace.visualstudio.com/items")
    )

    /// `…/app/bin/<cli>` → `…/app/product.json`.
    static func forEditorCLI(_ path: String) -> EditorExtensionGallery? {
        let product = URL(fileURLWithPath: path).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("product.json")
        if let data = try? Data(contentsOf: product), let gallery = parse(productJSON: data) { return gallery }
        // Microsoft's VS Code builds always use its marketplace.
        return path.contains("/Visual Studio Code") ? visualStudioMarketplace : nil
    }

    static func parse(productJSON data: Data) -> EditorExtensionGallery? {
        struct Product: Decodable {
            struct Gallery: Decodable { let serviceUrl: String?; let itemUrl: String? }
            let extensionsGallery: Gallery?
        }
        guard let gallery = (try? JSONDecoder().decode(Product.self, from: data))?.extensionsGallery,
              let service = gallery.serviceUrl.flatMap(URL.init(string:)),
              service.scheme?.lowercased() == "https", service.host?.isEmpty == false
        else { return nil }
        let item = gallery.itemUrl.flatMap(URL.init(string:)).flatMap { $0.scheme?.lowercased() == "https" ? $0 : nil }
        return EditorExtensionGallery(serviceURL: service, itemURL: item)
    }

    var queryURL: URL { serviceURL.appendingPathComponent("extensionquery") }

    func itemPage(for extensionID: String) -> URL? {
        guard let itemURL, var components = URLComponents(url: itemURL, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "itemName", value: extensionID)]
        return components.url
    }
}

private func nvmInstallationContext(for path: String) -> String? {
    if let marker = path.range(of: "/.nvm/versions/node/") {
        let suffix = path[marker.upperBound...]
        guard let version = suffix.split(separator: "/").first else { return nil }
        return "NVM Node \(version.trimmingCharacters(in: CharacterSet(charactersIn: "vV")))"
    }
    if let marker = path.range(of: "/fnm/node-versions/") {
        let suffix = path[marker.upperBound...]
        guard let version = suffix.split(separator: "/").first else { return nil }
        return "fnm Node \(version.trimmingCharacters(in: CharacterSet(charactersIn: "vV")))"
    }
    if path.contains("/.volta/bin/") { return "Volta default" }
    if path.contains("/.asdf/shims/") { return "asdf active" }
    if path.contains("/mise/shims/") { return "mise active" }
    return nil
}

private func joinedWarnings(_ values: String?...) -> String? {
    let messages = values.compactMap { $0 }.filter { !$0.isEmpty }
    return messages.isEmpty ? nil : messages.joined(separator: " ")
}

private func packagesFromNPMRegistry(
    installed: [String: String],
    manager: DeveloperPackageManager,
    executablePath: String,
    context: String?
) async -> ManagerScanResult {
    let values = await withTaskGroup(of: (DeveloperPackage, Bool).self) { group in
        for (name, versionRange) in installed {
            group.addTask {
                let version = versionRange.trimmingCharacters(in: CharacterSet(charactersIn: "^~>=< "))
                let latest = await npmRegistryLatestVersion(package: name)
                return (DeveloperPackage(
                    name: name, currentVersion: version, latestVersion: latest ?? version,
                    manager: manager, executablePath: executablePath,
                    registryIdentifier: name, installationContext: context
                ), latest == nil)
            }
        }
        var output: [(DeveloperPackage, Bool)] = []
        for await value in group { output.append(value) }
        return output
    }
    let failures = values.count { $0.1 }
    return ManagerScanResult(
        manager: manager,
        packages: values.map(\.0),
        warning: failures == 0 ? nil : "\(manager.rawValue): registry checks failed for \(failures) global package\(failures == 1 ? "" : "s")."
    )
}

private func normalizedComposerVersion(_ value: String) -> String {
    value.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
}

private func latestStableVersion(in versions: [String]) -> String? {
    versions.first { !VersionComparator.isPrerelease($0) }
}

/// nodejs.org lists alpha and RC builds first while a new major is in
/// testing. A stable install only moves to stable releases; an installed
/// prerelease is already on that track. `preferLatestMajor` is for the default
/// Node, which follows the newest major; other installs stay on their major.
func latestNodeRelease(in releases: [String], installed: String, preferLatestMajor: Bool) -> String? {
    let allowsPrereleases = VersionComparator.isPrerelease(installed)
    let installedMajor = installed.split(separator: ".").first.map(String.init)
    return releases.first { release in
        guard allowsPrereleases || !VersionComparator.isPrerelease(release) else { return false }
        return preferLatestMajor || release.split(separator: ".").first.map(String.init) == installedMajor
    }
}

/// The Ruby the user chose comes before macOS's own. `/usr/bin/gem` belongs to
/// the system Ruby, whose gems macOS ships and updates; it is used only when
/// no other Ruby is installed. Homebrew's Ruby is keg-only, so its `opt` path
/// is checked as well as the linked one.
///
/// rbenv's shim runs whichever Ruby `rbenv global` names. Upkeep runs outside
/// any project, so that is the version in `<rbenv root>/version`; with no file
/// or `system` the shim runs `/usr/bin/gem` while looking like a user Ruby, so
/// it is skipped.
func rubyGemExecutableCandidates(
    home: String = NSHomeDirectory(),
    environment: [String: String] = ProcessInfo.processInfo.environment
) -> [String] {
    let rbenvRoot = environment["RBENV_ROOT"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.rbenv"
    let rbenvShim = rbenvGlobalVersion(root: rbenvRoot).map { _ in rbenvRoot + "/shims/gem" }
    return (rbenvShim.map { [$0] } ?? []) + [
        "/opt/homebrew/opt/ruby/bin/gem",
        "/usr/local/opt/ruby/bin/gem",
        "/opt/homebrew/bin/gem",
        "/usr/local/bin/gem",
        "/usr/bin/gem"
    ]
}

/// The Ruby `rbenv global` selects, or nil when it is unset or `system`.
func rbenvGlobalVersion(root: String) -> String? {
    guard let contents = try? String(contentsOfFile: root + "/version", encoding: .utf8) else { return nil }
    let version = contents.split(whereSeparator: \.isNewline).first
        .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    return version.isEmpty || version == "system" ? nil : version
}

private func executable(named name: String, extra: [String]) -> String? {
    (extra + ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"])
        .first { FileManager.default.isExecutableFile(atPath: $0) }
}

func nvmExecutables(named name: String,
                    root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".nvm/versions/node", isDirectory: true)) -> [String] {
    let versions = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                                options: .skipsHiddenFiles)) ?? []
    return versions.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
        .map { $0.appendingPathComponent("bin/\(name)").path }
        .filter { FileManager.default.isExecutableFile(atPath: $0) }
}

private func nvmDefaultExecutable(named name: String) -> String? {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let candidates = nvmExecutables(named: name)
    guard !candidates.isEmpty else { return nil }
    let aliasURL = home.appendingPathComponent(".nvm/alias/default")
    guard let alias = try? String(contentsOf: aliasURL, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !alias.isEmpty else { return candidates.first }
    return preferredNVMExecutable(candidates: candidates, alias: alias) ?? candidates.first
}

private func nodeToolExecutables(named name: String, defaultNode: String?) -> [String] {
    var candidates: [String] = []
    if let defaultNode {
        candidates.append(URL(fileURLWithPath: defaultNode).deletingLastPathComponent().appendingPathComponent(name).path)
    }
    candidates.append(contentsOf: nvmExecutables(named: name))
    candidates.append(homePath(".volta/bin/\(name)"))
    candidates.append(homePath(".asdf/shims/\(name)"))
    candidates.append(homePath(".local/share/mise/shims/\(name)"))
    candidates.append(contentsOf: fnmExecutables(named: name))
    var seen = Set<String>()
    return candidates.filter { seen.insert($0).inserted }
}

private func fnmExecutables(named name: String) -> [String] {
    let roots = [
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/fnm/node-versions"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/fnm/node-versions")
    ]
    return roots.flatMap { root -> [String] in
        let versions = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return versions.map { $0.appendingPathComponent("installation/bin/\(name)").path }
    }.filter { FileManager.default.isExecutableFile(atPath: $0) }
}

func preferredNVMExecutable(candidates: [String], alias: String) -> String? {
    let normalizedAlias = alias.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    guard normalizedAlias.first?.isNumber == true else { return candidates.first }
    return candidates.first { path in
        let version = URL(fileURLWithPath: path)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .lastPathComponent
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        return version == normalizedAlias || version.hasPrefix(normalizedAlias + ".")
    }
}

func nvmDirectory(for executablePath: String) -> String? {
    guard let marker = executablePath.range(of: "/.nvm/versions/node/") else { return nil }
    return String(executablePath[..<marker.lowerBound]) + "/.nvm"
}

func nvmNodeVersion(for executablePath: String) -> String? {
    guard nvmDirectory(for: executablePath) != nil else { return nil }
    let version = URL(fileURLWithPath: executablePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .lastPathComponent
        .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    return version.first?.isNumber == true ? version : nil
}

func nvmNodeUpdateArguments(
    nvmDirectory: String,
    currentVersion: String,
    targetVersion: String,
    isDefault: Bool
) -> [String] {
    let command = #"""
    source "$1/nvm.sh" &&
    target="$(nvm version "$3" 2>/dev/null || true)" &&
    if [ "$target" = "N/A" ]; then
        nvm install "$3" --reinstall-packages-from="$2"
    else
        nvm use "$target" && nvm reinstall-packages "$2"
    fi &&
    if [ "$4" = "default" ]; then
        nvm alias default "$3"
    fi &&
    nvm uninstall "$2"
    """#
    return [
        "-c", command, "upkeep-node", nvmDirectory,
        currentVersion, targetVersion, isDefault ? "default" : "secondary"
    ]
}

func captureDeveloperCommand(
    _ executable: URL,
    _ arguments: [String],
    baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
) -> (data: Data, status: Int32) {
    let environment = developerCommandEnvironment(for: executable, base: baseEnvironment)
    do {
        let result = try CommandRunner.capture(executable, arguments, environment: environment,
            directory: developerCommandWorkingDirectory(base: environment), timeout: CommandRunner.deadline(for: arguments))
        return (result.output, result.status)
    } catch { return (Data(error.localizedDescription.utf8), -1) }
}

func developerCommandWorkingDirectory(
    base: [String: String],
    fileManager: FileManager = .default
) -> URL {
    let candidates: [String?] = [base["HOME"], fileManager.homeDirectoryForCurrentUser.path]
    for case let path? in candidates {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              URL(fileURLWithPath: path).standardizedFileURL.path != "/",
              fileManager.isWritableFile(atPath: path) else { continue }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
    return URL(fileURLWithPath: developerCommandTemporaryDirectory(base: base), isDirectory: true)
}

func captureDeveloperCommandAsync(
    _ executable: URL,
    _ arguments: [String],
    baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
    qos: DispatchQoS.QoSClass = .utility,
    purpose: CommandRunner.Purpose = .automatic
) async -> (data: Data, status: Int32) {
    let environment = developerCommandEnvironment(for: executable, base: baseEnvironment)
    do {
        let result = try await CommandRunner.run(executable, arguments, environment: environment,
            directory: developerCommandWorkingDirectory(base: environment), timeout: CommandRunner.deadline(for: arguments, purpose: purpose))
        return (result.output, result.status)
    } catch { return (Data(error.localizedDescription.utf8), -1) }
}

func developerNodeRuntimePath(for executable: URL,
                              base: [String: String] = ProcessInfo.processInfo.environment) -> String? {
    let environment = developerCommandEnvironment(for: executable, base: base)
    for directory in (environment["PATH"] ?? "").split(separator: ":") {
        let node = URL(fileURLWithPath: String(directory)).appendingPathComponent("node")
        if FileManager.default.isExecutableFile(atPath: node.path) {
            return node.resolvingSymlinksInPath().standardizedFileURL.path
        }
    }
    return nil
}

func developerCommandEnvironment(
    for executable: URL,
    base: [String: String] = ProcessInfo.processInfo.environment
) -> [String: String] {
    var environment = CommandRunner.commandEnvironment(base)
    let executableDirectory = executable.deletingLastPathComponent().standardizedFileURL.path
    let homeDirectory = environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
    let pnpmHome = environment["PNPM_HOME"] ?? "\(homeDirectory)/Library/pnpm"
    let fallbackDirectories = [
        executableDirectory,
        "\(pnpmHome)/bin",
        pnpmHome,
        "\(homeDirectory)/.local/share/pnpm",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
    ]
    let existingDirectories = (environment["PATH"] ?? "")
        .split(separator: ":")
        .map(String.init)
    var seen = Set<String>()
    environment["PATH"] = (fallbackDirectories + existingDirectories)
        .filter { !$0.isEmpty && seen.insert($0).inserted }
        .joined(separator: ":")

    if executableDirectory.contains("/.nvm/versions/node/") {
        environment["NVM_BIN"] = executableDirectory
    }
    let temporaryDirectory = developerCommandTemporaryDirectory(base: environment)
    environment["TMPDIR"] = temporaryDirectory
    environment["TMP"] = temporaryDirectory
    environment["TEMP"] = temporaryDirectory
    environment["PNPM_HOME"] = pnpmHome
    return environment
}

func developerCommandTemporaryDirectory(
    base: [String: String],
    fileManager: FileManager = .default
) -> String {
    for key in ["TMPDIR", "TMP", "TEMP"] {
        guard let path = base[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty,
              URL(fileURLWithPath: path).standardizedFileURL.path != "/",
              fileManager.isWritableFile(atPath: path)
        else { continue }
        return path
    }

    if let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
        let directory = cachesDirectory
            .appendingPathComponent("Upkeep", isDirectory: true)
            .appendingPathComponent("Temporary", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if fileManager.isWritableFile(atPath: directory.path) { return directory.path }
        } catch {
            // Fall through to the system-wide temporary directory.
        }
    }

    return "/tmp"
}

private struct NPMList: Decodable { let dependencies: [String: NPMInstalled] }
private struct NPMInstalled: Decodable { let version: String }
private struct NPMOutdated: Decodable { let latest: String }
private struct PNPMRoot: Decodable {
    let path: String?
    let dependencies: [String: PNPMEntry]?
    let devDependencies: [String: PNPMEntry]?
}
private struct PNPMEntry: Decodable { let version: String }
private struct BunGlobalManifest: Decodable {
    let dependencies: [String: String]?
    let devDependencies: [String: String]?
}
private struct PipxList: Decodable {
    let venvs: [String: Environment]
    struct Environment: Decodable { let metadata: Metadata }
    struct Metadata: Decodable {
        let mainPackage: MainPackage?
        enum CodingKeys: String, CodingKey { case mainPackage = "main_package" }
    }
    struct MainPackage: Decodable {
        let package: String?
        let packageVersion: String?
        enum CodingKeys: String, CodingKey { case package; case packageVersion = "package_version" }
    }
}
struct GoInstalledTool: Sendable {
    let command: String
    let module: String
    let version: String
}
private struct ComposerOutdated: Decodable {
    let installed: [Package]
    struct Package: Decodable { let name: String; let version: String; let latest: String? }
}

/// pnpm keeps global packages in one folder whichever Node.js runs pnpm, so
/// the same packages are found through every nvm Node.js version's pnpm.
func parsePNPMGlobalDirectory(_ data: Data) -> String? {
    let decoder = JSONDecoder()
    let roots = (try? decoder.decode([PNPMRoot].self, from: data)) ?? (try? decoder.decode(PNPMRoot.self, from: data)).map { [$0] }
    return roots?.compactMap(\.path).first
}

/// "pnpm global · ~/Library/pnpm" for ~/Library/pnpm/global/v11. Packages
/// found through different pnpm executables share this context, so they are
/// listed once.
func pnpmGlobalContext(_ directory: String, home: String = NSHomeDirectory()) -> String {
    var folder = directory
    if let range = folder.range(of: "/global/") { folder = String(folder[..<range.lowerBound]) }
    if folder.hasPrefix(home) { folder = "~" + folder.dropFirst(home.count) }
    return "pnpm global · " + folder
}

func parsePNPMInstalledPackages(_ data: Data) -> [String: String]? {
    let decoder = JSONDecoder()
    let roots: [PNPMRoot]
    if let values = try? decoder.decode([PNPMRoot].self, from: data) {
        roots = values
    } else if let value = try? decoder.decode(PNPMRoot.self, from: data) {
        roots = [value]
    } else {
        return nil
    }
    return roots.reduce(into: [String: String]()) { values, root in
        for (name, package) in root.dependencies ?? [:] where values[name] == nil {
            values[name] = package.version
        }
        for (name, package) in root.devDependencies ?? [:] where values[name] == nil {
            values[name] = package.version
        }
    }
}
private struct PipInstalled: Decodable { let name: String; let version: String }
private struct PipOutdated: Decodable {
    let name: String; let latestVersion: String
    enum CodingKeys: String, CodingKey { case name; case latestVersion = "latest_version" }
}
private struct PyPIResponse: Decodable {
    let info: Info?
    let releases: [String: [ReleaseFile]]
    struct Info: Decodable { let version: String? }
    struct ReleaseFile: Decodable {}
}
private struct RubyGemVersion: Decodable { let number: String }
private struct NodeRelease: Decodable { let version: String }
private struct GitHubReleaseVersion: Decodable {
    let tagName: String
    enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
}
private struct NPMRegistryPackage: Decodable { let versions: [String: RegistryVersion] }
private struct RegistryVersion: Decodable {}
private struct NPMRegistryLatest: Decodable { let version: String }
private struct CrateResponse: Decodable {
    let crate: Crate
    struct Crate: Decodable {
        let maxVersion: String
        enum CodingKeys: String, CodingKey { case maxVersion = "max_version" }
    }
}
private struct CrateVersionsResponse: Decodable {
    let versions: [Version]
    struct Version: Decodable { let num: String; let yanked: Bool }
}
private struct VSMarketplaceResponse: Decodable {
    let results: [Result]
    struct Result: Decodable { let extensions: [Extension] }
    struct Extension: Decodable {
        let versions: [Version]
        let extensionName: String?
        let publisher: Publisher?
    }
    struct Publisher: Decodable { let publisherName: String? }
    struct Version: Decodable { let version: String; let targetPlatform: String? }
}
private struct GoRelease: Decodable { let version: String; let stable: Bool }
private struct PackagistResponse: Decodable {
    let packages: [String: [PackageVersion]]
    struct PackageVersion: Decodable { let version: String; let versionNormalized: String?
        enum CodingKeys: String, CodingKey { case version; case versionNormalized = "version_normalized" }
    }
}
private struct NugetVersions: Decodable { let versions: [String] }

actor RegistryRequestCache {
    static let shared = RegistryRequestCache()
    static let freshnessInterval: TimeInterval = 10 * 60
    private struct Entry { let data: Data; let date: Date }
    private var entries: [String: Entry] = [:]
    private var totalBytes = 0
    private var inFlight: [String: Task<Data?, Never>] = [:]
    private let maximumEntries: Int
    private let maximumBytes: Int

    init(maximumEntries: Int = 512, maximumBytes: Int = 32 * 1_024 * 1_024) {
        self.maximumEntries = max(1, maximumEntries)
        self.maximumBytes = max(1, maximumBytes)
    }

    var entryCount: Int { entries.count }

    func data(for request: URLRequest, key: String) async -> Data? {
        if let entry = entries[key], Date().timeIntervalSince(entry.date) < Self.freshnessInterval {
            return entry.data
        }
        if let task = inFlight[key] { return await task.value }
        let task = Task<Data?, Never> {
            guard let (data, response) = try? await PublisherHTTPClient.data(for: request),
                  200..<300 ~= response.statusCode else { return nil }
            return data
        }
        inFlight[key] = task
        let value = await task.value
        inFlight[key] = nil
        if let value { store(value, for: key) }
        return value
    }

    func cachedData(for key: String, now: Date = Date()) -> Data? {
        guard let entry = entries[key], now.timeIntervalSince(entry.date) < Self.freshnessInterval else { return nil }
        return entry.data
    }

    /// Inserts a response, then evicts expired entries and, if still over the
    /// entry or byte cap, the oldest entries.
    func store(_ data: Data, for key: String, now: Date = Date()) {
        if let previous = entries.removeValue(forKey: key) { totalBytes -= previous.data.count }
        for (existingKey, entry) in entries where now.timeIntervalSince(entry.date) >= Self.freshnessInterval {
            entries[existingKey] = nil
            totalBytes -= entry.data.count
        }
        guard data.count <= maximumBytes else { return }
        entries[key] = Entry(data: data, date: now)
        totalBytes += data.count
        guard entries.count > maximumEntries || totalBytes > maximumBytes else { return }
        for (oldKey, entry) in entries.sorted(by: { $0.value.date < $1.value.date }) where oldKey != key {
            guard entries.count > maximumEntries || totalBytes > maximumBytes else { break }
            entries[oldKey] = nil
            totalBytes -= entry.data.count
        }
    }
}

/// `npm outdated` offers npm's newest release whatever Node runs it, but each
/// npm major supports only some Node versions (npm 12 needs Node 22.22.2,
/// 24.15 or 26+). The newest npm whose `engines.node` accepts the Node beside
/// this npm is offered instead. Without that Node version or the registry's
/// data, npm's own answer is kept.
private func newestNPMSupportingNode(nextTo npmPath: String, current: String, latest: String) async -> String {
    let node = URL(fileURLWithPath: npmPath).deletingLastPathComponent().appendingPathComponent("node")
    guard FileManager.default.isExecutableFile(atPath: node.path) else { return latest }
    let result = await captureDeveloperCommandAsync(node, ["--version"])
    guard result.status == 0,
          let output = String(data: result.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !output.isEmpty,
          let url = URL(string: "https://registry.npmjs.org/npm")
    else { return latest }
    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    request.setValue("Upkeep/0.9", forHTTPHeaderField: "User-Agent")
    // The abbreviated document still carries `engines` and is a fifth the size.
    request.setValue("application/vnd.npm.install-v1+json", forHTTPHeaderField: "Accept")
    guard let data = await RegistryRequestCache.shared.data(for: request, key: "GET-abbreviated:\(url.absoluteString)"),
          let document = try? JSONDecoder().decode(NPMEnginesDocument.self, from: data)
    else { return latest }
    let engines = document.versions.mapValues { $0.engines?.node }
    return newestPackageVersion(
        engines: engines, nodeVersion: output.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
        current: current, latest: latest
    )
}

/// The newest stable version up to `latest` whose Node range accepts
/// `nodeVersion`, or `current` when none newer does.
func newestPackageVersion(engines: [String: String?], nodeVersion: String, current: String, latest: String) -> String {
    guard engines[latest] != nil else { return latest }
    let candidates = VersionComparator.sortedNewestFirst(Set(engines.keys)).filter {
        !VersionComparator.isPrerelease($0)
            && !VersionComparator.isNewer($0, than: latest)
            && VersionComparator.isNewer($0, than: current)
    }
    return candidates.first { version in
        guard let range = engines[version] ?? nil else { return true }
        return NodeEngineRange.satisfies(nodeVersion, range: range)
    } ?? current
}

/// The subset of npm's semver ranges used in `engines.node`: `||` alternatives,
/// space-separated comparators (`>=`, `>`, `<=`, `<`, `=`), caret, tilde,
/// `x` wildcards and hyphen ranges. A range it can't read is treated as
/// satisfied, matching npm, which only warns about engines.
enum NodeEngineRange {
    static func satisfies(_ version: String, range: String) -> Bool {
        guard let installed = triple(version) else { return true }
        let alternatives = range.components(separatedBy: "||")
        return alternatives.contains { alternative in
            let trimmed = alternative.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed == "*" { return true }
            guard let comparators = comparators(trimmed) else { return true }
            return comparators.allSatisfy { $0(installed) }
        }
    }

    private typealias Comparator = ([Int]) -> Bool

    private static func comparators(_ value: String) -> [Comparator]? {
        let parts = value.split(separator: " ").map(String.init)
        if parts.count == 3, parts[1] == "-", let low = triple(parts[0]), let high = triple(parts[2]) {
            return [{ compare($0, low) >= 0 }, { compare($0, high) <= 0 }]
        }
        var result: [Comparator] = []
        for part in parts {
            guard let comparator = comparator(part) else { return nil }
            result.append(contentsOf: comparator)
        }
        return result
    }

    private static func comparator(_ token: String) -> [Comparator]? {
        for op in [">=", "<=", ">", "<", "="] where token.hasPrefix(op) {
            guard let bound = triple(String(token.dropFirst(op.count))) else { return nil }
            switch op {
            case ">=": return [{ compare($0, bound) >= 0 }]
            case "<=": return [{ compare($0, bound) <= 0 }]
            case ">": return [{ compare($0, bound) > 0 }]
            case "<": return [{ compare($0, bound) < 0 }]
            default: return [{ compare($0, bound) == 0 }]
            }
        }
        if token.hasPrefix("^") {
            guard let low = triple(String(token.dropFirst())) else { return nil }
            let high = low[0] > 0 ? [low[0] + 1, 0, 0] : low[1] > 0 ? [0, low[1] + 1, 0] : [0, 0, low[2] + 1]
            return [{ compare($0, low) >= 0 }, { compare($0, high) < 0 }]
        }
        if token.hasPrefix("~") {
            guard let low = triple(String(token.dropFirst())) else { return nil }
            return [{ compare($0, low) >= 0 }, { compare($0, [low[0], low[1] + 1, 0]) < 0 }]
        }
        // `20`, `20.x` and `20.5.x` match within that major or minor.
        let fields = token.split(separator: ".").map(String.init)
        let numbers = fields.prefix { Int($0) != nil }.compactMap(Int.init)
        guard !numbers.isEmpty, fields.dropFirst(numbers.count).allSatisfy({ ["x", "X", "*"].contains($0) }) else { return nil }
        if numbers.count >= 3 { let exact = Array(numbers.prefix(3)); return [{ $0 == exact }] }
        return [{ Array($0.prefix(numbers.count)) == numbers }]
    }

    private static func triple(_ value: String) -> [Int]? {
        let core = value.trimmingCharacters(in: CharacterSet(charactersIn: "vV= "))
            .split(separator: "-").first.map(String.init) ?? ""
        var numbers: [Int] = []
        for field in core.split(separator: ".") {
            if ["x", "X", "*"].contains(String(field)) { break }
            guard let number = Int(field) else { return nil }
            numbers.append(number)
        }
        guard !numbers.isEmpty, numbers.count <= 3 else { return nil }
        return numbers + Array(repeating: 0, count: 3 - numbers.count)
    }

    private static func compare(_ lhs: [Int], _ rhs: [Int]) -> Int {
        for (left, right) in zip(lhs, rhs) where left != right { return left < right ? -1 : 1 }
        return 0
    }
}

private struct NPMEnginesDocument: Decodable {
    let versions: [String: Version]
    struct Version: Decodable {
        let engines: Engines?
        struct Engines: Decodable {
            let node: String?
            init(from decoder: Decoder) throws {
                // Old releases list engines as an array or with non-string values.
                node = try? decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(String.self, forKey: .node)
            }
            enum CodingKeys: String, CodingKey { case node }
        }
        init(from decoder: Decoder) throws {
            engines = try? decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(Engines.self, forKey: .engines)
        }
        enum CodingKeys: String, CodingKey { case engines }
    }
}

private func registryData(from url: URL) async -> Data? {
    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    request.setValue("Upkeep/0.9", forHTTPHeaderField: "User-Agent")
    return await RegistryRequestCache.shared.data(for: request, key: "GET:\(url.absoluteString)")
}

private func nodeReleaseVersions() async -> [String] {
    guard let url = URL(string: "https://nodejs.org/dist/index.json"),
          let data = await registryData(from: url),
          let releases = try? JSONDecoder().decode([NodeRelease].self, from: data)
    else { return [] }
    return VersionComparator.sortedNewestFirst(
        Set(releases.map { $0.version.trimmingCharacters(in: CharacterSet(charactersIn: "vV")) })
    )
}

private func latestPublisherReleaseVersions(repository: String) async -> [String] {
    if repository == "oven-sh/bun" {
        return await BunReleaseLookup.latest { await registryData(from: $0) }
    }
    // The release page redirect does not use GitHub's hourly API limit.
    if let tag = await githubLatestReleaseTag(repository: repository) {
        return [normalizedJavaScriptRuntimeVersion(tag)]
    }
    guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest"),
          let data = await registryData(from: url),
          let release = try? JSONDecoder().decode(GitHubReleaseVersion.self, from: data)
    else { return [] }
    return [normalizedJavaScriptRuntimeVersion(release.tagName)]
}

private func npmRegistryVersions(package: String) async -> [String] {
    guard let encoded = package.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
          let url = URL(string: "https://registry.npmjs.org/\(encoded)"),
          let data = await registryData(from: url),
          let response = try? JSONDecoder().decode(NPMRegistryPackage.self, from: data)
    else { return [] }
    return VersionComparator.sortedNewestFirst(response.versions.keys)
}

private func npmRegistryLatestVersion(package: String) async -> String? {
    guard let encoded = package.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
          let url = URL(string: "https://registry.npmjs.org/\(encoded)/latest"),
          let data = await registryData(from: url),
          let response = try? JSONDecoder().decode(NPMRegistryLatest.self, from: data)
    else { return nil }
    return response.version
}

private func latestPyPIVersion(package: String) async -> String? {
    guard let encoded = package.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
          let url = URL(string: "https://pypi.org/pypi/\(encoded)/json"),
          let data = await registryData(from: url),
          let response = try? JSONDecoder().decode(PyPIResponse.self, from: data) else { return nil }
    return response.info?.version
}

/// Looks up many extensions in one marketplace query, keyed by lowercased
/// `publisher.name`. Missing or failed entries are simply absent.
func visualStudioMarketplaceVersions(
    extensionIDs: [String],
    gallery: EditorExtensionGallery = .visualStudioMarketplace
) async -> [String: [String]] {
    let ids = Array(Set(extensionIDs.map { $0.lowercased() })).sorted()
    guard !ids.isEmpty else { return [:] }
    let url = gallery.queryURL
    let host = gallery.serviceURL.host ?? "gallery"
    var output: [String: [String]] = [:]
    for chunk in stride(from: 0, to: ids.count, by: 50).map({ Array(ids[$0..<min($0 + 50, ids.count)]) }) {
        guard let body = try? JSONSerialization.data(withJSONObject: [
            "filters": [[
                "criteria": chunk.map { ["filterType": 7, "value": $0] },
                "pageNumber": 1,
                "pageSize": chunk.count
            ]],
            "flags": 914
        ]) else { continue }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json;api-version=7.2-preview.1", forHTTPHeaderField: "Accept")
        request.setValue("Upkeep/0.9", forHTTPHeaderField: "User-Agent")
        guard let data = await RegistryRequestCache.shared.data(for: request, key: "VSCode-batch:\(host):\(chunk.joined(separator: ","))") else { continue }
        output.merge(parseVisualStudioMarketplaceBatch(data), uniquingKeysWith: { first, _ in first })
    }
    return output
}

func parseVisualStudioMarketplaceBatch(_ data: Data) -> [String: [String]] {
    guard let root = try? JSONDecoder().decode(VSMarketplaceResponse.self, from: data) else { return [:] }
    var output: [String: [String]] = [:]
    for item in root.results.flatMap(\.extensions) {
        guard let publisher = item.publisher?.publisherName, let name = item.extensionName else { continue }
        output["\(publisher).\(name)".lowercased()] = compatibleMarketplaceVersions(item.versions)
    }
    return output
}

private func compatibleMarketplaceVersions(_ versions: [VSMarketplaceResponse.Version]) -> [String] {
    #if arch(arm64)
    let platform = "darwin-arm64"
    #else
    let platform = "darwin-x64"
    #endif
    let compatible = versions.filter {
        $0.targetPlatform == nil || $0.targetPlatform == "universal" || $0.targetPlatform == platform
    }
    return VersionComparator.sortedNewestFirst(Set(compatible.map(\.version)))
}

private func visualStudioMarketplaceVersions(extensionID: String, gallery: EditorExtensionGallery) async -> [String] {
    let url = gallery.queryURL
    guard let body = try? JSONSerialization.data(withJSONObject: [
            "filters": [["criteria": [["filterType": 7, "value": extensionID]]]],
            "flags": 914
          ]) else { return [] }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = body
    request.timeoutInterval = 20
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json;api-version=7.2-preview.1", forHTTPHeaderField: "Accept")
    request.setValue("Upkeep/0.9", forHTTPHeaderField: "User-Agent")
    guard let data = await RegistryRequestCache.shared.data(for: request, key: "VSCode:\(gallery.serviceURL.host ?? ""):\(extensionID.lowercased())"),
          let root = try? JSONDecoder().decode(VSMarketplaceResponse.self, from: data) else { return [] }
    return compatibleMarketplaceVersions(root.results.flatMap(\.extensions).flatMap(\.versions))
}

private func goModuleVersions(module: String) async -> [String] {
    let escaped = goProxyEscaped(module)
    guard let encoded = escaped.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
          let url = URL(string: "https://proxy.golang.org/\(encoded)/@v/list"),
          let data = await registryData(from: url),
          let output = String(data: data, encoding: .utf8) else { return [] }
    return VersionComparator.sortedNewestFirst(Set(output.split(separator: "\n").map {
        String($0).trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }))
}

private func latestGoReleaseVersion() async -> String? {
    guard let url = URL(string: "https://go.dev/dl/?mode=json"),
          let data = await registryData(from: url),
          let releases = try? JSONDecoder().decode([GoRelease].self, from: data) else { return nil }
    return releases.first(where: \.stable)?.version.replacingOccurrences(of: "go", with: "")
}

private func goProxyEscaped(_ module: String) -> String {
    module.reduce(into: "") { output, character in
        if character.isUppercase { output.append("!"); output.append(contentsOf: character.lowercased()) }
        else { output.append(character) }
    }
}

private func composerPackageVersions(_ package: String) async -> [String] {
    guard let encoded = package.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
          let url = URL(string: "https://repo.packagist.org/p2/\(encoded).json"),
          let data = await registryData(from: url),
          let response = try? JSONDecoder().decode(PackagistResponse.self, from: data) else { return [] }
    return VersionComparator.sortedNewestFirst(
        Set((response.packages[package] ?? []).map { normalizedComposerVersion($0.version) })
    )
}

private func nugetPackageVersions(_ package: String) async -> [String] {
    let identifier = package.lowercased()
    guard let encoded = identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
          let url = URL(string: "https://api.nuget.org/v3-flatcontainer/\(encoded)/index.json"),
          let data = await registryData(from: url),
          let response = try? JSONDecoder().decode(NugetVersions.self, from: data) else { return [] }
    return VersionComparator.sortedNewestFirst(Set(response.versions))
}
