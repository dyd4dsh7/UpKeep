import Foundation
import Testing
@testable import Upkeep

@Test func unreadableBackupRootSurvivesCountAndBytePruning() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("BackupSizes-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let backups = root.appendingPathComponent("Backups")
    try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
    let unknown = backups.appendingPathComponent("Unreadable.app")
    try FileManager.default.createSymbolicLink(at: unknown, withDestinationURL: root.appendingPathComponent("missing"))
    let regular = backups.appendingPathComponent("Known-file")
    try Data(repeating: 1, count: 32_768).write(to: regular)
    let store = UpdateHistoryStore(root: root, maximumBackupsPerApp: 0, maximumBackupsTotal: 0, maximumBackupBytes: 0)
    let before = try #require(await store.recoveryStorage())
    #expect(before.backups.first { URL(fileURLWithPath: $0.path).lastPathComponent == unknown.lastPathComponent }?.bytes == nil)
    #expect(try #require(before.backups.first { URL(fileURLWithPath: $0.path).lastPathComponent == regular.lastPathComponent }?.bytes) > 0)
    await store.maintainStorage()
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: unknown.path) == root.appendingPathComponent("missing").path)
    #expect(!FileManager.default.fileExists(atPath: regular.path))
    let after = try #require(await store.recoveryStorage())
    #expect(after.backups.count == 1)
    #expect(after.unknownSizes)
    // A later maintenance pass must remeasure a formerly unavailable backup.
    try FileManager.default.removeItem(at: unknown)
    try Data(repeating: 2, count: 32_768).write(to: unknown)
    await store.maintainStorage()
    #expect(!FileManager.default.fileExists(atPath: unknown.path))
    #expect(try #require(await store.recoveryStorage()).backups.isEmpty)
}

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

