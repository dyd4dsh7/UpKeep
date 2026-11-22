import Foundation

// Scanners for Flutter, GHCup, swiftly, Conda and SDKMAN. These tools were not
// installed while this was written, so commands and output formats follow
// each tool's source code (November 2026) and live checks of their public
// endpoints, not runs of the tools themselves.

private func sourceManagerWarning(_ manager: DeveloperPackageManager, _ command: String, _ result: (data: Data, status: Int32)) -> String {
    let output = String(decoding: result.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return "\(manager.rawValue) \(command) failed: \(output.isEmpty ? "command exited with status \(result.status)" : String(output.prefix(400)))"
}

/// Some tools print progress before their JSON; parse from the first brace.
func jsonPayload(_ data: Data) -> Data {
    guard let start = data.firstIndex(where: { $0 == UInt8(ascii: "{") || $0 == UInt8(ascii: "[") }) else { return data }
    return data[start...]
}

private func publicData(_ url: URL) async -> Data? {
    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    request.setValue("Upkeep/1.0", forHTTPHeaderField: "User-Agent")
    return await RegistryRequestCache.shared.data(for: request, key: "GET:\(url.absoluteString)")
}

// MARK: - Flutter

struct FlutterInstallation: Equatable, Sendable {
    let version: String
    let channel: String
    let revision: String
}

/// `flutter --version --machine` (packages/flutter_tools/lib/src/version.dart).
func parseFlutterVersion(_ data: Data) -> FlutterInstallation? {
    struct Machine: Decodable { let frameworkVersion: String; let channel: String; let frameworkRevision: String }
    guard let value = try? JSONDecoder().decode(Machine.self, from: jsonPayload(data)) else { return nil }
    return FlutterInstallation(version: value.frameworkVersion, channel: value.channel, revision: value.frameworkRevision)
}

/// The release a channel currently points to, from Flutter's releases_macos.json.
func flutterChannelRelease(_ data: Data, channel: String) -> (version: String, hash: String)? {
    struct Releases: Decodable {
        struct Release: Decodable { let hash: String; let version: String; let channel: String }
        let current_release: [String: String]
        let releases: [Release]
    }
    guard let releases = try? JSONDecoder().decode(Releases.self, from: data),
          let hash = releases.current_release[channel],
          let release = releases.releases.first(where: { $0.hash == hash && $0.channel == channel })
    else { return nil }
    return (release.version, hash)
}

func scanFlutter(_ path: String) async -> ManagerScanResult {
    let result = await captureDeveloperStandardOutput(URL(fileURLWithPath: path), ["--version", "--machine"])
    guard result.status == 0, let installed = parseFlutterVersion(result.data) else {
        return ManagerScanResult(manager: .flutter, packages: [], warning: sourceManagerWarning(.flutter, "version check", result))
    }
    // The main/master channel is not published as a release.
    var release: (version: String, hash: String)?
    if let url = URL(string: "https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json"),
       let data = await publicData(url) {
        release = flutterChannelRelease(data, channel: installed.channel)
    }
    let latest = release.map { $0.hash != installed.revision && VersionComparator.isNewer($0.version, than: installed.version)
        ? $0.version : installed.version } ?? installed.version
    return ManagerScanResult(manager: .flutter, packages: [
        DeveloperPackage(name: "Flutter SDK", currentVersion: installed.version, latestVersion: latest,
            manager: .flutter, executablePath: path, registryIdentifier: "flutter",
            installationContext: "\(installed.channel.capitalized) channel")
    ], warning: nil)
}

// MARK: - GHCup

struct GHCupRow: Equatable, Sendable {
    let tool: String
    let version: String
    let tags: Set<String>
}

/// `ghcup list -r`: "tool version tags notes", joined by single spaces with
/// comma-separated tags (lib/GHCup/List.hs, Types.hs). Raw mode has no
/// installed or set marks, so callers filter with `-c set`.
func parseGHCupRawList(_ text: String) -> [GHCupRow] {
    text.split(whereSeparator: \.isNewline).compactMap { line in
        let fields = line.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 2, !fields[0].isEmpty, fields[1].first?.isNumber == true else { return nil }
        let tags = fields.count > 2 ? Set(fields[2].split(separator: ",").map(String.init)) : []
        return GHCupRow(tool: fields[0], version: fields[1], tags: tags)
    }
}

/// Each active tool against GHCup's recommended version, falling back to latest.
func ghcupPackages(active: [GHCupRow], available: [GHCupRow], executablePath: String) -> [DeveloperPackage] {
    active.map { row in
        let candidates = available.filter { $0.tool == row.tool }
        let target = candidates.first { $0.tags.contains("recommended") } ?? candidates.first { $0.tags.contains("latest") }
        let latest = target.map { VersionComparator.isNewer($0.version, than: row.version) ? $0.version : row.version } ?? row.version
        return DeveloperPackage(name: row.tool, currentVersion: row.version, latestVersion: latest,
            manager: .ghcup, executablePath: executablePath, registryIdentifier: row.tool)
    }
}

func scanGHCup(_ path: String) async -> ManagerScanResult {
    let executable = URL(fileURLWithPath: path)
    let active = await captureDeveloperStandardOutput(executable, ["--offline", "list", "-r", "-c", "set"])
    guard active.status == 0 else {
        return ManagerScanResult(manager: .ghcup, packages: [], warning: sourceManagerWarning(.ghcup, "inventory", active))
    }
    let rows = parseGHCupRawList(String(decoding: active.data, as: UTF8.self))
    guard !rows.isEmpty else { return ManagerScanResult(manager: .ghcup, packages: [], warning: nil) }
    // Without --offline GHCup refreshes its release metadata (cached for 5 minutes).
    let available = await captureDeveloperStandardOutput(executable, ["list", "-r"])
    let packages = ghcupPackages(active: rows,
        available: available.status == 0 ? parseGHCupRawList(String(decoding: available.data, as: UTF8.self)) : [],
        executablePath: path)
    return ManagerScanResult(manager: .ghcup, packages: packages,
        warning: available.status == 0 ? nil : sourceManagerWarning(.ghcup, "release check", available))
}

// MARK: - swiftly

struct SwiftlyToolchain: Equatable, Sendable {
    let name: String
    let major: Int
    let minor: Int
    let isDefault: Bool
}

/// Stable toolchains from `swiftly list --format json` or
/// `swiftly list-available --format json` (Sources/SwiftlyCore/OutputSchema.swift).
func parseSwiftlyToolchains(_ data: Data) -> [SwiftlyToolchain] {
    struct Output: Decodable {
        struct Toolchain: Decodable {
            struct Version: Decodable { let name: String; let major: Int?; let minor: Int?; let type: String }
            let version: Version
            let isDefault: Bool?
        }
        let toolchains: [Toolchain]
    }
    guard let output = try? JSONDecoder().decode(Output.self, from: jsonPayload(data)) else { return [] }
    return output.toolchains.compactMap {
        guard $0.version.type == "stable", let major = $0.version.major, let minor = $0.version.minor else { return nil }
        return SwiftlyToolchain(name: $0.version.name, major: major, minor: minor, isDefault: $0.isDefault ?? false)
    }
}

/// `swiftly update <toolchain>` moves a stable toolchain to the newest patch of
/// its minor release, so each installed toolchain is compared within its line.
func swiftlyPackages(installed: [SwiftlyToolchain], available: [SwiftlyToolchain], executablePath: String) -> [DeveloperPackage] {
    installed.map { toolchain in
        let newest = available.filter { $0.major == toolchain.major && $0.minor == toolchain.minor }
            .map(\.name).max { VersionComparator.compare($0, $1) == .orderedAscending }
        let latest = newest.map { VersionComparator.isNewer($0, than: toolchain.name) ? $0 : toolchain.name } ?? toolchain.name
        return DeveloperPackage(name: "Swift \(toolchain.major).\(toolchain.minor)", currentVersion: toolchain.name,
            latestVersion: latest, manager: .swiftly, executablePath: executablePath,
            registryIdentifier: toolchain.name, installationContext: toolchain.isDefault ? "Default toolchain" : nil)
    }
}

func scanSwiftly(_ path: String) async -> ManagerScanResult {
    let executable = URL(fileURLWithPath: path)
    let list = await captureDeveloperStandardOutput(executable, ["list", "--format", "json"])
    guard list.status == 0 else {
        return ManagerScanResult(manager: .swiftly, packages: [], warning: sourceManagerWarning(.swiftly, "inventory", list))
    }
    let installed = parseSwiftlyToolchains(list.data)
    guard !installed.isEmpty else { return ManagerScanResult(manager: .swiftly, packages: [], warning: nil) }
    let available = await captureDeveloperStandardOutput(executable, ["list-available", "--format", "json"])
    return ManagerScanResult(manager: .swiftly,
        packages: swiftlyPackages(installed: installed,
            available: available.status == 0 ? parseSwiftlyToolchains(available.data) : [], executablePath: path),
        warning: available.status == 0 ? nil : sourceManagerWarning(.swiftly, "release check", available))
}

// MARK: - Conda

/// conda, Miniforge and Anaconda base installs. `conda` is usually a shell
/// function; `<root>/condabin/conda` runs without shell setup.
func condaExecutables(environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    var candidates = [environment["CONDA_EXE"]].compactMap { $0 }
    candidates += ["miniforge3", "miniconda3", "anaconda3", "mambaforge"].map { "\(home)/\($0)/condabin/conda" }
    candidates += [
        "/opt/homebrew/Caskroom/miniforge/base/condabin/conda",
        "/opt/homebrew/Caskroom/miniconda/base/condabin/conda",
        "/opt/homebrew/anaconda3/condabin/conda",
        "/opt/anaconda3/condabin/conda", "/opt/miniconda3/condabin/conda"
    ]
    var seen = Set<String>()
    return candidates.filter {
        FileManager.default.isExecutableFile(atPath: $0)
            && seen.insert(URL(fileURLWithPath: $0).resolvingSymlinksInPath().path).inserted
    }
}

/// `conda list --json`: a bare array, or `{"packages": [...]}` from mamba 2.9+.
/// pip-installed packages (channel `pypi`) are left to pip.
func parseCondaList(_ data: Data) -> [(name: String, version: String)] {
    struct Record: Decodable { let name: String; let version: String; let channel: String? }
    struct Wrapped: Decodable { let packages: [Record] }
    let payload = jsonPayload(data)
    let records = (try? JSONDecoder().decode([Record].self, from: payload))
        ?? (try? JSONDecoder().decode(Wrapped.self, from: payload))?.packages ?? []
    return records.filter { $0.channel != "pypi" }.map { ($0.name, $0.version) }
}

/// Newer versions from `conda update --all --dry-run --json` (`actions.LINK`).
/// Downgrades proposed by the solver are ignored.
func parseCondaDryRun(_ data: Data, installed: [String: String]) -> [String: String] {
    struct Output: Decodable {
        struct Actions: Decodable { struct Record: Decodable { let name: String; let version: String }; let LINK: [Record]? }
        let actions: Actions?
    }
    guard let links = (try? JSONDecoder().decode(Output.self, from: jsonPayload(data)))?.actions?.LINK else { return [:] }
    var output: [String: String] = [:]
    for link in links {
        guard let current = installed[link.name], VersionComparator.isNewer(link.version, than: current) else { continue }
        output[link.name] = link.version
    }
    return output
}

func scanConda(_ path: String) async -> ManagerScanResult {
    let executable = URL(fileURLWithPath: path)
    let list = await captureDeveloperStandardOutput(executable, ["list", "-n", "base", "--json"])
    guard list.status == 0 else {
        return ManagerScanResult(manager: .conda, packages: [], warning: sourceManagerWarning(.conda, "inventory", list))
    }
    let installed = parseCondaList(list.data)
    let versions = Dictionary(installed.map { ($0.name, $0.version) }, uniquingKeysWith: { first, _ in first })
    let dryRun = await captureDeveloperStandardOutput(executable, ["update", "-n", "base", "--all", "--dry-run", "--json"])
    let updates = dryRun.status == 0 ? parseCondaDryRun(dryRun.data, installed: versions) : [:]
    let packages = installed.map {
        DeveloperPackage(name: $0.name, currentVersion: $0.version, latestVersion: updates[$0.name] ?? $0.version,
            manager: .conda, executablePath: path, registryIdentifier: $0.name, installationContext: "base environment")
    }
    return ManagerScanResult(manager: .conda, packages: packages,
        warning: dryRun.status == 0 ? nil : sourceManagerWarning(.conda, "update check", dryRun))
}

// MARK: - SDKMAN

/// SDKMAN's init script. `sdk` is a bash function sourced from it.
func sdkmanInitScript(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
    let root = environment["SDKMAN_DIR"].flatMap { $0.isEmpty ? nil : $0 }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".sdkman").path
    let script = (root as NSString).appendingPathComponent("bin/sdkman-init.sh")
    return FileManager.default.fileExists(atPath: script) ? script : nil
}

