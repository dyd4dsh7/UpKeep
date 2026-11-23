import Foundation

// Scanners for pixi, Krew, juliaup, opam, Dart and Poetry. Each command and
// file format here was checked against the real tool: pixi 0.84, Krew 0.5,
// juliaup 1.24, opam 2.6, Dart 3.14 and Poetry 2.5.

/// stdout only. Some tools print progress on stderr ("Using channels: …"),
/// which would break JSON parsing of the combined output.
func captureDeveloperStandardOutput(_ executable: URL, _ arguments: [String]) async -> (data: Data, status: Int32) {
    let environment = developerCommandEnvironment(for: executable, base: ProcessInfo.processInfo.environment)
    do {
        let result = try await CommandRunner.run(executable, arguments, environment: environment,
            directory: developerCommandWorkingDirectory(base: environment), timeout: CommandRunner.deadline(for: arguments))
        return (result.status == 0 ? result.stdout : result.output, result.status)
    } catch { return (Data(error.localizedDescription.utf8), -1) }
}

private func additionalManagerWarning(_ manager: DeveloperPackageManager, _ command: String, _ result: (data: Data, status: Int32)) -> String {
    let output = String(decoding: result.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return "\(manager.rawValue) \(command) failed: \(output.isEmpty ? "command exited with status \(result.status)" : String(output.prefix(400)))"
}

private func environmentPath(_ name: String) -> URL? {
    guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else { return nil }
    return URL(fileURLWithPath: (value as NSString).expandingTildeInPath, isDirectory: true)
}

private var homeDirectory: URL { FileManager.default.homeDirectoryForCurrentUser }

private func fetchRegistryData(_ url: URL) async -> Data? {
    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    request.setValue("Upkeep/1.0", forHTTPHeaderField: "User-Agent")
    return await RegistryRequestCache.shared.data(for: request, key: "GET:\(url.absoluteString)")
}

// MARK: - pixi

struct PixiGlobalEnvironment: Equatable, Sendable {
    struct Dependency: Equatable, Sendable { let name: String; let version: String }
    let name: String
    let dependencies: [Dependency]
}

/// `pixi global list --json`.
func parsePixiGlobalList(_ data: Data) -> [PixiGlobalEnvironment] {
    struct Environment: Decodable {
        struct Dependency: Decodable { let name: String; let version: String }
        let name: String
        let dependencies: [Dependency]?
    }
    guard let environments = try? JSONDecoder().decode([Environment].self, from: data) else { return [] }
    return environments.map {
        PixiGlobalEnvironment(name: $0.name, dependencies: ($0.dependencies ?? []).map { .init(name: $0.name, version: $0.version) })
    }
}

/// Channels and dependency specs from `manifests/pixi-global.toml`. Only the
/// simple forms pixi writes (`channels = [...]`, `dependencies = { a = "*" }`) are read.
struct PixiManifestEnvironment: Equatable, Sendable {
    var channels: [String] = []
    var specs: [String: String] = [:]
}

func parsePixiGlobalManifest(_ text: String) -> [String: PixiManifestEnvironment] {
    var environments: [String: PixiManifestEnvironment] = [:]
    var current: String?
    var inDependencyTable = false
    func strings(_ value: Substring) -> [String] {
        value.split(separator: ",").compactMap {
            let item = $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t[]\""))
            return item.isEmpty ? nil : item
        }
    }
    func pairs(_ value: Substring) -> [(String, String)] {
        value.split(separator: ",").compactMap { pair in
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let key = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: " \t{}\""))
            let spec = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " \t{}\""))
            return key.isEmpty ? nil : (key, spec)
        }
    }
    for raw in text.split(whereSeparator: \.isNewline) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("[") {
            inDependencyTable = false
            let header = line.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            let parts = header.split(separator: ".").map(String.init)
            guard parts.first == "envs", parts.count >= 2 else { current = nil; continue }
            current = parts[1]
            environments[parts[1], default: .init()] = environments[parts[1]] ?? .init()
            inDependencyTable = parts.count == 3 && parts[2] == "dependencies"
            continue
        }
        guard let environment = current, let equals = line.firstIndex(of: "=") else { continue }
        let key = line[..<equals].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: equals)...]
        if inDependencyTable {
            environments[environment]?.specs[key.trimmingCharacters(in: CharacterSet(charactersIn: "\""))] =
                value.trimmingCharacters(in: CharacterSet(charactersIn: " \t\""))
        } else if key == "channels" {
            environments[environment]?.channels = strings(value)
        } else if key == "dependencies" {
            for (name, spec) in pairs(value) { environments[environment]?.specs[name] = spec }
        }
    }
    return environments
}

