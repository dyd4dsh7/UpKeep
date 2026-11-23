import Foundation
import Testing
@testable import Upkeep

private struct PermissionDenied: Error {}

private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func add(_ value: String) { lock.withLock { values.append(value) } }
    var all: [String] { lock.withLock { values } }
}

private let app = URL(fileURLWithPath: "/Applications/Pages.app")

@Test func appsMoveToTheTrashDirectlyWhenTheyCan() async throws {
    let calls = Calls()
    let uninstaller = AppUninstaller(trashItem: { _ in URL(fileURLWithPath: "/Users/test/.Trash/Pages.app") },
                                     runFinder: { _ in calls.add("finder"); return (0, "") })
    #expect(try await uninstaller.moveToTrash(app)?.path == "/Users/test/.Trash/Pages.app")
    #expect(calls.all.isEmpty)
}

@Test func administratorOwnedAppsFallBackToFinder() async throws {
    let calls = Calls()
    let uninstaller = AppUninstaller(trashItem: { _ in throw PermissionDenied() },
                                     runFinder: { url in calls.add(url.path); return (0, "") },
                                     fileExists: { _ in false })
    // Finder does not report where it put the app, so Put Back is not offered.
    #expect(try await uninstaller.moveToTrash(app) == nil)
    #expect(calls.all == [app.path])
}

@Test func cancellingFinderPasswordPromptReportsCancelled() async {
    let uninstaller = AppUninstaller(trashItem: { _ in throw PermissionDenied() },
                                     runFinder: { _ in (1, "execution error: User canceled. (-128)") })
    await #expect(throws: AppUninstaller.UninstallError.self) { try await uninstaller.moveToTrash(app) }
    do { _ = try await uninstaller.moveToTrash(app) } catch let error as AppUninstaller.UninstallError {
        if case .cancelled = error {} else { Issue.record("Expected cancelled, got \(error)") }
    } catch { Issue.record("Unexpected \(error)") }
}

@Test func finderFailuresAndLeftoverAppsAreErrors() async {
    let failing = AppUninstaller(trashItem: { _ in throw PermissionDenied() },
                                 runFinder: { _ in (1, "Not authorized to send Apple events to Finder. (-1743)") })
    do { _ = try await failing.moveToTrash(app) } catch let error as AppUninstaller.UninstallError {
        guard case let .finderFailed(message) = error else {
            Issue.record("Expected finderFailed, got \(error)")
            return
        }
        #expect(message.contains("-1743"))
        #expect(error.localizedDescription.contains("Automation"))
    } catch { Issue.record("Unexpected \(error)") }

    let stillThere = AppUninstaller(trashItem: { _ in throw PermissionDenied() },
                                    runFinder: { _ in (0, "") }, fileExists: { _ in true })
    do { _ = try await stillThere.moveToTrash(app) } catch let error as AppUninstaller.UninstallError {
        if case .stillInstalled = error {} else { Issue.record("Expected stillInstalled, got \(error)") }
    } catch { Issue.record("Unexpected \(error)") }
}

@Test func appStoreUpdatesRunSudoMasUpdateInTerminal() async throws {
    let calls = Calls()
    let updater = MasAppStoreUpdater(mas: URL(fileURLWithPath: "/opt/homebrew/bin/mas"), launch: { executable, arguments, subject in
        calls.add(([executable.path] + arguments + ["(\(subject))"]).joined(separator: " "))
    })
    try await updater.update(appID: "409201541")
    #expect(calls.all == ["/usr/bin/sudo /opt/homebrew/bin/mas update 409201541 (App Store update)"])
}

@Test func onlyNumericAppIDsReachSudo() async {
    let calls = Calls()
    let updater = MasAppStoreUpdater(mas: URL(fileURLWithPath: "/opt/homebrew/bin/mas"), launch: { _, arguments, _ in
        calls.add(arguments.joined(separator: " "))
    })
    for bad in ["", "123; rm -rf ~", "--force", "١٢٣"] {
        await #expect(throws: (any Error).self) { try await updater.update(appID: bad) }
    }
    #expect(calls.all.isEmpty)

    let missing = MasAppStoreUpdater(mas: nil, launch: { _, _, _ in calls.add("ran") })
    #expect(!missing.isAvailable)
    await #expect(throws: (any Error).self) { try await missing.update(appID: "409201541") }
    #expect(calls.all.isEmpty)
}
