import Foundation
import Testing
@testable import Upkeep

@Test func appStoreLooksUpMacListingBeforeUniversalListing() {
    // macSoftware returned TestFlight's iPhone version (4.4.1) while the Mac
    // App Store offered 4.4.0; desktopSoftware matches the Mac App Store.
    #expect(AppStoreClient.lookupEntities == ["desktopSoftware", "macSoftware"])
}

@Test func nodeSkipsPrereleasesForStableInstalls() {
    let releases = ["27.0.0-alpha.0.1.1", "26.3.0", "26.2.0", "24.22.2", "24.22.1"]
    #expect(latestNodeRelease(in: releases, installed: "24.22.1", preferLatestMajor: true) == "26.3.0")
    #expect(latestNodeRelease(in: releases, installed: "24.22.1", preferLatestMajor: false) == "24.22.2")
    // An installed prerelease is already on that track.
    #expect(latestNodeRelease(in: releases, installed: "27.0.0-alpha.0.1.0", preferLatestMajor: false) == "27.0.0-alpha.0.1.1")
    #expect(latestNodeRelease(in: ["27.0.0-rc.1"], installed: "26.3.0", preferLatestMajor: true) == nil)
}

@Test func rubyGemsPrefersUserRubyOverSystemRuby() throws {
    let fileManager = FileManager.default
    let home = fileManager.temporaryDirectory.appendingPathComponent("Upkeep-rbenv-\(UUID().uuidString)")
    defer { try? fileManager.removeItem(at: home) }
    try fileManager.createDirectory(at: home.appendingPathComponent(".rbenv"), withIntermediateDirectories: true)

    // No `rbenv global`: the shim would run the system Ruby, so it is skipped.
    var candidates = rubyGemExecutableCandidates(home: home.path, environment: [:])
    #expect(!candidates.contains { $0.contains(".rbenv") })
    try "system\n".write(to: home.appendingPathComponent(".rbenv/version"), atomically: true, encoding: .utf8)
    #expect(!rubyGemExecutableCandidates(home: home.path, environment: [:]).contains { $0.contains(".rbenv") })

    try "3.4.1\n".write(to: home.appendingPathComponent(".rbenv/version"), atomically: true, encoding: .utf8)
    candidates = rubyGemExecutableCandidates(home: home.path, environment: [:])
    #expect(candidates.first == home.path + "/.rbenv/shims/gem")
    #expect(candidates.last == "/usr/bin/gem")
    #expect(candidates.firstIndex(of: "/opt/homebrew/opt/ruby/bin/gem")! < candidates.firstIndex(of: "/opt/homebrew/bin/gem")!)
}

@Test func rubyGemsUsesUserInstallOnlyForSystemRuby() {
    let system = DeveloperPackage(name: "bundler", currentVersion: "1.17.2", latestVersion: "2.7.0",
                                  manager: .rubyGems, executablePath: "/usr/bin/gem")
    let homebrew = DeveloperPackage(name: "bundler", currentVersion: "2.6.0", latestVersion: "2.7.0",
                                    manager: .rubyGems, executablePath: "/opt/homebrew/bin/gem")
    #expect(rubyGemInstallArguments(for: system, version: "2.7.0").last == "--user-install")
    #expect(rubyGemInstallArguments(for: homebrew, version: "2.7.0") == ["install", "bundler", "--version", "2.7.0"])
}

@Test func npmEnginesRangesMatchNodeVersions() {
    let npm12 = "^22.22.2 || ^24.15.0 || >=26.0.0"
    #expect(NodeEngineRange.satisfies("24.22.1", range: npm12))
    #expect(NodeEngineRange.satisfies("26.13.1", range: npm12))
    #expect(!NodeEngineRange.satisfies("20.19.0", range: npm12))
    #expect(!NodeEngineRange.satisfies("24.14.9", range: npm12))
    #expect(!NodeEngineRange.satisfies("23.0.0", range: npm12))
    #expect(NodeEngineRange.satisfies("20.18.0", range: "^20.17.0 || >=22.9.0"))
    #expect(NodeEngineRange.satisfies("18.2.0", range: ">=10"))
    #expect(NodeEngineRange.satisfies("16.4.0", range: "16.x"))
    #expect(!NodeEngineRange.satisfies("17.0.0", range: "16.x"))
    #expect(NodeEngineRange.satisfies("14.18.1", range: "~14.18.0"))
    #expect(NodeEngineRange.satisfies("14.0.0", range: "12 - 14.0.0"))
    #expect(NodeEngineRange.satisfies("20.0.0", range: "something odd"))
}

