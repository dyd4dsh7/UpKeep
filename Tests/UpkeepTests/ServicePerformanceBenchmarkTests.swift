import Foundation
import Testing
@testable import Upkeep

/// Offline benchmarks for startup diagnostics and the developer release menu.
/// Run: UPKEEP_SERVICE_BENCHMARK=1 swift test -c release --filter servicePerformanceBenchmark
@MainActor
@Test func servicePerformanceBenchmark() throws {
    guard ProcessInfo.processInfo.environment["UPKEEP_SERVICE_BENCHMARK"] == "1" else { return }
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("Upkeep-ServiceBenchmark-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fileURL = directory.appendingPathComponent("diagnostics.json")
    let entries = (0..<2_000).map { index in
        DiagnosticEntry(
            date: Date(timeIntervalSince1970: Double(index)), level: .info, category: .source,
            message: "Application source request \(index) completed",
            metadata: ["Item": "Application \(index)", "Duration": "125 ms", "Result": "Current"]
        )
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(entries).write(to: fileURL)
    let plain = entries.flatMap { [$0.message] + $0.metadata.keys.sorted().flatMap { [$0, $0 == "Duration" ? "125 ms" : "Current"] } }
    let mixed = (0..<2_000).map { index in
        index.isMultiple(of: 10)
            ? "Request failed https://example.com/feed?token=example-secret-\(index)"
            : "Application \(index) current"
    }
    let expectedMixed = mixed.map(DiagnosticRedactor.redact)
    let clock = ContinuousClock()

    for sample in 0...7 {
        var started = clock.now
        let loaded = DiagnosticsStore(fileURL: fileURL).entries()
        let load = serviceMilliseconds(started.duration(to: clock.now))
        #expect(loaded == entries.reversed())
        started = clock.now
        let redacted = plain.map(DiagnosticRedactor.redact)
        let redact = serviceMilliseconds(started.duration(to: clock.now))
        #expect(redacted == plain)
        started = clock.now
        let redactedMixed = mixed.map(DiagnosticRedactor.redact)
        let mixedTime = serviceMilliseconds(started.duration(to: clock.now))
        #expect(redactedMixed == expectedMixed)
        #expect(!redactedMixed.joined().contains("example-secret"))
        if sample > 0 {
            print("SERVICE_BENCHMARK sample=\(sample) diagnostics_load_ms=\(load) plain_redact_ms=\(redact) mixed_redact_ms=\(mixedTime) entries=\(loaded.count) plain_strings=\(redacted.count) mixed_strings=\(redactedMixed.count)")
        }
    }

    for size in [200, 5_000] {
        let versions = (0..<size).map { offset -> String in
            let index = (offset * 7_919) % size
            let suffix = ["", "-beta.1", "-darwin-arm64", "+build.2"][index % 4]
            return "\(index / 100 + 1).\(index % 100).0\(suffix)"
        }
        let package = DeveloperPackage(
            name: "benchmark", currentVersion: "0.1.0", latestVersion: "99.0.0",
            manager: .npm, executablePath: "/not-executed/npm"
        )
        let expected = Set(versions + [package.currentVersion, package.latestVersion])
            .sorted(by: VersionComparator.newestFirst)
        for sample in 0...7 {
            let started = clock.now
            let result = selectableDeveloperPackageVersions(
                discovered: versions, package: package, includePrereleases: true
            )
            let elapsed = serviceMilliseconds(started.duration(to: clock.now))
            #expect(result == expected)
            if sample > 0 {
                print("RELEASE_MENU_BENCHMARK size=\(size) sample=\(sample) elapsed_ms=\(elapsed) results=\(result.count)")
            }
        }
    }
}

private func serviceMilliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
}
