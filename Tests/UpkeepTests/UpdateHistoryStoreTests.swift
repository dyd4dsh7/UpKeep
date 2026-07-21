import Foundation
import Testing
@testable import Upkeep

private func historyTestApp(at url: URL, name: String = "Example") throws -> InstalledApp {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try Data("payload".utf8).write(to: url.appendingPathComponent("payload.txt"))
    return InstalledApp(
        name: name,
        bundleIdentifier: "com.example.\(name.lowercased())",
        installedVersion: "1.0",
        buildVersion: "100",
        url: url,
        sparkleFeedURL: nil,
        githubRepository: nil,
        hasAppStoreReceipt: false
    )
}

@Test func failedUpdateBackupCanBeDiscarded() async throws {
    let temporaryRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("UpkeepHistoryTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    let app = try historyTestApp(at: temporaryRoot.appendingPathComponent("Example.app"))
    let store = UpdateHistoryStore(root: temporaryRoot.appendingPathComponent("Data"))

    let record = try await store.prepareAppBackup(app: app, toVersion: "2.0", kind: .homebrew)
    let backupPath = try #require(record.backupPath)
    #expect(FileManager.default.fileExists(atPath: backupPath))

    await store.discardBackup(for: record)
    #expect(!FileManager.default.fileExists(atPath: backupPath))
}

@Test func inFlightBackupSurvivesHistoryRefreshBeforeItIsRecorded() async throws {
    let temporaryRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("UpkeepHistoryTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    let app = try historyTestApp(at: temporaryRoot.appendingPathComponent("Example.app"))
    let store = UpdateHistoryStore(root: temporaryRoot.appendingPathComponent("Data"))

    let record = try await store.prepareAppBackup(app: app, toVersion: "2.0", kind: .homebrew)
    _ = await store.records()

    let backupPath = try #require(record.backupPath)
    #expect(FileManager.default.fileExists(atPath: backupPath))
    try await store.add(record)
    #expect(FileManager.default.fileExists(atPath: backupPath))
}

@Test func corruptHistoryDoesNotDeleteRecoverableBackups() async throws {
    let temporaryRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("UpkeepHistoryTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    let dataRoot = temporaryRoot.appendingPathComponent("Data")
    let app = try historyTestApp(at: temporaryRoot.appendingPathComponent("Example.app"))
    let firstStore = UpdateHistoryStore(root: dataRoot)
    let record = try await firstStore.prepareAppBackup(app: app, toVersion: "2.0", kind: .homebrew)
    try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
    try Data("not-json".utf8).write(to: dataRoot.appendingPathComponent("history.json"))

    let relaunchedStore = UpdateHistoryStore(root: dataRoot)
    #expect(await relaunchedStore.records().isEmpty)
    #expect(FileManager.default.fileExists(atPath: try #require(record.backupPath)))
}

@Test func backupRetentionKeepsNewestPerAppAndGlobalLimit() async throws {
    let temporaryRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("UpkeepHistoryTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    let app = try historyTestApp(at: temporaryRoot.appendingPathComponent("Example.app"))
    let store = UpdateHistoryStore(
        root: temporaryRoot.appendingPathComponent("Data"),
        maximumBackupsPerApp: 2,
        maximumBackupsTotal: 2
    )

    var records: [UpdateRecord] = []
    for version in ["2.0", "3.0", "4.0"] {
        let record = try await store.prepareAppBackup(app: app, toVersion: version, kind: .homebrew)
        try await store.add(record)
        records.append(record)
    }

    let oldestPath = try #require(records.first?.backupPath)
    #expect(!FileManager.default.fileExists(atPath: oldestPath))
    #expect(!records[0].canRevertDirectly)
    #expect(records[1].canRevertDirectly)
    #expect(records[2].canRevertDirectly)
}
