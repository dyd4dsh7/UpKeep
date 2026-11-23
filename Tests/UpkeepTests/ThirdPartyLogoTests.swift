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
    // asdf and fnm publish no official logo, so they keep a system symbol. Docker
    // and Hugging Face logos are not bundled until their brand terms are reviewed.
    let withoutBundledLogo: Set<DeveloperPackageManager> = [
        .asdf, .fnm, .dockerImages, .pixi, .krew, .juliaup, .opam, .dart, .poetry, .flutter, .ghcup, .swiftly, .conda, .sdkman, .claudeCode, .nvm
    ]
    for manager in DeveloperPackageManager.allCases where !withoutBundledLogo.contains(manager) {
        #expect(ThirdPartyLogo.bundledNames.contains(manager.assetName), "No logo for \(manager.rawValue)")
    }
    for runtime in LocalModelRuntime.allCases where runtime != .huggingFace {
        #expect(ThirdPartyLogo.bundledNames.contains(runtime.assetName), "No logo for \(runtime.rawValue)")
    }
}

@Test func darkVariantsLoadWhereProvided() throws {
    for name in ["github", "mise", "ollama", "rustup"] {
        let url = try #require(ThirdPartyLogo.url(named: "\(name)-dark"))
        #expect(NSImage(contentsOf: url) != nil)
    }
}

@MainActor
@Test func systemSourceIconsComeFromInstalledAppsNotTheBundle() {
    // Apple and Steam icons are read at runtime and never bundled.
    for name in ["appstore", "testflight", "steam", "softwareupdate"] {
        #expect(ThirdPartyLogo.url(named: name) == nil)
    }
    #expect(SidebarDestination.appStore.installedAppPaths.first == "/System/Applications/App Store.app")
    #expect(ThirdPartyLogo.installedAppIcon(atAnyOf: ["/nonexistent/Fixture.app"]) == nil)
}
