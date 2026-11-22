import Darwin
import Foundation

struct HomebrewClient: Sendable {
    /// Inspects services for the current user without starting or stopping them.
    func services() async throws -> [HomebrewService] {
        guard let brew = Self.brewURL else { throw BrewError.failed("Homebrew is unavailable.") }
        let data = try await run(brew, ["services", "list", "--json"])
        do {
            return try JSONDecoder().decode([HomebrewService].self, from: data)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            throw BrewError.failed("Homebrew service inventory could not be read: \(error.localizedDescription)")
        }
    }

    func inventory(includePrereleases: Bool = false) async throws -> [HomebrewPackage] {
        guard let brew = Self.brewURL else { return [] }
        let data = try await runWithRetry(brew, ["info", "--json=v2", "--installed"])
        let response: InfoResponse
        do { response = try JSONDecoder().decode(InfoResponse.self, from: data) }
        catch { throw BrewError.failed("Homebrew inventory could not be read: \(error.localizedDescription)") }

        return packages(from: response, includePrereleases: includePrereleases)
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// Reads metadata for one installed token instead of loading the full Homebrew inventory.
    func package(
        token: String,
        kind: HomebrewPackageKind,
        includePrereleases: Bool = false
    ) async throws -> HomebrewPackage? {
        guard let brew = Self.brewURL else { return nil }
        var arguments = ["info", "--json=v2"]
        if kind == .cask { arguments.append("--cask") }
        arguments.append(token)
        let data = try await runWithRetry(brew, arguments)
        let response: InfoResponse
        do { response = try JSONDecoder().decode(InfoResponse.self, from: data) }
        catch { throw BrewError.failed("Homebrew package data could not be read: \(error.localizedDescription)") }
        return packages(from: response, includePrereleases: includePrereleases)
            .first { $0.kind == kind && $0.token == token }
    }

    func caskCatalog() async throws -> [CatalogCask] {
        guard Self.brewURL != nil, let catalogURL = URL(string: "https://formulae.brew.sh/api/cask.json") else { return [] }
        if let cached = cachedCaskCatalog(maximumAge: 6 * 60 * 60) { return cached }
        do {
            var request = URLRequest(url: catalogURL)
            request.timeoutInterval = 30
            request.cachePolicy = .returnCacheDataElseLoad
            request.setValue("Upkeep/0.2", forHTTPHeaderField: "User-Agent")
            let (data, http) = try await PublisherHTTPClient.data(for: request)
            guard 200..<300 ~= http.statusCode else { throw UpdateSourceError.httpStatus(http.statusCode) }
            let catalog: [CatalogCask]
            do { catalog = try JSONDecoder().decode([CatalogCask].self, from: data) }
            catch { throw UpdateSourceError.malformedData(error.localizedDescription) }
            cacheCaskCatalog(catalog)
            return catalog
        } catch {
            throw UpdateSourceError(error)
        }
    }

    static func adoptableApps(
        from apps: [InstalledApp],
        catalog: [CatalogCask],
        excluding packages: [HomebrewPackage]
    ) -> [AdoptableApp] {
        let installedTokens = Set(packages.lazy.filter { $0.kind == .cask }.map(\.token))
        var catalogIndexByName: [String: Int] = [:]
        catalogIndexByName.reserveCapacity(catalog.count * 2)
        for (index, cask) in catalog.enumerated() {
            guard !installedTokens.contains(cask.token),
                  !cask.token.hasPrefix("font-"),
                  !cask.autoUpdates
            else { continue }
            // Preserve the API's first-match behavior when aliases collide.
            for name in cask.name {
                let key = normalize(name)
                if catalogIndexByName[key] == nil { catalogIndexByName[key] = index }
            }
            for appName in cask.artifactAppNames {
                let key = normalize(
                    URL(fileURLWithPath: appName).deletingPathExtension().lastPathComponent
                )
                if catalogIndexByName[key] == nil { catalogIndexByName[key] = index }
            }
            let tokenKey = normalize(cask.token)
            if catalogIndexByName[tokenKey] == nil { catalogIndexByName[tokenKey] = index }
        }
        return apps.compactMap { app in
            guard app.allowsHomebrewAdoption else { return nil }
            guard let index = catalogIndexByName[normalize(app.name)] else { return nil }
            let cask = catalog[index]
            return AdoptableApp(app: app, caskToken: cask.token, caskVersion: cask.version)
        }.sorted { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending }
    }

    func upgrade(_ package: HomebrewPackage) async throws {
        var arguments = ["upgrade"]
        if package.kind == .cask { arguments.append("--cask") }
        arguments.append(package.token)
        try await execute(arguments)
    }

    func upgradeAll() async throws { try await execute(["upgrade"]) }

    func adopt(_ item: AdoptableApp) async throws {
        let arguments = ["install", "--cask", "--adopt", item.caskToken]
        do {
            try await execute(arguments)
        } catch let error as BrewError {
            guard case let .failed(message) = error,
                  BrewError.requiresAdoptionPermissionRepair(message),
                  let brew = Self.brewURL
            else { throw error }

            _ = try await runInTerminal(brew, arguments, permissionRepairURL: item.app.url)
        }
    }

    func installOrReplace(_ item: AdoptableApp) async throws {
        try await execute(["install", "--cask", "--force", item.caskToken])
    }

    func upgradeCask(token: String) async throws {
        try await execute(["upgrade", "--cask", token])
    }

    private func execute(_ arguments: [String]) async throws {
        guard let brew = Self.brewURL else { throw BrewError.notInstalled }
        do {
            _ = try await runWithRetry(brew, arguments)
        } catch let error as BrewError {
            guard case let .failed(message) = error,
                  BrewError.requiresInteractiveAuthorization(message)
            else { throw error }
            _ = try await runInTerminal(brew, arguments)
        }
    }

    static var brewURL: URL? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    enum BrewError: LocalizedError {
        case notInstalled
        case failed(String)
        var errorDescription: String? {
            switch self {
            case .notInstalled: "Homebrew is not installed."
            case let .failed(message): message
            }
        }

        static func isConcurrentCommandFailure(_ message: String) -> Bool {
            let value = message.lowercased()
            return value.contains("another active homebrew")
                || value.contains("already locked")
                || value.contains("could not acquire a lock")
                || value.contains("lock is held")
        }

        static func requiresInteractiveAuthorization(_ message: String) -> Bool {
            let value = message.lowercased()
            return value.contains("sudo: a terminal is required")
                || value.contains("sudo: no tty present")
                || (value.contains("sudo:") && value.contains("password is required"))
        }

        static func requiresAdoptionPermissionRepair(_ message: String) -> Bool {
            let value = message.lowercased()
            return value.contains("chmod")
                && value.contains("operation not permitted")
                && (value.contains("adopting existing app") || value.contains("/applications/"))
        }
    }
}

private func caskCatalogCacheURL() -> URL? {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Upkeep/Homebrew", isDirectory: true)
        .appendingPathComponent("cask-catalog-slim.json")
}

/// The cask catalog API is about 20 MB; Upkeep needs five fields per cask.
/// The cache stores only those fields (about 1 MB) and keeps the decoded
/// catalog in memory until the file changes, so scans neither re-read nor
/// re-decode the full catalog.
struct SlimCaskCatalog: Codable {
    static let currentFormat = 1
    let format: Int
    let casks: [Entry]

