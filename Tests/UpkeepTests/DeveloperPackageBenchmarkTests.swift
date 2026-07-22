import Foundation
import Testing
@testable import Upkeep

/// Opt-in live benchmark. This does not touch the production diagnostics store.
@Test func developerPackageScanBenchmark() async {
    guard ProcessInfo.processInfo.environment["UPKEEP_SCANNER_BENCHMARK"] == "developer" else { return }
    let clock = ContinuousClock()
    let started = clock.now
    let includePrereleases = ProcessInfo.processInfo.environment["UPKEEP_BENCHMARK_PRERELEASES"] == "1"
    let report = await DeveloperPackageClient().scan(includePrereleases: includePrereleases)
    let node = report.packages.first { $0.manager == .node }
    let bun = report.packages.first { $0.manager == .bun }
    let yarn = report.packages.first { $0.manager == .yarn }
    let npmNames = report.packages.filter { $0.manager == .npm }.map(\.name).sorted()
    let pnpmNames = report.packages.filter { $0.manager == .pnpm }.map(\.name).sorted()
    print(
        "DEVELOPER_SCAN_BENCHMARK elapsed=\(started.duration(to: clock.now)) "
            + "packages=\(report.packages.count) managers=\(report.installedManagers.count) "
            + "warnings=\(report.warnings.count) prereleases=\(includePrereleases) "
            + "node=\(node.map { "\($0.currentVersion)->\($0.latestVersion)" } ?? "not-installed") "
            + "bun=\(bun.map { "\($0.currentVersion)->\($0.latestVersion)" } ?? "not-installed") "
            + "yarn=\(yarn.map { "\($0.currentVersion)->\($0.latestVersion)" } ?? "not-installed") "
            + "npm=\(npmNames) pnpm=\(pnpmNames)"
    )
}

@Test func macOSUpdateScanBenchmark() async {
    guard ProcessInfo.processInfo.environment["UPKEEP_SCANNER_BENCHMARK"] == "macos" else { return }
    let clock = ContinuousClock()
    let started = clock.now
    let report = await MacOSUpdateClient().scan()
    print(
        "MACOS_SCAN_BENCHMARK elapsed=\(started.duration(to: clock.now)) "
            + "updates=\(report.updates.count) warnings=\(report.warnings.count)"
    )
}
