// swift-tools-version: 6.0
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
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "UpkeepTests",
            dependencies: ["Upkeep"],
            path: "Tests/UpkeepTests"
        )
    ]
)
