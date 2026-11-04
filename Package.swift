// swift-tools-version: 6.3
import PackageDescription
import Foundation

// SwiftBuild in some Command Line Tools releases omits the bundled Testing
// macro plugin when no -Xswiftc options are supplied. Resolve it from the
// selected compiler rather than requiring caller flags or a second Testing
// package. xcrun honors DEVELOPER_DIR and TOOLCHAINS, including CI's Xcode pin.
private func bundledTestingSettings() -> [SwiftSetting] {
    let lookup = Process()
    lookup.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    lookup.arguments = ["--find", "swiftc"]
    let output = Pipe()
    lookup.standardOutput = output
    lookup.standardError = FileHandle.nullDevice
    do {
        try lookup.run()
    } catch {
        return []
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    lookup.waitUntilExit()
    guard lookup.terminationStatus == 0,
          let compilerPath = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
          !compilerPath.isEmpty else { return [] }
    let bin = URL(fileURLWithPath: compilerPath).deletingLastPathComponent()
    let plugins = bin.deletingLastPathComponent()
        .appendingPathComponent("lib/swift/host/plugins/testing")
    let server = bin.appendingPathComponent("swift-plugin-server")
    guard FileManager.default.fileExists(atPath: plugins.appendingPathComponent("libTestingMacros.dylib").path),
          FileManager.default.isExecutableFile(atPath: server.path) else { return [] }
    return [.unsafeFlags(["-external-plugin-path", "\(plugins.path)#\(server.path)"], .when(platforms: [.macOS]))]
}

let package = Package(
    name: "Upkeep",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Upkeep", targets: ["Upkeep"])
    ],
    targets: [
        .executableTarget(
            name: "Upkeep",
            path: "Sources/Upkeep",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "UpkeepTests",
            // Swift Testing ships with the selected toolchain, including its
            // matching macro plugin and runtime. Do not build a second copy.
            dependencies: ["Upkeep"],
            path: "Tests/UpkeepTests",
            swiftSettings: bundledTestingSettings()
        )
    ]
)
