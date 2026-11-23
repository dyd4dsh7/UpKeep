import Foundation
import Testing
@testable import Upkeep

private func app(_ name: String, _ bundleID: String?, at path: String, version: String = "1.0") -> InstalledApp {
    InstalledApp(name: name, bundleIdentifier: bundleID, installedVersion: version, buildVersion: nil,
                 url: URL(fileURLWithPath: path), sparkleFeedURL: nil, githubRepository: nil, hasAppStoreReceipt: false)
}

private func package(_ name: String, _ manager: DeveloperPackageManager, _ version: String = "1.0",
                     context: String? = nil, executable: String = "/fixture/bin/tool") -> DeveloperPackage {
    DeveloperPackage(name: name, currentVersion: version, latestVersion: version, manager: manager,
                     executablePath: executable, installationContext: context)
}

private func formula(_ token: String, dependency: Bool = false) -> HomebrewPackage {
    HomebrewPackage(token: token, displayName: token, description: nil, homepage: nil, license: nil,
                    installedVersion: "1.0", currentVersion: "1.0", kind: .formula, isOutdated: false,
                    isDependency: dependency, dependencies: [])
}

private func groups(apps: [InstalledApp] = [], packages: [DeveloperPackage] = [], formulae: [HomebrewPackage] = [],
                    homebrewPaths: Set<String> = []) -> [DuplicateGroup] {
    DuplicateFinder.groups(apps: apps, developerPackages: packages, homebrewPackages: formulae,
                           isHomebrewInstalled: { homebrewPaths.contains($0) })
}

@Test func appsWithTheSameBundleIDAreOneGroup() {
    let found = groups(apps: [
        app("Editor", "com.example.editor", at: "/Applications/Editor.app", version: "2.0"),
        app("Editor", "com.example.editor", at: "/Users/test/Downloads/Editor.app", version: "1.5"),
        app("Other", "com.example.other", at: "/Applications/Other.app"),
        app("Upkeep", InstalledApp.upkeepBundleIdentifier, at: "/Applications/Upkeep.app"),
        app("Upkeep", InstalledApp.upkeepBundleIdentifier, at: "/tmp/Upkeep.app")
    ])
    #expect(found.count == 1)
    #expect(found[0].kind == .appCopies && found[0].members.count == 2)
    #expect(found[0].members.first { $0.id == found[0].newestID }?.version == "2.0")
}

@Test func globalToolsInstalledTwiceAreGroupedButBundledAndEnvironmentPackagesAreNot() {
    let found = groups(packages: [
        package("@openai/codex", .npm, "0.147.0", executable: "/opt/homebrew/bin/npm"),
        package("@openai/codex", .npm, "0.171.0", context: "NVM Node 24.22.1"),
        package("typescript", .npm, context: "NVM Node 22"), package("typescript", .pnpm),
        package("pnpm", .npm, "12.18.0", context: "NVM Node 24"), package("pnpm", .pnpm, "12.18.0", context: "NVM Node 24"),
        package("npm", .npm, context: "NVM Node 22"), package("npm", .npm, context: "NVM Node 24"),
        package("packaging", .python, executable: "/usr/bin/python3"), package("packaging", .python, executable: "/opt/homebrew/bin/python3"),
        package("json", .rubyGems, context: "Ruby 3.4"), package("json", .rubyGems, context: "Ruby 4.0")
    ])
    #expect(Set(found.map(\.id)) == ["package:javascript:@openai/codex", "package:javascript:typescript"])
    #expect(found.allSatisfy { $0.kind == .packageCopies && $0.members.count == 2 })
}

@Test func runtimeVersionsAreGroupedNewestFirst() {
    let found = groups(packages: [
        package("Node.js", .node, "22.23.4", context: "NVM Node 22.23.4"),
        package("Node.js", .node, "26.13.0", context: "NVM Node 26.13.0"),
        package("Node.js", .node, "24.22.2", context: "NVM Node 24.22.2"),
        package("stable-aarch64-apple-darwin", .rustup)
    ])
    #expect(found.count == 1)
    #expect(found[0].kind == .runtimeVersions && found[0].title == "Node.js" && found[0].members.count == 3)
    #expect(found[0].members.map(\.version) == ["26.13.0", "24.22.2", "22.23.4"])
    #expect(found[0].newestID == found[0].members.first?.id)
}

@Test func aToolFromHomebrewAndAnotherInstallerIsFlagged() {
    let nvmNode = package("Node.js", .node, "24.22.2", context: "NVM Node 24.22.2", executable: "/Users/test/.nvm/versions/node/v24.22.2/bin/node")
    let brewNode = package("Node.js", .node, "26.13.1", executable: "/opt/homebrew/bin/node")
    let found = groups(packages: [nvmNode, brewNode, package("pnpm", .npm, "12.0", executable: "/opt/homebrew/bin/npm")],
                       formulae: [formula("node"), formula("pnpm"), formula("libuv", dependency: true), formula("jq")],
                       homebrewPaths: ["/opt/homebrew/bin/node"])
    let twoInstallers = found.filter { $0.kind == .twoInstallers }
    #expect(twoInstallers.map(\.id) == ["tools:pnpm"])
    // Homebrew's own Node.js is already one of the listed versions.
    let node = found.first { $0.kind == .runtimeVersions }
    #expect(node?.members.map(\.id) == ["developer|\(brewNode.id)", "developer|\(nvmNode.id)"])

    // When Homebrew's Node.js is not listed as a runtime, its formula joins the versions.
    let withFormula = groups(packages: [nvmNode], formulae: [formula("node")])
    #expect(withFormula.first?.members.count == 2)
    #expect(withFormula.first?.members.last?.id == "homebrew|\(formula("node").id)")
    #expect(DuplicateFinder.homebrewBaseName("python@3.12") == "python")
}

