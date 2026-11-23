import Foundation

// pyenv and rbenv runtimes, Google Cloud CLI, Azure CLI extensions, and Xcode
// simulator runtimes.
//
// Verified in November 2026: pyenv 2.8.15 and rbenv with ruby-build were run
// from source checkouts; Azure CLI 2.x and Google Cloud CLI were run from
// throwaway installs; Xcode 27.2's `simctl` and `xcodebuild` were run on a Mac
// with simulator runtimes installed. None of the first four were installed on
// that Mac, so detection paths follow each tool's documented install layout.

private func runtimeManagerWarning(_ manager: DeveloperPackageManager, _ command: String, _ result: (data: Data, status: Int32)) -> String {
    let output = String(decoding: result.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return "\(manager.rawValue) \(command) failed: \(output.isEmpty ? "command exited with status \(result.status)" : String(output.prefix(400)))"
}

// MARK: - pyenv and rbenv

/// One installable version as pyenv or ruby-build names it. Only CPython and
/// CRuby release lines are checked; PyPy, Miniconda, JRuby, `-dev` builds and
/// the like have no patch line to follow.
struct RuntimeVersionName: Equatable, Sendable {
    let name: String
    let major: Int
    let minor: Int
    let patch: Int
    /// pyenv's free-threaded builds end in `t` and form their own line.
    let variant: String
    /// `a1`, `b2`, `rc1` (pyenv) or `preview1`, `rc1` (ruby-build); empty for a release.
    let prerelease: String

    var line: String { "\(major).\(minor)\(variant)" }
    var isPrerelease: Bool { !prerelease.isEmpty }

    static func python(_ value: String) -> RuntimeVersionName? {
        parse(value, pattern: #"^(\d+)\.(\d+)\.(\d+)((?:a|b|rc)\d+)?(t?)$"#)
    }

    static func ruby(_ value: String) -> RuntimeVersionName? {
        parse(value, pattern: #"^(\d+)\.(\d+)\.(\d+)(?:-((?:preview|rc)\d+))?()$"#)
    }

    private static func parse(_ value: String, pattern: String) -> RuntimeVersionName? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
        else { return nil }
        func group(_ index: Int) -> String {
            Range(match.range(at: index), in: trimmed).map { String(trimmed[$0]) } ?? ""
        }
        guard let major = Int(group(1)), let minor = Int(group(2)), let patch = Int(group(3)) else { return nil }
        return RuntimeVersionName(name: trimmed, major: major, minor: minor, patch: patch,
                                  variant: group(5), prerelease: group(4))
    }

    /// Releases sort after their own prereleases; prereleases by kind, then number.
    static func isOrderedBefore(_ lhs: RuntimeVersionName, _ rhs: RuntimeVersionName) -> Bool {
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        if lhs.isPrerelease != rhs.isPrerelease { return lhs.isPrerelease }
        return lhs.prerelease.localizedStandardCompare(rhs.prerelease) == .orderedAscending
    }
}

struct RuntimeLineUpdate: Equatable, Sendable {
    let line: String
    let current: String
    let latest: String
}

/// For each installed release line (3.12, 3.13t, 3.4) the newest installed
/// version and the newest installable one. A stable line is only offered
/// releases; a line whose newest install is a prerelease is also offered
/// newer prereleases. Installing a patch leaves the old one in place, so the
/// line, not each version, is the package: once the new patch is installed
/// the line is current.
func runtimeLineUpdates(installed: [RuntimeVersionName], available: [RuntimeVersionName]) -> [RuntimeLineUpdate] {
    let installedLines = Dictionary(grouping: installed, by: \.line)
    return installedLines.compactMap { line, versions -> RuntimeLineUpdate? in
        guard let current = versions.max(by: RuntimeVersionName.isOrderedBefore) else { return nil }
        let candidates = available.filter {
            $0.line == line && (current.isPrerelease || !$0.isPrerelease)
        }
        let newest = (candidates + [current]).max(by: RuntimeVersionName.isOrderedBefore) ?? current
        return RuntimeLineUpdate(line: line, current: current.name, latest: newest.name)
    }.sorted { $0.line.localizedStandardCompare($1.line) == .orderedAscending }
}

/// `pyenv install --list` and `rbenv install --list-all` print one name per
/// line, pyenv after an "Available versions:" heading.
func parseRuntimeVersionList(_ data: Data, parser: (String) -> RuntimeVersionName?) -> [RuntimeVersionName] {
    String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { parser(String($0)) }
}

func pyenvExecutable(environment: [String: String] = ProcessInfo.processInfo.environment,
                     home: String = NSHomeDirectory()) -> String? {
    let root = environment["PYENV_ROOT"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.pyenv"
    return [root + "/bin/pyenv", "/opt/homebrew/bin/pyenv", "/usr/local/bin/pyenv"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
}

func rbenvExecutable(environment: [String: String] = ProcessInfo.processInfo.environment,
                     home: String = NSHomeDirectory()) -> String? {
    let root = environment["RBENV_ROOT"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.rbenv"
    return [root + "/bin/rbenv", "/opt/homebrew/bin/rbenv", "/usr/local/bin/rbenv"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
}

func scanPyenv(_ path: String) async -> ManagerScanResult {
    await scanRuntimeVersionManager(
        .pyenv, path: path, listArguments: ["install", "--list"], parser: RuntimeVersionName.python,
        name: { "Python \($0)" }
    )
}

func scanRbenv(_ path: String) async -> ManagerScanResult {
    await scanRuntimeVersionManager(
        .rbenv, path: path, listArguments: ["install", "--list-all"], parser: RuntimeVersionName.ruby,
        name: { "Ruby \($0)" }
    )
}

private func scanRuntimeVersionManager(
    _ manager: DeveloperPackageManager,
    path: String,
    listArguments: [String],
    parser: @escaping (String) -> RuntimeVersionName?,
    name: (String) -> String
) async -> ManagerScanResult {
    let executable = URL(fileURLWithPath: path)
    async let installedCommand = captureDeveloperCommandAsync(executable, ["versions", "--bare"], purpose: .inventory)
    async let availableCommand = captureDeveloperCommandAsync(executable, listArguments, purpose: .inventory)
    let (installedResult, availableResult) = await (installedCommand, availableCommand)
    guard installedResult.status == 0 else {
        return ManagerScanResult(manager: manager, packages: [], warning: runtimeManagerWarning(manager, "version inventory", installedResult))
    }
    let installed = parseRuntimeVersionList(installedResult.data, parser: parser)
    guard !installed.isEmpty else { return ManagerScanResult(manager: manager, packages: [], warning: nil) }
    // rbenv without ruby-build has no `install` command; the versions are
    // still listed, as current.
    let available = availableResult.status == 0 ? parseRuntimeVersionList(availableResult.data, parser: parser) : []
    let packages = runtimeLineUpdates(installed: installed, available: available).map { update in
        DeveloperPackage(
            name: name(update.line), currentVersion: update.current, latestVersion: update.latest,
            manager: manager, executablePath: path, registryIdentifier: update.line
        )
    }
    let warning = availableResult.status == 0 ? nil : runtimeManagerWarning(manager, "release list", availableResult)
    return ManagerScanResult(manager: manager, packages: packages, warning: warning)
}

// MARK: - Google Cloud CLI

/// `gcloud components update` installs a whole Cloud CLI release, so the
/// release, not each component, is the package. The rapid channel's snapshot
/// is what `gcloud components update` reads.
let googleCloudChannelURL = URL(string: "https://dl.google.com/dl/cloudsdk/channels/rapid/components-2.json")!

func googleCloudExecutable(home: String = NSHomeDirectory()) -> String? {
    [
        "/opt/homebrew/bin/gcloud",
        "/usr/local/bin/gcloud",
        "/opt/homebrew/share/google-cloud-sdk/bin/gcloud",
        home + "/google-cloud-sdk/bin/gcloud"
    ].first { FileManager.default.isExecutableFile(atPath: $0) }
}

/// `gcloud version --format=json` maps "Google Cloud SDK" to the release.
func parseGoogleCloudVersion(_ data: Data) -> String? {
    guard let object = try? JSONSerialization.jsonObject(with: jsonPayload(data)) as? [String: Any] else { return nil }
    return object["Google Cloud SDK"] as? String
}

func parseGoogleCloudChannelVersion(_ data: Data) -> String? {
    struct Snapshot: Decodable { let version: String }
    return try? JSONDecoder().decode(Snapshot.self, from: data).version
}

func scanGoogleCloud(_ path: String) async -> ManagerScanResult {
    let result = await captureDeveloperStandardOutput(URL(fileURLWithPath: path), ["version", "--format=json"])
    guard result.status == 0, let installed = parseGoogleCloudVersion(result.data) else {
        return ManagerScanResult(manager: .googleCloud, packages: [], warning: runtimeManagerWarning(.googleCloud, "version check", result))
    }
    var request = URLRequest(url: googleCloudChannelURL)
    request.timeoutInterval = 20
    request.setValue("Upkeep/1.0", forHTTPHeaderField: "User-Agent")
    let latest = await RegistryRequestCache.shared.data(for: request, key: "GET:\(googleCloudChannelURL.absoluteString)")
        .flatMap(parseGoogleCloudChannelVersion)
    return ManagerScanResult(
        manager: .googleCloud,
        packages: [DeveloperPackage(
            name: "Google Cloud CLI", currentVersion: installed, latestVersion: latest ?? installed,
            manager: .googleCloud, executablePath: path, registryIdentifier: "google-cloud-sdk"
        )],
        warning: latest == nil ? "Google Cloud CLI: the release channel could not be read." : nil
    )
}

// MARK: - Azure CLI extensions

struct AzureExtension: Equatable, Sendable {
    let name: String
    let version: String
    let preview: Bool
}

/// `az extension list -o json`. Extensions added from a local folder
/// (`extensionType: dev`) have no index entry to compare with.
func parseAzureInstalledExtensions(_ data: Data) -> [AzureExtension]? {
    struct Entry: Decodable { let name: String; let version: String; let preview: Bool?; let extensionType: String? }
    guard let entries = try? JSONDecoder().decode([Entry].self, from: jsonPayload(data)) else { return nil }
    return entries.filter { $0.extensionType != "dev" }
        .map { AzureExtension(name: $0.name, version: $0.version, preview: $0.preview ?? false) }
}

/// `az extension list-available -o json` gives the newest version compatible
/// with this Azure CLI. Its `installed` field is `false`, `true`, or the string
/// "True (upgrade available)", so only `name`, `version` and `preview` are read.
func parseAzureAvailableExtensions(_ data: Data) -> [String: AzureExtension] {
    struct Entry: Decodable { let name: String; let version: String; let preview: Bool? }
    let entries = (try? JSONDecoder().decode([Entry].self, from: jsonPayload(data))) ?? []
    return Dictionary(entries.map { ($0.name, AzureExtension(name: $0.name, version: $0.version, preview: $0.preview ?? false)) },
                      uniquingKeysWith: { first, _ in first })
}

/// `az extension update` skips preview releases unless asked, so a stable
/// install is not offered one.
func azureExtensionLatest(installed: AzureExtension, available: AzureExtension?) -> String {
    guard let available, available.preview == false || installed.preview,
          VersionComparator.isNewer(available.version, than: installed.version)
    else { return installed.version }
    return available.version
}

func scanAzureExtensions(_ path: String) async -> ManagerScanResult {
    let executable = URL(fileURLWithPath: path)
    let installedResult = await captureDeveloperStandardOutput(executable, ["extension", "list", "--output", "json"])
    guard installedResult.status == 0, let installed = parseAzureInstalledExtensions(installedResult.data) else {
        return ManagerScanResult(manager: .azureCLI, packages: [], warning: runtimeManagerWarning(.azureCLI, "extension inventory", installedResult))
    }
    guard !installed.isEmpty else { return ManagerScanResult(manager: .azureCLI, packages: [], warning: nil) }
    let availableResult = await captureDeveloperStandardOutput(executable, ["extension", "list-available", "--output", "json"])
    let available = availableResult.status == 0 ? parseAzureAvailableExtensions(availableResult.data) : [:]
    let packages = installed.map { value in
        DeveloperPackage(
            name: value.name, currentVersion: value.version,
            latestVersion: azureExtensionLatest(installed: value, available: available[value.name]),
            manager: .azureCLI, executablePath: path, registryIdentifier: value.name
        )
    }
    let warning = availableResult.status == 0 ? nil : runtimeManagerWarning(.azureCLI, "extension index check", availableResult)
    return ManagerScanResult(manager: .azureCLI, packages: packages, warning: warning)
}

// MARK: - Xcode simulator runtimes

/// Xcode's public list of downloadable simulator runtimes, the one its
/// Components settings read.
let xcodeDownloadableIndexURL = URL(string: "https://devimages-cdn.apple.com/downloads/xcode/simulators/index2.dvtdownloadableindex")!

struct SimulatorRuntime: Equatable, Sendable {
    /// `com.apple.platform.iphoneos`, the SDK platform the index uses.
    let platform: String
    let version: String
    let build: String
}

struct SimulatorSDK: Equatable, Sendable {
    let platform: String
    let version: String
    let build: String
}

enum SimulatorPlatform {
    /// simctl names simulator platforms; the index names device platforms.
    static func sdkPlatform(simulatorPlatform: String) -> String? {
        [
            "com.apple.platform.iphonesimulator": "com.apple.platform.iphoneos",
            "com.apple.platform.watchsimulator": "com.apple.platform.watchos",
            "com.apple.platform.appletvsimulator": "com.apple.platform.appletvos",
            "com.apple.platform.xrsimulator": "com.apple.platform.xros"
        ][simulatorPlatform]
    }

    static func sdkPlatform(canonicalName: String) -> String? {
        let prefixes = [
            "iphonesimulator": "com.apple.platform.iphoneos",
            "watchsimulator": "com.apple.platform.watchos",
            "appletvsimulator": "com.apple.platform.appletvos",
            "xrsimulator": "com.apple.platform.xros"
        ]
        return prefixes.first { canonicalName.hasPrefix($0.key) }?.value
    }

    /// The `-downloadPlatform` argument and the display name.
    static func name(_ platform: String) -> String? {
        [
            "com.apple.platform.iphoneos": "iOS",
            "com.apple.platform.watchos": "watchOS",
            "com.apple.platform.appletvos": "tvOS",
            "com.apple.platform.xros": "visionOS"
        ][platform]
    }

    /// The `sdkIdentifier` prefix in the index's mappings.
    static func sdkIdentifierPrefix(_ platform: String) -> String? {
        [
            "com.apple.platform.iphoneos": "iphoneos",
            "com.apple.platform.watchos": "watchos",
            "com.apple.platform.appletvos": "appletvos",
            "com.apple.platform.xros": "xros"
        ][platform]
    }
}

/// `xcrun simctl runtime list -j`: a dictionary of disk images by identifier.
func parseSimulatorRuntimes(_ data: Data) -> [SimulatorRuntime]? {
    struct Image: Decodable { let build: String; let version: String; let platformIdentifier: String; let state: String? }
    guard let images = try? JSONDecoder().decode([String: Image].self, from: jsonPayload(data)) else { return nil }
    return images.values.compactMap { image in
        guard image.state == nil || image.state == "Ready",
              let platform = SimulatorPlatform.sdkPlatform(simulatorPlatform: image.platformIdentifier)
        else { return nil }
        return SimulatorRuntime(platform: platform, version: image.version, build: image.build)
    }
}

/// Identifiers of installed runtime images for a platform name ("iOS") and build.
func simulatorRuntimeIdentifiers(_ data: Data, platform: String, build: String) -> [String] {
    struct Image: Decodable { let build: String; let platformIdentifier: String }
    guard let images = try? JSONDecoder().decode([String: Image].self, from: jsonPayload(data)) else { return [] }
    return images.filter { _, image in
        image.build == build
            && SimulatorPlatform.sdkPlatform(simulatorPlatform: image.platformIdentifier)
                .flatMap(SimulatorPlatform.name) == platform
    }.keys.sorted()
}

/// `xcodebuild -showsdks -json`: the simulator SDKs in the selected Xcode.
func parseSimulatorSDKs(_ data: Data) -> [SimulatorSDK] {
    struct SDK: Decodable { let canonicalName: String; let platformVersion: String?; let productBuildVersion: String? }
    let sdks = (try? JSONDecoder().decode([SDK].self, from: jsonPayload(data))) ?? []
    return sdks.compactMap { sdk in
        guard let platform = SimulatorPlatform.sdkPlatform(canonicalName: sdk.canonicalName),
              let version = sdk.platformVersion, let build = sdk.productBuildVersion else { return nil }
        return SimulatorSDK(platform: platform, version: version, build: build)
    }
}

struct SimulatorMapping: Equatable, Sendable {
    let sdkIdentifier: String
    let sdkBuild: String
    let simulatorBuild: String
    let isPreferred: Bool
}

/// `sdkToSimulatorMappings` from the downloadable index: which runtime builds
/// go with each SDK build. One SDK can map to several builds (a runtime for
/// newer devices beside the general one); the general one is `preferred`.
func parseSimulatorMappings(_ data: Data) -> [SimulatorMapping]? {
    guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let mappings = plist["sdkToSimulatorMappings"] as? [[String: Any]]
    else { return nil }
    return mappings.compactMap { entry in
        guard let sdk = entry["sdkIdentifier"] as? String,
              let sdkBuild = entry["sdkBuildUpdate"] as? String,
              let simulatorBuild = entry["simulatorBuildUpdate"] as? String
        else { return nil }
        return SimulatorMapping(sdkIdentifier: sdk, sdkBuild: sdkBuild, simulatorBuild: simulatorBuild,
                                isPreferred: entry["affinity"] as? String == "preferred")
    }
}

struct SimulatorRuntimeStatus: Equatable, Sendable {
    let platform: String
    let version: String
    let current: String
    let latest: String
}

/// Runtimes for the selected Xcode's SDK versions. A runtime is current when
/// any installed build of that version is one the index maps to the SDK's
/// build. Otherwise (a beta or release-candidate runtime kept after Xcode
/// moved on) the preferred mapped build is offered. Runtimes for other
/// versions are kept for testing older systems and are not listed; a version
/// with no runtime installed is Xcode's to offer, not an update.
func simulatorRuntimeStatuses(
    runtimes: [SimulatorRuntime],
    sdks: [SimulatorSDK],
    mappings: [SimulatorMapping]
) -> [SimulatorRuntimeStatus] {
    sdks.compactMap { sdk -> SimulatorRuntimeStatus? in
        guard let prefix = SimulatorPlatform.sdkIdentifierPrefix(sdk.platform) else { return nil }
        let installed = runtimes.filter { $0.platform == sdk.platform && $0.version == sdk.version }
        guard !installed.isEmpty else { return nil }
        let matching = mappings.filter { $0.sdkIdentifier == prefix + sdk.version && $0.sdkBuild == sdk.build }
        // The preferred (general) build first, so it names the line when both are installed.
        let mappedBuilds = matching.sorted { $0.isPreferred && !$1.isPreferred }.map(\.simulatorBuild)
        if let current = mappedBuilds.lazy.compactMap({ build in installed.first { $0.build == build } }).first {
            return SimulatorRuntimeStatus(platform: sdk.platform, version: sdk.version, current: current.build, latest: current.build)
        }
        let newest = installed.map(\.build).sorted { $0.localizedStandardCompare($1) == .orderedDescending }.first!
        let target = (matching.first(where: \.isPreferred) ?? matching.first)?.simulatorBuild ?? newest
        return SimulatorRuntimeStatus(platform: sdk.platform, version: sdk.version, current: newest, latest: target)
    }.sorted { ($0.platform, $0.version) < ($1.platform, $1.version) }
}

/// simctl only works with a full Xcode selected, not the Command Line Tools.
func xcodeSimulatorExecutable() -> String? {
    guard FileManager.default.isExecutableFile(atPath: "/usr/bin/xcrun") else { return nil }
    let developerDirectory = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
        ?? (try? String(contentsOfFile: "/var/db/xcode_select_link", encoding: .utf8))
        ?? (try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link"))
    if let developerDirectory, developerDirectory.contains(".app/Contents/Developer") { return "/usr/bin/xcrun" }
    // No selection recorded: xcode-select falls back to /Applications/Xcode.app.
    return developerDirectory == nil && FileManager.default.fileExists(atPath: "/Applications/Xcode.app") ? "/usr/bin/xcrun" : nil
}

func scanXcodeSimulatorRuntimes(_ path: String) async -> ManagerScanResult {
    let xcrun = URL(fileURLWithPath: path)
    async let runtimeCommand = captureDeveloperStandardOutput(xcrun, ["simctl", "runtime", "list", "-j"])
    async let sdkCommand = captureDeveloperStandardOutput(xcrun, ["xcodebuild", "-showsdks", "-json"])
    let (runtimeResult, sdkResult) = await (runtimeCommand, sdkCommand)
    guard runtimeResult.status == 0, let runtimes = parseSimulatorRuntimes(runtimeResult.data) else {
        return ManagerScanResult(manager: .xcodeSimulators, packages: [],
                                 warning: runtimeManagerWarning(.xcodeSimulators, "runtime inventory", runtimeResult))
    }
    let sdks = sdkResult.status == 0 ? parseSimulatorSDKs(sdkResult.data) : []
    guard !runtimes.isEmpty, !sdks.isEmpty else { return ManagerScanResult(manager: .xcodeSimulators, packages: [], warning: nil) }
    var request = URLRequest(url: xcodeDownloadableIndexURL)
    request.timeoutInterval = 20
    request.setValue("Upkeep/1.0", forHTTPHeaderField: "User-Agent")
    guard let index = await RegistryRequestCache.shared.data(for: request, key: "GET:\(xcodeDownloadableIndexURL.absoluteString)"),
          let mappings = parseSimulatorMappings(index)
    else {
        return ManagerScanResult(manager: .xcodeSimulators, packages: [],
                                 warning: "Xcode Simulator Runtimes: Apple's runtime list could not be read.")
    }
    let packages = simulatorRuntimeStatuses(runtimes: runtimes, sdks: sdks, mappings: mappings).compactMap { status -> DeveloperPackage? in
        guard let name = SimulatorPlatform.name(status.platform) else { return nil }
        return DeveloperPackage(
            name: "\(name) \(status.version) Simulator", currentVersion: status.current, latestVersion: status.latest,
            manager: .xcodeSimulators, executablePath: path, registryIdentifier: name
        )
    }
    return ManagerScanResult(manager: .xcodeSimulators, packages: packages, warning: nil)
}
