import Foundation

struct DeveloperPackageClient: Sendable {
    struct Report: Sendable {
        let packages: [DeveloperPackage]
        let installedManagers: [DeveloperPackageManager]
    }

    func scan() async -> Report {
        var tools: [(DeveloperPackageManager, String)] = []
        if let npm = executable(named: "npm", extra: nvmExecutables(named: "npm")) { tools.append((.npm, npm)) }
        if let pnpm = executable(named: "pnpm", extra: nvmExecutables(named: "pnpm")) { tools.append((.pnpm, pnpm)) }
        if let python = executable(named: "python3", extra: ["/usr/bin/python3"]) { tools.append((.python, python)) }
        if let gem = executable(named: "gem", extra: ["/usr/bin/gem"]) { tools.append((.rubyGems, gem)) }
        if let cargo = executable(named: "cargo", extra: [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cargo/bin/cargo").path]) { tools.append((.cargo, cargo)) }

        let packages = await withTaskGroup(of: [DeveloperPackage].self) { group in
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
            var values: [DeveloperPackage] = []
            for await result in group { values.append(contentsOf: result) }
            return values.sorted {
                if $0.manager != $1.manager { return $0.manager.rawValue < $1.manager.rawValue }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
        return Report(packages: packages, installedManagers: tools.map(\.0))
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

private func scanNPM(_ path: String) -> [DeveloperPackage] {
    let installedData = capture(URL(fileURLWithPath: path), ["ls", "-g", "--depth=0", "--json"]).data
    guard let installed = try? JSONDecoder().decode(NPMList.self, from: installedData).dependencies else { return [] }
    let outdatedData = capture(URL(fileURLWithPath: path), ["outdated", "-g", "--json"]).data
    let outdated = (try? JSONDecoder().decode([String: NPMOutdated].self, from: outdatedData)) ?? [:]
    return installed.map { name, entry in
        DeveloperPackage(name: name, currentVersion: entry.version, latestVersion: outdated[name]?.latest ?? entry.version, manager: .npm, executablePath: path)
    }
}

private func scanPNPM(_ path: String) -> [DeveloperPackage] {
    let installedData = capture(URL(fileURLWithPath: path), ["list", "-g", "--depth=0", "--json"]).data
    let roots = (try? JSONDecoder().decode([PNPMRoot].self, from: installedData)) ?? []
    let installed = roots.reduce(into: [String: PNPMEntry]()) { values, root in
        values.merge(root.dependencies ?? [:]) { current, _ in current }
        values.merge(root.devDependencies ?? [:]) { current, _ in current }
    }
    let outdatedData = capture(URL(fileURLWithPath: path), ["outdated", "-g", "--format", "json"]).data
    let outdated = (try? JSONDecoder().decode([String: NPMOutdated].self, from: outdatedData)) ?? [:]
    return installed.map { name, entry in
        DeveloperPackage(name: name, currentVersion: entry.version, latestVersion: outdated[name]?.latest ?? entry.version, manager: .pnpm, executablePath: path)
    }
}

private func scanPython(_ path: String) -> [DeveloperPackage] {
    let installedData = capture(URL(fileURLWithPath: path), ["-m", "pip", "list", "--format=json", "--disable-pip-version-check"]).data
    guard let installed = try? JSONDecoder().decode([PipInstalled].self, from: installedData) else { return [] }
    let outdatedData = capture(URL(fileURLWithPath: path), ["-m", "pip", "list", "--outdated", "--format=json", "--disable-pip-version-check"]).data
    let outdatedValues = (try? JSONDecoder().decode([PipOutdated].self, from: outdatedData)) ?? []
    let outdated = Dictionary(uniqueKeysWithValues: outdatedValues.map { ($0.name.lowercased(), $0.latestVersion) })
    return installed.map {
        DeveloperPackage(name: $0.name, currentVersion: $0.version, latestVersion: outdated[$0.name.lowercased()] ?? $0.version, manager: .python, executablePath: path)
    }
}

private func scanGems(_ path: String) -> [DeveloperPackage] {
    let installedOutput = String(data: capture(URL(fileURLWithPath: path), ["list", "--local"]).data, encoding: .utf8) ?? ""
    let outdatedOutput = String(data: capture(URL(fileURLWithPath: path), ["outdated"]).data, encoding: .utf8) ?? ""
    let outdated = parseGemOutdated(outdatedOutput)
    let regex = try? NSRegularExpression(pattern: #"^(.+?)\s+\((?:default:\s*)?([^,\)]+)"#, options: .anchorsMatchLines)
    return installedOutput.split(separator: "\n").compactMap { line in
        let value = String(line)
        guard let match = regex?.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let nameRange = Range(match.range(at: 1), in: value), let versionRange = Range(match.range(at: 2), in: value)
        else { return nil }
        let name = String(value[nameRange]); let version = String(value[versionRange])
        return DeveloperPackage(name: name, currentVersion: version, latestVersion: outdated[name] ?? version, manager: .rubyGems, executablePath: path)
    }
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

private func scanCargo(_ path: String) async -> [DeveloperPackage] {
    let output = String(data: capture(URL(fileURLWithPath: path), ["install", "--list"]).data, encoding: .utf8) ?? ""
    let installed = output.split(separator: "\n").compactMap { line -> (String, String)? in
        guard !line.hasPrefix(" "), let colon = line.firstIndex(of: ":") else { return nil }
        let prefix = line[..<colon].split(separator: " "); guard prefix.count >= 2 else { return nil }
        return (String(prefix[0]), String(prefix[1]).trimmingCharacters(in: CharacterSet(charactersIn: "v")))
    }
    return await withTaskGroup(of: DeveloperPackage.self) { group in
        for (name, current) in installed {
            group.addTask {
                guard let url = URL(string: "https://crates.io/api/v1/crates/\(name)"),
                      let (data, _) = try? await URLSession.shared.data(from: url),
                      let response = try? JSONDecoder().decode(CrateResponse.self, from: data)
                else { return DeveloperPackage(name: name, currentVersion: current, latestVersion: current, manager: .cargo, executablePath: path) }
                return DeveloperPackage(name: name, currentVersion: current, latestVersion: response.crate.maxVersion, manager: .cargo, executablePath: path)
            }
        }
        var values: [DeveloperPackage] = []
        for await value in group { values.append(value) }
        return values
    }
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