@Test func npmIsOfferedTheNewestReleaseItsNodeSupports() {
    let engines: [String: String?] = [
        "12.2.3": "^22.22.2 || ^24.15.0 || >=26.0.0",
        "12.0.0-pre.1": ">=20",
        "11.21.3": "^20.17.0 || >=22.9.0",
        "11.19.1": "^20.17.0 || >=22.9.0",
        "10.9.9": "^18.17.0 || >=20.5.0"
    ]
    #expect(newestPackageVersion(engines: engines, nodeVersion: "20.19.0", current: "10.9.9", latest: "12.2.3") == "11.21.3")
    #expect(newestPackageVersion(engines: engines, nodeVersion: "24.22.1", current: "11.19.1", latest: "12.2.3") == "12.2.3")
    #expect(newestPackageVersion(engines: engines, nodeVersion: "18.20.0", current: "10.9.9", latest: "12.2.3") == "10.9.9")
    // A latest version the document doesn't know is kept.
    #expect(newestPackageVersion(engines: engines, nodeVersion: "18.20.0", current: "10.9.9", latest: "13.0.0") == "13.0.0")
}

@Test func staleMacPortsIndexWarns() throws {
    let now = Date()
    #expect(macPortsIndexWarning(lastRefreshed: now.addingTimeInterval(-3 * 86_400), now: now) == nil)
    #expect(macPortsIndexWarning(lastRefreshed: nil, now: now) == nil)
    #expect(macPortsIndexWarning(lastRefreshed: now.addingTimeInterval(-30 * 86_400), now: now)?.contains("30 days") == true)

    let fileManager = FileManager.default
    let sources = fileManager.temporaryDirectory.appendingPathComponent("Upkeep-MacPorts-\(UUID().uuidString)")
    defer { try? fileManager.removeItem(at: sources) }
    let tree = sources.appendingPathComponent("rsync.macports.org/macports/release/tarballs/ports")
    try fileManager.createDirectory(at: tree.appendingPathComponent("devel/git"), withIntermediateDirectories: true)
    let index = tree.appendingPathComponent("PortIndex")
    try Data("x".utf8).write(to: index)
    let date = now.addingTimeInterval(-20 * 86_400)
    try fileManager.setAttributes([.modificationDate: date], ofItemAtPath: index.path)
    #expect(abs((macPortsIndexDate(sources: sources)?.timeIntervalSince1970 ?? 0) - date.timeIntervalSince1970) < 1)
}

@Test func runtimeLinesFollowTheirOwnPatchReleases() {
    let installed = ["3.12.4", "3.12.6", "3.13.1t", "3.14.0rc1"].compactMap(RuntimeVersionName.python)
    let available = ["3.12.10", "3.12.9", "3.13.1", "3.13.9t", "3.14.0", "3.14.1", "3.15.0a2", "3.12-dev", "pypy3.10-7.3.17"]
        .compactMap(RuntimeVersionName.python)
    let updates = runtimeLineUpdates(installed: installed, available: available)
    #expect(updates == [
        RuntimeLineUpdate(line: "3.12", current: "3.12.6", latest: "3.12.10"),
        RuntimeLineUpdate(line: "3.13t", current: "3.13.1t", latest: "3.13.9t"),
        RuntimeLineUpdate(line: "3.14", current: "3.14.0rc1", latest: "3.14.1")
    ])
    // Stable lines are never offered prereleases.
    let ruby = runtimeLineUpdates(
        installed: ["3.4.1"].compactMap(RuntimeVersionName.ruby),
        available: ["3.4.8", "3.4.9-preview1", "4.0.0", "jruby-10.0.0.0"].compactMap(RuntimeVersionName.ruby)
    )
    #expect(ruby == [RuntimeLineUpdate(line: "3.4", current: "3.4.1", latest: "3.4.8")])
    #expect(RuntimeVersionName.python("miniconda3-latest") == nil)
}

