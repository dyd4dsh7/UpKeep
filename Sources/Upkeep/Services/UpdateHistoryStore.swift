import AppKit
import Foundation

actor UpdateHistoryStore {
    static let shared = UpdateHistoryStore()

    private let root: URL
    private let historyURL: URL

    init() {
        let library = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        root = library.appendingPathComponent("Upkeep", isDirectory: true)
        historyURL = root.appendingPathComponent("history.json")
    }

    func records() -> [UpdateRecord] {
        guard let data = try? Data(contentsOf: historyURL) else { return [] }
        return (try? JSONDecoder().decode([UpdateRecord].self, from: data)) ?? []
    }

    func prepareAppBackup(app: InstalledApp, toVersion: String, kind: UpdateRecordKind) throws -> UpdateRecord {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let id = UUID()
        let backupRoot = root.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        let backupURL = backupRoot.appendingPathComponent("\(id.uuidString)-\(app.url.lastPathComponent)")
        try FileManager.default.copyItem(at: app.url, to: backupURL)
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
        var values = records()
        values.insert(record, at: 0)
        let data = try JSONEncoder().encode(values)
        try data.write(to: historyURL, options: .atomic)
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

    enum HistoryError: LocalizedError {
        case noDirectRevert, backupMissing
        var errorDescription: String? {
            switch self {
            case .noDirectRevert: "This update requires macOS Recovery or manual package recovery."
            case .backupMissing: "The backup for this update is no longer available."
            }
        }
    }
}
