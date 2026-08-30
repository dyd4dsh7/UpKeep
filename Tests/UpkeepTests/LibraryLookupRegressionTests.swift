import Foundation
import Testing
@testable import Upkeep

@MainActor
@Test func libraryNameLookupsFollowRenamesReorderingAndMissingMatches() {
    let library = UpkeepLibraryState()
    let app = lookupApp("Widget Desktop")
    let first = lookupPackage("widget", "Widget")
    let second = lookupPackage("widget-app", "Widget App")
    library.apps = [app]
    library.homebrewPackages = [first, second]
    #expect(library.homebrewPackage(forAppNamed: app.name)?.id == first.id)
    #expect(library.app(for: second)?.id == app.id)
    #expect(library.homebrewPackage(forAppNamed: "Missing") == nil)

    library.homebrewPackages.reverse()
    #expect(library.homebrewPackage(forAppNamed: app.name)?.id == second.id)
    library.homebrewPackages = [lookupPackage("other", "Other")]
    #expect(library.homebrewPackage(forAppNamed: app.name) == nil)

    // The same bundle ID/path can acquire a different display name after refresh.
    library.apps = [lookupApp("Other App")]
    #expect(library.app(for: first) == nil)
    #expect(library.app(for: lookupPackage("other", "Other"))?.name == "Other App")

    // Lookups also accept snapshots not currently present in the library.
    #expect(library.homebrewPackage(forAppNamed: "Other Desktop")?.token == "other")
    #expect(library.app(for: lookupPackage("other-app", "Other Desktop"))?.name == "Other App")
    library.apps = []
    library.homebrewPackages = []
    #expect(library.app(for: first) == nil)
    #expect(library.homebrewPackage(forAppNamed: app.name) == nil)
}

@MainActor
@Test func libraryNameLookupsPreserveUnicodeAliasesAndFirstMatch() {
    let library = UpkeepLibraryState()
    library.apps = [lookupApp("Éditeur Desktop"), lookupApp("Éditeur App", path: "Second")]
    let package = lookupPackage("éditeur", "Éditeur")
    library.homebrewPackages = [package]
    #expect(library.homebrewPackage(forAppNamed: "ÉDITEUR Desktop")?.id == package.id)
    #expect(library.app(for: package)?.name == "Éditeur Desktop")
    library.apps.reverse()
    #expect(library.app(for: package)?.name == "Éditeur App")
}

private func lookupApp(_ name: String, path: String = "Widget") -> InstalledApp {
    InstalledApp(
        name: name, bundleIdentifier: "test.lookup.\(path)", installedVersion: "1.0",
        buildVersion: nil, url: URL(fileURLWithPath: "/Applications/\(path).app"),
        sparkleFeedURL: nil, githubRepository: nil, hasAppStoreReceipt: false
    )
}

private func lookupPackage(_ token: String, _ name: String) -> HomebrewPackage {
    HomebrewPackage(
        token: token, displayName: name, description: nil, homepage: nil, license: nil,
        installedVersion: "1.0", currentVersion: "1.1", kind: .cask,
        isOutdated: true, isDependency: false, dependencies: []
    )
}
