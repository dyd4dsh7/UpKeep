import Foundation
import Testing
@testable import Upkeep

/// Read-only benchmark of a real full scan on this Mac. It checks installed
/// apps and tools against their live sources and never installs or changes
/// anything. Network and tool caches make the first run slower than later runs.
///
/// Run: UPKEEP_LIVE_SCAN_BENCHMARK=1 swift test -c release --filter liveScanBenchmark
@Test func liveScanBenchmark() async throws {
    guard ProcessInfo.processInfo.environment["UPKEEP_LIVE_SCAN_BENCHMARK"] == "1" else { return }
    let runs = Int(ProcessInfo.processInfo.environment["UPKEEP_LIVE_SCAN_RUNS"] ?? "3") ?? 3
    let settings = ScanSettings(
        checkAppStore: true, checkSparkle: true, checkHomebrew: true, checkGitHub: true,
        checkMacOS: true, checkLocalModels: true, includePrereleaseUpdates: false,
        enabledDeveloperManagers: Set(DeveloperPackageManager.allCases), includeAdvancedSources: true
    )
    let scanner = UpdateScanner(dependencies: .live)

    print("Live full scan (\(runs) runs)")
    for run in 1...runs {
        let marks = PhaseMarks()
        let clock = ContinuousClock()
        let start = clock.now
        let report = await scanner.scan(settings: settings) { event in
            let elapsed = start.duration(to: clock.now)
            switch event {
            case .discovered: await marks.set("discovery", elapsed)
            case .homebrewInventory: await marks.set("homebrew inventory", elapsed)
            case .macOS: await marks.set("macOS", elapsed)
            case let .developerPackages(_, managers):
                await marks.set("developer: " + managers.map(\.rawValue).sorted().joined(separator: ", "), elapsed)
            case .localModels: await marks.set("AI models", elapsed)
            case let .appSource(_, _, _, _, completed, total):
                if completed == 1 { await marks.set("first app source", elapsed) }
                if completed == total { await marks.set("all app sources", elapsed) }
            }
        }
        let total = start.duration(to: clock.now)
        print("run \(run): total \(ms(total)) ms · \(report.apps.count) apps, \(report.homebrewPackages.count) Homebrew, \(report.developerPackages.count) developer, \(report.updates.count) app updates")
        for (name, at) in await marks.sorted() { print("  \(ms(at).padded()) ms  \(name)") }
    }

    print("Isolated phases")
    let deps = UpdateScannerDependencies.live
    await time("application discovery") { _ = await deps.applicationDiscovery.discover() }
    await time("homebrew inventory") { _ = try? await deps.homebrew.inventory(includePrereleases: false) }
    await time("homebrew cask catalog") { _ = try? await deps.homebrew.caskCatalog() }
    await time("macOS updates") { _ = try? await deps.macOS.scan(scope: .updates) }
    await time("AI models") { _ = await deps.localModels.scan() }
    for manager in DeveloperPackageManager.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
        await time("developer \(manager.rawValue)") {
            _ = await deps.developerPackages.scan(enabledManagers: [manager], includePrereleases: false)
        }
    }
}

private actor PhaseMarks {
    private var marks: [String: Duration] = [:]
    func set(_ name: String, _ at: Duration) { if marks[name] == nil { marks[name] = at } }
    func sorted() -> [(String, Duration)] { marks.sorted { $0.value < $1.value }.map { ($0.key, $0.value) } }
}

private func time(_ name: String, _ body: () async -> Void) async {
    let clock = ContinuousClock()
    let start = clock.now
    await body()
    print("  \(ms(start.duration(to: clock.now)).padded()) ms  \(name)")
}

private func ms(_ duration: Duration) -> Int {
    let parts = duration.components
    return Int(parts.seconds * 1_000 + parts.attoseconds / 1_000_000_000_000_000)
}

private extension Int {
    func padded() -> String { String(repeating: " ", count: Swift.max(0, 6 - String(self).count)) + String(self) }
}
