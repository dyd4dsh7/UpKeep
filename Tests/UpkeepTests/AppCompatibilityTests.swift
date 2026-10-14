import Foundation
import Testing
@testable import Upkeep

@Test func incompatibleStagedBundlePreservesInstalledFiles() throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("CompatibilityStage.\(UUID().uuidString)")
    defer { try? manager.removeItem(at: root) }
    let source = root.appendingPathComponent("Downloaded.app")
    let staged = root.appendingPathComponent("Staged.app")
    let installed = root.appendingPathComponent("Installed.app")
    let binaries = source.appendingPathComponent("Contents/MacOS")
    try manager.createDirectory(at: binaries, withIntermediateDirectories: true)
    try manager.copyItem(at: URL(fileURLWithPath: "/bin/echo"), to: binaries.appendingPathComponent("Fixture"))
    let info = source.appendingPathComponent("Contents/Info.plist")
    func writeMinimum(_ minimum: String) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleExecutable": "Fixture", "CFBundlePackageType": "APPL",
            "CFBundleIdentifier": "test.upkeep.compatibility", "LSMinimumSystemVersion": minimum
        ], format: .xml, options: 0)
        try data.write(to: info, options: .atomic)
    }
    try writeMinimum("1.0")
    try AppCompatibility.current.validateBundle(at: source)
    try writeMinimum("999.0")
    try manager.createDirectory(at: installed, withIntermediateDirectories: true)
    let sentinel = installed.appendingPathComponent("original")
    let original = Data("working-installed-app".utf8)
    try original.write(to: sentinel)
    var replaced = false
    #expect(throws: AppCompatibility.CompatibilityError.self) {
        try StagedReplacementTransaction.perform(replacement: source, staged: staged, installed: installed,
            copy: { try manager.copyItem(at: $0, to: $1) },
            validate: { try AppCompatibility.current.validateBundle(at: $0) },
            replace: { _, _ in replaced = true })
    }
    #expect(!replaced)
    #expect(try Data(contentsOf: sentinel) == original)
    #expect(manager.fileExists(atPath: staged.appendingPathComponent("Contents/MacOS/Fixture").path))
}

@Test func sparkleSelectsNewestCompatibleRelease() throws {
    let feed = """
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
    <item><sparkle:minimumSystemVersion>15.0.0</sparkle:minimumSystemVersion><enclosure sparkle:version="3.0" url="https://example.com/three.zip" /></item>
    <item><sparkle:minimumSystemVersion>14.0.0</sparkle:minimumSystemVersion><enclosure sparkle:version="2.0" url="https://example.com/two.zip" /></item>
    <item><sparkle:maximumSystemVersion>13.0.0</sparkle:maximumSystemVersion><enclosure sparkle:version="4.0" url="https://example.com/four.zip" /></item>
    <item><sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements><enclosure sparkle:version="5.0" url="https://example.com/five.zip" /></item>
    </channel></rss>
    """
    let parser = SparkleFeedParser(data: Data(feed.utf8), baseURL: URL(string: "https://example.com/feed")!)
    #expect(parser.parse(compatibility: AppCompatibility(systemVersion: "14.7.0", isAppleSilicon: false))?.version == "2.0")
    #expect(parser.parse(compatibility: AppCompatibility(systemVersion: "14.7.0", isAppleSilicon: true))?.version == "5.0")
}

@Test func stagedCompatibilityRejectsUnsupportedOSArchitectureAndMalformedRequirements() throws {
    let intel = AppCompatibility(systemVersion: "14.7.0", isAppleSilicon: false)
    #expect(throws: AppCompatibility.CompatibilityError.self) {
        try intel.validateBundle(info: ["LSMinimumSystemVersion": "15.0"], architectures: ["x86_64"])
    }
    #expect(throws: AppCompatibility.CompatibilityError.self) {
        try intel.validateBundle(info: [:], architectures: ["arm64"])
    }
    #expect(throws: AppCompatibility.CompatibilityError.self) {
        try intel.validateBundle(info: [:], architectures: [])
    }
    #expect(!intel.permits(minimum: "unknown"))
    #expect(!intel.permits(minimum: "14..0"))
    #expect(!intel.permits(minimum: nil, hardware: "unknown"))
    #expect(throws: AppCompatibility.CompatibilityError.self) {
        try intel.validateBundle(info: ["LSMinimumSystemVersion": 14], architectures: ["x86_64"])
    }
    #expect(throws: AppCompatibility.CompatibilityError.self) {
        try intel.validateBundle(info: ["LSMinimumSystemVersionByArchitecture": ["x86_64": 14]], architectures: ["x86_64"])
    }
    try intel.validateBundle(info: ["LSMinimumSystemVersion": "14.0"], architectures: ["arm64", "x86_64"])
    let arm = AppCompatibility(systemVersion: "14.7.0", isAppleSilicon: true)
    #expect(throws: AppCompatibility.CompatibilityError.self) {
        try arm.validateBundle(info: ["LSMinimumSystemVersionByArchitecture": ["arm64": "15.0", "x86_64": "13.0"]],
                               architectures: ["arm64", "x86_64"])
    }
}
