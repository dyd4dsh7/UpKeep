import Foundation
import Testing
@testable import Upkeep

@Test func formulaInventoryRetainsRevisionAndVersionScheme() throws {
    let data = Data(#"{"formulae":[{"name":"example","versions":{"stable":"1.2"},"revision":4,"version_scheme":2,"dependencies":[],"installed":[{"version":"1.2_3","installed_on_request":true}],"outdated":true}],"casks":[]}"#.utf8)
    let package = try #require(decodeHomebrewInventory(data).first)
    #expect(package.currentVersion == "1.2_4")
    #expect(package.versionScheme == 2)
    #expect(package.isRevisionUpdate)
    #expect(homebrewFormulaVersion("1.2", revision: 0) == "1.2")
    #expect(homebrewFormulaVersion("1.2", revision: 5) != package.currentVersion)
}

@MainActor
@Test func skippedFormulaTargetDoesNotHideLaterRevisionOrVersionScheme() throws {
    let name = "FormulaExclusion.\(UUID())"
    let defaults = try #require(UserDefaults(testSuiteName: name))
    defer { defaults.removeTestDomain(forName: name) }
    let settings = AppSettings(defaults: defaults)
    let store = UpkeepStore(settings: settings)
    var package = HomebrewPackage(token: "example", displayName: "Example", description: nil,
        homepage: nil, license: nil, installedVersion: "1.2_3", currentVersion: "1.2_4",
        kind: .formula, isOutdated: true, isDependency: false, dependencies: [])
    store.skip(package)
    #expect(store.isExcluded(package))
    package.versionScheme = 2
    #expect(!store.isExcluded(package))
    store.skip(package)
    #expect(store.isExcluded(package))
    let next = HomebrewPackage(token: package.token, displayName: package.displayName, description: nil,
        homepage: nil, license: nil, installedVersion: "1.2_3", currentVersion: "1.2_5",
        kind: .formula, isOutdated: true, isDependency: false, dependencies: [], versionScheme: 2)
    #expect(!store.isExcluded(next))
}

@Test func formulaMovedBackToAnOlderReleaseIsMarkedAsRollback() {
    let rollback = HomebrewPackage(token: "openssl@3", displayName: "openssl@3", description: nil,
        homepage: nil, license: nil, installedVersion: "3.6.5", currentVersion: "3.5.9",
        kind: .formula, isOutdated: true, isDependency: true, dependencies: [], versionScheme: 1)
    #expect(rollback.isVersionRollback)
    let revision = HomebrewPackage(token: "mysql@8.4", displayName: "mysql@8.4", description: nil,
        homepage: nil, license: nil, installedVersion: "8.4.13_1", currentVersion: "8.4.13.1",
        kind: .formula, isOutdated: true, isDependency: false, dependencies: [])
    #expect(!revision.isVersionRollback)
    let rebuild = HomebrewPackage(token: "example", displayName: "Example", description: nil,
        homepage: nil, license: nil, installedVersion: "1.2_3", currentVersion: "1.2_4",
        kind: .formula, isOutdated: true, isDependency: false, dependencies: [])
    #expect(!rebuild.isVersionRollback)
}
