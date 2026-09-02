import Foundation
import Testing
@testable import Upkeep

/// Measures the same projection used by GlobalSearchView, excluding fixture setup,
/// assertions, SwiftUI layout, and network work. One warm-up and seven samples.
@MainActor
@Test func searchPerformanceBenchmark() throws {
    guard ProcessInfo.processInfo.environment["UPKEEP_SEARCH_BENCHMARK"] == "1" else { return }
    let paired = ProcessInfo.processInfo.environment["UPKEEP_SEARCH_PAIRED"] == "1"
    for size in [200, 2_000] {
        let fixture = try SearchFixture(size: size)
        defer { fixture.cleanUp() }
        for (label, query) in [("name", "  Product \n"), ("missing", "no-such-result"), ("source", "GitHub"), ("dependency", "ssl zlib")] {
            fixture.store.searchText = query
            let expected = ReferenceSearch(store: fixture.store).results
            for sample in 0...7 {
                let clock = ContinuousClock()
                func measureReference() -> Double {
                    let start = clock.now
                    let reference = ReferenceSearch(store: fixture.store).results
                    let duration = start.duration(to: clock.now)
                    #expect(reference.identity == expected.identity)
                    return Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
                }
                var referenceTime: Double?
                if paired && sample.isMultiple(of: 2) { referenceTime = measureReference() }
                let start = clock.now
                let result = GlobalSearch(store: fixture.store).results
                let duration = start.duration(to: clock.now)
                assertSearchMatches(result, expected)
                if paired && !sample.isMultiple(of: 2) { referenceTime = measureReference() }
                if sample > 0 {
                    let ms = Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
                    let resultCounts: [Int] = [result.apps.count, result.adoptableApps.count,
                        result.homebrewPackages.count, result.developerPackages.count,
                        result.models.count, result.macOSUpdates.count, result.history.count]
                    print("SEARCH_BENCHMARK size=\(size) query=\(label) sample=\(sample) elapsed_ms=\(ms) results=\(resultCounts.reduce(0, +))")
                    if let referenceTime {
                        let referenceCounts: [Int] = [expected.apps.count, expected.adoptableApps.count,
                            expected.homebrewPackages.count, expected.developerPackages.count,
                            expected.models.count, expected.macOSUpdates.count, expected.history.count]
                        print("SEARCH_REFERENCE size=\(size) query=\(label) sample=\(sample) elapsed_ms=\(referenceTime) results=\(referenceCounts.reduce(0, +))")
                    }
                }
            }
        }
    }
}

@MainActor
@Test func searchPreservesFieldsOrderingAndFreshInventory() throws {
    let fixture = try SearchFixture(size: 24)
    defer { fixture.cleanUp() }
    let queries = ["", " \n ", "PRODUCT", "  product \n", "no-such-result", "github", "homebrew",
                   "Homebrew GitHub", "GitHub Homebrew", "sparkle", "app store", "direct", "test.search", "/Applications/",
                   "1.0", "2.0", "formula", "cask", "description", "ssl zlib", "openssl", "npm",
                   "/not-executed/", "ollama", "lm studio", "q4", "revision", "macOS", "label", "GB",
                   "recovery", "Developer", "Café", "CAFE", "Cafe\u{301}", "工具", "🛠"]
    for query in queries {
        fixture.store.searchText = query
        assertSearchMatches(GlobalSearch(store: fixture.store).results, ReferenceSearch(store: fixture.store).results)
    }
    fixture.store.searchText = "Product"
    let original = GlobalSearch(store: fixture.store).results
    #expect(original.apps.count == 24)
    #expect(original.homebrewPackages.count == 24)
    #expect(original.developerPackages.count == 24)
    #expect(original.history.count == 24)
    fixture.store.apps = Array(fixture.store.apps.reversed().dropFirst())
    fixture.store.homebrewPackages = []
    fixture.store.developerPackages = []
    fixture.store.adoptableApps = []
    fixture.store.localModels = []
    fixture.store.macOSUpdates = []
    fixture.store.updateHistory = Array(fixture.store.updateHistory.dropFirst())
    let updated = GlobalSearch(store: fixture.store).results
    assertSearchMatches(updated, ReferenceSearch(store: fixture.store).results)
    #expect(updated.apps.count == 23)
    #expect(updated.homebrewPackages.isEmpty)
    #expect(updated.developerPackages.isEmpty)
    #expect(updated.history.count == 23)
}