/// Newest version in `pixi search --json` output for one platform.
func parsePixiSearchLatest(_ data: Data, platform: String) -> String? {
    struct Record: Decodable { let version: String }
    guard let platforms = try? JSONDecoder().decode([String: [Record]].self, from: data) else { return nil }
    let versions = (platforms[platform] ?? []) + (platforms["noarch"] ?? [])
    return VersionComparator.sortedNewestFirst(Set(versions.map(\.version))).first
}

private var pixiPlatform: String {
    #if arch(arm64)
    "osx-arm64"
    #else
    "osx-64"
    #endif
}

func scanPixiGlobal(_ path: String) async -> ManagerScanResult {
    let executable = URL(fileURLWithPath: path)
    let list = await captureDeveloperStandardOutput(executable, ["global", "list", "--json"])
    guard list.status == 0 else {
        return ManagerScanResult(manager: .pixi, packages: [], warning: additionalManagerWarning(.pixi, "global inventory", list))
    }
    let manifestURL = (environmentPath("PIXI_HOME") ?? homeDirectory.appendingPathComponent(".pixi"))
        .appendingPathComponent("manifests/pixi-global.toml")
    let manifest = parsePixiGlobalManifest((try? String(contentsOf: manifestURL, encoding: .utf8)) ?? "")
    let rows = parsePixiGlobalList(list.data).flatMap { environment in
        environment.dependencies.map { (environment: environment, dependency: $0) }
    }
    let values = await withTaskGroup(of: (DeveloperPackage, Bool).self) { group in
        for row in rows {
            group.addTask {
                let settings = manifest[row.environment.name] ?? .init()
                let spec = settings.specs[row.dependency.name] ?? "*"
                var latest = row.dependency.version
                var failed = false
                // A pinned spec cannot move, so only unconstrained dependencies are compared.
                if spec == "*" {
                    let channels = settings.channels.isEmpty ? ["conda-forge"] : settings.channels
                    let search = await captureDeveloperStandardOutput(executable,
                        ["search", row.dependency.name, "--json", "--platform", pixiPlatform]
                            + channels.flatMap { ["--channel", $0] })
                    if search.status == 0, let found = parsePixiSearchLatest(search.data, platform: pixiPlatform) {
                        latest = found
                    } else {
                        failed = true
                    }
                }
                return (DeveloperPackage(
                    name: row.dependency.name, currentVersion: row.dependency.version, latestVersion: latest,
                    manager: .pixi, executablePath: path,
                    registryIdentifier: "\(row.environment.name)/\(row.dependency.name)",
                    installationContext: row.environment.name == row.dependency.name ? nil : "pixi environment \(row.environment.name)",
                    canUpdateAutomatically: spec == "*"
                ), failed)
            }
        }
        var output: [(DeveloperPackage, Bool)] = []
        for await value in group { output.append(value) }
        return output
    }
    let failures = values.count { $0.1 }
    return ManagerScanResult(manager: .pixi, packages: values.map(\.0),
        warning: failures == 0 ? nil : "pixi: channel checks failed for \(failures) package\(failures == 1 ? "" : "s").")
}

// MARK: - Krew

struct KrewReceipt: Equatable, Sendable {
    let name: String
    let version: String
    let index: String
}

