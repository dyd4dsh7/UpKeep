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
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw UpdateSourceError.invalidResponse }
            guard 200..<300 ~= http.statusCode else { throw UpdateSourceError.httpStatus(http.statusCode) }
            let catalog: [CatalogCask]
            do { catalog = try JSONDecoder().decode([CatalogCask].self, from: data) }
            catch { throw UpdateSourceError.malformedData(error.localizedDescription) }
            cacheCaskCatalog(data)
            return catalog
        } catch {
            if let stale = cachedCaskCatalog(maximumAge: .infinity) { return stale }
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
            guard !installedTokens.contains(cask.token), !cask.token.hasPrefix("font-") else { continue }
            // Preserve the API's first-match behavior when aliases collide.
            for name in cask.name {
                let key = normalize(name)
                if catalogIndexByName[key] == nil { catalogIndexByName[key] = index }
            }
            let tokenKey = normalize(cask.token)
            if catalogIndexByName[tokenKey] == nil { catalogIndexByName[tokenKey] = index }
        }
        return apps.compactMap { app in
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
        try await execute(["install", "--cask", "--adopt", item.caskToken])
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
            _ = try await runWithRetry(brew, arguments)
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
struct CatalogCask: Decodable, Sendable { let token: String; let name: [String]; let version: String }
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