private func assertSearchMatches(_ actual: GlobalSearchResults, _ expected: ReferenceSearchResults) {
    #expect(actual.apps == expected.apps)
    #expect(actual.adoptableApps == expected.adoptableApps)
    #expect(actual.homebrewPackages == expected.homebrewPackages)
    #expect(actual.developerPackages == expected.developerPackages)
    #expect(actual.models == expected.models)
    #expect(actual.macOSUpdates == expected.macOSUpdates)
    #expect(actual.history == expected.history)
    #expect(actual.identity == expected.identity)
    #expect(actual.isEmpty == expected.isEmpty)
}

@MainActor
private struct SearchFixture {
    let store: UpkeepStore
    let defaults: UserDefaults
    let suite: String

    init(size: Int) throws {
        suite = "UpkeepTests.Search.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        store = UpkeepStore(settings: AppSettings(defaults: defaults))
        // Alphabetic names keep Homebrew's digit-stripping name matching unique.
        let names = (0..<size).map { index -> String in
            var value = index
            var suffix = ""
            repeat {
                suffix.append(Character(UnicodeScalar(97 + value % 26)!))
                value /= 26
            } while value > 0
            return "Product \(suffix)"
        }
        store.apps = (0..<size).reversed().map { index in
            InstalledApp(name: names[index] + " Desktop", bundleIdentifier: index.isMultiple(of: 3) ? nil : "test.search.\(index)",
                         installedVersion: "1.0", buildVersion: nil,
                         url: URL(fileURLWithPath: "/Applications/Product \(index).app"),
                         sparkleFeedURL: index.isMultiple(of: 3) ? URL(string: "https://example.com/feed") : nil,
                         githubRepository: "example/product-\(index)", hasAppStoreReceipt: index.isMultiple(of: 5))
        }
        store.homebrewPackages = (0..<size).reversed().map { index in
            HomebrewPackage(token: names[index].lowercased().replacingOccurrences(of: " ", with: "-"), displayName: names[index],
                            description: index.isMultiple(of: 2) ? "Description Café 工具 🛠" : nil,
                            homepage: nil, license: nil, installedVersion: "1.0", currentVersion: "2.0",
                            kind: .cask, isOutdated: true, isDependency: false, dependencies: ["openssl", "zlib", "libarchive"])
        }
        store.adoptableApps = store.apps.enumerated().compactMap { index, app in
            index.isMultiple(of: 4) ? AdoptableApp(app: app, caskToken: "adoptable-\(index)", caskVersion: "2.0") : nil
        }
        store.developerPackages = (0..<size).reversed().map { index in
            DeveloperPackage(name: names[index], currentVersion: "1.0", latestVersion: "2.0", manager: .npm, executablePath: "/not-executed/npm")
        }
        store.localModels = (0..<20).reversed().map { index in
            LocalLLMModel(id: "model-\(index)", name: "Product model \(index)", variant: index.isMultiple(of: 2) ? "Q4" : nil,
                          runtime: index.isMultiple(of: 2) ? .ollama : .lmStudio, installedRevision: "revision-a", latestRevision: "revision-b",
                          sizeBytes: nil, modifiedAt: nil, homepage: nil, executablePath: nil, updateReference: "model-\(index)", isOutdated: true)
        }
        store.macOSUpdates = (0..<3).reversed().map { index in
            MacOSUpdate(label: "label-\(index)", title: "macOS \(index)", version: "2.0", size: "1 GB",
                        requiresRestart: true, isBeta: false, isFullInstaller: false)
        }
        store.updateHistory = (0..<size).map { index in
            UpdateRecord(id: UUID(), date: Date(timeIntervalSince1970: Double(index)), name: names[index],
                         fromVersion: "1.0", toVersion: "2.0", kind: index.isMultiple(of: 2) ? .app : .developer,
                         originalAppPath: nil, backupPath: nil, recoveryNote: index.isMultiple(of: 2) ? "Recovery Café 工具 🛠" : nil)
        }
    }

    func cleanUp() { defaults.removePersistentDomain(forName: suite) }
}
