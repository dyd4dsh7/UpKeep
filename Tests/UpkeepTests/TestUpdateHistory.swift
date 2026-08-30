import Foundation
@testable import Upkeep

/// Tests must explicitly opt into an isolated history store, never the user's store.
actor TestUpdateHistory: UpdateHistoryManaging {
    private var values: [UpdateRecord] = []

    func records() -> [UpdateRecord] { values }
    func prepareAppBackup(app: InstalledApp, toVersion: String, kind: UpdateRecordKind) throws -> UpdateRecord {
        UpdateRecord(
            id: UUID(), date: Date(), name: app.name,
            fromVersion: app.installedVersion, toVersion: toVersion, kind: kind,
            originalAppPath: app.url.path, backupPath: nil, recoveryNote: "Test fixture"
        )
    }
    func add(_ record: UpdateRecord) { values.insert(record, at: 0) }
    func discardBackup(for record: UpdateRecord) {}
    func addMacOSPlan(update: MacOSUpdate) {}
    func revert(_ record: UpdateRecord) {}
}