/// The default version per candidate, from `candidates/<name>/current`.
func sdkmanCurrentVersions(root: URL) -> [(candidate: String, version: String)] {
    let candidates = root.appendingPathComponent("candidates", isDirectory: true)
    let names = (try? FileManager.default.contentsOfDirectory(atPath: candidates.path)) ?? []
    return names.sorted().compactMap { name in
        let link = candidates.appendingPathComponent("\(name)/current")
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { return nil }
        let version = URL(fileURLWithPath: target).lastPathComponent
        return version.isEmpty ? nil : (name, version)
    }
}

/// SDKMAN identifiers carry a vendor suffix for some candidates ("21.0.5-tem").
/// A different vendor is a different distribution, not an update.
func sdkmanUpdate(current: String, default latest: String) -> String {
    func split(_ value: String) -> (version: String, vendor: String?) {
        guard let dash = value.lastIndex(of: "-"), value[value.index(after: dash)...].allSatisfy(\.isLetter) else {
            return (value, nil)
        }
        return (String(value[..<dash]), String(value[value.index(after: dash)...]))
    }
    let installed = split(current), available = split(latest)
    guard installed.vendor == available.vendor, VersionComparator.isNewer(available.version, than: installed.version)
    else { return current }
    return latest
}

func scanSDKMAN(_ initScript: String) async -> ManagerScanResult {
    let root = URL(fileURLWithPath: initScript).deletingLastPathComponent().deletingLastPathComponent()
    let values = await withTaskGroup(of: (DeveloperPackage, Bool).self) { group in
        for (candidate, version) in sdkmanCurrentVersions(root: root) {
            group.addTask {
                // The broker answers with the default version as plain text; `sdk upgrade` uses the same call.
                var latest: String?
                if let url = URL(string: "https://api.sdkman.io/2/candidates/default/\(candidate)"),
                   let data = await publicData(url),
                   let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !text.isEmpty, !text.contains(where: \.isWhitespace) {
                    latest = text
                }
                return (DeveloperPackage(name: candidate, currentVersion: version,
                    latestVersion: latest.map { sdkmanUpdate(current: version, default: $0) } ?? version,
                    manager: .sdkman, executablePath: initScript, registryIdentifier: candidate), latest == nil)
            }
        }
        var output: [(DeveloperPackage, Bool)] = []
        for await value in group { output.append(value) }
        return output
    }
    let failures = values.count { $0.1 }
    return ManagerScanResult(manager: .sdkman, packages: values.map(\.0),
        warning: failures == 0 ? nil : "SDKMAN: default-version checks failed for \(failures) candidate\(failures == 1 ? "" : "s").")
}