    struct Entry: Codable {
        let t: String
        let n: [String]
        let v: String
        let a: Bool?
        let apps: [String]?
    }

    init(_ catalog: [CatalogCask]) {
        format = Self.currentFormat
        casks = catalog.map {
            Entry(t: $0.token, n: $0.name, v: $0.version, a: $0.autoUpdates ? true : nil,
                  apps: $0.artifactAppNames.isEmpty ? nil : $0.artifactAppNames)
        }
    }

    var catalog: [CatalogCask] {
        casks.map { CatalogCask(token: $0.t, name: $0.n, version: $0.v, autoUpdates: $0.a ?? false, artifactAppNames: $0.apps ?? []) }
    }

    static func decode(_ data: Data) -> [CatalogCask]? {
        guard let value = try? JSONDecoder().decode(SlimCaskCatalog.self, from: data),
              value.format == currentFormat else { return nil }
        return value.catalog
    }
}

private final class DecodedCaskCatalog: @unchecked Sendable {
    static let shared = DecodedCaskCatalog()
    private let lock = NSLock()
    private var value: (modified: Date, size: Int, catalog: [CatalogCask])?

    func catalog(modified: Date, size: Int) -> [CatalogCask]? {
        lock.withLock {
            guard let value, value.modified == modified, value.size == size else { return nil }
            return value.catalog
        }
    }

