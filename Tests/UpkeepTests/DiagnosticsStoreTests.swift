import Foundation
import Testing
@testable import Upkeep

@Test func inMemoryDiagnosticsDoNotReadOrOverwritePersistentLogs() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("upkeep-diagnostics-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("diagnostics.json")
    let persistent = DiagnosticsStore(fileURL: fileURL)
    persistent.record(.info, category: .application, "Real app event")
    persistent.flush()
    let before = try Data(contentsOf: fileURL)

    let isolated = DiagnosticsStore(fileURL: fileURL, persistent: false)
    #expect(isolated.entries().isEmpty)
    isolated.record(.error, category: .update, "Simulated test failure")
    #expect(isolated.exportText().contains("Simulated test failure"))
    #expect(try Data(contentsOf: fileURL) == before)
    isolated.clear()
    #expect(isolated.entries().isEmpty)
    #expect(try Data(contentsOf: fileURL) == before)
}

@Test func diagnosticDurationFormattingIsDeterministic() {
    let startedAt = Date(timeIntervalSince1970: 100)
    let finishedAt = startedAt.addingTimeInterval(1.234)

    #expect(formattedDiagnosticDuration(since: startedAt, now: finishedAt) == "1234 ms")
}

@Test func diagnosticsAreRedactedBeforePersistenceAndExport() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("upkeep-diagnostics-tests-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directory.appendingPathComponent("diagnostics.json")
    defer { try? FileManager.default.removeItem(at: directory) }

    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let store = DiagnosticsStore(fileURL: fileURL)
    store.record(.error, category: .source, "Request failed at \(home)/Applications", metadata: [
        "URL": "https://example.com/feed?token=super-secret-value",
        "Authenticated URL": "https://username:password@example.com/feed",
        "Authorization": "Bearer ghp_1234567890abcdefghijklmnop"
    ])
    store.flush()

    let persisted = DiagnosticsStore(fileURL: fileURL).entries()
    #expect(persisted.count == 1)
    #expect(persisted[0].message.contains("~/Applications"))
    #expect(!persisted[0].message.contains(home))
    #expect(!persisted[0].metadata.values.joined().contains("super-secret-value"))
    #expect(!persisted[0].metadata.values.joined().contains("ghp_1234567890abcdefghijklmnop"))
    #expect(!persisted[0].metadata.values.joined().contains("username:password"))

    let exported = store.exportText()
    #expect(exported.contains("<redacted>"))
    #expect(!exported.contains("super-secret-value"))
}

@Test func diagnosticsRetentionIsBoundedWhenFlushed() {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("upkeep-diagnostics-tests-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directory.appendingPathComponent("diagnostics.json")
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = DiagnosticsStore(fileURL: fileURL)
    for index in 0..<2_001 {
        store.recordBuffered(.info, category: .scan, "Buffered \(index)")
    }
    store.record(.info, category: .scan, "Flush")
    store.flush()

    let persisted = DiagnosticsStore(fileURL: fileURL).entries()
    #expect(persisted.count == 2_000)
    #expect(persisted.contains { $0.message == "Flush" })
    #expect(!persisted.contains { $0.message == "Buffered 0" })
    #expect(!persisted.contains { $0.message == "Buffered 1" })
}

@Test func diagnosticsCanBeCleared() {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("upkeep-diagnostics-tests-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directory.appendingPathComponent("diagnostics.json")
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = DiagnosticsStore(fileURL: fileURL)
    store.record(.info, category: .scan, "Scan completed")
    #expect(store.entries().count == 1)
    store.clear()
    #expect(store.entries().isEmpty)
    #expect(DiagnosticsStore(fileURL: fileURL).entries().isEmpty)
}

@Test func diagnosticsLoadedFromDiskAreRedactedAgain() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("upkeep-diagnostics-tests-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directory.appendingPathComponent("diagnostics.json")
    defer { try? FileManager.default.removeItem(at: directory) }

    let rawEntry = #"""
        [{"id":"00000000-0000-0000-0000-000000000001","date":"2026-08-24T00:00:00Z","level":"Error","category":"Update Source","message":"Authorization: Bearer ghp_1234567890abcdefghijklmnop","metadata":{"URL":"https://example.com/feed?token=super-secret-value"}}]
        """#
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(rawEntry.utf8).write(to: fileURL)

    let loaded = DiagnosticsStore(fileURL: fileURL).entries()
    #expect(loaded.count == 1)
    #expect(loaded[0].message.contains("<redacted>"))
    #expect(!loaded[0].message.contains("ghp_1234567890abcdefghijklmnop"))
    #expect(!loaded[0].metadata.values.joined().contains("super-secret-value"))
}

@Test func diagnosticsPersistenceIsCoalescedAndEntriesStaySorted() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("upkeep-diagnostics-tests-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directory.appendingPathComponent("diagnostics.json")
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = DiagnosticsStore(fileURL: fileURL)
    store.record(.info, category: .scan, "First")
    // The write is deferred to the background queue.
    #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    store.record(.info, category: .scan, "Second")
    store.flush()
    let persisted = DiagnosticsStore(fileURL: fileURL).entries()
    #expect(persisted.map(\.message) == ["Second", "First"])

    // Entries loaded out of order are read newest first without sorting on read.
    let shuffled = [3.0, 1.0, 2.0, 0.0].map {
        DiagnosticEntry(date: Date(timeIntervalSince1970: $0), level: .info, category: .scan, message: "t\(Int($0))")
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let shuffledURL = directory.appendingPathComponent("shuffled.json")
    try encoder.encode(shuffled).write(to: shuffledURL)
    let loaded = DiagnosticsStore(fileURL: shuffledURL)
    #expect(loaded.entries().map(\.message) == ["t3", "t2", "t1", "t0"])
    loaded.recordBuffered(.info, category: .scan, "now")
    #expect(loaded.entries().first?.message == "now")
}
