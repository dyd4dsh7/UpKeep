// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Upkeep",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Upkeep", targets: ["Upkeep"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "0.12.0")
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