    func store(_ catalog: [CatalogCask], modified: Date, size: Int) {
        lock.withLock { value = (modified, size, catalog) }
    }
}

private func cachedCaskCatalog(maximumAge: TimeInterval) -> [CatalogCask]? {
    guard let url = caskCatalogCacheURL(),
          let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
          let modified = attributes[.modificationDate] as? Date,
          let size = attributes[.size] as? NSNumber,
          size.intValue <= PublisherHTTPClient.metadataLimit,
          Date().timeIntervalSince(modified) <= maximumAge else { return nil }
    if let decoded = DecodedCaskCatalog.shared.catalog(modified: modified, size: size.intValue) { return decoded }
    guard let data = try? Data(contentsOf: url), let catalog = SlimCaskCatalog.decode(data) else { return nil }
    DecodedCaskCatalog.shared.store(catalog, modified: modified, size: size.intValue)
    return catalog
}

private func cacheCaskCatalog(_ catalog: [CatalogCask]) {
    guard let url = caskCatalogCacheURL(), let data = try? JSONEncoder().encode(SlimCaskCatalog(catalog)) else { return }
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        // The previous cache stored the full API response; it is no longer read.
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent().appendingPathComponent("cask-catalog.json"))
    } catch {
        // Catalog caching is an optimization; the fresh result remains usable.
    }
}

private func runWithRetry(_ executable: URL, _ arguments: [String]) async throws -> Data {
    let delays: [UInt64] = [1, 2, 4]
    for attempt in 0...delays.count {
        do { return try await run(executable, arguments) }
        catch let error as HomebrewClient.BrewError {
            guard case let .failed(message) = error,
                  HomebrewClient.BrewError.isConcurrentCommandFailure(message),
                  attempt < delays.count
            else { throw error }
            DiagnosticsStore.shared.record(.warning, category: .command, "Homebrew command is busy; retrying", metadata: [
                "Command": "brew " + arguments.joined(separator: " "),
                "Attempt": "\(attempt + 1)",
                "Retry delay": "\(delays[attempt])s",
                "Output": message
            ])
            try await Task.sleep(nanoseconds: delays[attempt] * 1_000_000_000)
        }
    }
    throw HomebrewClient.BrewError.failed("Homebrew did not become available after retrying.")
}

private func run(_ executable: URL, _ arguments: [String]) async throws -> Data {
    let startedAt = Date()
    let command = "brew " + arguments.joined(separator: " ")
    do {
        let result = try await CommandRunner.run(executable, arguments, timeout: CommandRunner.deadline(for: arguments))
        var metadata = ["Command": command, "Exit status": "\(result.status)",
                        "Duration": formattedDiagnosticDuration(since: startedAt), "Output bytes": "\(result.output.count)"]
        if arguments.first != "info" || result.status != 0 {
            metadata["Output"] = String(decoding: result.output.prefix(1_200), as: UTF8.self)
        }
        DiagnosticsStore.shared.record(result.status == 0 ? .info : .error, category: .command,
            "Homebrew command \(result.status == 0 ? "completed" : "failed")", metadata: metadata)
        guard result.status == 0 else {
            throw HomebrewClient.BrewError.failed(String(decoding: result.output, as: UTF8.self))
        }
        return result.output
    } catch {
        DiagnosticsStore.shared.record(.error, category: .command, "Homebrew command failed", metadata: [
            "Command": command, "Duration": formattedDiagnosticDuration(since: startedAt), "Error": error.localizedDescription
        ])
        throw error
    }
}

private func runInTerminal(
    _ executable: URL,
    _ arguments: [String],
    permissionRepairURL: URL? = nil
) async throws -> Data {
    let commandLog = OperationCommandLogContext.current
    let cancellation = CommandRunner.Cancellation()
    return try await awaitingInteractiveCommand(onCancellation: {
        cancellation.cancel()
        commandLog?.append("Cancellation requested. Waiting for the dedicated Terminal command group to stop before releasing the install reservation.")
    }) {
        try await runInTerminalUntilCompletion(executable, arguments, permissionRepairURL: permissionRepairURL,
                                              cancellation: cancellation)
    }
}

