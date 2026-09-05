import Darwin
import Foundation

struct HomebrewClient: Sendable {
    func inventory(includePrereleases: Bool = false) async throws -> [HomebrewPackage] {
        guard let brew = Self.brewURL else { return [] }
        return try await Task.detached(priority: .utility) {
            let data = try await runWithRetry(brew, ["info", "--json=v2", "--installed"])
            let response: InfoResponse
            do { response = try JSONDecoder().decode(InfoResponse.self, from: data) }
            catch { throw BrewError.failed("Homebrew inventory could not be read: \(error.localizedDescription)") }

            let formulae = response.formulae.compactMap { formula -> HomebrewPackage? in
                guard let installed = formula.installed.last else { return nil }
                return HomebrewPackage(
                    token: formula.name,
                    displayName: formula.name,
                    description: formula.desc,
                    homepage: formula.homepage.flatMap(URL.init(string:)),
                    license: formula.license,
                    installedVersion: installed.version,
                    currentVersion: formula.versions.stable ?? installed.version,
                    kind: .formula,
                    isOutdated: formula.outdated && (includePrereleases || !VersionComparator.isPrerelease(formula.versions.stable ?? installed.version)),
                    isDependency: !installed.installedOnRequest,
                    dependencies: formula.dependencies
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
                    isOutdated: cask.outdated && (includePrereleases || !VersionComparator.isPrerelease(cask.version)),
                    isDependency: false,
                    dependencies: []
                )
            }
            return (formulae + casks).sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        }.value
    }

    /// Reads metadata for one installed token instead of loading the full Homebrew inventory.
    func package(
        token: String,
        kind: HomebrewPackageKind,
        includePrereleases: Bool = false
    ) async throws -> HomebrewPackage? {
        guard let brew = Self.brewURL else { return nil }
        return try await Task.detached(priority: .utility) {
            var arguments = ["info", "--json=v2"]
            if kind == .cask { arguments.append("--cask") }
            arguments.append(token)
            let data = try await runWithRetry(brew, arguments)
            let response: InfoResponse
            do { response = try JSONDecoder().decode(InfoResponse.self, from: data) }
            catch { throw BrewError.failed("Homebrew package data could not be read: \(error.localizedDescription)") }
            return packages(from: response, includePrereleases: includePrereleases)
                .first { $0.kind == kind && $0.token == token }
        }.value
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
            cacheCaskCatalog(data)
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

            try await Task.detached(priority: .userInitiated) {
                _ = try await runInTerminal(
                    brew,
                    arguments,
                    permissionRepairURL: item.app.url
                )
            }.value
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
        try await Task.detached(priority: .userInitiated) {
            do {
                _ = try await runWithRetry(brew, arguments)
            } catch let error as BrewError {
                guard case let .failed(message) = error,
                      BrewError.requiresInteractiveAuthorization(message)
                else { throw error }
                _ = try await runInTerminal(brew, arguments)
            }
        }.value
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
        .appendingPathComponent("cask-catalog.json")
}

private func cachedCaskCatalog(maximumAge: TimeInterval) -> [CatalogCask]? {
    guard let url = caskCatalogCacheURL(),
          let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
          let modified = attributes[.modificationDate] as? Date,
          let size = attributes[.size] as? NSNumber,
          size.intValue <= PublisherHTTPClient.metadataLimit,
          Date().timeIntervalSince(modified) <= maximumAge,
          let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode([CatalogCask].self, from: data)
}

private func cacheCaskCatalog(_ data: Data) {
    guard let url = caskCatalogCacheURL() else { return }
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    } catch {
        // Catalog caching is an optimization; the fresh result remains usable.
    }
}

