import AppKit
import Foundation

actor UpdateHistoryStore {
    static let shared = UpdateHistoryStore()

    private let root: URL
    private let historyURL: URL
    private let backupRoot: URL
    private let maximumBackupsPerApp: Int
    private let maximumBackupsTotal: Int
    private var pendingBackupPaths = Set<String>()

    init(root: URL? = nil, maximumBackupsPerApp: Int = 3, maximumBackupsTotal: Int = 20) {
        let library = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.root = root ?? library.appendingPathComponent("Upkeep", isDirectory: true)
        self.maximumBackupsPerApp = max(0, maximumBackupsPerApp)
        self.maximumBackupsTotal = max(0, maximumBackupsTotal)
        backupRoot = self.root.appendingPathComponent("Backups", isDirectory: true)
        historyURL = self.root.appendingPathComponent("history.json")
    }

    func records() -> [UpdateRecord] {
        guard let values = loadRecords() else { return [] }
        maintainBackups(referencedBy: values)
        return values
    }

    func prepareAppBackup(app: InstalledApp, toVersion: String, kind: UpdateRecordKind) throws -> UpdateRecord {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let id = UUID()
        try FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        let backupURL = backupRoot.appendingPathComponent("\(id.uuidString)-\(app.url.lastPathComponent)")
        do {
            try FileManager.default.copyItem(at: app.url, to: backupURL)
        } catch {
            try? FileManager.default.removeItem(at: backupURL)
            throw error
        }
        pendingBackupPaths.insert(backupURL.standardizedFileURL.path)
        return UpdateRecord(
            id: id,
            date: Date(),
            name: app.name,
            fromVersion: app.installedVersion,
            toVersion: toVersion,
            kind: kind,
            originalAppPath: app.url.path,
            backupPath: backupURL.path,
            recoveryNote: nil
        )
    }

    func add(_ record: UpdateRecord) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard var values = loadRecords() else { throw HistoryError.historyUnreadable }
        values.insert(record, at: 0)
        let data = try JSONEncoder().encode(values)
        try data.write(to: historyURL, options: .atomic)
        if let backupPath = record.backupPath,
           let backupURL = managedBackupURL(for: backupPath) {
            pendingBackupPaths.remove(backupURL.standardizedFileURL.path)
        }
        maintainBackups(referencedBy: values)
    }

    func discardBackup(for record: UpdateRecord) {
        guard let backupPath = record.backupPath,
              let backupURL = managedBackupURL(for: backupPath)
        else { return }
        pendingBackupPaths.remove(backupURL.standardizedFileURL.path)
        try? FileManager.default.removeItem(at: backupURL)
    }

    func addMacOSPlan(update: MacOSUpdate) throws {
        try add(UpdateRecord(
            id: UUID(), date: Date(), name: update.title,
            fromVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            toVersion: update.version, kind: .macOS,
            originalAppPath: nil, backupPath: nil,
            recoveryNote: "macOS creates a pre-install local snapshot when Time Machine snapshots are enabled. Use macOS Recovery or Time Machine to restore; in-place OS downgrades are not supported."
        ))
    }

    func revert(_ record: UpdateRecord) throws {
        guard let originalPath = record.originalAppPath, let backupPath = record.backupPath else {
            throw HistoryError.noDirectRevert
        }
        let original = URL(fileURLWithPath: originalPath)
        let backup = URL(fileURLWithPath: backupPath)
        guard FileManager.default.fileExists(atPath: backup.path) else { throw HistoryError.backupMissing }
        if FileManager.default.fileExists(atPath: original.path) {
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: original, resultingItemURL: &resultingURL)
        }
        try FileManager.default.copyItem(at: backup, to: original)
    }

    private func loadRecords() -> [UpdateRecord]? {
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return [] }
        guard let data = try? Data(contentsOf: historyURL) else { return nil }
        return try? JSONDecoder().decode([UpdateRecord].self, from: data)
    }

    private func maintainBackups(referencedBy records: [UpdateRecord]) {
        var keptPaths = pendingBackupPaths
        var keptPerApp: [String: Int] = [:]
        var keptTotal = 0

        for record in records.sorted(by: { $0.date > $1.date }) {
            guard keptTotal < maximumBackupsTotal,
                  let originalPath = record.originalAppPath,
                  keptPerApp[originalPath, default: 0] < maximumBackupsPerApp,
                  let backupPath = record.backupPath,
                  let backupURL = managedBackupURL(for: backupPath),
                  FileManager.default.fileExists(atPath: backupURL.path)
            else { continue }
            keptPaths.insert(backupURL.standardizedFileURL.path)
            keptPerApp[originalPath, default: 0] += 1
            keptTotal += 1
        }

        guard let storedBackups = try? FileManager.default.contentsOfDirectory(
            at: backupRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for backup in storedBackups where !keptPaths.contains(backup.standardizedFileURL.path) {
            try? FileManager.default.removeItem(at: backup)
        }
    }

    private func managedBackupURL(for path: String) -> URL? {
        let candidate = URL(fileURLWithPath: path).standardizedFileURL
        let managedRoot = backupRoot.standardizedFileURL.path + "/"
        return candidate.path.hasPrefix(managedRoot) ? candidate : nil
    }

    enum HistoryError: LocalizedError {
        case noDirectRevert, backupMissing, historyUnreadable
        var errorDescription: String? {
            switch self {
            case .noDirectRevert: "This update requires macOS Recovery or manual package recovery."
            case .backupMissing: "The backup for this update is no longer available."
            case .historyUnreadable: "The existing update history could not be read, so it was not overwritten."
            }
        }
    }
}