/// A Krew receipt or index manifest: `metadata.name`, `spec.version`, `status.source.name`.
func parseKrewManifest(_ text: String) -> KrewReceipt? {
    var section = ""
    var subsection = ""
    var name: String?, version: String?, index = "default"
    for raw in text.split(whereSeparator: \.isNewline) {
        let line = String(raw)
        let indent = line.prefix { $0 == " " }.count
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let colon = trimmed.firstIndex(of: ":") else { continue }
        let key = String(trimmed[..<colon])
        let value = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
        if indent == 0 { section = key; subsection = ""; continue }
        if indent == 2 { subsection = key }
        switch (section, indent, key) {
        case ("metadata", 2, "name"): name = value
        case ("spec", 2, "version"): version = value
        case ("status", 4, "name") where subsection == "source": index = value
        default: break
        }
    }
    guard let name, let version, !name.isEmpty, !version.isEmpty else { return nil }
    return KrewReceipt(name: name, version: version, index: index)
}

func scanKrewPlugins(_ path: String) async -> ManagerScanResult {
    let root = environmentPath("KREW_ROOT") ?? homeDirectory.appendingPathComponent(".krew")
    let receiptsURL = root.appendingPathComponent("receipts", isDirectory: true)
    let files = ((try? FileManager.default.contentsOfDirectory(at: receiptsURL, includingPropertiesForKeys: nil)) ?? [])
        .filter { $0.pathExtension == "yaml" }
    let receipts = files.compactMap { (try? String(contentsOf: $0, encoding: .utf8)).flatMap(parseKrewManifest) }
    let values = await withTaskGroup(of: (DeveloperPackage, Bool).self) { group in
        for receipt in receipts {
            group.addTask {
                let latest: String?
                if receipt.index == "default" {
                    // The public index is what `kubectl krew update` pulls.
                    let url = URL(string: "https://raw.githubusercontent.com/kubernetes-sigs/krew-index/master/plugins/\(receipt.name).yaml")
                    latest = await url.asyncFlatMap { await fetchRegistryData($0) }
                        .flatMap { String(data: $0, encoding: .utf8) }.flatMap(parseKrewManifest)?.version
                } else {
                    let local = root.appendingPathComponent("index/\(receipt.index)/plugins/\(receipt.name).yaml")
                    latest = (try? String(contentsOf: local, encoding: .utf8)).flatMap(parseKrewManifest)?.version
                }
                let identifier = receipt.index == "default" ? receipt.name : "\(receipt.index)/\(receipt.name)"
                return (DeveloperPackage(
                    name: receipt.name, currentVersion: receipt.version, latestVersion: latest ?? receipt.version,
                    manager: .krew, executablePath: path, registryIdentifier: identifier,
                    installationContext: receipt.index == "default" ? nil : "Index \(receipt.index)"
                ), latest == nil)
            }
        }
        var output: [(DeveloperPackage, Bool)] = []
        for await value in group { output.append(value) }
        return output
    }
    let failures = values.count { $0.1 }
    return ManagerScanResult(manager: .krew, packages: values.map(\.0),
        warning: failures == 0 ? nil : "Krew: index checks failed for \(failures) plugin\(failures == 1 ? "" : "s").")
}

private extension Optional {
    func asyncFlatMap<T>(_ transform: (Wrapped) async -> T?) async -> T? {
        guard let value = self else { return nil }
        return await transform(value)
    }
}

// MARK: - juliaup

struct JuliaupChannel: Equatable, Sendable {
    let channel: String
    let installed: String
    let latest: String
}

/// "1.10.14+0.aarch64.apple.darwin14" → "1.10.14".
func juliaVersion(_ value: String) -> String {
    String(value.split(separator: "+", maxSplits: 1).first ?? Substring(value))
}

