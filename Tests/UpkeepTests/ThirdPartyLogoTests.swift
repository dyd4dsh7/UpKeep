import AppKit
import Testing
@testable import Upkeep

@Test func everyPermittedLogoIsBundledAndLoadable() throws {
    for name in ThirdPartyLogo.bundledNames {
        let url = try #require(ThirdPartyLogo.url(named: name), "Missing logo for \(name)")
        #expect(NSImage(contentsOf: url) != nil, "Unreadable logo for \(name)")
    }
}

@Test func logosNeedingPermissionAreNotBundled() {
    // npm, Node.js, VS Code, Go and Ollama require permission; asdf and fnm have
    // no official logo; MacPorts, uv, Volta, Python and .NET are not cleared.
    for name in ["npm", "node", "vscode", "go", "ollama", "asdf", "fnm", "macports", "uv", "volta", "python", "dotnet"] {
        #expect(ThirdPartyLogo.url(named: name) == nil, "\(name) must not be bundled")
    }
}

@Test func darkVariantsLoadWhereProvided() throws {
    for name in ["github", "mise", "rustup"] {
        let url = try #require(ThirdPartyLogo.url(named: "\(name)-dark"))
        #expect(NSImage(contentsOf: url) != nil)
    }
}