private func runWithRetry(_ executable: URL, _ arguments: [String]) async throws -> Data {
    let delays: [UInt64] = [1, 2, 4]
    for attempt in 0...delays.count {
        do { return try run(executable, arguments) }
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

private func run(_ executable: URL, _ arguments: [String]) throws -> Data {
    let startedAt = Date()
    let command = "brew " + arguments.joined(separator: " ")
    let process = Process()
    let output = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = output
    do { try process.run() }
    catch {
        DiagnosticsStore.shared.record(.error, category: .command, "Homebrew command could not start", metadata: [
            "Command": command,
            "Duration": String(format: "%.0f ms", Date().timeIntervalSince(startedAt) * 1_000),
            "Error": error.localizedDescription
        ])
        throw error
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let outputText = String(data: data.prefix(1_200), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    var metadata = [
        "Command": command,
        "Exit status": "\(process.terminationStatus)",
        "Duration": String(format: "%.0f ms", Date().timeIntervalSince(startedAt) * 1_000),
        "Output bytes": "\(data.count)"
    ]
    if arguments.first != "info" || process.terminationStatus != 0 {
        metadata["Output"] = outputText.isEmpty ? "(no output)" : outputText
    }
    DiagnosticsStore.shared.record(
        process.terminationStatus == 0 ? .info : .error,
        category: .command,
        "Homebrew command \(process.terminationStatus == 0 ? "completed" : "failed")",
        metadata: metadata
    )
    guard process.terminationStatus == 0 else {
        throw HomebrewClient.BrewError.failed(String(data: data, encoding: .utf8) ?? "Homebrew failed")
    }
    return data
}

private func runInTerminal(
    _ executable: URL,
    _ arguments: [String],
    permissionRepairURL: URL? = nil
) async throws -> Data {
    let fileManager = FileManager.default
    let directory = fileManager.temporaryDirectory
        .appendingPathComponent("Upkeep-Homebrew-\(UUID().uuidString)", isDirectory: true)
    let outputURL = directory.appendingPathComponent("output.log")
    let statusURL = directory.appendingPathComponent("status")
    let processIDURL = directory.appendingPathComponent("pid")
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    defer { try? fileManager.removeItem(at: directory) }

    let command = ([executable.path] + arguments).map(shellQuote).joined(separator: " ")
    let permissionRepair: String
    if let permissionRepairURL {
        permissionRepair = """
        print "Homebrew could not adjust permissions inside the existing app."
        print "Upkeep will repair only that app bundle, then retry adoption."
        print
        /usr/bin/sudo /bin/chmod -R a+rX \(shellQuote(permissionRepairURL.path)) 2>&1 | /usr/bin/tee \(shellQuote(outputURL.path))
        upkeep_status=${pipestatus[1]}
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

    let outputMode = permissionRepairURL == nil ? "" : "-a "
    let terminalCommand = """
    set -o pipefail
    typeset -i upkeep_status=1
    print -r -- "$$" > \(shellQuote(processIDURL.path))
    trap 'print -r -- "$upkeep_status" > \(shellQuote(statusURL.path))' EXIT HUP INT TERM
    print
    print "Upkeep needs administrator approval to finish this Homebrew update."
    print "Enter your macOS password when sudo asks for it."
    print
    \(permissionRepair)
    \(command) 2>&1 | /usr/bin/tee \(outputMode)\(shellQuote(outputURL.path))
    upkeep_status=${pipestatus[1]}
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

    DiagnosticsStore.shared.record(.info, category: .command, "Homebrew needs interactive authorization", metadata: [
        "Command": "brew " + arguments.joined(separator: " "),
        "Action": permissionRepairURL == nil
            ? "Opened Terminal for the administrator password prompt"
            : "Opened Terminal to repair app permissions and retry Homebrew adoption",
        "App path": permissionRepairURL?.path ?? "(not applicable)"
    ])

    let opener = Process()
    opener.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    opener.arguments = terminalAppleScriptArguments(command: terminalCommand)
    do {
        try opener.run()
        opener.waitUntilExit()
    } catch {
        throw HomebrewClient.BrewError.failed(
            "Homebrew needs administrator approval, but Upkeep could not open Terminal: \(error.localizedDescription)"
        )
    }
    guard opener.terminationStatus == 0 else {
        throw HomebrewClient.BrewError.failed(
            "Homebrew needs administrator approval, but Terminal could not be opened."
        )
    }

    try await waitForTerminalStatus(at: statusURL, processIDURL: processIDURL)

    let statusText = (try? String(contentsOf: statusURL, encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let status = Int32(statusText ?? "") ?? 1
    let data = (try? Data(contentsOf: outputURL)) ?? Data()
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
    while !FileManager.default.fileExists(atPath: statusURL.path) {
        try Task.checkCancellation()
        if processID == nil {
            processID = terminalProcessID(at: processIDURL)
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

private func terminalProcessID(at url: URL) -> Int32? {
    guard let value = try? String(contentsOf: url, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    else { return nil }
    return Int32(value)
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
    let versions: Versions; let dependencies: [String]; let installed: [Installed]; let outdated: Bool
    struct Versions: Decodable { let stable: String? }
    struct Installed: Decodable {
        let version: String; let installedOnRequest: Bool
        enum CodingKeys: String, CodingKey { case version; case installedOnRequest = "installed_on_request" }
    }
}
private struct CaskDTO: Decodable {
    let token: String; let name: [String]; let desc: String?; let homepage: String?; let version: String; let outdated: Bool
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
        let current = formula.versions.stable ?? installed.version
        return HomebrewPackage(
            token: formula.name,
            displayName: formula.name,
            description: formula.desc,
            homepage: formula.homepage.flatMap(URL.init(string:)),
            license: formula.license,
            installedVersion: installed.version,
            currentVersion: current,
            kind: .formula,
            isOutdated: formula.outdated && (includePrereleases || !VersionComparator.isPrerelease(current)),
            isDependency: !installed.installedOnRequest,
            dependencies: formula.dependencies
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
            isOutdated: cask.outdated && (includePrereleases || !VersionComparator.isPrerelease(cask.version)),
            isDependency: false,
            dependencies: []
        )
    }
    return formulae + casks
}
