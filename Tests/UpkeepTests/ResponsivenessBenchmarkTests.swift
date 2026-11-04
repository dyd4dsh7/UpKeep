import Foundation
import Testing
@testable import Upkeep

/// Run with UPKEEP_RESPONSIVENESS_BENCHMARK=1 swift test -c release
/// --filter responsivenessBenchmark. Fixtures and assertions are outside timed regions.
/// No scans, network requests, package commands, or production settings are used.
@MainActor
@Test func responsivenessBenchmark() throws {
    guard ProcessInfo.processInfo.environment["UPKEEP_RESPONSIVENESS_BENCHMARK"] == "1" else { return }

    for size in [200, 2_000] {
        let suite = "UpkeepTests.Responsiveness.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let apps = (0..<size).map { index in
            InstalledApp(
                name: "Product \(benchmarkSuffix(index)) Desktop",
                bundleIdentifier: "test.performance.\(index)", installedVersion: "1.0.0",
                buildVersion: nil,
                url: URL(fileURLWithPath: "/Applications/Product \(index).app"),
                sparkleFeedURL: nil, githubRepository: "example/product-\(index)",
                hasAppStoreReceipt: false
            )
        }
        let packages = (0..<size).map { index in
            HomebrewPackage(
                token: "product-\(benchmarkSuffix(index))",
                displayName: "Product \(benchmarkSuffix(index))", description: nil,
                homepage: nil, license: nil, installedVersion: "1.0.0", currentVersion: "1.1.0",
                kind: index.isMultiple(of: 2) ? .cask : .formula, isOutdated: true,
                isDependency: !index.isMultiple(of: 2), dependencies: []
            )
        }
        let developers = (0..<size).map { index in
            DeveloperPackage(
                name: "tool-\(index)", currentVersion: "1.0.0", latestVersion: "1.1.0",
                manager: .npm, executablePath: "/usr/local/bin/npm"
            )
        }
        let updates = apps.map { app in
            AvailableUpdate(
                app: app, availableVersion: "1.1.0", source: .github,
                releaseNotes: nil, actionURL: nil, homebrewToken: nil
            )
        }
        let exclusions = stride(from: 0, to: size, by: 4).map { index in
            UpdateExclusion(
                key: apps[index].updateExclusionKey, name: apps[index].name,
                category: "App", version: "1.1.0", mode: .skipped, expiresAt: nil
            )
        }
        defaults.set(try JSONEncoder().encode(exclusions), forKey: "updateExclusions")
        let settings = AppSettings(defaults: defaults)
        let store = UpkeepStore(settings: settings)
        store.apps = apps
        store.homebrewPackages = packages
        store.developerPackages = developers
        store.updates = updates
        let keys = apps.map(\.updateExclusionKey)
        // GitHub offers do not represent Homebrew casks in this fixture. The
        // unified count includes all package and developer updates, including
        // dependency formulae, as well as the non-excluded application offers.
        let expectedUpdateCount = updates.count - exclusions.count + packages.count + developers.count

        for sample in 0...7 {
            let clock = ContinuousClock()
            var started = clock.now
            var matches = 0
            var sources = 0
            for app in apps {
                matches += store.homebrewPackage(for: app) == nil ? 0 : 1
                sources += store.sources(for: app).count
            }
            for package in packages where package.kind == .cask {
                matches += store.homebrewPackageApp(for: package) == nil ? 0 : 1
            }
            let lookupTime = started.duration(to: clock.now)
            #expect(matches == size)
            #expect(sources == size + size / 2)

            started = clock.now
            var count = 0
            for _ in 0..<20 { count += store.totalUpdateCount }
            let countTime = started.duration(to: clock.now)
            #expect(count == expectedUpdateCount * 20)

            started = clock.now
            var excluded = 0
            for _ in 0..<20 {
                for key in keys { excluded += settings.isExcluded(key: key, version: "1.1.0") ? 1 : 0 }
            }
            let exclusionTime = started.duration(to: clock.now)
            #expect(excluded == exclusions.count * 20)

            // Include the cost of maintaining indexes, not just their warm reads.
            started = clock.now
            store.apps = apps
            store.homebrewPackages = packages
            let rebuildTime = started.duration(to: clock.now)

            if sample > 0 {
                print("RESPONSIVENESS size=\(size) sample=\(sample) lookup_ms=\(milliseconds(lookupTime)) count20_ms=\(milliseconds(countTime)) exclusion20_ms=\(milliseconds(exclusionTime)) rebuild_ms=\(milliseconds(rebuildTime)) checksum=\(matches + sources + count + excluded)")
            }
        }
    }
}

private func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
}

// Name matching discards digits; alphabetic suffixes keep this fixture unique.
private func benchmarkSuffix(_ index: Int) -> String {
    var value = index
    var suffix = ""
    repeat {
        suffix.append(Character(UnicodeScalar(97 + value % 26)!))
        value /= 26
    } while value > 0
    return suffix
}
