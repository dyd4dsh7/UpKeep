// swift-tools-version: 6.3
import PackageDescription

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
            resources: [.process("Resources")],
            // Upkeep waits on networks and package managers rather than the CPU.
            // Optimizing for size saves about 1 MB (16%) of code with no
            // measurable change in the list, search, or responsiveness benchmarks.
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]
        ),
        .testTarget(
            name: "UpkeepTests",
            // Swift Testing ships with the selected toolchain, including its
            // matching macro plugin and runtime. Do not build a second copy.
            dependencies: ["Upkeep"],
            path: "Tests/UpkeepTests"
        )
    ]
)
