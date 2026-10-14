import Foundation
import Testing
@testable import Upkeep

@MainActor
@Test func listProjectionBenchmark() throws {
    guard ProcessInfo.processInfo.environment["UPKEEP_LIST_BENCHMARK"] == "1" else { return }
    for size in [200, 2_000] {
        let suite = "ListBenchmark.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.showCurrentDeveloperPackages = false
        let store = UpkeepStore(settings: settings)
        let packages = (0..<size).map { DeveloperPackage(name: "tool-\($0)", currentVersion: "1",
            latestVersion: "2", manager: .npm, executablePath: "/not-executed/npm") }
        store.developerPackages = packages
        let query = "tool-7"
        store.searchText = query
        let expected = packages.filter { $0.name.localizedCaseInsensitiveContains(query) }.map(\.id)
        #expect(!expected.isEmpty)
        let clock = ContinuousClock()
        for sample in 0...7 {
            var cachedTime = Duration.zero
            var referenceTime = Duration.zero
            var cachedCount = 0
            var referenceCount = 0
            // Invalidate outside timing: each cached batch starts with a cold read.
            store.developerPackages = packages
            func cached() {
                let start = clock.now
                for _ in 0..<20 { cachedCount += store.filteredDeveloperPackages.count }
                cachedTime = start.duration(to: clock.now)
            }
            func reference() {
                let start = clock.now
                for _ in 0..<20 {
                    let scoped = packages.filter {
                        (settings.showCurrentDeveloperPackages || $0.isOutdated) && store.developerManagerFilter.includes($0.manager)
                    }
                    referenceCount += scoped.filter { $0.name.localizedCaseInsensitiveContains(query) }.count
                }
                referenceTime = start.duration(to: clock.now)
            }
            if sample.isMultiple(of: 2) { cached(); reference() }
            else { reference(); cached() }
            #expect(cachedCount == expected.count * 20)
            #expect(referenceCount == cachedCount)
            #expect(store.filteredDeveloperPackages.map(\.id) == expected)
            if sample > 0 {
                let cachedParts = cachedTime.components
                let referenceParts = referenceTime.components
                let cachedMS = Double(cachedParts.seconds) * 1000 + Double(cachedParts.attoseconds) / 1e15
                let referenceMS = Double(referenceParts.seconds) * 1000 + Double(referenceParts.attoseconds) / 1e15
                print("LIST size=\(size) sample=\(sample) cached_ms=\(cachedMS) reference_ms=\(referenceMS) checksum=\(cachedCount)")
            }
        }
    }
}
