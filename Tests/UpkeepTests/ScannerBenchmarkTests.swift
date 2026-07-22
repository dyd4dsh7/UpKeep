import Foundation
import Testing
@testable import Upkeep

@Test func homebrewAdoptionIndexPreservesFirstMatchingAlias() {
    let apps = [
        benchmarkApp(name: "Visual Studio Code"),
        benchmarkApp(name: "Token Only"),
        benchmarkApp(name: "Already Installed"),
        benchmarkApp(name: "Ignored Font")
    ]
    let catalog = [
        CatalogCask(token: "vscode-first", name: ["Visual Studio Code"], version: "2.0"),
        CatalogCask(token: "vscode-second", name: ["Visual Studio Code"], version: "3.0"),
        CatalogCask(token: "token-only", name: ["Different Product Name"], version: "1.0"),
        CatalogCask(token: "already-installed", name: ["Already Installed"], version: "1.0"),
        CatalogCask(token: "font-ignored-font", name: ["Ignored Font"], version: "1.0")
    ]

    let matches = HomebrewClient.adoptableApps(
        from: apps,
        catalog: catalog,
        excluding: [benchmarkCask(token: "already-installed")]
    )

    #expect(matches.map(\.caskToken) == ["token-only", "vscode-first"])
}

/// Opt-in algorithm benchmark. This deliberately retains the former linear scan
/// locally so the before/after comparison uses identical generated input.
@Test func homebrewAdoptionMatchingBenchmark() {
    guard ProcessInfo.processInfo.environment["UPKEEP_SCANNER_BENCHMARK"] == "matching" else { return }
    let catalog = (0..<10_000).map {
        let suffix = benchmarkLetters($0)
        return CatalogCask(token: "application-\(suffix)", name: ["Application \(suffix)"], version: "2.0")
    }
    let apps = stride(from: 9_900, to: 10_000, by: 1).map {
        benchmarkApp(name: "Application \(benchmarkLetters($0))")
    }
    let clock = ContinuousClock()

    let legacyStart = clock.now
    let legacy = apps.compactMap { app in
        let appName = benchmarkNormalize(app.name)
        return catalog.first { cask in
            cask.name.contains { benchmarkNormalize($0) == appName }
                || benchmarkNormalize(cask.token) == appName
        }
    }
    let legacyElapsed = legacyStart.duration(to: clock.now)

    let indexedStart = clock.now
    let indexed = HomebrewClient.adoptableApps(from: apps, catalog: catalog, excluding: [])
    let indexedElapsed = indexedStart.duration(to: clock.now)

    #expect(legacy.map(\.token).sorted() == indexed.map(\.caskToken).sorted())
    print(
        "HOMEBREW_MATCH_BENCHMARK legacy=\(legacyElapsed) indexed=\(indexedElapsed) "
            + "apps=\(apps.count) casks=\(catalog.count)"
    )
}

@Test func fullUpdateScanBenchmark() async {
    guard ProcessInfo.processInfo.environment["UPKEEP_SCANNER_BENCHMARK"] == "full" else { return }
    let settings = ScanSettings(
        checkAppStore: true,
        checkSparkle: true,
        checkHomebrew: true,
        checkGitHub: true,
        checkMacOS: true,
        checkLocalModels: true,
        includePrereleaseUpdates: false,
        enabledDeveloperManagers: Set(DeveloperPackageManager.allCases),
        includeAdvancedSources: true
    )
    let clock = ContinuousClock()
    for iteration in 1...2 {
        let started = clock.now
        let report = await UpdateScanner().scan(settings: settings)
        print(
            "FULL_SCAN_BENCHMARK iteration=\(iteration) elapsed=\(started.duration(to: clock.now)) "
                + "apps=\(report.apps.count) packages=\(report.developerPackages.count) "
                + "homebrew=\(report.homebrewPackages.count) warnings=\(report.warnings.count)"
        )
    }
}

private func benchmarkApp(name: String) -> InstalledApp {
    InstalledApp(
        name: name,
        bundleIdentifier: "test.\(name)",
        installedVersion: "1.0",
        buildVersion: nil,
        url: URL(fileURLWithPath: "/Applications/\(name).app"),
        sparkleFeedURL: nil,
        githubRepository: nil,
        hasAppStoreReceipt: false
    )
}

private func benchmarkNormalize(_ value: String) -> String {
    value.lowercased().filter(\.isLetter)
}

private func benchmarkCask(token: String) -> HomebrewPackage {
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

private func benchmarkLetters(_ number: Int) -> String {
    var value = number
    var output = ""
    repeat {
        output.append(Character(UnicodeScalar(97 + value % 26)!))
        value /= 26
    } while value > 0
    return output
}
