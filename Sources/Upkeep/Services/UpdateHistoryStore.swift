import AppKit
import Foundation

actor UpdateHistoryStore {
    static let shared = UpdateHistoryStore()

    private let root: URL
    private let historyURL: URL
    private let backupRoot: URL
    private let recoveryRoot: URL
    private let maximumBackupsPerApp: Int
    private let maximumBackupsTotal: Int
    private var pendingBackupPaths = Set<String>()

    init(root: URL? = nil, maximumBackupsPerApp: Int = 3, maximumBackupsTotal: Int = 20) {
        let library = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.root = root ?? library.appendingPathComponent("Upkeep", isDirectory: true)
        self.maximumBackupsPerApp = max(0, maximumBackupsPerApp)
        self.maximumBackupsTotal = max(0, maximumBackupsTotal)
        backupRoot = self.root.appendingPathComponent("Backups", isDirectory: true)
        recoveryRoot = self.root.appendingPathComponent("RecoveryRecords", isDirectory: true)
        historyURL = self.root.appendingPathComponent("history.json")
    }

    func records() -> [UpdateRecord] {
        let values = loadRecords()
        let recovery = loadRecoveryRecords().filter {
            !pendingBackupPaths.contains($0.backupPath ?? "")
        }
        let merged = Dictionary((values ?? []).map { ($0.id, $0) } + recovery.map { ($0.id, $0) },
                                uniquingKeysWith: { saved, _ in saved }).values
        if let values { maintainBackups(referencedBy: values) }
        return merged.sorted { $0.date > $1.date }
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
        let record = UpdateRecord(
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
        // Persist recovery metadata before any installation. A failed history
        // write or app crash must not turn this backup into a cleanup orphan.
        do {
            try FileManager.default.createDirectory(at: recoveryRoot, withIntermediateDirectories: true)
            let recovery = UpdateRecord(
                id: record.id, date: record.date, name: record.name,
                fromVersion: record.fromVersion, toVersion: record.toVersion,
                kind: record.kind, originalAppPath: record.originalAppPath, backupPath: record.backupPath,
                recoveryNote: "Recovery backup from an interrupted update or history-save failure. Check the installed version before restoring."
            )
            try JSONEncoder().encode(recovery).write(to: recoveryURL(for: record), options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: backupURL)
            throw error
        }
        pendingBackupPaths.insert(backupURL.standardizedFileURL.path)
        return record
    }

    func add(_ record: UpdateRecord) throws {
        defer {
            if let path = record.backupPath { pendingBackupPaths.remove(path) }
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard var values = loadRecords() else { throw HistoryError.historyUnreadable }
        values.insert(record, at: 0)
        let data = try JSONEncoder().encode(values)
        try data.write(to: historyURL, options: .atomic)
        try? FileManager.default.removeItem(at: recoveryURL(for: record))
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
        try? FileManager.default.removeItem(at: recoveryURL(for: record))
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
        let manager = FileManager.default
        let parent = original.deletingLastPathComponent()
        let staged = parent.appendingPathComponent(".Upkeep-Restore-\(UUID().uuidString).app")
        let displaced = parent.appendingPathComponent(".Upkeep-Previous-\(UUID().uuidString).app")
        defer { try? manager.removeItem(at: staged) }
        let originalIdentifier = Bundle(url: original)?.bundleIdentifier
        let hadInstalledApp = try AppRestoreTransaction.perform(
            backup: backup, installed: original, staged: staged, displaced: displaced,
            exists: { manager.fileExists(atPath: $0.path) },
            copy: { try manager.copyItem(at: $0, to: $1) },
            validate: { candidate in
                guard let bundle = Bundle(url: candidate),
                      let identifier = bundle.bundleIdentifier,
                      originalIdentifier == nil || identifier == originalIdentifier,
                      let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                        ?? bundle.object(forInfoDictionaryKey: "CFBundleVersion")) as? String,
                      version == record.fromVersion
                else { throw AppRestoreTransaction.RestoreError.invalidBackup }
            },
            move: { try manager.moveItem(at: $0, to: $1) }
        )
        if hadInstalledApp {
            var resultingURL: NSURL?
            // Trash is housekeeping after success. If unavailable, retain the old
            // app at the displaced path rather than undoing a successful restore.
            try? manager.trashItem(at: displaced, resultingItemURL: &resultingURL)
        }
    }

    private func loadRecords() -> [UpdateRecord]? {
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return [] }
        guard let data = try? Data(contentsOf: historyURL) else { return nil }
        return try? JSONDecoder().decode([UpdateRecord].self, from: data)
    }

    private func recoveryURL(for record: UpdateRecord) -> URL {
        recoveryRoot.appendingPathComponent("\(record.id.uuidString).json")
    }

    private func loadRecoveryRecords() -> [UpdateRecord] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: recoveryRoot, includingPropertiesForKeys: nil) else { return [] }
        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let record = try? JSONDecoder().decode(UpdateRecord.self, from: data),
                  let path = record.backupPath,
                  let backup = managedBackupURL(for: path),
                  FileManager.default.fileExists(atPath: backup.path) else { return nil }
            return record
        }
    }

    private func maintainBackups(referencedBy records: [UpdateRecord]) {
        var keptPaths = pendingBackupPaths
        keptPaths.formUnion(loadRecoveryRecords().compactMap(\.backupPath))
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
