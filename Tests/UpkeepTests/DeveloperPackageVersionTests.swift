import Foundation
import Testing
@testable import Upkeep

@Test func findsNVMDirectoryFromNodeExecutable() {
    #expect(nvmDirectory(for: "/Users/example/.nvm/versions/node/v24.15.0/bin/node") == "/Users/example/.nvm")
    #expect(nvmDirectory(for: "/opt/homebrew/bin/node") == nil)
    #expect(nvmNodeVersion(for: "/Users/example/.nvm/versions/node/v24.15.0/bin/node") == "24.15.0")
    #expect(nvmNodeVersion(for: "/opt/homebrew/bin/node") == nil)
}

@Test func selectsNodeExecutableMatchingNVMDefaultAlias() {
    let candidates = [
        "/Users/example/.nvm/versions/node/v26.5.0/bin/node",
        "/Users/example/.nvm/versions/node/v24.15.0/bin/node"
    ]

    #expect(preferredNVMExecutable(candidates: candidates, alias: "24") == candidates[1])
    #expect(preferredNVMExecutable(candidates: candidates, alias: "v26.5.0") == candidates[0])
}

@Test func nvmNodeUpdateReplacesTheSelectedRuntimeAndPreservesDefault() throws {
    let fileManager = FileManager.default
    let directory = fileManager.temporaryDirectory
        .appendingPathComponent("UpkeepNVMUpdateTests-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: directory) }

    let log = directory.appendingPathComponent("calls.log")
    let nvmScript = directory.appendingPathComponent("nvm.sh")
    let fakeNVM = """
    nvm() {
        printf '%s\\n' "$*" >> "$NVM_TEST_LOG"
        if [ "$1" = "version" ]; then
            printf 'N/A\\n'
            return 3
        fi
    }
    """
    try Data(fakeNVM.utf8).write(to: nvmScript)

    let arguments = nvmNodeUpdateArguments(
        nvmDirectory: directory.path,
        currentVersion: "22.22.3",
        targetVersion: "22.23.1",
        isDefault: true
    )
    let result = captureDeveloperCommand(
        URL(fileURLWithPath: "/bin/zsh"),
        arguments,
        baseEnvironment: [
            "HOME": directory.path,
            "PATH": "/usr/bin:/bin",
            "NVM_TEST_LOG": log.path
        ]
    )

    #expect(result.status == 0)
    let calls = try String(contentsOf: log, encoding: .utf8)
    #expect(calls.contains("install 22.23.1 --reinstall-packages-from=22.22.3"))
    #expect(calls.contains("alias default 22.23.1"))
    #expect(calls.contains("uninstall 22.22.3"))
}

@Test func nvmNodeUpdateReconcilesAnAlreadyInstalledTarget() throws {
    let fileManager = FileManager.default
    let directory = fileManager.temporaryDirectory
        .appendingPathComponent("UpkeepNVMReconcileTests-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: directory) }

    let log = directory.appendingPathComponent("calls.log")
    let nvmScript = directory.appendingPathComponent("nvm.sh")
    let fakeNVM = """
    nvm() {
        printf '%s\\n' "$*" >> "$NVM_TEST_LOG"
        if [ "$1" = "version" ]; then printf 'v22.23.1\\n'; fi
    }
    """
    try Data(fakeNVM.utf8).write(to: nvmScript)

    let result = captureDeveloperCommand(
        URL(fileURLWithPath: "/bin/zsh"),
        nvmNodeUpdateArguments(
            nvmDirectory: directory.path,
            currentVersion: "22.22.3",
            targetVersion: "22.23.1",
            isDefault: false
        ),
        baseEnvironment: [
            "HOME": directory.path,
            "PATH": "/usr/bin:/bin",
            "NVM_TEST_LOG": log.path
        ]
    )

    #expect(result.status == 0)
    let calls = try String(contentsOf: log, encoding: .utf8)
    #expect(calls.contains("use v22.23.1"))
    #expect(calls.contains("reinstall-packages 22.22.3"))
    #expect(calls.contains("uninstall 22.22.3"))
    #expect(!calls.contains("alias default"))
    #expect(!calls.contains("install 22.23.1"))
}

@Test func parsesCurrentPNPMGlobalInventoryShape() throws {
    let empty = Data(#"[{"path":"/Users/example/Library/pnpm/global/v11","private":true,"dependencies":{}}]"#.utf8)
    #expect(parsePNPMInstalledPackages(empty) == [:])

    let populated = Data(#"[{"dependencies":{"typescript":{"version":"5.9.2"}},"devDependencies":{"tsx":{"version":"4.20.3"}}}]"#.utf8)
    let packages = try #require(parsePNPMInstalledPackages(populated))
    #expect(packages == ["typescript": "5.9.2", "tsx": "4.20.3"])
}

@Test func normalizesJavaScriptRuntimeReleaseVersions() {
    #expect(normalizedJavaScriptRuntimeVersion("1.3.11") == "1.3.11")
    #expect(normalizedJavaScriptRuntimeVersion("bun-v1.3.14") == "1.3.14")
    #expect(normalizedJavaScriptRuntimeVersion("deno 2.9.3") == "2.9.3")
    #expect(normalizedJavaScriptRuntimeVersion("v26.5.0") == "26.5.0")
}

@Test func parsesEditorExtensionInventoryUsingTheLastAtSign() {
    let data = Data("publisher.extension@1.2.3\n@scope/tool@4.5.6\n".utf8)
    #expect(parseExtensionInventory(data) == [
        "publisher.extension": "1.2.3",
        "@scope/tool": "4.5.6"
    ])
}

@Test func parsesYarnClassicGlobalTreeEvents() {
    let data = Data(#"{"type":"tree","data":{"type":"list","trees":[{"name":"typescript@5.9.2","children":[],"hint":null,"color":null,"depth":0},{"name":"@scope/tool@2.1.0","children":[],"hint":null,"color":null,"depth":0}]}}"#.utf8)
    #expect(parseYarnGlobalPackages(data) == ["typescript": "5.9.2", "@scope/tool": "2.1.0"])
}

@Test func parsesRustupUpdateChecks() {
    let data = Data("stable-aarch64-apple-darwin - Update available : 1.88.0 -> 1.89.0\nnightly-aarch64-apple-darwin - Up to date : 1.90.0-nightly\n".utf8)
    let values = parseRustupCheck(data)
    #expect(values.count == 2)
    #expect(values[0].current == "1.88.0")
    #expect(values[0].latest == "1.89.0")
    #expect(values[1].current == values[1].latest)
}

@Test func parsesGoEmbeddedModuleMetadata() throws {
    let data = Data("/Users/example/go/bin/gopls: go1.26.0\n\tpath\tgolang.org/x/tools/gopls\n\tmod\tgolang.org/x/tools\tv0.37.0\n".utf8)
    let tool = try #require(parseGoBuildInfo(data))
    #expect(tool.command == "golang.org/x/tools/gopls")
    #expect(tool.module == "golang.org/x/tools")
    #expect(tool.version == "0.37.0")
}

@Test func developerPackageIdentitySeparatesInstallations() {
    let first = DeveloperPackage(name: "typescript", currentVersion: "5.9.0", latestVersion: "5.9.2", manager: .npm, executablePath: "/nvm/v24/npm", installationContext: "Node 24")
    let second = DeveloperPackage(name: "typescript", currentVersion: "5.9.0", latestVersion: "5.9.2", manager: .npm, executablePath: "/nvm/v26/npm", installationContext: "Node 26")
    #expect(first.id != second.id)
}

@Test func replacingLatestDeveloperPackageVersionPreservesIdentityAndMetadata() {
    let package = DeveloperPackage(
        name: "typescript",
        currentVersion: "5.9.0",
        latestVersion: "5.9.2",
        manager: .npm,
        executablePath: "/nvm/v24/npm",
        registryIdentifier: "typescript",
        installationContext: "Node 24",
        canUpdateAutomatically: false
    )

    let updated = package.replacingLatestVersion(with: "6.0.0-beta.1")

    #expect(updated.id == package.id)
    #expect(updated.name == package.name)
    #expect(updated.currentVersion == package.currentVersion)
    #expect(updated.latestVersion == "6.0.0-beta.1")
    #expect(updated.manager == package.manager)
    #expect(updated.executablePath == package.executablePath)
    #expect(updated.registryIdentifier == package.registryIdentifier)
    #expect(updated.installationContext == package.installationContext)
    #expect(updated.canUpdateAutomatically == package.canUpdateAutomatically)
}

@Test func partialManagerFailureRetainsOnlyTheFailedInstallation() {
    let old24 = DeveloperPackage(name: "npm", currentVersion: "10.0.0", latestVersion: "10.0.0", manager: .npm, executablePath: "/nvm/v24/npm", installationContext: "Node 24")
    let old26 = DeveloperPackage(name: "npm", currentVersion: "11.0.0", latestVersion: "11.0.0", manager: .npm, executablePath: "/nvm/v26/npm", installationContext: "Node 26")
    let new26 = DeveloperPackage(name: "npm", currentVersion: "11.0.0", latestVersion: "11.1.0", manager: .npm, executablePath: "/nvm/v26/npm", installationContext: "Node 26")
    let merged = mergeDeveloperPackageResults(
        fresh: [new26], previous: [old24, old26], failedManagers: [], failedExecutablePaths: ["/nvm/v24/npm"]
    )
    #expect(Set(merged.map(\.id)) == [old24.id, new26.id])
    #expect(merged.first(where: { $0.id == new26.id })?.latestVersion == "11.1.0")
}

@Test func parsesUVManagedPythonNamesAndAvailablePatches() throws {
    let runtime = try #require(parseUVPythonDirectoryName("cpython-3.13.5-macos-aarch64-none"))
    #expect(runtime.implementation == "CPython")
    #expect(runtime.version == "3.13.5")
    #expect(runtime.minor == "3.13")
    let list = Data("cpython-3.13.7-macos-aarch64-none <download available>\ncpython-3.13.5-macos-aarch64-none /managed/python\n".utf8)
    #expect(parseUVPythonList(list, matchingMinor: "3.13") == ["3.13.7", "3.13.5"])
}

@Test func parsesGlobalManagerInventories() {
    let dotnet = Data("Package Id      Version      Commands\n---------------------------------------\ndotnetsay       2.1.0        dotnetsay\n".utf8)
    #expect(parseDotnetToolList(dotnet) == ["dotnetsay": "2.1.0"])

    let ports = Data("The following ports are currently installed:\n  wget @1.25.0_0+ssl (active)\n".utf8)
    #expect(parseMacPortsInstalled(ports).first?.name == "wget")
    #expect(parseMacPortsInstalled(ports).first?.version == "1.25.0")

    let outdated = Data("wget 1.25.0_0 < 1.25.1_0\n".utf8)
    #expect(parseMacPortsOutdated(outdated).first?.latest == "1.25.1")

    let asdf = Data("nodejs 24.0.0\npython 3.13.2\n".utf8)
    #expect(parseASDFCurrent(asdf) == ["nodejs": "24.0.0", "python": "3.13.2"])

    let volta = Data("runtime node@24.15.0\npackage typescript@5.9.2\n".utf8)
    #expect(parseVoltaList(volta) == ["node": "24.15.0", "typescript": "5.9.2"])

    let fnm = Data("* v24.15.0 default\n  v22.22.0\n".utf8)
    let fnmValues = parseFNMList(fnm)
    #expect(fnmValues.count == 2)
    #expect(fnmValues.first?.isDefault == true)
}

@Test func parsesStructuredAndArrowStyleUpdateReports() {
    let mise = Data(#"{"python":{"requested":"3.11","current":"3.11.0","latest":"3.11.9"}}"#.utf8)
    let miseValues = parseGenericOutdatedJSON(mise)
    #expect(miseValues.first?.name == "python")
    #expect(miseValues.first?.latest == "3.11.9")
    let miseInstalled = Data(#"{"node":[{"version":"24.15.0","install_path":"/mise/node/24.15.0"}],"python":[{"version":"3.13.2"}]}"#.utf8)
    #expect(Set(parseMiseInstalledJSON(miseInstalled).map { "\($0.name)@\($0.version)" }) == ["node@24.15.0", "python@3.13.2"])

    let nix = Data("hello: 2.12.1 -> 2.12.2\n".utf8)
    let nixValues = parseNixDryRun(nix)
    #expect(nixValues.first?.name == "hello")
    #expect(nixValues.first?.latest == "2.12.2")
    let profile = Data(#"{"elements":{"hello":{"storePaths":["/nix/store/abcdefghijklmnopqrstuvwxyz123456-hello-2.12.1"]}}}"#.utf8)
    let profileValues = parseNixProfileJSON(profile)
    #expect(profileValues.first?.name == "hello")
    #expect(profileValues.first?.version == "2.12.1")
    #expect(profileValues.first?.selector == "hello")
}

@Test func groupsJavaScriptRuntimesAndPackageManagers() {
    let grouped: Set<DeveloperPackageManager> = [.node, .bun, .deno, .npm, .pnpm, .yarn, .volta, .fnm]
    #expect(Set(DeveloperPackageManager.allCases.filter(\.belongsToJavaScriptEcosystem)) == grouped)
}

@Test func developerSidebarFiltersRemainValidAfterManagerDiscovery() {
    let installed: [DeveloperPackageManager] = [.node, .npm, .python, .vsCode]

    #expect(DeveloperManagerFilter.javaScript.isAvailable(in: installed))
    #expect(DeveloperManagerFilter.javaScript.includes(.node))
    #expect(DeveloperManagerFilter.javaScript.includes(.npm))
    #expect(!DeveloperManagerFilter.javaScript.includes(.python))
    #expect(DeveloperManagerFilter.manager(.vsCode).isAvailable(in: installed))
    #expect(!DeveloperManagerFilter.manager(.cargo).isAvailable(in: installed))
}

@Test func stableVersionMenuFiltersPrereleasesButKeepsInstalledPrerelease() {
    let package = DeveloperPackage(
        name: "example",
        currentVersion: "1.1.0-beta.1",
        latestVersion: "1.0.5",
        manager: .npm,
        executablePath: "/example/npm"
    )
    let versions = selectableDeveloperPackageVersions(
        discovered: [
            "1.2.0-alpha.2", "1.1.0-beta.1", "1.0.5",
            "1.0.5-darwin-arm64", "1.0.4"
        ],
        package: package,
        includePrereleases: false
    )

    #expect(versions.contains("1.1.0-beta.1"))
    #expect(versions.contains("1.0.5"))
    #expect(versions.contains("1.0.4"))
    #expect(!versions.contains("1.2.0-alpha.2"))
    #expect(versions.contains("1.0.5-darwin-arm64"))
    #expect(package.prereleaseChannel == .beta)
}

@Test func prereleaseVersionMenuIncludesAllPublishedChannels() {
    let package = DeveloperPackage(
        name: "example",
        currentVersion: "1.0.4",
        latestVersion: "1.0.5",
        manager: .pnpm,
        executablePath: "/example/pnpm"
    )
    let versions = selectableDeveloperPackageVersions(
        discovered: ["1.2.0-alpha.2", "1.0.5-darwin-arm64", "1.0.5"],
        package: package,
        includePrereleases: true
    )

    #expect(versions.contains("1.2.0-alpha.2"))
    #expect(versions.contains("1.0.5-darwin-arm64"))
}

@Test func canonicalVersionSortsAheadOfEquivalentPlatformBuilds() {
    let versions = [
        "0.144.6-darwin-arm64", "0.144.6-linux-x64", "0.144.6"
    ].sorted(by: VersionComparator.newestFirst)

    #expect(versions.first == "0.144.6")
}
