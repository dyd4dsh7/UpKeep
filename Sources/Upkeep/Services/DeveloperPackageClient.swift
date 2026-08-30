import Foundation

struct DeveloperPackageClient: Sendable {
    struct Report: Sendable {
        let packages: [DeveloperPackage]
        let installedManagers: [DeveloperPackageManager]
        let warnings: [String]
        let failedManagers: Set<DeveloperPackageManager>
        let failedExecutablePaths: Set<String>

        static let empty = Report(
            packages: [], installedManagers: [], warnings: [],
            failedManagers: [], failedExecutablePaths: []
        )
    }

    func scan(
        enabledManagers: Set<DeveloperPackageManager> = Set(DeveloperPackageManager.allCases),
        includePrereleases: Bool = false
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
        appendDetected(.rubyGems, named: "gem", extra: ["/usr/bin/gem"], enabledManagers: enabledManagers, to: &tools)
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

        var seenTargets = Set<String>()
        tools = tools.filter { seenTargets.insert("\($0.0.rawValue):\($0.1)").inserted }

        let results = await withTaskGroup(of: ManagerScanResult.self) { group in
            for (manager, path) in tools {
                group.addTask {
                    await scanDeveloperTarget(manager: manager, path: path, defaultNode: defaultNode)
                }
            }
            var values: [ManagerScanResult] = []
            for await result in group { values.append(result) }
            return values
        }
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
        return Report(
            packages: packages,
            installedManagers: Array(Set(tools.map(\.0))).sorted { $0.rawValue < $1.rawValue },
            warnings: results.compactMap(\.warning),
            failedManagers: Set(Set(tools.map(\.0)).filter { manager in
                let managerResults = results.filter { $0.manager == manager }
                return !managerResults.isEmpty && managerResults.allSatisfy { $0.warning != nil && $0.packages.isEmpty }
            }),
            failedExecutablePaths: Set(results.compactMap { result in
                result.warning != nil ? result.executablePath : nil
            })
        )
    }

