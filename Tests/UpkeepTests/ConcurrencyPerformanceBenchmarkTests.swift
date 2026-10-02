import Darwin
import Foundation
import Testing
@testable import Upkeep

private actor ConcurrencyFixtureLoad {
    private var active = 0
    private var hosts: [String: Int] = [:]
    private(set) var maximumActive = 0
    private(set) var maximumHost = 0
    func begin(host: String) -> Bool {
        active += 1
        hosts[host, default: 0] += 1
        maximumActive = max(maximumActive, active)
        maximumHost = max(maximumHost, hosts[host, default: 0])
        // Explicit fixture policy; this is not an observed publisher response.
        return hosts[host, default: 0] <= 2
    }
    func end(host: String) { active -= 1; hosts[host, default: 0] -= 1 }
}

/// Run each mode in a separate filtered process so high-water RSS is not carried
/// over from the other policy. No HTTP request or child process is launched.
@Test func concurrencyPerformanceBenchmark() async throws {
    let mode = ProcessInfo.processInfo.environment["UPKEEP_CONCURRENCY_BENCHMARK"]
    guard mode == "bounded" || mode == "unbounded" else { return }
    let bounded = mode == "bounded"
    let count = 1_000
    let bufferBytes = 65_536
    let gate = SourceRequestGate.shared
    let clock = ContinuousClock()
    for sample in 0...7 {
        let probe = ConcurrencyFixtureLoad()
        let started = clock.now
        let results = try await withThrowingTaskGroup(of: (Bool, UInt64).self) { tasks in
            for index in 0..<count {
                tasks.addTask {
                    let host = "fixture-\(index % 8).invalid"
                    let operation: @Sendable () async throws -> (Bool, UInt64) = {
                        let accepted = await probe.begin(host: host)
                        let buffer = Data(repeating: UInt8(index % 251), count: bufferBytes)
                        try await Task.sleep(for: .milliseconds(2))
                        let checksum = UInt64(buffer[0]) + UInt64(buffer[buffer.count - 1])
                        await probe.end(host: host)
                        return (accepted, checksum)
                    }
                    if bounded {
                        return try await gate.withPermit(host: host,
                            priority: index.isMultiple(of: 50) ? .foreground : .background,
                            operation: operation)
                    }
                    return try await operation()
                }
            }
            var values: [(Bool, UInt64)] = []
            for try await result in tasks { values.append(result) }
            return values
        }
        let elapsed = started.duration(to: clock.now)
        let active = await probe.maximumActive
        let perHost = await probe.maximumHost
        let failures = results.filter { !$0.0 }.count
        let checksum = results.reduce(UInt64(0)) { $0 + $1.1 }
        let expected = (0..<count).reduce(UInt64(0)) { $0 + UInt64($1 % 251) * 2 }
        #expect(results.count == count)
        #expect(checksum == expected)
        if bounded {
            #expect(active <= 8)
            #expect(perHost <= 2)
            #expect(failures == 0)
            #expect(await gate.activeCount == 0)
            #expect(await gate.pendingCount == 0)
        }
        var usage = rusage()
        let memoryAvailable = getrusage(RUSAGE_SELF, &usage) == 0
        let milliseconds = Double(elapsed.components.seconds) * 1_000
            + Double(elapsed.components.attoseconds) / 1e15
        print("CONCURRENCY_BENCHMARK mode=\(bounded ? "bounded" : "unbounded") sample=\(sample) requests=\(count) hosts=8 elapsed_ms=\(milliseconds) max_active=\(active) max_per_host=\(perHost) fixture_buffer_peak_bytes=\(active * bufferBytes) process_peak_rss_bytes=\(memoryAvailable ? usage.ru_maxrss : -1) simulated_429=\(failures) checksum=\(checksum)")
    }
}
