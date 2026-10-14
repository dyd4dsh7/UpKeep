import Foundation
import Testing
@testable import Upkeep

@Test func customRuntimeRootsAndXDGOwnershipRespectDirectoryBoundaries() {
    let environment = ["HOME": "/fixture/home", "ASDF_DATA_DIR": "/fixture/custom-a",
                       "MISE_DATA_DIR": "/fixture/custom-m", "VOLTA_HOME": "/fixture/custom-v"]
    #expect(runtimeEnvironmentOwners(for: "/fixture/custom-a/shims/npm", environment: environment) == ["asdf"])
    #expect(runtimeEnvironmentOwners(for: "/fixture/custom-m/installs/node/20/bin/npm", environment: environment) == ["mise"])
    #expect(runtimeEnvironmentOwners(for: "/fixture/custom-v/bin/npm", environment: environment) == ["volta"])
    #expect(runtimeEnvironmentOwners(for: "/fixture/custom-a-other/shims/npm", environment: environment).isEmpty)
    #expect(runtimeEnvironmentOwners(for: "/fixture/xdg/mise/shims/npm", environment: ["XDG_DATA_HOME": "/fixture/xdg"]) == ["mise"])
    #expect(runtimeEnvironmentOwners(for: "/fixture/xdg/mise/shims/npm", environment: ["XDG_DATA_HOME": "/fixture/xdg", "MISE_DATA_DIR": "/fixture/override"]).isEmpty == false)
}

@Test func customFNMRootOwnershipResolvesDirectoryAliases() throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("OwnerAliases-\(UUID())")
    defer { try? manager.removeItem(at: root) }
    let data = root.appendingPathComponent("custom data")
    let bin = data.appendingPathComponent("node-versions/v20/installation/bin")
    try manager.createDirectory(at: bin, withIntermediateDirectories: true)
    let executable = bin.appendingPathComponent("npm")
    try Data("fixture".utf8).write(to: executable)
    let alias = root.appendingPathComponent("alias")
    try manager.createSymbolicLink(at: alias, withDestinationURL: data)
    let environment = ["FNM_DIR": alias.path, "HOME": root.path]
    #expect(runtimeEnvironmentOwners(for: executable.path, environment: environment) == ["fnm"])
    #expect(runtimeEnvironmentOwners(for: alias.appendingPathComponent("node-versions/v20/installation/bin/npm").path,
                                    environment: environment) == ["fnm"])
    #expect(runtimeEnvironmentOwners(for: root.appendingPathComponent("custom data-other/node-versions/v20/bin/npm").path,
                                    environment: environment).isEmpty)
    #expect(runtimeEnvironmentOwners(for: executable.path, environment: ["FNM_DIR": "", "HOME": root.path]).isEmpty)
}

@Test func relativeRuntimeOverridesUseTheManagerCommandWorkingDirectory() throws {
    let manager = FileManager.default
    let home = manager.temporaryDirectory.appendingPathComponent("RelativeOwner-\(UUID())")
    try manager.createDirectory(at: home, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: home) }
    let environment = ["HOME": home.path, "ASDF_DATA_DIR": "data-a", "MISE_DATA_DIR": "data-m",
                       "VOLTA_HOME": "data-v", "FNM_DIR": "data-f"]
    #expect(developerCommandWorkingDirectory(base: environment).standardizedFileURL == home.standardizedFileURL)
    for (directory, suffix, owner) in [("data-a", "shims/npm", "asdf"),
                                       ("data-m", "installs/node/20/bin/npm", "mise"),
                                       ("data-v", "bin/npm", "volta"),
                                       ("data-f", "node-versions/v20/installation/bin/npm", "fnm")] {
        let executable = home.appendingPathComponent(directory).appendingPathComponent(suffix)
        try manager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: executable)
        #expect(runtimeEnvironmentOwners(for: executable.path, environment: environment) == [owner])
    }
}