    private func includingPrereleaseUpdates(in packages: [DeveloperPackage]) async -> [DeveloperPackage] {
        let passthroughManagers: Set<DeveloperPackageManager> = [.node, .bun, .deno, .yarn]
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
                ? await latestGitHubReleaseVersions(repository: "oven-sh/bun")
                : await npmRegistryVersions(package: package.registryIdentifier ?? package.name)
        case .deno:
            discovered = await latestGitHubReleaseVersions(repository: "denoland/deno")
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
            discovered = await visualStudioMarketplaceVersions(extensionID: package.registryIdentifier ?? package.name)
        case .rustup, .macPorts, .nix, .mise, .asdf, .volta, .fnm:
            discovered = [package.currentVersion, package.latestVersion]
        case .githubCLI:
            discovered = await latestGitHubReleaseVersions(repository: package.registryIdentifier ?? package.name)
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
                qos: .userInitiated
            )
            guard result.status == 0 else {
                let output = String(data: result.data, encoding: .utf8)
                throw ClientError.failed(output?.isEmpty == false ? output! : failureMessage)
            }
        }
    }

    func uninstall(_ package: DeveloperPackage) async throws {
        let plan = try DeveloperPackageUninstallAdapters.plan(for: package)
        let result = await captureDeveloperCommandAsync(
            plan.executable,
            plan.arguments,
            qos: .userInitiated
        )
        guard result.status == 0 else {
            let output = String(data: result.data, encoding: .utf8)
            throw ClientError.failed(output?.isEmpty == false ? output! : plan.failureMessage)
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
            qos: .userInitiated
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
    let installedMajor = installed.split(separator: ".").first.map(String.init)
    let latest = preferLatestMajor
        ? releases.first
        : releases.first { $0.split(separator: ".").first.map(String.init) == installedMajor }
    guard let latest else {
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
    guard let latest = await latestGitHubReleaseVersions(repository: repository).first else {
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
    let globals = parseYarnGlobalPackages(globalsResult.data)
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
    let installedResult = await captureDeveloperCommandAsync(
        URL(fileURLWithPath: path), ["ls", "-g", "--depth=0", "--json"]
    )
    guard let installed = try? JSONDecoder().decode(NPMList.self, from: installedResult.data).dependencies else {
        return failedManagerScan(.npm, command: "inventory", result: installedResult)
    }
    let outdatedResult = await captureDeveloperCommandAsync(
        URL(fileURLWithPath: path), ["outdated", "-g", "--json"]
    )
    let outdated = try? JSONDecoder().decode([String: NPMOutdated].self, from: outdatedResult.data)
    let packages = installed.map { name, entry in
        DeveloperPackage(
            name: name, currentVersion: entry.version, latestVersion: outdated?[name]?.latest ?? entry.version,
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
    let installedResult = await captureDeveloperCommandAsync(
        URL(fileURLWithPath: path), ["list", "-g", "--depth=0", "--json"]
    )
    guard let installed = parsePNPMInstalledPackages(installedResult.data) else {
        return failedManagerScan(.pnpm, command: "inventory", result: installedResult)
    }
    let outdatedResult = await captureDeveloperCommandAsync(
        URL(fileURLWithPath: path), ["outdated", "-g", "--format", "json"]
    )
    let outdated = try? JSONDecoder().decode([String: NPMOutdated].self, from: outdatedResult.data)
    let packages = installed.map { name, version in
        DeveloperPackage(
            name: name, currentVersion: version, latestVersion: outdated?[name]?.latest ?? version,
            manager: .pnpm, executablePath: path, installationContext: nvmInstallationContext(for: path)
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
    let installedResult = await captureDeveloperCommandAsync(
        URL(fileURLWithPath: path), ["-m", "pip", "list", "--format=json", "--disable-pip-version-check"]
    )
    guard let installed = try? JSONDecoder().decode([PipInstalled].self, from: installedResult.data) else {
        return failedManagerScan(.python, command: "inventory", result: installedResult)
    }
    let outdatedResult = await captureDeveloperCommandAsync(
        URL(fileURLWithPath: path),
        ["-m", "pip", "list", "--outdated", "--format=json", "--disable-pip-version-check"]
    )
    let outdatedValues = try? JSONDecoder().decode([PipOutdated].self, from: outdatedResult.data)
    let outdated = Dictionary(uniqueKeysWithValues: (outdatedValues ?? []).map { ($0.name.lowercased(), $0.latestVersion) })
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
    let installedResult = await captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["list", "--local"])
    guard installedResult.status == 0 else { return failedManagerScan(.rubyGems, command: "inventory", result: installedResult) }
    let installedOutput = String(data: installedResult.data, encoding: .utf8) ?? ""
    let outdatedResult = await captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["outdated"])
    let outdatedOutput = String(data: outdatedResult.data, encoding: .utf8) ?? ""
    let outdated = parseGemOutdated(outdatedOutput)
    let regex = try? NSRegularExpression(pattern: #"^(.+?)\s+\((?:default:\s*)?([^,\)]+)"#, options: .anchorsMatchLines)
    let packages = installedOutput.split(separator: "\n").compactMap { line -> DeveloperPackage? in
        let value = String(line)
        guard let match = regex?.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let nameRange = Range(match.range(at: 1), in: value), let versionRange = Range(match.range(at: 2), in: value)
        else { return nil }
        let name = String(value[nameRange]); let version = String(value[versionRange])
        return DeveloperPackage(name: name, currentVersion: version, latestVersion: outdated[name] ?? version, manager: .rubyGems, executablePath: path)
    }
    return ManagerScanResult(
        manager: .rubyGems,
        packages: packages,
        warning: outdatedResult.status == 0 ? nil : commandWarning(.rubyGems, command: "outdated check", result: outdatedResult)
    )
}

private func parseGemOutdated(_ output: String) -> [String: String] {
    let regex = try? NSRegularExpression(pattern: #"^(.+?)\s+\([^\s]+\s+<\s+([^\)]+)\)$"#, options: .anchorsMatchLines)
    return output.split(separator: "\n").reduce(into: [:]) { values, line in
        let value = String(line)
        guard let match = regex?.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let nameRange = Range(match.range(at: 1), in: value), let latestRange = Range(match.range(at: 2), in: value)
        else { return }
        values[String(value[nameRange])] = String(value[latestRange])
    }
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
    let installed = parseExtensionInventory(result.data)
    let context = editorName(for: path)
    let values = await withTaskGroup(of: (DeveloperPackage, Bool).self) { group in
        for (identifier, version) in installed {
            group.addTask {
                let versions = await visualStudioMarketplaceVersions(extensionID: identifier)
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
        warning: failures == 0 ? nil : "\(context): marketplace checks failed for \(failures) extension\(failures == 1 ? "" : "s")."
    )
}

func scanUVTools(_ path: String) async -> ManagerScanResult {
    let result = await captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["tool", "list", "--show-version-specifiers"])
    guard result.status == 0 else { return failedManagerScan(.uv, command: "tool inventory", result: result) }
    async let toolScan = scanPyPIToolInventory(parseSimpleToolList(result.data), manager: .uv, executablePath: path)
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
    let installed = directories.compactMap { parseUVPythonDirectoryName($0.lastPathComponent) }
    let values = await withTaskGroup(of: DeveloperPackage.self) { group in
        for runtime in installed {
            group.addTask {
                let result = await captureDeveloperCommandAsync(
                    URL(fileURLWithPath: path), ["python", "list", runtime.minor, "--managed-python"]
                )
                let latest = parseUVPythonList(result.data, matchingMinor: runtime.minor).first ?? runtime.version
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
    let packages = parseRustupCheck(result.data).filter { $0.name != "rustup" }.map { toolchain in
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
    let installed = parseGitHubExtensionList(listResult.data)
    let updatesResult = await captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["extension", "upgrade", "--all", "--dry-run"])
    let updates = parseGitHubExtensionUpdates(updatesResult.data)
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
                return parseGoBuildInfo(result.data)
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
    if let currentRuntime = parseGoRuntimeVersion(versionResult.data) {
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
    let installed = parseDotnetToolList(result.data)
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
    let installed = parseMacPortsInstalled(installedResult.data)
    let outdated = Dictionary(uniqueKeysWithValues: parseMacPortsOutdated(outdatedResult.data).map { ($0.name, $0.latest) })
    let packages = installed.map {
        DeveloperPackage(
            name: $0.name, currentVersion: $0.version, latestVersion: outdated[$0.name] ?? $0.version,
            manager: .macPorts, executablePath: path, registryIdentifier: $0.name,
            canUpdateAutomatically: false
        )
    }
    return ManagerScanResult(manager: .macPorts, packages: packages, warning: nil)
}

func scanNixProfile(_ path: String) async -> ManagerScanResult {
    async let listCommand = captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["profile", "list", "--json"])
    async let updateCommand = captureDeveloperCommandAsync(URL(fileURLWithPath: path), ["profile", "upgrade", "--all", "--dry-run"])
    let (listResult, updateResult) = await (listCommand, updateCommand)
    guard listResult.status == 0 else { return failedManagerScan(.nix, command: "profile inventory", result: listResult) }
    guard updateResult.status == 0 else { return failedManagerScan(.nix, command: "profile update check", result: updateResult) }
    let updates = parseNixDryRun(updateResult.data)
    let latestByName = Dictionary(uniqueKeysWithValues: updates.map { ($0.name, $0.latest) })
    let packages = parseNixProfileJSON(listResult.data).map {
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
    let outdated = Dictionary(uniqueKeysWithValues: parseGenericOutdatedJSON(outdatedResult.data).map { ($0.name, $0.latest) })
    let packages = parseMiseInstalledJSON(installedResult.data).map {
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
    let installed = parseASDFCurrent(configData)
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
    let installed = parseVoltaList(result.data)
    let nodeReleases = installed.keys.contains("node") ? await nodeReleaseVersions() : []
    let packages = await withTaskGroup(of: DeveloperPackage.self) { group in
        for (name, version) in installed {
            group.addTask {
                let latest: String
                if name == "node" { latest = nodeReleases.first ?? version }
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
    let installed = parseFNMList(result.data)
    let releases = await nodeReleaseVersions()
    let packages = installed.map { version, isDefault in
        let major = version.split(separator: ".").first.map(String.init)
        let latest = isDefault
            ? releases.first
            : releases.first { $0.split(separator: ".").first.map(String.init) == major }
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

private func editorCLIs() -> [String] {
    let candidates = [
        "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
        homePath("Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"),
        "/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code",
        homePath("Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code"),
        "/Applications/Cursor.app/Contents/Resources/app/bin/cursor",
        homePath("Applications/Cursor.app/Contents/Resources/app/bin/cursor")
    ]
    var seen = Set<String>()
    return candidates.filter { FileManager.default.isExecutableFile(atPath: $0) && seen.insert($0).inserted }
}

private func editorName(for path: String) -> String {
    if path.contains("Cursor.app") { return "Cursor" }
    if path.contains("Insiders.app") { return "VS Code Insiders" }
    return "VS Code"
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

func parseExtensionInventory(_ data: Data) -> [String: String] {
    let output = String(data: data, encoding: .utf8) ?? ""
    return output.split(separator: "\n").reduce(into: [:]) { values, line in
        guard let separator = line.lastIndex(of: "@") else { return }
        let name = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let text = String(line)
        let textSeparator = text.index(text.startIndex, offsetBy: line.distance(from: line.startIndex, to: separator))
        let version = String(text[text.index(after: textSeparator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, !version.isEmpty { values[name] = version }
    }
}

func parseYarnGlobalPackages(_ data: Data) -> [String: String] {
    let output = String(data: data, encoding: .utf8) ?? ""
    var packages: [String: String] = [:]
    for line in output.split(separator: "\n") {
        guard let lineData = String(line).data(using: .utf8),
              let event = try? JSONDecoder().decode(YarnListEvent.self, from: lineData),
              event.type == "tree" else { continue }
        for tree in event.data?.trees ?? [] {
            guard let separator = tree.name.lastIndex(of: "@") else { continue }
            let name = String(tree.name[..<separator])
            let version = String(tree.name[tree.name.index(after: separator)...])
            if !name.isEmpty, !version.isEmpty { packages[name] = version }
        }
    }
    return packages
}

func parseSimpleToolList(_ data: Data) -> [String: String] {
    let output = String(data: data, encoding: .utf8) ?? ""
    return output.split(separator: "\n").reduce(into: [:]) { values, rawLine in
        let parts = rawLine.split(whereSeparator: \.isWhitespace)
        guard parts.count >= 2 else { return }
        let name = String(parts[0])
        let version = String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        if version.first?.isNumber == true { values[name] = version }
    }
}

func parseUVPythonDirectoryName(_ name: String) -> (implementation: String, version: String, minor: String)? {
    let regex = try? NSRegularExpression(pattern: #"^(cpython|pypy)-(\d+\.\d+\.\d+)(?:[-+].*)?$"#, options: .caseInsensitive)
    guard let match = regex?.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
          let implementationRange = Range(match.range(at: 1), in: name),
          let versionRange = Range(match.range(at: 2), in: name) else { return nil }
    let version = String(name[versionRange])
    let components = version.split(separator: ".")
    guard components.count >= 2 else { return nil }
    let implementation = String(name[implementationRange]).lowercased() == "pypy" ? "PyPy" : "CPython"
    return (implementation, version, components.prefix(2).joined(separator: "."))
}

func parseUVPythonList(_ data: Data, matchingMinor minor: String) -> [String] {
    let output = String(data: data, encoding: .utf8) ?? ""
    let regex = try? NSRegularExpression(pattern: #"(?:cpython|pypy)-(\d+\.\d+\.\d+)"#, options: .caseInsensitive)
    let versions = output.split(separator: "\n").compactMap { rawLine -> String? in
        let line = String(rawLine)
        guard let match = regex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else { return nil }
        let version = String(line[range])
        return version.hasPrefix(minor + ".") ? version : nil
    }
    return VersionComparator.sortedNewestFirst(Set(versions))
}

func parseRustupCheck(_ data: Data) -> [(name: String, current: String, latest: String)] {
    let output = String(data: data, encoding: .utf8) ?? ""
    let versionPattern = #"\d+\.\d+(?:\.\d+)?(?:[-+][0-9A-Za-z.-]+)?"#
    let regex = try? NSRegularExpression(pattern: versionPattern)
    return output.split(separator: "\n").compactMap { rawLine in
        let line = String(rawLine)
        guard let divider = line.range(of: " - "), line.contains(":") else { return nil }
        let name = String(line[..<divider.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = regex?.matches(in: line, range: NSRange(line.startIndex..., in: line)) ?? []
        let versions = matches.compactMap { Range($0.range, in: line).map { String(line[$0]) } }
        guard let current = versions.first else { return nil }
        return (name, current, versions.count > 1 ? versions.last! : current)
    }
}

func parseGitHubExtensionList(_ data: Data) -> [String: String] {
    let output = String(data: data, encoding: .utf8) ?? ""
    var values: [String: String] = [:]
    for rawLine in output.split(separator: "\n") {
        let fields = rawLine.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let repository = fields.first(where: { $0.contains("/") }) else { continue }
        let version = fields.reversed().first(where: {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).first?.isNumber == true
        })?.trimmingCharacters(in: CharacterSet(charactersIn: "vV")) ?? "unknown"
        values[repository] = version
    }
    return values
}

func parseGitHubExtensionUpdates(_ data: Data) -> [String: String] {
    let output = String(data: data, encoding: .utf8) ?? ""
    let regex = try? NSRegularExpression(pattern: #"([\w.-]+/[\w.-]+).*?(?:to|->)\s+v?([0-9][0-9A-Za-z.+-]*)"#, options: .caseInsensitive)
    return output.split(separator: "\n").reduce(into: [:]) { values, rawLine in
        let line = String(rawLine)
        guard let match = regex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let repositoryRange = Range(match.range(at: 1), in: line),
              let versionRange = Range(match.range(at: 2), in: line) else { return }
        values[String(line[repositoryRange])] = String(line[versionRange])
    }
}

func parseGoBuildInfo(_ data: Data) -> GoInstalledTool? {
    let lines = (String(data: data, encoding: .utf8) ?? "").split(separator: "\n").map(String.init)
    let command = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("path\t") })?
        .split(separator: "\t", maxSplits: 1).last.map(String.init)
    let moduleFields = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("mod\t") })?
        .split(separator: "\t").map(String.init)
    guard let command, let moduleFields, moduleFields.count >= 3 else { return nil }
    let version = moduleFields[2].trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    guard version.first?.isNumber == true else { return nil }
    return GoInstalledTool(command: command, module: moduleFields[1], version: version)
}

func parseGoRuntimeVersion(_ data: Data) -> String? {
    let output = String(data: data, encoding: .utf8) ?? ""
    let regex = try? NSRegularExpression(pattern: #"\bgo(\d+\.\d+(?:\.\d+)?)\b"#)
    guard let match = regex?.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
          let range = Range(match.range(at: 1), in: output) else { return nil }
    return String(output[range])
}

func parseDotnetToolList(_ data: Data) -> [String: String] {
    if let root = try? JSONDecoder().decode(DotnetToolList.self, from: data) {
        return root.data.reduce(into: [:]) { values, tool in values[tool.packageId] = tool.version }
    }
    let output = String(data: data, encoding: .utf8) ?? ""
    return output.split(separator: "\n").reduce(into: [:]) { values, rawLine in
        let fields = rawLine.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count >= 2, fields[1].first?.isNumber == true else { return }
        values[fields[0]] = fields[1]
    }
}

func parseMacPortsOutdated(_ data: Data) -> [(name: String, current: String, latest: String)] {
    let output = String(data: data, encoding: .utf8) ?? ""
    let regex = try? NSRegularExpression(pattern: #"^\s*(\S+)\s+@?([^\s]+).*?<\s+@?([^\s]+)"#, options: .anchorsMatchLines)
    return output.split(separator: "\n").compactMap { rawLine in
        let line = String(rawLine)
        guard let match = regex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let name = Range(match.range(at: 1), in: line),
              let current = Range(match.range(at: 2), in: line),
              let latest = Range(match.range(at: 3), in: line) else { return nil }
        return (String(line[name]), stripPackageRevision(String(line[current])), stripPackageRevision(String(line[latest])))
    }
}

func parseMacPortsInstalled(_ data: Data) -> [(name: String, version: String)] {
    let output = String(data: data, encoding: .utf8) ?? ""
    let regex = try? NSRegularExpression(pattern: #"^\s*(\S+)\s+@([^\s]+)"#, options: .anchorsMatchLines)
    return output.split(separator: "\n").compactMap { rawLine in
        let line = String(rawLine)
        guard let match = regex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let name = Range(match.range(at: 1), in: line),
              let version = Range(match.range(at: 2), in: line) else { return nil }
        return (String(line[name]), stripPackageRevision(String(line[version])))
    }
}

func parseNixDryRun(_ data: Data) -> [(name: String, current: String, latest: String, selector: String)] {
    let output = String(data: data, encoding: .utf8) ?? ""
    let regex = try? NSRegularExpression(
        pattern: #"(?:upgrade|upgrading)\s+['\"]?([^'\"\s]+)['\"]?.*?from\s+['\"]?v?([^'\"\s]+)['\"]?\s+(?:to|->)\s+['\"]?v?([^'\"\s]+)"#,
        options: .caseInsensitive
    )
    let arrowRegex = try? NSRegularExpression(
        pattern: #"^\s*['\"]?([^:'\"\s]+)['\"]?\s*:\s*['\"]?v?([0-9][^'\"\s]*)['\"]?\s*(?:->|→)\s*['\"]?v?([0-9][^'\"\s]*)"#,
        options: .caseInsensitive
    )
    return output.split(separator: "\n").compactMap { rawLine in
        let line = String(rawLine)
        let match = regex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
            ?? arrowRegex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
        guard let match,
              let selectorRange = Range(match.range(at: 1), in: line),
              let currentRange = Range(match.range(at: 2), in: line),
              let latestRange = Range(match.range(at: 3), in: line) else { return nil }
        let selector = String(line[selectorRange])
        let name = selector.split(separator: "#").last.map(String.init) ?? selector
        return (name, String(line[currentRange]), String(line[latestRange]), selector)
    }
}

func parseNixProfileJSON(_ data: Data) -> [(name: String, version: String, selector: String)] {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
    let elements = (root["elements"] as? [String: Any]) ?? root
    return elements.compactMap { selector, rawValue in
        guard let value = rawValue as? [String: Any] else { return nil }
        let storePaths = value["storePaths"] as? [String] ?? value["store-paths"] as? [String] ?? []
        guard let storePath = storePaths.first,
              let parsed = parseNixStorePath(storePath) else { return nil }
        return (parsed.name, parsed.version, selector)
    }
}

private func parseNixStorePath(_ path: String) -> (name: String, version: String)? {
    let fileName = URL(fileURLWithPath: path).lastPathComponent
    let withoutHash = fileName.split(separator: "-", maxSplits: 1).dropFirst().first.map(String.init) ?? fileName
    let regex = try? NSRegularExpression(pattern: #"^(.+)-([0-9][0-9A-Za-z.+_-]*)$"#)
    guard let match = regex?.firstMatch(in: withoutHash, range: NSRange(withoutHash.startIndex..., in: withoutHash)),
          let name = Range(match.range(at: 1), in: withoutHash),
          let version = Range(match.range(at: 2), in: withoutHash) else { return nil }
    return (String(withoutHash[name]), stripPackageRevision(String(withoutHash[version])))
}

func parseGenericOutdatedJSON(_ data: Data) -> [(name: String, current: String, latest: String)] {
    guard let value = try? JSONSerialization.jsonObject(with: data) else { return [] }
    var results: [(String, String, String)] = []
    func visit(_ value: Any, hintedName: String? = nil) {
        if let dictionary = value as? [String: Any] {
            let name = (dictionary["name"] as? String) ?? (dictionary["tool"] as? String) ?? hintedName
            let current = (dictionary["current"] as? String) ?? (dictionary["version"] as? String)
            let latest = (dictionary["latest"] as? String) ?? (dictionary["new_version"] as? String)
            if let name, let current, let latest, current != latest { results.append((name, current, latest)) }
            for (key, child) in dictionary { visit(child, hintedName: key) }
        } else if let array = value as? [Any] {
            for child in array { visit(child, hintedName: hintedName) }
        }
    }
    visit(value)
    var seen = Set<String>()
    return results.filter { seen.insert("\($0.0):\($0.1):\($0.2)").inserted }
}

func parseMiseInstalledJSON(_ data: Data) -> [(name: String, version: String)] {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
    var values: [(String, String)] = []
    for (name, rawEntries) in root {
        let entries = rawEntries as? [[String: Any]] ?? []
        for entry in entries {
            guard let version = entry["version"] as? String, !version.isEmpty else { continue }
            values.append((name, version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))))
        }
    }
    return values
}

func parseASDFCurrent(_ data: Data) -> [String: String] {
    let output = String(data: data, encoding: .utf8) ?? ""
    return output.split(separator: "\n").reduce(into: [:]) { values, line in
        let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count >= 2, fields[1] != "______", fields[1] != "No" else { return }
        values[fields[0]] = fields[1].trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }
}

func parseVoltaList(_ data: Data) -> [String: String] {
    let output = String(data: data, encoding: .utf8) ?? ""
    return output.split(separator: "\n").reduce(into: [:]) { values, line in
        let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let token = fields.first(where: { $0.contains("@") }),
              let separator = token.lastIndex(of: "@") else { return }
        let name = String(token[..<separator])
        let version = String(token[token.index(after: separator)...]).trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        if !name.isEmpty, version.first?.isNumber == true, values[name] == nil { values[name] = version }
    }
}

func parseFNMList(_ data: Data) -> [(version: String, isDefault: Bool)] {
    let output = String(data: data, encoding: .utf8) ?? ""
    return output.split(separator: "\n").compactMap { line in
        let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let versionToken = fields.first(where: { $0.trimmingCharacters(in: CharacterSet(charactersIn: "*vV" )).first?.isNumber == true }) else { return nil }
        return (
            versionToken.trimmingCharacters(in: CharacterSet(charactersIn: "*vV")),
            line.contains("default") || line.hasPrefix("*")
        )
    }
}

private func stripPackageRevision(_ value: String) -> String {
    value.split(separator: "_").first.map(String.init) ?? value
}

private func normalizedComposerVersion(_ value: String) -> String {
    value.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
}

private func latestStableVersion(in versions: [String]) -> String? {
    versions.first { !VersionComparator.isPrerelease($0) }
}

private func executable(named name: String, extra: [String]) -> String? {
    (extra + ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"])
        .first { FileManager.default.isExecutableFile(atPath: $0) }
}

private func nvmExecutables(named name: String) -> [String] {
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".nvm/versions/node", isDirectory: true)
    let versions = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
    return versions.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
        .map { $0.appendingPathComponent("bin/\(name)").path }
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
    let process = Process(); let output = Pipe()
    process.executableURL = executable; process.arguments = arguments
    process.environment = developerCommandEnvironment(for: executable, base: baseEnvironment)
    // Finder launches apps from `/`. pnpm probes the current directory when
    // locating its store, independently of TMPDIR. These are global commands;
    // do not inherit the read-only root or an unrelated project's configuration.
    process.currentDirectoryURL = developerCommandWorkingDirectory(base: process.environment ?? [:])
    process.standardOutput = output; process.standardError = output
    do { try process.run() }
    catch { return (Data(error.localizedDescription.utf8), -1) }
    let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    return (data, process.terminationStatus)
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
    qos: DispatchQoS.QoSClass = .utility
) async -> (data: Data, status: Int32) {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: qos).async {
            continuation.resume(returning: captureDeveloperCommand(
                executable,
                arguments,
                baseEnvironment: baseEnvironment
            ))
        }
    }
}

func developerCommandEnvironment(
    for executable: URL,
    base: [String: String] = ProcessInfo.processInfo.environment
) -> [String: String] {
    var environment = base
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
private struct PNPMRoot: Decodable { let dependencies: [String: PNPMEntry]?; let devDependencies: [String: PNPMEntry]? }
private struct PNPMEntry: Decodable { let version: String }
private struct BunGlobalManifest: Decodable {
    let dependencies: [String: String]?
    let devDependencies: [String: String]?
}
private struct YarnListEvent: Decodable {
    let type: String
    let data: TreeData?
    struct TreeData: Decodable { let trees: [Tree] }
    struct Tree: Decodable { let name: String }
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
private struct DotnetToolList: Decodable {
    let data: [Tool]
    struct Tool: Decodable {
        let packageId: String
        let version: String
        enum CodingKeys: String, CodingKey { case packageId = "packageId"; case version }
    }
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
    struct Extension: Decodable { let versions: [Version] }
    struct Version: Decodable { let version: String; let targetPlatform: String? }
}
private struct GoProxyLatest: Decodable { let version: String
    enum CodingKeys: String, CodingKey { case version = "Version" }
}
private struct GoRelease: Decodable { let version: String; let stable: Bool }
private struct PackagistResponse: Decodable {
    let packages: [String: [PackageVersion]]
    struct PackageVersion: Decodable { let version: String; let versionNormalized: String?
        enum CodingKeys: String, CodingKey { case version; case versionNormalized = "version_normalized" }
    }
}
private struct NugetVersions: Decodable { let versions: [String] }

private actor RegistryRequestCache {
    static let shared = RegistryRequestCache()
    private static let freshnessInterval: TimeInterval = 10 * 60
    private struct Entry { let data: Data; let date: Date }
    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<Data?, Never>] = [:]

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
        if let value { entries[key] = Entry(data: value, date: Date()) }
        return value
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

private func latestGitHubReleaseVersions(repository: String) async -> [String] {
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

private func visualStudioMarketplaceVersions(extensionID: String) async -> [String] {
    guard let url = URL(string: "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery"),
          let body = try? JSONSerialization.data(withJSONObject: [
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
    guard let data = await RegistryRequestCache.shared.data(for: request, key: "VSCode:\(extensionID.lowercased())"),
          let root = try? JSONDecoder().decode(VSMarketplaceResponse.self, from: data) else { return [] }
    #if arch(arm64)
    let platform = "darwin-arm64"
    #else
    let platform = "darwin-x64"
    #endif
    let compatible = root.results.flatMap(\.extensions).flatMap(\.versions).filter {
        $0.targetPlatform == nil || $0.targetPlatform == "universal" || $0.targetPlatform == platform
    }
    return VersionComparator.sortedNewestFirst(Set(compatible.map(\.version)))
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
