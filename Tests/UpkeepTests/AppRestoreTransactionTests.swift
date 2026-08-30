import Foundation
import Testing
@testable import Upkeep

@Test(arguments: ["copy", "validate", "replace", "success", "missing"])
func restoreStagesAndValidatesBeforeReplacingTheInstalledApp(failure: String) throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("UpkeepRestore-\(UUID())")
    defer { try? manager.removeItem(at: root) }
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    let backup = root.appendingPathComponent("backup.app")
    let installed = root.appendingPathComponent("installed.app")
    let staged = root.appendingPathComponent("staged.app")
    let displaced = root.appendingPathComponent("displaced.app")
    try Data("backup".utf8).write(to: backup)
    if failure != "missing" { try Data("current".utf8).write(to: installed) }
    var caughtFailure = false
    do {
        let hadInstalled = try AppRestoreTransaction.perform(
            backup: backup, installed: installed, staged: staged, displaced: displaced,
            exists: { manager.fileExists(atPath: $0.path) },
            copy: {
                if failure == "copy" { throw RestoreTestError.injected }
                try manager.copyItem(at: $0, to: $1)
            },
            validate: {
                #expect(try String(contentsOf: $0, encoding: .utf8) == "backup")
                if failure != "missing" {
                    #expect(try String(contentsOf: installed, encoding: .utf8) == "current")
                }
                if failure == "validate" { throw RestoreTestError.injected }
            },
            move: {
                if failure == "replace", $0 == staged { throw RestoreTestError.injected }
                try manager.moveItem(at: $0, to: $1)
            }
        )
        #expect(hadInstalled == (failure != "missing"))
    } catch { caughtFailure = true }
    let shouldFail = ["copy", "validate", "replace"].contains(failure)
    #expect(caughtFailure == shouldFail)
    #expect(try String(contentsOf: installed, encoding: .utf8) == (shouldFail ? "current" : "backup"))
    #expect(try String(contentsOf: backup, encoding: .utf8) == "backup")
    if failure == "success" {
        #expect(try String(contentsOf: displaced, encoding: .utf8) == "current")
    }
}

@Test func restoreReportsPreservedLocationIfRollbackRenameAlsoFails() throws {
    var moves: [(String, String)] = []
    do {
        _ = try AppRestoreTransaction.perform(
            backup: URL(fileURLWithPath: "/backup"), installed: URL(fileURLWithPath: "/installed"),
            staged: URL(fileURLWithPath: "/staged"), displaced: URL(fileURLWithPath: "/preserved"),
            exists: { _ in true }, copy: { _, _ in }, validate: { _ in },
            move: { from, to in
                moves.append((from.path, to.path))
                if from.path != "/installed" { throw RestoreTestError.injected }
            }
        )
        Issue.record("Expected restore failure")
    } catch {
        #expect(error.localizedDescription.contains("/preserved"))
        #expect(moves.map(\.0) == ["/installed", "/staged", "/preserved"])
    }
}

private enum RestoreTestError: Error { case injected }
