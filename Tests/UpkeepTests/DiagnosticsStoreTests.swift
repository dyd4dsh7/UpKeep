import Foundation
import Testing
@testable import Upkeep

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
