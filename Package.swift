// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Upkeep",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Upkeep", targets: ["Upkeep"])
    ],
    dependencies: [
        // Resolve the same Testing sources locally and in CI. Some Command Line
        // Tools installations omit required runtime support; use full Xcode
        // if the test linker cannot find `_TestingInterop`.
        .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.4.1")
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