/// `juliaup.json` installed channels against the version database juliaup
/// keeps up to date. Linked channels (a custom command) are skipped.
func parseJuliaupChannels(configuration: Data, versionDatabase: Data?) -> [JuliaupChannel] {
    struct Configuration: Decodable {
        struct Channel: Decodable { let Version: String? }
        let InstalledChannels: [String: Channel]?
    }
    struct Database: Decodable {
        struct Channel: Decodable { let Version: String }
        let AvailableChannels: [String: Channel]?
    }
    guard let channels = (try? JSONDecoder().decode(Configuration.self, from: configuration))?.InstalledChannels else { return [] }
    let available = versionDatabase.flatMap { try? JSONDecoder().decode(Database.self, from: $0) }?.AvailableChannels ?? [:]
    return channels.compactMap { name, channel in
        guard let installed = channel.Version else { return nil }
        return JuliaupChannel(channel: name, installed: installed, latest: available[name]?.Version ?? installed)
    }.sorted { $0.channel.localizedStandardCompare($1.channel) == .orderedAscending }
}

func scanJuliaup(_ path: String) async -> ManagerScanResult {
    let root = environmentPath("JULIAUP_DEPOT_PATH")?.appendingPathComponent("juliaup")
        ?? homeDirectory.appendingPathComponent(".julia/juliaup")
    guard let configuration = try? Data(contentsOf: root.appendingPathComponent("juliaup.json")) else {
        return ManagerScanResult(manager: .juliaup, packages: [], warning: nil)
    }
    let database = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
        .first { $0.lastPathComponent.hasPrefix("versiondb-") && $0.pathExtension == "json" }
        .flatMap { try? Data(contentsOf: $0) }
    let packages = parseJuliaupChannels(configuration: configuration, versionDatabase: database).map {
        DeveloperPackage(
            name: "Julia \($0.channel)", currentVersion: juliaVersion($0.installed), latestVersion: juliaVersion($0.latest),
            manager: .juliaup, executablePath: path, registryIdentifier: $0.channel
        )
    }
    return ManagerScanResult(manager: .juliaup, packages: packages, warning: nil)
}

// MARK: - opam

/// `opam list --installed --roots --columns=name,installed-version --color=never`.
/// Compiler and `base` compatibility packages are left out.
func parseOpamRoots(_ text: String) -> [(name: String, version: String)] {
    let compilerPackages: Set<String> = ["ocaml", "ocaml-system", "ocaml-base-compiler", "ocaml-variants", "ocaml-config"]
    return text.split(whereSeparator: \.isNewline).compactMap { line in
        guard !line.hasPrefix("#") else { return nil }
        let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count >= 2, fields[1] != "base", !compilerPackages.contains(fields[0]),
              !fields[0].hasPrefix("ocaml-option-"), !fields[0].hasPrefix("base-") else { return nil }
        return (fields[0], fields[1])
    }
}

/// New versions from `opam upgrade --dry-run --json=<file>`. opam writes an
/// upgrade as `{"change": ["up", old, new]}` or as a remove/install pair.
func parseOpamUpgradeSolution(_ data: Data) -> [String: String] {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let solution = root["solution"] as? [[String: Any]] else { return [:] }
    func package(_ value: Any?) -> (String, String)? {
        guard let object = value as? [String: Any], let name = object["name"] as? String,
              let version = object["version"] as? String else { return nil }
        return (name, version)
    }
    var output: [String: String] = [:]
    for action in solution {
        if let change = action["change"] as? [Any], change.count == 3, change[0] as? String == "up",
           let (name, version) = package(change[2]) {
            output[name] = version
        } else if let (name, version) = package(action["install"]) {
            output[name] = version
        }
    }
    return output
}