private func runInTerminalUntilCompletion(
    _ executable: URL,
    _ arguments: [String],
    permissionRepairURL: URL?, cancellation: CommandRunner.Cancellation
) async throws -> Data {
    let fileManager = FileManager.default
    let directory = fileManager.temporaryDirectory
        .appendingPathComponent("Upkeep-Homebrew-\(UUID().uuidString)", isDirectory: true)
    let outputURL = directory.appendingPathComponent("output.log")
    let statusURL = directory.appendingPathComponent("status")
    let processIDURL = directory.appendingPathComponent("pid")
    let scriptURL = directory.appendingPathComponent("command.zsh")
    let launchFence = TerminalLaunchFence(url: directory.appendingPathComponent("launch-cancelled"),
                                          processIDURL: processIDURL)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    let commandLog = OperationCommandLogContext.current
    var commandStopped = false
    defer {
        if !commandStopped || (try? TerminalCommandFiles.removeCompletedWorkspace(directory, statusURL: statusURL)) != true {
            commandLog?.append("Terminal result unavailable; command files retained at \(directory.path). The command may still be running. Review Terminal before retrying.")
            DiagnosticsStore.shared.record(.warning, category: .command,
                "Terminal command files retained because completion is unverified",
                metadata: ["Location": directory.path])
        }
    }
    commandLog?.append("Terminal command: " + executable.lastPathComponent + " " + arguments.joined(separator: " "))
    defer { commandLog?.appendTerminalOutput(outputURL: outputURL, statusURL: statusURL) }

    let command = ([executable.path] + arguments).map(shellQuote).joined(separator: " ")
    guard fileManager.isExecutableFile(atPath: TerminalOutputRelay.executable.path) else {
        throw HomebrewClient.BrewError.failed("The system command-output relay is unavailable. Run this update manually in Terminal.")
    }
    func relay(append: Bool) -> String {
        ([TerminalOutputRelay.executable.path] + TerminalOutputRelay.arguments(output: outputURL, append: append))
            .map(shellQuote).joined(separator: " ")
    }
    let pipelineStatus = TerminalOutputRelay.pipelineStatus
    let permissionRepair: String
    if let permissionRepairURL {
        permissionRepair = """
        print "Homebrew could not adjust permissions inside the existing app."
        print "Upkeep will repair only that app bundle, then retry adoption."
        print
        /usr/bin/sudo /bin/chmod -R a+rX \(shellQuote(permissionRepairURL.path)) 2>&1 | \(relay(append: false))
        \(pipelineStatus)
        if (( upkeep_status != 0 )); then
          print -r -- "$upkeep_status" > \(shellQuote(statusURL.path))
          print
          print "Permission repair failed with status $upkeep_status. You can close this window."
          exit $upkeep_status
        fi
        print
        print "Permissions repaired. Retrying Homebrew adoption…"
        print
        """
    } else {
        permissionRepair = ""
    }

    let commandScript = """
    setopt NO_MONITOR
    set -o pipefail
    typeset -i upkeep_status=1
    \(launchFence.scriptPreamble(statusURL: statusURL))
    trap 'print -r -- "$upkeep_status" > \(shellQuote(statusURL.path))' EXIT HUP INT TERM
    print
    print "Upkeep needs administrator approval to finish this Homebrew update."
    print "Enter your macOS password when sudo asks for it."
    print
    \(permissionRepair)
    \(command) 2>&1 | \(relay(append: permissionRepairURL != nil))
    \(pipelineStatus)
    print -r -- "$upkeep_status" > \(shellQuote(statusURL.path))
    trap - EXIT HUP INT TERM
    print
    if (( upkeep_status == 0 )); then
      print "Homebrew update completed. You can close this window."
    else
      print "Homebrew update failed with status $upkeep_status. You can close this window."
    fi
    exit $upkeep_status
    """
    try commandScript.write(to: scriptURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: scriptURL.path)
    guard fileManager.isExecutableFile(atPath: TerminalCommandLaunch.executable.path) else {
        throw HomebrewClient.BrewError.failed("The system interactive command launcher is unavailable. Run this update manually in Terminal.")
    }
    let terminalCommand = ([TerminalCommandLaunch.executable.path] + TerminalCommandLaunch.arguments(script: scriptURL))
        .map(shellQuote).joined(separator: " ")

    DiagnosticsStore.shared.record(.info, category: .command, "Homebrew needs interactive authorization", metadata: [
        "Command": "brew " + arguments.joined(separator: " "),
        "Action": permissionRepairURL == nil
            ? "Opened Terminal for the administrator password prompt"
            : "Opened Terminal to repair app permissions and retry Homebrew adoption",
        "App path": permissionRepairURL?.path ?? "(not applicable)"
    ])

    let opener: CommandRunner.Result
    do {
        opener = try await CommandRunner.run(URL(fileURLWithPath: "/usr/bin/osascript"),
                                             terminalAppleScriptArguments(command: terminalCommand), timeout: 30)
    } catch {
        commandStopped = await settleFailedTerminalLaunch(fence: launchFence, statusURL: statusURL,
            scriptURL: scriptURL, cancellation: cancellation)
        throw HomebrewClient.BrewError.failed(
            "Homebrew needs administrator approval, but Upkeep could not open Terminal: \(error.localizedDescription)"
        )
    }
    guard opener.status == 0 else {
        commandStopped = await settleFailedTerminalLaunch(fence: launchFence, statusURL: statusURL,
            scriptURL: scriptURL, cancellation: cancellation)
        throw HomebrewClient.BrewError.failed(
            "Homebrew needs administrator approval, but Terminal could not be opened."
        )
    }

    let completion: TerminalCommandCompletion
    do {
        completion = try await monitorOwnedTerminalCommand(statusURL: statusURL, processIDURL: processIDURL,
                                                         scriptURL: scriptURL, cancellation: cancellation)
    } catch {
        commandStopped = await settleFailedTerminalLaunch(fence: launchFence, statusURL: statusURL,
            scriptURL: scriptURL, cancellation: cancellation)
        throw error
    }
    commandStopped = true
    switch completion {
    case .timedOut: throw CommandRunner.Failure.timedOut
    case .cancelled: throw CommandRunner.Failure.cancelled
    case .missingReceipt:
        throw HomebrewClient.BrewError.failed("The Terminal command stopped without reporting a result. Refresh the installed item to verify its state.")
    case .completed: break
    }

    guard let status = TerminalCommandFiles.status(at: statusURL) else {
        throw HomebrewClient.BrewError.failed(
            "Terminal did not report a valid Homebrew exit status. Refresh the installed item to verify its state."
        )
    }
    let data = (try? TerminalCommandFiles.readOutput(at: outputURL).displayData) ?? Data()
    guard status == 0 else {
        let message = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        throw HomebrewClient.BrewError.failed(
            message?.isEmpty == false
                ? message!
                : "Homebrew failed in Terminal with status \(status)."
        )
    }
    return data
}

