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
    private let maximumBackupBytes: Int64
    private var pendingBackupPaths = Set<String>()
    private var historyCache: (fingerprint: String, records: [UpdateRecord]?)?
    private var recoveryCache: [URL: (fingerprint: String, record: UpdateRecord?)] = [:]

    init(root: URL? = nil, maximumBackupsPerApp: Int = 3, maximumBackupsTotal: Int = 20,
         maximumBackupBytes: Int64 = 5 * 1_024 * 1_024 * 1_024) {
        let library = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.root = root ?? library.appendingPathComponent("Upkeep", isDirectory: true)
        self.maximumBackupsPerApp = max(0, maximumBackupsPerApp)
        self.maximumBackupsTotal = max(0, maximumBackupsTotal)
        self.maximumBackupBytes = max(0, maximumBackupBytes)
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
        return merged.sorted { $0.date > $1.date }
    }

    /// Reads never delete backups. Run on startup and after history mutations.
    func maintainStorage() async {
        guard let values = loadRecords(useCache: false) else { return }
        maintainBackups(referencedBy: values)
    }

    func recoveryStorage() async -> RecoveryStorage? {
        let recovery = authoritativeRecoveryRecords()
        let metadataUnavailable = recovery == nil || loadRecords(useCache: false) == nil
        let protected = pendingBackupPaths.union((recovery ?? []).compactMap(\.backupPath))
        let urls = (try? FileManager.default.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil)) ?? []
        return RecoveryStorage(directory: backupRoot, byteLimit: maximumBackupBytes,
            backups: urls.map { url in
                RecoveryStorage.Backup(path: url.path, bytes: backupBytes(at: url),
                    protected: metadataUnavailable || protected.contains(url.standardizedFileURL.path))
            }.sorted { $0.path < $1.path }, metadataUnavailable: metadataUnavailable)
    }

    private func backupBytes(at url: URL) -> Int64? {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
                                      .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let root = try? url.resourceValues(forKeys: Set(keys)), root.isSymbolicLink == false else { return nil }
        if root.isRegularFile == true {
            guard let bytes = root.totalFileAllocatedSize ?? root.fileAllocatedSize, bytes >= 0 else { return nil }
            return Int64(bytes)
        }
        guard root.isDirectory == true else { return nil }
        var failed = false
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys,
            errorHandler: { _, _ in failed = true; return true }) else { return nil }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: Set(keys)) else { failed = true; continue }
            if values.isRegularFile == true {
                guard let bytes = values.totalFileAllocatedSize ?? values.fileAllocatedSize else { failed = true; continue }
                guard bytes >= 0 else { failed = true; continue }
                let addition = total.addingReportingOverflow(Int64(bytes))
                guard !addition.overflow else { failed = true; continue }
                total = addition.partialValue
            }
        }
        return failed ? nil : total
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
            recoveryNote: nil, fromBuildVersion: app.buildVersion
        )
        // Persist recovery metadata before any installation. A failed history
        // write or app crash must not turn this backup into a cleanup orphan.
        do {
            try FileManager.default.createDirectory(at: recoveryRoot, withIntermediateDirectories: true)
            let recovery = UpdateRecord(
                id: record.id, date: record.date, name: record.name,
                fromVersion: record.fromVersion, toVersion: record.toVersion,
                kind: record.kind, originalAppPath: record.originalAppPath, backupPath: record.backupPath,
                recoveryNote: "Recovery backup from an interrupted update or history-save failure. Check the installed version before restoring.",
                fromBuildVersion: record.fromBuildVersion, toBuildVersion: record.toBuildVersion
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
        if let path = record.backupPath, managedBackupURL(for: path) != nil {
            // Preserve the observed result before committing normal history.
            // If history is unreadable or unwritable, recovery still describes
            // the actual installation rather than the originally requested one.
            try FileManager.default.createDirectory(at: recoveryRoot, withIntermediateDirectories: true)
            let recovery = UpdateRecord(id: record.id, date: record.date, name: record.name,
                fromVersion: record.fromVersion, toVersion: record.toVersion, kind: record.kind,
                originalAppPath: record.originalAppPath, backupPath: record.backupPath,
                recoveryNote: "Installed result recorded, but normal update history could not be committed. Check the installed version before restoring.",
                fromBuildVersion: record.fromBuildVersion, toBuildVersion: record.toBuildVersion)
            try JSONEncoder().encode(recovery).write(to: recoveryURL(for: record), options: .atomic)
        }
        guard var values = loadRecords(useCache: false) else { throw HistoryError.historyUnreadable }
        values.insert(record, at: 0)
        let data = try JSONEncoder().encode(values)
        try data.write(to: historyURL, options: .atomic)
        historyCache = nil
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

    private func loadRecords(useCache: Bool = true) -> [UpdateRecord]? {
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return [] }
        let fingerprint = fileFingerprint(historyURL)
        if useCache, let fingerprint, let cache = historyCache, cache.fingerprint == fingerprint { return cache.records }
        let records = (try? Data(contentsOf: historyURL)).flatMap { try? JSONDecoder().decode([UpdateRecord].self, from: $0) }
        if let fingerprint { historyCache = (fingerprint, records) }
        return records
    }

    private func recoveryURL(for record: UpdateRecord) -> URL {
        recoveryRoot.appendingPathComponent("\(record.id.uuidString).json")
    }

    private func loadRecoveryRecords() -> [UpdateRecord] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: recoveryRoot, includingPropertiesForKeys: nil) else { return [] }
        let existing = Set(urls)
        recoveryCache = recoveryCache.filter { existing.contains($0.key) }
        return urls.compactMap { url in
            let fingerprint = fileFingerprint(url)
            let value: UpdateRecord?
            if let fingerprint, let cached = recoveryCache[url], cached.fingerprint == fingerprint {
                value = cached.record
            } else {
                value = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(UpdateRecord.self, from: $0) }
                if let fingerprint { recoveryCache[url] = (fingerprint, value) }
            }
            guard let record = value,
                  let path = record.backupPath,
                  let backup = managedBackupURL(for: path),
                  FileManager.default.fileExists(atPath: backup.path) else { return nil }
            return record
        }
    }

    private func fileFingerprint(_ url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else { return nil }
        return "\(modified.timeIntervalSince1970)|\(size)|\(inode)"
    }

    private func maintainBackups(referencedBy records: [UpdateRecord]) {
        guard let recovery = authoritativeRecoveryRecords() else { return }
        // Cache only for this synchronous maintenance pass, including unavailable
        // readings. Later passes must measure again rather than reuse stale sizes.
        var measuredSizes: [String: Int64?] = [:]
        func measuredBytes(_ url: URL) -> Int64? {
            let path = url.standardizedFileURL.path
            if let cached = measuredSizes[path] { return cached }
            let bytes = backupBytes(at: url)
            measuredSizes.updateValue(bytes, forKey: path)
            return bytes
        }
        var keptPaths = pendingBackupPaths
        keptPaths.formUnion(recovery.compactMap(\.backupPath))
        var keptPerApp: [String: Int] = [:]
        var keptTotal = 0
        var protectedSizes: [Int64] = []
        for path in keptPaths {
            guard let bytes = measuredBytes(URL(fileURLWithPath: path)) else { return }
            protectedSizes.append(bytes)
        }
        var keptBytes = RecoveryStorage.boundedSum(protectedSizes)

        for record in records.sorted(by: { $0.date > $1.date }) {
            guard keptTotal < maximumBackupsTotal,
                  let originalPath = record.originalAppPath,
                  keptPerApp[originalPath, default: 0] < maximumBackupsPerApp,
                  let backupPath = record.backupPath,
                  let backupURL = managedBackupURL(for: backupPath),
                  FileManager.default.fileExists(atPath: backupURL.path)
            else { continue }
            let path = backupURL.standardizedFileURL.path
            // Unknown sizes are retained rather than deleted based on an estimate.
            // Interrupted-update recovery records are always protected, even over budget.
            if !keptPaths.contains(path), let bytes = measuredBytes(backupURL) {
                guard bytes <= maximumBackupBytes - min(keptBytes, maximumBackupBytes) else { continue }
                keptBytes += bytes
            }
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
            // Count limits must not override protection for an unreadable size.
            guard measuredBytes(backup) != nil else { continue }
            try? FileManager.default.removeItem(at: backup)
        }
    }

    /// Pruning must not rely on cached or partially decoded recovery metadata.
    private func authoritativeRecoveryRecords() -> [UpdateRecord]? {
        let manager = FileManager.default
        guard manager.fileExists(atPath: recoveryRoot.path) else { return [] }
        guard let urls = try? manager.contentsOfDirectory(at: recoveryRoot, includingPropertiesForKeys: nil) else { return nil }
        var records: [UpdateRecord] = []
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let record = try? JSONDecoder().decode(UpdateRecord.self, from: data),
                  let path = record.backupPath, managedBackupURL(for: path) != nil else { return nil }
            records.append(record)
        }
        return records
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