func scanOpamPackages(_ path: String) async -> ManagerScanResult {
    let root = environmentPath("OPAMROOT") ?? homeDirectory.appendingPathComponent(".opam")
    guard FileManager.default.fileExists(atPath: root.path) else {
        return ManagerScanResult(manager: .opam, packages: [], warning: nil)
    }
    let executable = URL(fileURLWithPath: path)
    let list = await captureDeveloperStandardOutput(executable,
        ["list", "--installed", "--roots", "--columns=name,installed-version", "--color=never"])
    guard list.status == 0 else {
        return ManagerScanResult(manager: .opam, packages: [], warning: additionalManagerWarning(.opam, "inventory", list))
    }
    let roots = parseOpamRoots(String(decoding: list.data, as: UTF8.self))
    guard !roots.isEmpty else { return ManagerScanResult(manager: .opam, packages: [], warning: nil) }
    // The dry run plans what `opam upgrade` would do from opam's last `opam update`.
    let solutionURL = FileManager.default.temporaryDirectory.appendingPathComponent("Upkeep-opam-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: solutionURL) }
    let upgrade = await captureDeveloperStandardOutput(executable,
        ["upgrade", "--dry-run", "-y", "--color=never", "--json=\(solutionURL.path)"])
    let latest = upgrade.status == 0 ? parseOpamUpgradeSolution((try? Data(contentsOf: solutionURL)) ?? Data()) : [:]
    let packages = roots.map {
        DeveloperPackage(name: $0.name, currentVersion: $0.version, latestVersion: latest[$0.name] ?? $0.version,
            manager: .opam, executablePath: path, registryIdentifier: $0.name)
    }
    return ManagerScanResult(manager: .opam, packages: packages,
        warning: upgrade.status == 0 ? nil : additionalManagerWarning(.opam, "upgrade check", upgrade))
}

// MARK: - Dart

/// `dart pub global list`: "name version". Git and path activations are left
/// out because pub.dev does not describe them.
func parseDartGlobalList(_ text: String) -> [(name: String, version: String)] {
    text.split(whereSeparator: \.isNewline).compactMap { line in
        let fields = line.split(separator: " ").map(String.init)
        guard fields.count == 2, fields[1].first?.isNumber == true else { return nil }
        return (fields[0], fields[1])
    }
}

func pubDevVersions(_ package: String) async -> [String] {
    struct Response: Decodable {
        struct Version: Decodable { let version: String; let retracted: Bool? }
        let versions: [Version]
    }
    guard let encoded = package.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
          let url = URL(string: "https://pub.dev/api/packages/\(encoded)"),
          let data = await fetchRegistryData(url),
          let response = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
    return VersionComparator.sortedNewestFirst(Set(response.versions.filter { $0.retracted != true }.map(\.version)))
}

func scanDartGlobalPackages(_ path: String) async -> ManagerScanResult {
    let list = await captureDeveloperStandardOutput(URL(fileURLWithPath: path), ["pub", "global", "list"])
    guard list.status == 0 else {
        return ManagerScanResult(manager: .dart, packages: [], warning: additionalManagerWarning(.dart, "global inventory", list))
    }
    let values = await withTaskGroup(of: (DeveloperPackage, Bool).self) { group in
        for (name, version) in parseDartGlobalList(String(decoding: list.data, as: UTF8.self)) {
            group.addTask {
                let versions = await pubDevVersions(name)
                let latest = versions.first { !VersionComparator.isPrerelease($0) } ?? versions.first
                return (DeveloperPackage(name: name, currentVersion: version, latestVersion: latest ?? version,
                    manager: .dart, executablePath: path, registryIdentifier: name), versions.isEmpty)
            }
        }
        var output: [(DeveloperPackage, Bool)] = []
        for await value in group { output.append(value) }
        return output
    }
    let failures = values.count { $0.1 }
    return ManagerScanResult(manager: .dart, packages: values.map(\.0),
        warning: failures == 0 ? nil : "Dart: pub.dev checks failed for \(failures) package\(failures == 1 ? "" : "s").")
}

// MARK: - Poetry

/// Poetry from the official installer manages itself with `poetry self update`.
/// Homebrew, pipx and uv copies are updated by those managers instead.
func officialPoetryExecutables() -> [String] {
    var candidates: [URL] = []
    if let home = environmentPath("POETRY_HOME") { candidates.append(home.appendingPathComponent("venv/bin/poetry")) }
    candidates.append(homeDirectory.appendingPathComponent("Library/Application Support/pypoetry/venv/bin/poetry"))
    return candidates.map(\.path).filter { FileManager.default.isExecutableFile(atPath: $0) }
}

/// "Poetry (version 2.5.2)" → "2.5.2".
func parsePoetryVersion(_ text: String) -> String? {
    guard let range = text.range(of: #"version\s+([0-9][^\s)]*)"#, options: .regularExpression) else { return nil }
    return String(text[range]).split(whereSeparator: \.isWhitespace).last.map(String.init)
}

func scanPoetry(_ path: String) async -> ManagerScanResult {
    let result = await captureDeveloperStandardOutput(URL(fileURLWithPath: path), ["--version", "--no-ansi"])
    guard result.status == 0, let version = parsePoetryVersion(String(decoding: result.data, as: UTF8.self)) else {
        return ManagerScanResult(manager: .poetry, packages: [], warning: additionalManagerWarning(.poetry, "version check", result))
    }
    let latest = await pyPIStableVersion("poetry")
    return ManagerScanResult(manager: .poetry, packages: [
        DeveloperPackage(name: "Poetry", currentVersion: version, latestVersion: latest ?? version,
            manager: .poetry, executablePath: path, registryIdentifier: "poetry")
    ], warning: latest == nil ? "Poetry: the PyPI check failed." : nil)
}

private func pyPIStableVersion(_ package: String) async -> String? {
    struct Response: Decodable { struct Info: Decodable { let version: String }; let info: Info }
    guard let url = URL(string: "https://pypi.org/pypi/\(package)/json"),
          let data = await fetchRegistryData(url) else { return nil }
    return (try? JSONDecoder().decode(Response.self, from: data))?.info.version
}

// MARK: - Claude Code (native installer)

/// The native installer links `~/.local/bin/claude` to a build in
/// `~/.local/share/claude/versions/<version>`. npm and Homebrew installs are
/// covered by those managers.
func claudeCodeNativeLauncher(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
    let launcher = home.appendingPathComponent(".local/bin/claude").path
    guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: launcher),
          claudeCodeNativeVersion(linkTarget: target) != nil else { return nil }
    return launcher
}

/// ".../.local/share/claude/versions/2.1.330" → "2.1.330".
func claudeCodeNativeVersion(linkTarget: String) -> String? {
    let url = URL(fileURLWithPath: linkTarget)
    guard url.deletingLastPathComponent().path.hasSuffix(".local/share/claude/versions") else { return nil }
    let version = url.lastPathComponent
    return version.first?.isNumber == true ? version : nil
}

/// `autoUpdatesChannel` in Claude Code's settings: "latest" (the default when
/// unset), "stable", or "rc", which has no published pointer.
func claudeCodeUpdateChannel(settings: Data?) -> String {
    guard let settings,
          let object = try? JSONSerialization.jsonObject(with: settings) as? [String: Any],
          let channel = object["autoUpdatesChannel"] as? String, !channel.isEmpty else { return "latest" }
    return channel
}

func scanClaudeCode(_ path: String) async -> ManagerScanResult {
    guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path),
          let version = claudeCodeNativeVersion(linkTarget: target) else {
        return ManagerScanResult(manager: .claudeCode, packages: [], warning: nil)
    }
    let configuration = environmentPath("CLAUDE_CONFIG_DIR") ?? homeDirectory.appendingPathComponent(".claude")
    let channel = claudeCodeUpdateChannel(settings: try? Data(contentsOf: configuration.appendingPathComponent("settings.json")))
    var latest: String?
    if ["latest", "stable"].contains(channel),
       let url = URL(string: "https://downloads.claude.ai/claude-code-releases/\(channel)"),
       let data = await fetchRegistryData(url),
       let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
       text.first?.isNumber == true, !text.contains(where: \.isWhitespace) {
        latest = text
    }
    // A build newer than the channel (for example latest while following stable) stays put.
    let offered = latest.map { VersionComparator.isNewer($0, than: version) ? $0 : version } ?? version
    return ManagerScanResult(manager: .claudeCode, packages: [
        DeveloperPackage(name: "Claude Code", currentVersion: version, latestVersion: offered,
            manager: .claudeCode, executablePath: path, registryIdentifier: "claude-code",
            installationContext: "\(channel.capitalized) channel")
    ], warning: latest == nil && channel != "rc" ? "Claude Code: the release check failed." : nil)
}