func waitForTerminalStatus(
    at statusURL: URL,
    processIDURL: URL,
    launchTimeout: Duration = .seconds(30),
    pollInterval: Duration = .milliseconds(250),
    processIsRunning: @Sendable (Int32) -> Bool = terminalProcessIsRunning
) async throws {
    let clock = ContinuousClock()
    let launchDeadline = clock.now.advanced(by: launchTimeout)
    var processID: Int32?
    var stoppedPollCount = 0
    while TerminalCommandFiles.status(at: statusURL) == nil {
        try Task.checkCancellation()
        if processID == nil {
            processID = TerminalCommandFiles.processID(at: processIDURL)
        }
        if let processID {
            if processIsRunning(processID) {
                stoppedPollCount = 0
            } else {
                stoppedPollCount += 1
                guard stoppedPollCount < 3 else {
                    throw HomebrewClient.BrewError.failed(
                        "The Terminal command stopped without reporting a Homebrew result. Review the Terminal output, then try again."
                    )
                }
            }
        } else if clock.now >= launchDeadline {
            throw HomebrewClient.BrewError.failed(
                "The Homebrew command did not start in Terminal. Close the Terminal window and try again."
            )
        }
        try await Task.sleep(for: pollInterval)
    }
}

private func terminalProcessIsRunning(_ processID: Int32) -> Bool {
    guard processID > 0 else { return false }
    return kill(processID, 0) == 0 || errno == EPERM
}

func terminalAppleScriptArguments(command: String) -> [String] {
    [
        "-e", "on run argv",
        "-e", "tell application \"Terminal\"",
        "-e", "do script (item 1 of argv)",
        "-e", "activate",
        "-e", "end tell",
        "-e", "end run",
        command
    ]
}

