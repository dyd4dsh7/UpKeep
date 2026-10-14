import Testing
@testable import Upkeep

private func impactPackage(_ token: String, kind: HomebrewPackageKind = .formula,
                           dependencies: [String] = [], outdated: Bool = false) -> HomebrewPackage {
    HomebrewPackage(token: token, displayName: token, description: nil, homepage: nil, license: nil,
        installedVersion: "1", currentVersion: outdated ? "2" : "1", kind: kind,
        isOutdated: outdated, isDependency: false, dependencies: dependencies)
}

@Test(arguments: [false, true]) func serviceImpactIncludesTransitiveDependentsOfOutdatedLibraries(outdated: Bool) {
    let library = impactPackage("library", dependencies: ["server"], outdated: outdated)
    let selected = impactPackage("selected", dependencies: ["library"])
    let helper = impactPackage("helper", dependencies: ["library"])
    let server = impactPackage("server", dependencies: ["helper"])
    let unrelated = impactPackage("unrelated")
    let services = ["server", "unrelated"].map {
        HomebrewService(name: $0, status: "started", user: nil, file: nil, exitCode: nil)
    }
    let impact = HomebrewImpact(package: selected, inventory: [library, selected, helper, server, unrelated], services: services)
    #expect(impact.relatedServices.map(\.name) == (outdated ? ["server"] : []))
    #expect(impact.dependents.isEmpty)
}

@Test func serviceImpactMatchesFormulaAndDependentWithoutGuessingAmbiguousNames() {
    let core = impactPackage("core")
    let server = impactPackage("owner/tap/server", dependencies: ["core"])
    let other = impactPackage("unrelated")
    let services = ["server", "unrelated", "lib"].map {
        HomebrewService(name: $0, status: "started", user: nil, file: nil, exitCode: nil)
    }
    let impact = HomebrewImpact(package: core, inventory: [core, server, other,
        impactPackage("one/tap/lib"), impactPackage("two/tap/lib")], services: services)
    #expect(impact.relatedServices.map(\.name) == ["server"])
    #expect(impact.unresolvedServiceNames == ["lib"])
}

@Test func impactTraversesDependenciesAndDependentsWithoutCycleDuplicates() {
    let core = impactPackage("core", dependencies: ["leaf", "missing"])
    let leaf = impactPackage("leaf", dependencies: ["core"], outdated: true)
    let tool = impactPackage("tool", dependencies: ["core"])
    let app = impactPackage("app", kind: .cask, dependencies: ["tool"])
    let impact = HomebrewImpact(package: core, inventory: [core, leaf, tool, app])
    #expect(impact.dependencies.map(\.token) == ["leaf"])
    #expect(impact.outdatedDependencies.map(\.token) == ["leaf"])
    #expect(impact.dependents.map(\.token) == ["app", "leaf", "tool"])
    #expect(impact.unresolvedDependencies == ["missing"])
}

@Test func impactDoesNotGuessAmbiguousTapDependenciesOrConfuseCasks() {
    let app = impactPackage("app", kind: .cask, dependencies: ["lib", "owner/tap/exact"])
    let one = impactPackage("one/tap/lib")
    let two = impactPackage("two/tap/lib")
    let exact = impactPackage("owner/tap/exact")
    let sameNameCask = impactPackage("lib", kind: .cask)
    let impact = HomebrewImpact(package: app, inventory: [app, one, two, exact, sameNameCask])
    #expect(impact.dependencies.map(\.token) == ["owner/tap/exact"])
    #expect(impact.unresolvedDependencies == ["lib"])
    let unique = HomebrewImpact(package: app, inventory: [app, one, exact])
    #expect(Set(unique.dependencies.map(\.token)) == ["one/tap/lib", "owner/tap/exact"])
}