@Test(arguments: [false, true])
func unreadableRecoveryManifestBlocksPruningAfterRestart(warmCache: Bool) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("RecoveryCorruption.\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let app = try historyTestApp(at: root.appendingPathComponent("Example.app"))
    let dataRoot = root.appendingPathComponent("Data")
    let originalStore = UpdateHistoryStore(root: dataRoot)
    let record = try await originalStore.prepareAppBackup(app: app, toVersion: "2", kind: .app)
    let restarted = UpdateHistoryStore(root: dataRoot, maximumBackupBytes: 0)
    if warmCache { #expect(await restarted.records().contains { $0.id == record.id }) }
    let manifest = dataRoot.appendingPathComponent("RecoveryRecords/\(record.id.uuidString).json")
    try Data("corrupt recovery manifest".utf8).write(to: manifest)
    await restarted.maintainStorage()
    #expect(FileManager.default.fileExists(atPath: try #require(record.backupPath)))
    let storage = try #require(await restarted.recoveryStorage())
    #expect(storage.backups.count == 1)
    #expect(storage.backups.first?.protected == true)
    #expect(storage.metadataUnavailable)
    #expect(try String(contentsOf: manifest, encoding: .utf8) == "corrupt recovery manifest")
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

@Test func historyReadsDoNotPruneBackupsAndMaintenancePreservesRecovery() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("HistoryReadIsolation.\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let app = try historyTestApp(at: root.appendingPathComponent("Example.app"))
    let dataRoot = root.appendingPathComponent("Data")
    let store = UpdateHistoryStore(root: dataRoot)
    let recovery = try await store.prepareAppBackup(app: app, toVersion: "2.0", kind: .app)
    let orphan = dataRoot.appendingPathComponent("Backups/orphan.app")
    try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
    _ = await store.records()
    _ = await store.records()
    #expect(FileManager.default.fileExists(atPath: orphan.path))
    await store.maintainStorage()
    #expect(!FileManager.default.fileExists(atPath: orphan.path))
    #expect(FileManager.default.fileExists(atPath: try #require(recovery.backupPath)))
}

@Test(arguments: [false, true])
func cachedHistoryDetectsExternalCorruptionBeforeWriting(preserveMetadata: Bool) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("HistoryCacheValidation.\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let app = try historyTestApp(at: root.appendingPathComponent("Example.app"))
    let dataRoot = root.appendingPathComponent("Data")
    let store = UpdateHistoryStore(root: dataRoot)
    let record = try await store.prepareAppBackup(app: app, toVersion: "2.0", kind: .app)
    try await store.add(record)
    let path = dataRoot.appendingPathComponent("history.json")
    if preserveMetadata {
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: path.path)
    }
    #expect(await store.records().map(\.id) == [record.id])
    let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
    let corrupt = preserveMetadata ? Data(repeating: 88, count: try Data(contentsOf: path).count) : Data("corrupt".utf8)
    try corrupt.write(to: path, options: preserveMetadata ? [] : .atomic)
    if preserveMetadata {
        try FileManager.default.setAttributes([.modificationDate: try #require(attributes[.modificationDate])], ofItemAtPath: path.path)
        let after = try FileManager.default.attributesOfItem(atPath: path.path)
        #expect(after[.size] as? NSNumber == attributes[.size] as? NSNumber)
        #expect(after[.systemFileNumber] as? NSNumber == attributes[.systemFileNumber] as? NSNumber)
        #expect(after[.modificationDate] as? Date == attributes[.modificationDate] as? Date)
    }
    await #expect(throws: UpdateHistoryStore.HistoryError.self) { try await store.add(record) }
    #expect(try Data(contentsOf: path) == corrupt)
    await store.maintainStorage()
    #expect(FileManager.default.fileExists(atPath: try #require(record.backupPath)))
    let storage = try #require(await store.recoveryStorage())
    #expect(storage.metadataUnavailable)
    #expect(storage.backups.allSatisfy { $0.protected })
}

@Test func byteBudgetPrunesSavedBackupsButProtectsInterruptedRecovery() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("HistoryByteBudget.\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let app = try historyTestApp(at: root.appendingPathComponent("Example.app"))
    let store = UpdateHistoryStore(root: root.appendingPathComponent("Data"), maximumBackupBytes: 0)
    let saved = try await store.prepareAppBackup(app: app, toVersion: "2.0", kind: .app)
    try await store.add(saved)
    #expect(!FileManager.default.fileExists(atPath: try #require(saved.backupPath)))
    let pending = try await store.prepareAppBackup(app: app, toVersion: "3.0", kind: .app)
    await store.maintainStorage()
    #expect(FileManager.default.fileExists(atPath: try #require(pending.backupPath)))
    let storage = try #require(await store.recoveryStorage())
    #expect(storage.backups.count == 1)
    #expect(storage.backups[0].protected)
    #expect(storage.measuredBytes > 0)
    #expect(storage.protectedBytes == storage.measuredBytes)
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
    #expect(await relaunchedStore.records().map(\.id) == [record.id])
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

@Test func globalBackupLimitAppliesAcrossDifferentApps() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GlobalRetention.\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let first = try historyTestApp(at: root.appendingPathComponent("First.app"), name: "First")
    let second = try historyTestApp(at: root.appendingPathComponent("Second.app"), name: "Second")
    let dataRoot = root.appendingPathComponent("Data")
    let store = UpdateHistoryStore(root: dataRoot, maximumBackupsPerApp: 2, maximumBackupsTotal: 3)
    var saved: [UpdateRecord] = []
    for app in [first, first, first, second, second] {
        let record = try await store.prepareAppBackup(app: app, toVersion: "2", kind: .app)
        try await store.add(record)
        saved.append(record)
        if saved.count == 3 {
            let storage = try #require(await store.recoveryStorage())
            #expect(storage.backups.count == 2)
            #expect(!FileManager.default.fileExists(atPath: try #require(saved[0].backupPath)))
        }
    }
    let restarted = UpdateHistoryStore(root: dataRoot, maximumBackupsPerApp: 2, maximumBackupsTotal: 3)
    await restarted.maintainStorage()
    let storage = try #require(await restarted.recoveryStorage())
    #expect(storage.backups.count == 3)
    for (index, record) in saved.enumerated() {
        #expect(FileManager.default.fileExists(atPath: try #require(record.backupPath)) == (index >= 2))
    }
    #expect(await restarted.records().count == 5)
}

@Test func historyWriteFailureKeepsRecoverableBackupAcrossRelaunchAndCleanup() async throws {
    let manager = FileManager.default
    let temporaryRoot = manager.temporaryDirectory.appendingPathComponent("UpkeepHistoryTests-\(UUID())")
    defer { try? manager.removeItem(at: temporaryRoot) }
    let dataRoot = temporaryRoot.appendingPathComponent("Data")
    let app = try historyTestApp(at: temporaryRoot.appendingPathComponent("Example.app"))
    let store = UpdateHistoryStore(root: dataRoot, maximumBackupsPerApp: 0, maximumBackupsTotal: 0)
    let record = try await store.prepareAppBackup(app: app, toVersion: "2.0", kind: .app)
    // A directory at history.json forces an actual persistence failure.
    let historyURL = dataRoot.appendingPathComponent("history.json")
    try manager.createDirectory(at: historyURL, withIntermediateDirectories: true)
    do {
        let observed = UpdateRecord(id: record.id, date: record.date, name: record.name,
            fromVersion: record.fromVersion, toVersion: "2.1", kind: record.kind,
            originalAppPath: record.originalAppPath, backupPath: record.backupPath, recoveryNote: nil,
            fromBuildVersion: "10", toBuildVersion: "21")
        try await store.add(observed)
        Issue.record("Expected a history write failure")
    } catch { }
    #expect(await store.records().map(\.id) == [record.id])
    try manager.removeItem(at: historyURL)
    let relaunched = UpdateHistoryStore(root: dataRoot, maximumBackupsPerApp: 0, maximumBackupsTotal: 0)
    let recovered = await relaunched.records()
    #expect(recovered.map(\.id) == [record.id])
    #expect(recovered.first?.toVersion == "2.1")
    #expect(recovered.first?.fromBuildVersion == "10")
    #expect(recovered.first?.toBuildVersion == "21")
    #expect(recovered.first?.recoveryNote?.contains("could not be committed") == true)
    #expect(manager.fileExists(atPath: try #require(record.backupPath)))
    _ = await relaunched.records()
    #expect(manager.fileExists(atPath: try #require(record.backupPath)))
}

@Test func recoveryStorageTotalsRejectNegativeAndOverflowingMeasurements() {
    #expect(RecoveryStorage.exactSum([2, 3]) == 5)
    #expect(RecoveryStorage.exactSum([Int64.max, 1]) == nil)
    #expect(RecoveryStorage.exactSum([-1]) == nil)
    let storage = RecoveryStorage(directory: URL(fileURLWithPath: "/fixture"), byteLimit: 100,
        backups: [.init(path: "a", bytes: Int64.max, protected: true),
                  .init(path: "b", bytes: 1, protected: true)])
    #expect(storage.unknownSizes)
    #expect(storage.measuredBytes == Int64.max)
    #expect(storage.protectedBytes == Int64.max)
}
