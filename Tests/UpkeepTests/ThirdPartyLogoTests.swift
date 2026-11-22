import AppKit
import Testing
@testable import Upkeep

@Test func everyBundledLogoIsLoadable() throws {
    for name in ThirdPartyLogo.bundledNames {
        let url = try #require(ThirdPartyLogo.url(named: name), "Missing logo for \(name)")
        #expect(NSImage(contentsOf: url) != nil, "Unreadable logo for \(name)")
    }
}

@Test func everyDeveloperManagerWithAnOfficialLogoHasOne() {
    // asdf and fnm publish no official logo, so they keep a system symbol.
    for manager in DeveloperPackageManager.allCases where ![.asdf, .fnm].contains(manager) {
        #expect(ThirdPartyLogo.bundledNames.contains(manager.assetName), "No logo for \(manager.rawValue)")
    }
    for runtime in LocalModelRuntime.allCases {
        #expect(ThirdPartyLogo.bundledNames.contains(runtime.assetName), "No logo for \(runtime.rawValue)")
    }
}

@Test func darkVariantsLoadWhereProvided() throws {
    for name in ["github", "mise", "ollama", "rustup"] {
        let url = try #require(ThirdPartyLogo.url(named: "\(name)-dark"))
        #expect(NSImage(contentsOf: url) != nil)
    }
}
