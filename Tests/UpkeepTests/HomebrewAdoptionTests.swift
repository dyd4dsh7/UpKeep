import Foundation
import Testing
@testable import Upkeep

@Test func homebrewAdoptionIndexPreservesFirstMatchingAlias() {
    let apps = [
        adoptionApp(name: "Visual Studio Code"),
        adoptionApp(name: "Token Only"),
        adoptionApp(name: "Already Installed"),
        adoptionApp(name: "Ignored Font"),
        adoptionApp(name: "Discord"),
        adoptionApp(name: "App Store Edition", updateManagement: .appStore),
        adoptionApp(name: "Sparkle App", hasBuiltInUpdater: true)
    ]
    let catalog = [
        CatalogCask(token: "vscode-first", name: ["Visual Studio Code"], version: "2.0"),
        CatalogCask(token: "vscode-second", name: ["Visual Studio Code"], version: "3.0"),
        CatalogCask(token: "token-only", name: ["Different Product Name"], version: "1.0"),
        CatalogCask(token: "already-installed", name: ["Already Installed"], version: "1.0"),
        CatalogCask(token: "font-ignored-font", name: ["Ignored Font"], version: "1.0"),
        CatalogCask(token: "discord", name: ["Discord"], version: "1.0", autoUpdates: true),
        CatalogCask(token: "app-store-edition", name: ["App Store Edition"], version: "1.0"),
        CatalogCask(token: "sparkle-app", name: ["Sparkle App"], version: "1.0")
    ]

    let matches = HomebrewClient.adoptableApps(
        from: apps,
        catalog: catalog,
        excluding: [installedCask(token: "already-installed")]
    )

    #expect(matches.map(\.caskToken) == ["sparkle-app", "token-only", "vscode-first"])
}

@Test func homebrewAdoptionSkipsAppsOwnedByAnInstalledSiblingCask() {
    let catalog = [
        CatalogCask(token: "utm", name: ["UTM"], version: "5.0.9", artifactAppNames: ["UTM.app"]),
        CatalogCask(token: "utm@beta", name: ["UTM"], version: "5.0.9", artifactAppNames: ["UTM.app"])
    ]
    var installed = installedCask(token: "utm")
    installed.appArtifactNames = ["UTM.app"]

    let matches = HomebrewClient.adoptableApps(
        from: [adoptionApp(name: "UTM")],
        catalog: catalog,
        excluding: [installed]
    )

    #expect(matches.isEmpty)
}

@Test func homebrewAdoptionSkipsAppsOutsideApplications() {
    let catalog = [
        CatalogCask(token: "utm", name: ["UTM"], version: "5.0.9"),
        CatalogCask(token: "stats", name: ["Stats"], version: "3.0")
    ]
    let home = FileManager.default.homeDirectoryForCurrentUser
    let apps = [
        adoptionApp(name: "UTM", url: home.appendingPathComponent("Applications/UTM.app")),
        adoptionApp(name: "Stats", url: URL(fileURLWithPath: "/Applications/Utilities/Stats.app"))
    ]

    let matches = HomebrewClient.adoptableApps(from: apps, catalog: catalog, excluding: [])

    #expect(matches.isEmpty)
}

@Test func homebrewCatalogDecodesAutoUpdateOwnership() throws {
    let data = Data(#"""
        [
          {"token":"discord","name":["Discord"],"version":"0.0.402","auto_updates":true},
          {"token":"tablepro","name":["TablePro"],"version":"0.59.0"}
        ]
        """#.utf8)

    let catalog = try JSONDecoder().decode([CatalogCask].self, from: data)

    #expect(catalog[0].autoUpdates)
    #expect(!catalog[1].autoUpdates)
}

@Test func homebrewAdoptionIndexMeetsInteractiveBudget() {
    let catalog = (0..<10_000).map {
        let suffix = letters($0)
        return CatalogCask(token: "application-\(suffix)", name: ["Application \(suffix)"], version: "2.0")
    }
    let apps = stride(from: 9_900, to: 10_000, by: 1).map {
        adoptionApp(name: "Application \(letters($0))")
    }
    let clock = ContinuousClock()
    let started = clock.now

    let matches = HomebrewClient.adoptableApps(from: apps, catalog: catalog, excluding: [])
    let elapsed = started.duration(to: clock.now)

    #expect(matches.count == apps.count)
    #expect(elapsed < .seconds(1), "Indexed adoption matching exceeded its 1-second interaction budget: \(elapsed)")
}

private func adoptionApp(
    name: String,
    updateManagement: AppUpdateManagement = .direct,
    hasBuiltInUpdater: Bool = false,
    url: URL? = nil
) -> InstalledApp {
    InstalledApp(
        name: name,
        bundleIdentifier: "test.\(name)",
        installedVersion: "1.0",
        buildVersion: nil,
        url: url ?? URL(fileURLWithPath: "/Applications/\(name).app"),
        sparkleFeedURL: nil,
        githubRepository: nil,
        hasAppStoreReceipt: updateManagement == .appStore,
        updateManagement: updateManagement,
        hasBuiltInUpdater: hasBuiltInUpdater
    )
}

private func installedCask(token: String) -> HomebrewPackage {
    HomebrewPackage(
        token: token,
        displayName: token,
        description: nil,
        homepage: nil,
        license: nil,
        installedVersion: "1.0",
        currentVersion: "1.0",
        kind: .cask,
        isOutdated: false,
        isDependency: false,
        dependencies: []
    )
}

/// A distinct all-letter suffix for each number, so names survive normalization.
private func letters(_ number: Int) -> String {
    var value = number
    var output = ""
    repeat {
        output.append(Character(UnicodeScalar(97 + value % 26)!))
        value /= 26
    } while value > 0
    return output
}
