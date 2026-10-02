import Testing
@testable import Upkeep

@Test func gemInventoryKeepsDefaultAndMultipleVersionsAndIgnoresMalformedLines() {
    let packages = DeveloperInventoryParsers.parseGemInventory(
        "rake (13.2.1, 13.1.0)\njson (default: 2.9.1)\ninvalid line\n",
        outdatedOutput: "rake (13.2.1 < 13.3.0)\ninvalid line\n",
        executablePath: "/fixture/gem")
    #expect(packages.map(\.name) == ["rake", "json"])
    #expect(packages.map(\.currentVersion) == ["13.2.1", "2.9.1"])
    #expect(packages.map(\.latestVersion) == ["13.3.0", "2.9.1"])
    #expect(packages.allSatisfy { $0.manager == .rubyGems && $0.executablePath == "/fixture/gem" })
}
