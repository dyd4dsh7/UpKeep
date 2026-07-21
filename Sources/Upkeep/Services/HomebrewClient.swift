import Foundation

struct HomebrewClient: Sendable {
    func inventory() async -> [HomebrewPackage] {
        guard let brew = Self.brewURL else { return [] }
        return await Task.detached(priority: .utility) {
            guard let data = try? run(brew, ["info", "--json=v2", "--installed"]),
                  let response = try? JSONDecoder().decode(InfoResponse.self, from: data)
            else { return [] }

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
                    isOutdated: formula.outdated,
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
                    isOutdated: cask.outdated,
                    isDependency: false,
                    dependencies: []
                )
            }
            return (formulae + casks).sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        }.value
    }

    func adoptableApps(from apps: [InstalledApp], excluding packages: [HomebrewPackage]) async -> [AdoptableApp] {
        guard Self.brewURL != nil, let catalogURL = URL(string: "https://formulae.brew.sh/api/cask.json") else { return [] }
        do {
            var request = URLRequest(url: catalogURL)
            request.timeoutInterval = 30
            request.setValue("Upkeep/0.2", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return [] }
            let catalog = try JSONDecoder().decode([CatalogCask].self, from: data)
            let installedTokens = Set(packages.filter { $0.kind == .cask }.map(\.token))
            var matches: [AdoptableApp] = []
            for app in apps {
                let appName = normalize(app.name)
                guard let cask = catalog.first(where: {
                    !installedTokens.contains($0.token) && !$0.token.hasPrefix("font-") &&
                    ($0.name.contains(where: { normalize($0) == appName }) || normalize($0.token) == appName)
                }) else { continue }
                matches.append(AdoptableApp(app: app, caskToken: cask.token, caskVersion: cask.version))
            }
            return matches.sorted { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending }
        } catch {
            return []
        }
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
            _ = try run(brew, arguments)
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
    }
}

private func run(_ executable: URL, _ arguments: [String]) throws -> Data {
    let process = Process()
    let output = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
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
private struct CatalogCask: Decodable { let token: String; let name: [String]; let version: String }
private func normalize(_ value: String) -> String { value.lowercased().filter(\.isLetter) }