@Test func googleCloudVersionsParse() {
    let version = Data(#"{"Google Cloud SDK": "594.0.1", "bq": "2.1.42", "core": "2026.11.21"}"#.utf8)
    #expect(parseGoogleCloudVersion(version) == "594.0.1")
    #expect(parseGoogleCloudChannelVersion(Data(#"{"components": [], "revision": 20261121205138, "version": "594.0.1"}"#.utf8)) == "594.0.1")
}

@Test func azureExtensionsSkipPreviewsAndDevBuilds() throws {
    let installed = try #require(parseAzureInstalledExtensions(Data("""
        [{"experimental": false, "extensionType": "whl", "name": "ssh", "path": "/x/ssh", "preview": false, "version": "2.0.5"},
         {"experimental": false, "extensionType": "dev", "name": "mine", "path": "/src/mine", "preview": false, "version": "0.1.0"},
         {"experimental": false, "extensionType": "whl", "name": "acat", "path": "/x/acat", "preview": false, "version": "0.9.0"}]
        """.utf8)))
    #expect(installed.map(\.name) == ["ssh", "acat"])
    let available = parseAzureAvailableExtensions(Data("""
        [{"experimental": false, "installed": "True (upgrade available)", "name": "ssh", "preview": false, "summary": "s", "version": "2.0.9"},
         {"experimental": false, "installed": true, "name": "acat", "preview": true, "summary": "a", "version": "1.0.0b1"}]
        """.utf8))
    #expect(azureExtensionLatest(installed: installed[0], available: available["ssh"]) == "2.0.9")
    #expect(azureExtensionLatest(installed: installed[1], available: available["acat"]) == "0.9.0")
}

@Test func simulatorRuntimesFollowTheSelectedXcode() throws {
    let runtimes = try #require(parseSimulatorRuntimes(Data("""
        {"A": {"build": "24B8117", "version": "27.2", "platformIdentifier": "com.apple.platform.iphonesimulator", "state": "Ready"},
         "B": {"build": "24B91016s", "version": "27.2", "platformIdentifier": "com.apple.platform.iphonesimulator", "state": "Ready"},
         "C": {"build": "24S116", "version": "27.2", "platformIdentifier": "com.apple.platform.watchsimulator", "state": "Ready"},
         "D": {"build": "23A100", "version": "26.0", "platformIdentifier": "com.apple.platform.iphonesimulator", "state": "Ready"}}
        """.utf8)))
    let sdks = parseSimulatorSDKs(Data("""
        [{"canonicalName": "iphonesimulator27.2", "platformVersion": "27.2", "productBuildVersion": "24B8118"},
         {"canonicalName": "watchsimulator27.2", "platformVersion": "27.2", "productBuildVersion": "24S118"},
         {"canonicalName": "appletvsimulator27.2", "platformVersion": "27.2", "productBuildVersion": "24K122"},
         {"canonicalName": "macosx27.2", "platformVersion": "27.2", "productBuildVersion": "26C100"}]
        """.utf8))
    let index = try PropertyListSerialization.data(fromPropertyList: ["sdkToSimulatorMappings": [
        ["sdkIdentifier": "iphoneos27.2", "sdkBuildUpdate": "24B8118", "simulatorBuildUpdate": "24B8117", "affinity": "preferred"],
        ["sdkIdentifier": "iphoneos27.2", "sdkBuildUpdate": "24B8118", "simulatorBuildUpdate": "24B91016s"],
        ["sdkIdentifier": "watchos27.2", "sdkBuildUpdate": "24S118", "simulatorBuildUpdate": "24S118"],
        ["sdkIdentifier": "appletvos27.2", "sdkBuildUpdate": "24K122", "simulatorBuildUpdate": "24K150"]
    ]], format: .xml, options: 0)
    let mappings = try #require(parseSimulatorMappings(index))
    let statuses = simulatorRuntimeStatuses(runtimes: runtimes, sdks: sdks, mappings: mappings)
    #expect(statuses == [
        SimulatorRuntimeStatus(platform: "com.apple.platform.iphoneos", version: "27.2", current: "24B8117", latest: "24B8117"),
        // The release-candidate watch runtime is offered the release build.
        SimulatorRuntimeStatus(platform: "com.apple.platform.watchos", version: "27.2", current: "24S116", latest: "24S118")
    ])
}

@Test func newManagersHaveInstallPlans() throws {
    let pyenv = DeveloperPackage(name: "Python 3.12", currentVersion: "3.12.6", latestVersion: "3.12.10",
                                 manager: .pyenv, executablePath: "/opt/homebrew/bin/pyenv", registryIdentifier: "3.12")
    guard case let .command(_, arguments, _) = try DeveloperPackageInstallAdapters.plan(for: pyenv, version: "3.12.10") else {
        Issue.record("Expected a command"); return
    }
    #expect(arguments == ["install", "--skip-existing", "3.12.10"])
    let gcloud = DeveloperPackage(name: "Google Cloud CLI", currentVersion: "590.0.0", latestVersion: "594.0.1",
                                  manager: .googleCloud, executablePath: "/opt/homebrew/bin/gcloud")
    guard case let .command(_, gcloudArguments, _) = try DeveloperPackageInstallAdapters.plan(for: gcloud, version: "594.0.1") else {
        Issue.record("Expected a command"); return
    }
    #expect(gcloudArguments == ["components", "update", "--version=594.0.1", "--quiet"])
    let simulator = DeveloperPackage(name: "watchOS 27.2 Simulator", currentVersion: "24S116", latestVersion: "24S118",
                                     manager: .xcodeSimulators, executablePath: "/usr/bin/xcrun", registryIdentifier: "watchOS")
    #expect(simulator.isOutdated)
    guard case let .command(_, simulatorArguments, _) = try DeveloperPackageInstallAdapters.plan(for: simulator, version: "24S118") else {
        Issue.record("Expected a command"); return
    }
    #expect(simulatorArguments == ["xcodebuild", "-downloadPlatform", "watchOS"])
}
