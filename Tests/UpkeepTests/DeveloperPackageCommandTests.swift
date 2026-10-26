import Foundation
import Testing
@testable import Upkeep

@Test func commandsSupplyHomeWhenLaunchedWithoutAShellEnvironment() throws {
    let expectedHome = FileManager.default.homeDirectoryForCurrentUser.path
    for base: [String: String] in [[:], ["HOME": ""], ["HOME": "  "]] {
        let result = try CommandRunner.capture(URL(fileURLWithPath: "/bin/sh"),
            ["-c", "printf '%s' \"$HOME\""], environment: base)
        #expect(result.status == 0)
        #expect(String(decoding: result.output, as: UTF8.self) == expectedHome)
        let developerEnvironment = developerCommandEnvironment(for: URL(fileURLWithPath: "/usr/bin/true"), base: base)
        #expect(developerEnvironment["HOME"] == expectedHome)
    }
}

@Test func commandEnvironmentPreservesExplicitHomeAndOtherVariables() {
    let base = ["HOME": "/custom/home", "PATH": "/custom/bin", "CUSTOM_SETTING": "preserved"]
    #expect(CommandRunner.commandEnvironment(base) == base)
    #expect(developerCommandEnvironment(for: URL(fileURLWithPath: "/usr/bin/true"), base: base)["HOME"] == "/custom/home")
}

@Test func nvmDiscoveryIgnoresFinderMetadataAndIncompleteInstallations() throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("UpkeepNVMDiscovery-\(UUID())")
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }
    try Data("Finder metadata".utf8).write(to: root.appendingPathComponent(".DS_Store"))
    for version in ["v24.1.0", "v22.1.0", "v20.1.0"] {
        try manager.createDirectory(at: root.appendingPathComponent("\(version)/bin"), withIntermediateDirectories: true)
    }
    let valid = root.appendingPathComponent("v24.1.0/bin/node")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: valid)
    try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: valid.path)
    let notExecutable = root.appendingPathComponent("v22.1.0/bin/node")
    try Data().write(to: notExecutable)
    try manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: notExecutable.path)
    let discovered = nvmExecutables(named: "node", root: root)
    #expect(discovered.count == 1)
    #expect(discovered.first?.hasSuffix("/v24.1.0/bin/node") == true)
    #expect(nvmExecutables(named: "npm", root: root).isEmpty)
}

@Test func globalDeveloperCommandsProbeWritableHomeInsteadOfLaunchDirectory() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("UpkeepCommandCWDTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    // Mimic pnpm's store-location probe, which uses cwd rather than TMPDIR.
    let result = captureDeveloperCommand(
        URL(fileURLWithPath: "/bin/sh"),
        ["-c", "pwd -P; touch .upkeep-store-probe; test -f .upkeep-store-probe"],
        baseEnvironment: ["HOME": directory.path, "PATH": "/usr/bin:/bin", "TMPDIR": "/"]
    )
    #expect(result.status == 0)
    #expect(String(data: result.data, encoding: .utf8)?.contains(directory.lastPathComponent) == true)
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(".upkeep-store-probe").path))
}

@Test func nodePackageManagerFindsSiblingNodeFromGUIEnvironment() throws {
    let fileManager = FileManager.default
    let directory = fileManager.temporaryDirectory
        .appendingPathComponent("UpkeepNodePathTests-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: directory) }

    let node = directory.appendingPathComponent("node")
    let nodeScript = "#!/bin/sh\nprintf '{\"name\":\"lib\",\"dependencies\":{}}\\n'\n"
    try Data(nodeScript.utf8).write(to: node)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)

    for commandName in ["npm", "pnpm"] {
        let command = directory.appendingPathComponent(commandName)
        try Data("#!/usr/bin/env node\n".utf8).write(to: command)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: command.path)

        let result = captureDeveloperCommand(
            command,
            ["list", "-g", "--json"],
            baseEnvironment: ["HOME": directory.path, "PATH": "/usr/bin:/bin"]
        )
        #expect(result.status == 0)
        #expect(String(data: result.data, encoding: .utf8)?.contains("dependencies") == true)
    }
}

@Test func developerCommandPathKeepsRuntimeDirectoryFirst() throws {
    let executable = URL(fileURLWithPath: "/example/.nvm/versions/node/v24.15.0/bin/npm")
    let environment = developerCommandEnvironment(
        for: executable,
        base: ["HOME": "/Users/tester", "PATH": "/usr/bin:/bin"]
    )

    #expect(environment["PATH"]?.hasPrefix("/example/.nvm/versions/node/v24.15.0/bin:") == true)
    #expect(environment["NVM_BIN"] == "/example/.nvm/versions/node/v24.15.0/bin")
    #expect(environment["PATH"]?.contains("/Users/tester/Library/pnpm/bin") == true)
    #expect(environment["PNPM_HOME"] == "/Users/tester/Library/pnpm")
}

@Test func developerCommandReplacesReadOnlyRootTemporaryDirectory() {
    let executable = URL(fileURLWithPath: "/example/.bun/bin/bun")
    let environment = developerCommandEnvironment(
        for: executable,
        base: [
            "HOME": "/Users/tester",
            "PATH": "/usr/bin:/bin",
            "TMPDIR": "/"
        ]
    )

    let temporaryDirectory = environment["TMPDIR"]
    #expect(temporaryDirectory != nil)
    #expect(temporaryDirectory != "/")
    #expect(environment["TMP"] == temporaryDirectory)
    #expect(environment["TEMP"] == temporaryDirectory)
    #expect(FileManager.default.isWritableFile(atPath: temporaryDirectory ?? "") == true)
}