private func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private struct InfoResponse: Decodable { let formulae: [FormulaDTO]; let casks: [CaskDTO] }
private struct FormulaDTO: Decodable {
    let name: String; let desc: String?; let license: String?; let homepage: String?
    let revision: Int?; let versionScheme: Int?; let tap: String?
    enum CodingKeys: String, CodingKey {
        case name, desc, license, homepage, versions, dependencies, installed, outdated, revision, tap
        case versionScheme = "version_scheme"
    }
    let versions: Versions; let dependencies: [String]; let installed: [Installed]; let outdated: Bool
    struct Versions: Decodable { let stable: String? }
    struct Installed: Decodable {
        let version: String; let installedOnRequest: Bool
        enum CodingKeys: String, CodingKey { case version; case installedOnRequest = "installed_on_request" }
    }
}
private struct CaskDTO: Decodable {
    let token: String; let name: [String]; let desc: String?; let homepage: String?; let version: String; let outdated: Bool
    let tap: String?
    private let installed: FlexibleString?
    var installedVersion: String? { installed?.value }
}
private struct FlexibleString: Decodable {
    let value: String
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) { value = string; return }
        if let strings = try? container.decode([String].self), let string = strings.last { value = string; return }
        throw DecodingError.typeMismatch(String.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected string"))
    }
}
struct CatalogCask: Decodable, Sendable {
    let token: String
    let name: [String]
    let version: String
    let autoUpdates: Bool
    let artifactAppNames: [String]

    init(
        token: String,
        name: [String],
        version: String,
        autoUpdates: Bool = false,
        artifactAppNames: [String] = []
    ) {
        self.token = token
        self.name = name
        self.version = version
        self.autoUpdates = autoUpdates
        self.artifactAppNames = artifactAppNames
    }

    private enum CodingKeys: String, CodingKey {
        case token, name, version, artifacts
        case autoUpdates = "auto_updates"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decode(String.self, forKey: .token)
        name = try container.decode([String].self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        autoUpdates = try container.decodeIfPresent(Bool.self, forKey: .autoUpdates) ?? false
        let artifacts = try? container.decode([CatalogArtifact].self, forKey: .artifacts)
        artifactAppNames = artifacts?.flatMap(\.appNames) ?? []
    }
}

private struct CatalogArtifact: Decodable {
    let appNames: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dictionary = try? container.decode([String: [String]].self) {
            appNames = dictionary["app"] ?? []
        } else if let dictionary = try? container.decode([String: String].self),
                  let app = dictionary["app"] {
            appNames = [app]
        } else {
            appNames = []
        }
    }
}
private func normalize(_ value: String) -> String { value.lowercased().filter(\.isLetter) }

private func packages(from response: InfoResponse, includePrereleases: Bool) -> [HomebrewPackage] {
    let formulae = response.formulae.compactMap { formula -> HomebrewPackage? in
        guard let installed = formula.installed.last else { return nil }
        let current = formula.versions.stable.map { homebrewFormulaVersion($0, revision: formula.revision ?? 0) } ?? installed.version
        return HomebrewPackage(
            token: formula.name,
            displayName: formula.name,
            description: formula.desc,
            homepage: formula.homepage.flatMap(URL.init(string:)),
            license: formula.license,
            installedVersion: installed.version,
            currentVersion: current,
            kind: .formula,
            isOutdated: formula.outdated && (includePrereleases || !VersionComparator.isHomebrewPrerelease(current)),
            isDependency: !installed.installedOnRequest,
            dependencies: formula.dependencies,
            versionScheme: formula.versionScheme ?? 0, tap: formula.tap
        )
    }
    let casks = response.casks.compactMap { cask -> HomebrewPackage? in
        guard let installed = cask.installedVersion else { return nil }
        return HomebrewPackage(
            token: cask.token,
            displayName: cask.name.first ?? cask.token,
            description: cask.desc,
            homepage: cask.homepage.flatMap(URL.init(string:)),
            license: nil,
            installedVersion: installed,
            currentVersion: cask.version,
            kind: .cask,
            isOutdated: cask.outdated && (includePrereleases || !VersionComparator.isHomebrewPrerelease(cask.version)),
            isDependency: false,
            dependencies: [], tap: cask.tap
        )
    }
    return formulae + casks
}

func homebrewFormulaVersion(_ upstream: String, revision: Int) -> String {
    revision > 0 ? "\(upstream)_\(revision)" : upstream
}

func decodeHomebrewInventory(_ data: Data, includePrereleases: Bool = false) throws -> [HomebrewPackage] {
    packages(from: try JSONDecoder().decode(InfoResponse.self, from: data), includePrereleases: includePrereleases)
}
