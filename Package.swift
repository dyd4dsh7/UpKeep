// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Upkeep",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Upkeep", targets: ["Upkeep"])
    ],
    dependencies: [
        // Command Line Tools exposes `Testing` but not its `_TestingInternals`
        // support module. Keep the package dependency so local CLI builds and CI
        // resolve the same complete test runtime.
        .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.3.2")
    ],
    targets: [
        .executableTarget(
            name: "Upkeep",
            path: "Sources/Upkeep",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "UpkeepTests",
            dependencies: [
                "Upkeep",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/UpkeepTests"
        )
    ]
)
