import Foundation
import Testing
@testable import Upkeep

// Outputs below were captured from pixi 0.84.2, Krew 0.5.0, juliaup 1.24.0,
// opam 2.6.1, Dart 3.14.1 and Poetry 2.5.2.

@Test func pixiGlobalListAndManifestParse() {
    let list = Data(#"[{"name":"ripgrep","dependencies":[{"name":"ripgrep","version":"15.2.0"}],"exposed":[{"exposed_name":"rg","executable":"rg"}]}]"#.utf8)
    #expect(parsePixiGlobalList(list) == [.init(name: "ripgrep", dependencies: [.init(name: "ripgrep", version: "15.2.0")])])

    let manifest = parsePixiGlobalManifest("""
        version = 1

        [envs.ripgrep]
        channels = ["conda-forge"]
        dependencies = { ripgrep = "*" }
        exposed = { rg = "rg" }

        [envs.tools]
        channels = ["conda-forge", "bioconda"]

        [envs.tools.dependencies]
        samtools = "==1.21"
        """)
    #expect(manifest["ripgrep"] == PixiManifestEnvironment(channels: ["conda-forge"], specs: ["ripgrep": "*"]))
    #expect(manifest["tools"]?.channels == ["conda-forge", "bioconda"])
    #expect(manifest["tools"]?.specs["samtools"] == "==1.21")
}

@Test func pixiSearchPicksTheNewestVersionForThePlatform() {
    let search = Data(#"{"osx-arm64":[{"version":"15.1.0","build":"h0"},{"version":"15.2.0","build":"h1"}],"osx-64":[{"version":"16.0.0"}]}"#.utf8)
    #expect(parsePixiSearchLatest(search, platform: "osx-arm64") == "15.2.0")
    #expect(parsePixiSearchLatest(Data("{}".utf8), platform: "osx-arm64") == nil)
}

@Test func krewReceiptsAndIndexManifestsParse() {
    let receipt = """
        apiVersion: krew.googlecontainertools.github.com/v1alpha2
        kind: Plugin
        metadata:
          creationTimestamp: "2026-11-22T21:58:40Z"
          name: ctx
        spec:
          caveats: |
            If fzf is installed on your machine, you can interactively choose
          homepage: https://github.com/ahmetb/kubectx
          platforms:
          - bin: kubectx
            files:
            - from: kubectx-*/kubectx
              to: .
          version: v0.11.0
        status:
          source:
            name: default
        """
    #expect(parseKrewManifest(receipt) == KrewReceipt(name: "ctx", version: "v0.11.0", index: "default"))
    // Index manifests have no status block; the index defaults to "default".
    #expect(parseKrewManifest("metadata:\n  name: ctx\nspec:\n  version: v0.12.0\n")?.version == "v0.12.0")
    #expect(parseKrewManifest("metadata:\n  name: ctx\n") == nil)
}

@Test func juliaupChannelsCompareWithTheVersionDatabase() {
    let configuration = Data(#"""
        {"Default":"1.10","InstalledVersions":{"1.10.14+0.aarch64.apple.darwin14":{"Path":"./julia-1.10.14"}},
         "InstalledChannels":{"1.10":{"Version":"1.10.14+0.aarch64.apple.darwin14"},"release":{"Version":"1.13.3+0.aarch64.apple.darwin14"},
         "dev":{"Command":"/usr/local/bin/julia"}}}
        """#.utf8)
    let database = Data(#"{"AvailableChannels":{"1.10":{"Version":"1.10.14+0.aarch64.apple.darwin14"},"release":{"Version":"1.13.4+0.aarch64.apple.darwin14"}}}"#.utf8)
    let channels = parseJuliaupChannels(configuration: configuration, versionDatabase: database)
    #expect(channels.map(\.channel) == ["1.10", "release"])
    #expect(channels.last.map { juliaVersion($0.latest) } == "1.13.4")
    #expect(juliaVersion("1.10.14+0.aarch64.apple.darwin14") == "1.10.14")
}

@Test func opamRootsAndUpgradePlansParse() {
    let roots = parseOpamRoots("""
        # Packages matching: installed & root
        # Name       # Installed
        ocaml-system 5.5.2
        seq          base
        upkeep-dummy 1.0
        """)
    #expect(roots.map(\.name) == ["upkeep-dummy"])
    // Real dry run output, and the `change` form from opam's OpamActionGraph.to_json.
    let pair = Data(#"{"solution":[{"remove":{"name":"upkeep-dummy","version":"1.0"}},{"install":{"name":"upkeep-dummy","version":"2.0"}}]}"#.utf8)
    #expect(parseOpamUpgradeSolution(pair) == ["upkeep-dummy": "2.0"])
    let change = Data(#"{"solution":[{"change":["up",{"name":"dune","version":"3.17.0"},{"name":"dune","version":"3.20.2"}]},{"change":["down",{"name":"x","version":"2"},{"name":"x","version":"1"}]}]}"#.utf8)
    #expect(parseOpamUpgradeSolution(change) == ["dune": "3.20.2"])
    #expect(parseOpamUpgradeSolution(Data(#"{"solution":[]}"#.utf8)).isEmpty)
}

@Test func dartAndPoetryOutputsParse() {
    let list = parseDartGlobalList("dhttpd 4.0.0\nwebdev 3.7.0 from Git repository \"https://example.com/webdev\"\nlocal 1.0.0 at path \"/tmp/local\"\n")
    #expect(list.map(\.name) == ["dhttpd"])
    #expect(parsePoetryVersion("Poetry (version 2.5.2)") == "2.5.2")
    #expect(parsePoetryVersion("Poetry (version 2.0.0b3)") == "2.0.0b3")
    #expect(parsePoetryVersion("nonsense") == nil)
}

// Formats below follow each tool's source code; these tools were not installed.

@Test func flutterVersionAndReleasesParse() {
    let machine = Data("""
        Waiting for another flutter command to release the startup lock...
        {"frameworkVersion":"3.38.0","channel":"stable","repositoryUrl":"https://github.com/flutter/flutter.git",
         "frameworkRevision":"aaa111","dartSdkVersion":"3.10.0","flutterVersion":"3.38.0"}
        """.utf8)
    #expect(parseFlutterVersion(machine) == FlutterInstallation(version: "3.38.0", channel: "stable", revision: "aaa111"))
    let releases = Data(#"""
        {"base_url":"https://storage.googleapis.com/flutter_infra_release/releases","current_release":{"stable":"bbb222","beta":"ccc333"},
         "releases":[{"hash":"bbb222","channel":"stable","version":"3.50.1","dart_sdk_arch":"arm64"},
                     {"hash":"bbb222","channel":"stable","version":"3.50.1","dart_sdk_arch":"x64"},
                     {"hash":"ccc333","channel":"beta","version":"3.51.0-0.1.pre"}]}
        """#.utf8)
    #expect(flutterChannelRelease(releases, channel: "stable")?.version == "3.50.1")
    #expect(flutterChannelRelease(releases, channel: "master") == nil)
}

@Test func ghcupRawListComparesWithRecommended() {
    let active = parseGHCupRawList("ghc 9.6.6 base-4.18.2.1 hls-powered,2024-07-01\ncabal 3.12.1.0 recommended \n")
    let available = parseGHCupRawList("""
        ghc 9.6.7 recommended,base-4.18.3.0 hls-powered,2025-03-01
        ghc 9.12.2 latest,base-4.21.0.0 2025-03-04
        cabal 3.12.1.0 recommended,latest 
        """)
    let packages = ghcupPackages(active: active, available: available, executablePath: "/x/ghcup")
    #expect(packages.map { "\($0.name) \($0.currentVersion)->\($0.latestVersion)" } == ["ghc 9.6.6->9.6.7", "cabal 3.12.1.0->3.12.1.0"])
}

@Test func swiftlyToolchainsUpdateWithinTheirMinorRelease() {
    let installed = parseSwiftlyToolchains(Data(#"""
        {"toolchains":[{"inUse":true,"isDefault":true,"location":"/x","version":{"major":6,"minor":2,"name":"6.2.0","patch":0,"type":"stable"}},
                       {"inUse":false,"isDefault":false,"location":"/y","version":{"branch":"main","date":"2026-01-01","name":"main-snapshot-2026-01-01","type":"snapshot"}}]}
        """#.utf8))
    #expect(installed == [SwiftlyToolchain(name: "6.2.0", major: 6, minor: 2, isDefault: true)])
    let available = [SwiftlyToolchain(name: "6.2.3", major: 6, minor: 2, isDefault: false),
                     SwiftlyToolchain(name: "6.3.0", major: 6, minor: 3, isDefault: false)]
    let package = swiftlyPackages(installed: installed, available: available, executablePath: "/x/swiftly").first
    #expect(package?.latestVersion == "6.2.3")
    #expect(package?.installationContext == "Default toolchain")
}

@Test func condaListAndDryRunParse() {
    let array = Data(#"[{"name":"numpy","version":"2.1.0","channel":"conda-forge"},{"name":"requests","version":"2.32.0","channel":"pypi"}]"#.utf8)
    let wrapped = Data(#"{"packages":[{"name":"numpy","version":"2.1.0","channel":"conda-forge"}]}"#.utf8)
    #expect(parseCondaList(array).map(\.name) == ["numpy"])
    #expect(parseCondaList(wrapped).map(\.name) == ["numpy"])
    let dryRun = Data(#"""
        {"success":true,"dry_run":true,"actions":{"PREFIX":"/x","LINK":[{"name":"numpy","version":"2.3.1"},{"name":"openssl","version":"3.0.0"}],
         "UNLINK":[{"name":"numpy","version":"2.1.0"},{"name":"openssl","version":"3.5.0"}]}}
        """#.utf8)
    #expect(parseCondaDryRun(dryRun, installed: ["numpy": "2.1.0", "openssl": "3.5.0"]) == ["numpy": "2.3.1"])
    #expect(parseCondaDryRun(Data(#"{"success":true,"message":"All requested packages already installed."}"#.utf8),
        installed: ["numpy": "2.1.0"]).isEmpty)
}

@Test func sdkmanKeepsTheInstalledVendor() throws {
    #expect(sdkmanUpdate(current: "21.0.5-tem", default: "25.0.1-tem") == "25.0.1-tem")
    #expect(sdkmanUpdate(current: "21.0.5-zulu", default: "25.0.1-tem") == "21.0.5-zulu")
    #expect(sdkmanUpdate(current: "9.9.1", default: "9.9.2") == "9.9.2")
    #expect(sdkmanUpdate(current: "9.9.2", default: "9.9.1") == "9.9.2")

    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("Upkeep-SDKMAN-\(UUID().uuidString)")
    defer { try? fileManager.removeItem(at: root) }
    for (candidate, version) in [("java", "21.0.5-tem"), ("gradle", "8.10")] {
        let directory = root.appendingPathComponent("candidates/\(candidate)")
        try fileManager.createDirectory(at: directory.appendingPathComponent(version), withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(atPath: directory.appendingPathComponent("current").path, withDestinationPath: version)
    }
    try fileManager.createDirectory(at: root.appendingPathComponent("candidates/maven"), withIntermediateDirectories: true)
    #expect(sdkmanCurrentVersions(root: root).map { "\($0.candidate) \($0.version)" } == ["gradle 8.10", "java 21.0.5-tem"])

    // A vendor suffix reads like a prerelease to the version helpers.
    let java = DeveloperPackage(name: "java", currentVersion: "21.0.5-tem", latestVersion: "25.0.1-tem",
        manager: .sdkman, executablePath: "/x/sdkman-init.sh", registryIdentifier: "java")
    #expect(java.isOutdated)
    #expect(java.prereleaseChannel == nil)
    guard case let .command(executable, arguments, _) = try DeveloperPackageInstallAdapters.plan(for: java, version: "25.0.1-tem") else {
        Issue.record("Expected a bash command")
        return
    }
    #expect(executable.path == "/bin/bash")
    #expect(arguments.suffix(3) == ["/x/sdkman-init.sh", "java", "25.0.1-tem"])
}

@Test func pixiUpdatesTheWholeEnvironment() throws {
    let package = DeveloperPackage(name: "samtools", currentVersion: "1.20", latestVersion: "1.21", manager: .pixi,
        executablePath: "/x/pixi", registryIdentifier: "tools/samtools", installationContext: "pixi environment tools")
    guard case let .command(_, arguments, _) = try DeveloperPackageInstallAdapters.plan(for: package, version: "1.21") else {
        Issue.record("Expected a pixi command")
        return
    }
    #expect(arguments == ["global", "update", "tools"])
    let uninstall = try DeveloperPackageUninstallAdapters.plan(for: package)
    #expect(uninstall.arguments == ["global", "remove", "--environment", "tools", "samtools"])
}
