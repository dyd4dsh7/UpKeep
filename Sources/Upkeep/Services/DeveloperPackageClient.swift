import Foundation

struct DeveloperPackageClient: Sendable {
    struct Report: Sendable {
        let packages: [DeveloperPackage]
        let installedManagers: [DeveloperPackageManager]
        let warnings: [String]
        let failedManagers: Set<DeveloperPackageManager>
    }

    func scan(enabledManagers: Set<DeveloperPackageManager> = Set(DeveloperPackageManager.allCases)) async -> Report {
        var tools: [(DeveloperPackageManager, String)] = []
        if enabledManagers.contains(.npm), let npm = executable(named: "npm", extra: nvmExecutables(named: "npm")) { tools.append((.npm, npm)) }
        if enabledManagers.contains(.pnpm), let pnpm = executable(named: "pnpm", extra: nvmExecutables(named: "pnpm")) { tools.append((.pnpm, pnpm)) }
        if enabledManagers.contains(.python), let python = executable(named: "python3", extra: ["/usr/bin/python3"]) { tools.append((.python, python)) }
        if enabledManagers.contains(.rubyGems), let gem = executable(named: "gem", extra: ["/usr/bin/gem"]) { tools.append((.rubyGems, gem)) }
        if enabledManagers.contains(.cargo), let cargo = executable(named: "cargo", extra: [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cargo/bin/cargo").path]) { tools.append((.cargo, cargo)) }

        let results = await withTaskGroup(of: ManagerScanResult.self) { group in
            for (manager, path) in tools {
                group.addTask {
                    switch manager {
                    case .npm: scanNPM(path)
                    case .pnpm: scanPNPM(path)
                    case .python: scanPython(path)
                    case .rubyGems: scanGems(path)
                    case .cargo: await scanCargo(path)
                    }
                }
            }
            var values: [ManagerScanResult] = []
            for await result in group { values.append(result) }
            return values
        }
        let packages = results.flatMap(\.packages).sorted {
                if $0.manager != $1.manager { return $0.manager.rawValue < $1.manager.rawValue }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return Report(
            packages: packages,
            installedManagers: tools.map(\.0),
            warnings: results.compactMap(\.warning),
            failedManagers: Set(results.filter { $0.warning != nil }.map(\.manager))
        )
    }

    func availableVersions(for package: DeveloperPackage, includePrereleases: Bool) async -> [String] {
        let discovered: [String]
        switch package.manager {
        case .npm, .pnpm:
            discovered = await Task.detached(priority: .utility) {
                let result = capture(URL(fileURLWithPath: package.executablePath), ["view", package.name, "versions", "--json"])
                guard result.status == 0 else { return [] }
                if let values = try? JSONDecoder().decode([String].self, from: result.data) { return values }
                if let value = try? JSONDecoder().decode(String.self, from: result.data) { return [value] }
                return []
            }.value
        case .python:
            discovered = await Task.detached(priority: .utility) {
                let executable = URL(fileURLWithPath: package.executablePath)
                let result = capture(executable, ["-m", "pip", "index", "versions", package.name, "--json", "--disable-pip-version-check"])
                if result.status == 0,
                   let object = try? JSONSerialization.jsonObject(with: result.data) as? [String: Any],
                   let versions = object["versions"] as? [String] { return versions }
                let fallback = capture(executable, ["-m", "pip", "index", "versions", package.name, "--disable-pip-version-check"])
                let output = String(data: fallback.data, encoding: .utf8) ?? ""
                guard let line = output.split(separator: "\n").first(where: { $0.localizedCaseInsensitiveContains("Available versions:") }),
                      let colon = line.firstIndex(of: ":") else { return [] }
                return line[line.index(after: colon)...].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            }.value
        case .rubyGems:
            discovered = await Task.detached(priority: .utility) {
                let result = capture(URL(fileURLWithPath: package.executablePath), ["list", "--remote", "--all", "--exact", package.name])
                let output = String(data: result.data, encoding: .utf8) ?? ""
                guard let open = output.firstIndex(of: "("), let close = output[open...].firstIndex(of: ")") else { return [] }
                return output[output.index(after: open)..<close].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            }.value
        case .cargo:
            guard let encoded = package.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "https://crates.io/api/v1/crates/\(encoded)"),
                  let data = await registryData(from: url),
                  let response = try? JSONDecoder().decode(CrateVersionsResponse.self, from: data)
            else { discovered = [] ; break }
            discovered = response.versions.filter { !$0.yanked }.map(\.num)
        }

        let allowed = includePrereleases ? discovered : discovered.filter { !isPrerelease($0) }
        let unique = Set(allowed + [package.latestVersion, package.currentVersion])
        return unique.sorted { VersionComparator.compare($0, $1) == .orderedDescending }
    }

    func install(_ package: DeveloperPackage, version: String) async throws {
        let executable = URL(fileURLWithPath: package.executablePath)
        let arguments: [String]
        switch package.manager {
        case .npm: arguments = ["install", "-g", "\(package.name)@\(version)"]
        case .pnpm: arguments = ["add", "-g", "\(package.name)@\(version)"]
        case .python: arguments = ["-m", "pip", "install", "--user", "\(package.name)==\(version)"]
        case .rubyGems: arguments = ["install", package.name, "--version", version, "--user-install"]
        case .cargo: arguments = ["install", package.name, "--version", version, "--force"]
        }
        try await Task.detached(priority: .userInitiated) {
            let result = capture(executable, arguments)
            guard result.status == 0 else {
                throw ClientError.failed(String(data: result.data, encoding: .utf8) ?? "Package update failed")
            }
        }.value
    }

    enum ClientError: LocalizedError {
        case failed(String)
        var errorDescription: String? { if case let .failed(message) = self { return message }; return nil }
    }
}

private struct ManagerScanResult: Sendable {
    let manager: DeveloperPackageManager
    let packages: [DeveloperPackage]
    let warning: String?
}

private func scanNPM(_ path: String) -> ManagerScanResult {
    let installedResult = capture(URL(fileURLWithPath: path), ["ls", "-g", "--depth=0", "--json"])
    guard let installed = try? JSONDecoder().decode(NPMList.self, from: installedResult.data).dependencies else {
        return failedManagerScan(.npm, command: "inventory", result: installedResult)
    }
    let outdatedResult = capture(URL(fileURLWithPath: path), ["outdated", "-g", "--json"])
    let outdated = try? JSONDecoder().decode([String: NPMOutdated].self, from: outdatedResult.data)
    let packages = installed.map { name, entry in
        DeveloperPackage(name: name, currentVersion: entry.version, latestVersion: outdated?[name]?.latest ?? entry.version, manager: .npm, executablePath: path)
    }
    return ManagerScanResult(
        manager: .npm,
        packages: packages,
        warning: outdated == nil && (outdatedResult.status != 0 || !outdatedResult.data.isEmpty)
            ? commandWarning(.npm, command: "outdated check", result: outdatedResult) : nil
    )
}

private func scanPNPM(_ path: String) -> ManagerScanResult {
    let installedResult = capture(URL(fileURLWithPath: path), ["list", "-g", "--depth=0", "--json"])
    guard let roots = try? JSONDecoder().decode([PNPMRoot].self, from: installedResult.data) else {
        return failedManagerScan(.pnpm, command: "inventory", result: installedResult)
    }
    let installed = roots.reduce(into: [String: PNPMEntry]()) { values, root in
        values.merge(root.dependencies ?? [:]) { current, _ in current }
        values.merge(root.devDependencies ?? [:]) { current, _ in current }
    }
    let outdatedResult = capture(URL(fileURLWithPath: path), ["outdated", "-g", "--format", "json"])
    let outdated = try? JSONDecoder().decode([String: NPMOutdated].self, from: outdatedResult.data)
    let packages = installed.map { name, entry in
        DeveloperPackage(name: name, currentVersion: entry.version, latestVersion: outdated?[name]?.latest ?? entry.version, manager: .pnpm, executablePath: path)
    }
    return ManagerScanResult(
        manager: .pnpm,
        packages: packages,
        warning: outdated == nil && (outdatedResult.status != 0 || !outdatedResult.data.isEmpty)
            ? commandWarning(.pnpm, command: "outdated check", result: outdatedResult) : nil
    )
}

private func scanPython(_ path: String) -> ManagerScanResult {
    let installedResult = capture(URL(fileURLWithPath: path), ["-m", "pip", "list", "--format=json", "--disable-pip-version-check"])
    guard let installed = try? JSONDecoder().decode([PipInstalled].self, from: installedResult.data) else {
        return failedManagerScan(.python, command: "inventory", result: installedResult)
    }
    let outdatedResult = capture(URL(fileURLWithPath: path), ["-m", "pip", "list", "--outdated", "--format=json", "--disable-pip-version-check"])
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

private func scanGems(_ path: String) -> ManagerScanResult {
    let installedResult = capture(URL(fileURLWithPath: path), ["list", "--local"])
    guard installedResult.status == 0 else { return failedManagerScan(.rubyGems, command: "inventory", result: installedResult) }
    let installedOutput = String(data: installedResult.data, encoding: .utf8) ?? ""
    let outdatedResult = capture(URL(fileURLWithPath: path), ["outdated"])
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

private func scanCargo(_ path: String) async -> ManagerScanResult {
    let installedResult = capture(URL(fileURLWithPath: path), ["install", "--list"])
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

private func capture(_ executable: URL, _ arguments: [String]) -> (data: Data, status: Int32) {
    let process = Process(); let output = Pipe()
    process.executableURL = executable; process.arguments = arguments
    process.standardOutput = output; process.standardError = output
    do { try process.run() } catch { return (Data(), -1) }
    let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    return (data, process.terminationStatus)
}

private struct NPMList: Decodable { let dependencies: [String: NPMInstalled] }
private struct NPMInstalled: Decodable { let version: String }
private struct NPMOutdated: Decodable { let latest: String }
private struct PNPMRoot: Decodable { let dependencies: [String: PNPMEntry]?; let devDependencies: [String: PNPMEntry]? }
private struct PNPMEntry: Decodable { let version: String }
private struct PipInstalled: Decodable { let name: String; let version: String }
private struct PipOutdated: Decodable {
    let name: String; let latestVersion: String
    enum CodingKeys: String, CodingKey { case name; case latestVersion = "latest_version" }
}
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

private func isPrerelease(_ version: String) -> Bool {
    let value = version.lowercased()
    return ["alpha", "beta", "-rc", ".rc", "-pre", ".dev", "snapshot"].contains { value.contains($0) }
}

private func registryData(from url: URL) async -> Data? {
    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    request.setValue("Upkeep/0.9", forHTTPHeaderField: "User-Agent")
    guard let (data, response) = try? await URLSession.shared.data(for: request),
          let http = response as? HTTPURLResponse,
          200..<300 ~= http.statusCode else { return nil }
    return data
}
