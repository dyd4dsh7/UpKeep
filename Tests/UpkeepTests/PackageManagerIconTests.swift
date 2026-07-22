import AppKit
import Testing
@testable import Upkeep

@Test func everyDeveloperManagerHasALoadableLogo() throws {
    for manager in DeveloperPackageManager.allCases {
        let url = try #require(bundledPackageAssetURL(named: manager.assetName), "Missing logo for \(manager.rawValue)")
        #expect(NSImage(contentsOf: url) != nil, "Unreadable logo for \(manager.rawValue)")
    }
}