@MainActor
@Test func keepOnlyRemovesTheOtherCopiesAndHiddenGroupsStayHidden() async {
    let suite = "Upkeep.DuplicateTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removeTestDomain(forName: suite) }
    let settings = AppSettings(defaults: UserDefaults(testSuiteName: suite)!)
    let uninstaller = TrashRecorder()
    let store = CVEStoreFixture.makeStore(settings: settings, appUninstaller: uninstaller,
                                          appDataLibrary: FileManager.default.temporaryDirectory)
    let original = CVEStoreFixture.app
    let copy = app(original.name, original.bundleIdentifier, at: "/fixture/Downloads/Editor.app", version: "0.9")
    store.apps = [original, copy]
    let group = try! #require(store.duplicateGroups.first)
    let kept = try! #require(group.members.first { $0.version == original.installedVersion })

    await store.keepOnly(kept, in: group)
    #expect(await uninstaller.trashed == [copy.url])
    #expect(store.apps == [original])
    #expect(store.duplicateGroups.isEmpty)

    store.apps = [original, copy]
    settings.setDuplicateGroupIgnored(true, id: group.id)
    #expect(store.duplicateGroups.isEmpty)
    settings.restoreIgnoredDuplicateGroups()
    #expect(store.duplicateGroups.count == 1)
}

private actor TrashRecorder: AppUninstalling {
    var trashed: [URL] = []
    func moveToTrash(_ url: URL) async throws -> URL? { trashed.append(url); return nil }
    func moveDataToTrash(_ urls: [URL]) async -> AppDataTrashResult { AppDataTrashResult() }
}

// MARK: - The copy in use

private func makeNpmPrefix(_ root: URL, packages: [String]) throws -> URL {
    let bin = root.appendingPathComponent("bin"), modules = root.appendingPathComponent("lib/node_modules")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    try Data().write(to: bin.appendingPathComponent("npm"))
    for name in packages {
        let script = modules.appendingPathComponent(name).appendingPathComponent("bin/cli.js")
        try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: script)
        try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent(URL(fileURLWithPath: name).lastPathComponent),
                                                   withDestinationURL: script)
    }
    return bin
}

@Test func theCopyFirstOnPATHIsInUse() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("UpkeepActive-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let brewBin = try makeNpmPrefix(root.appendingPathComponent("homebrew"), packages: ["@openai/codex"])
    let nvmBin = try makeNpmPrefix(root.appendingPathComponent("nvm"), packages: ["@openai/codex"])
    let emptyBin = try makeNpmPrefix(root.appendingPathComponent("other"), packages: [])
    let brewCopy = package("@openai/codex", .npm, "0.147.0", executable: brewBin.appendingPathComponent("npm").path)
    let nvmCopy = package("@openai/codex", .npm, "0.171.0", context: "NVM Node 24", executable: nvmBin.appendingPathComponent("npm").path)
    let notThere = package("@openai/codex", .npm, "0.100.0", context: "Other", executable: emptyBin.appendingPathComponent("npm").path)
    let found = groups(packages: [brewCopy, nvmCopy, notThere])

    let nvmFirst = ActiveInstallations.activeIDs(in: found, path: [emptyBin.path, nvmBin.path, brewBin.path])
    #expect(nvmFirst == ["developer|\(nvmCopy.id)"])
    let brewFirst = ActiveInstallations.activeIDs(in: found, path: ["/usr/bin", brewBin.path + "/", nvmBin.path])
    #expect(brewFirst == ["developer|\(brewCopy.id)"])
    #expect(ActiveInstallations.activeIDs(in: found, path: ["/usr/bin"]).isEmpty)
}

@Test func theAppMacOSOpensIsMarked() {
    let primary = app("Editor", "com.example.editor", at: "/Applications/Editor.app")
    let copy = app("Editor", "com.example.editor", at: "/Users/test/Downloads/Editor.app")
    let found = groups(apps: [primary, copy])
    let active = ActiveInstallations.activeIDs(in: found, path: [], defaultApp: { _ in URL(fileURLWithPath: "/Users/test/Downloads/Editor.app") })
    #expect(active == ["app|\(copy.id)"])
}

@Test func shellStartupOutputIsIgnoredWhenReadingPATH() {
    let output = "Welcome back!\nUPKEEP_PATH=/Users/test/.nvm/versions/node/v24/bin:/opt/homebrew/bin:relative:/usr/bin\n"
    #expect(LoginShellPath.parse(output) == ["/Users/test/.nvm/versions/node/v24/bin", "/opt/homebrew/bin", "/usr/bin"])
    #expect(LoginShellPath.parse("no marker").isEmpty)
}

@Test func copiesDescribeWhereTheyLive() {
    let brew = DuplicateMember.developer(package("@openai/codex", .npm, executable: "/opt/homebrew/bin/npm"))
    #expect(brew.place == "Homebrew’s npm")
    #expect(brew.path == "/opt/homebrew/bin")
    let nvm = DuplicateMember.developer(package("pnpm", .npm, context: "NVM Node 24.22.1", executable: "/x/bin/npm"))
    #expect(nvm.place == "NVM Node 24.22.1")
}
