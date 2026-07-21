import Foundation
import Testing
@testable import Upkeep

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
