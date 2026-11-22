import AppKit
import Foundation
import UserNotifications

/// Checks for and installs updates to Upkeep itself.
@MainActor
final class SelfUpdateController: ObservableObject {
    static let shared = SelfUpdateController()

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate(Date)
        case available(SelfUpdateRelease)
        case installing(SelfUpdateRelease)
        case failed(String)
    }

    /// Automatic checks run at most this often; menu checks always run.
    static let automaticInterval: TimeInterval = 6 * 60 * 60

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var dismissedVersion: String?

    /// Whether Upkeep may quit now (no update, restore, or cleanup running).
    var isBusy: @MainActor () -> Bool = { false }
    /// Whether prerelease versions of Upkeep should be offered.
    var includePrereleases: @MainActor () -> Bool = { false }
    var notificationsEnabled: @MainActor () -> Bool = { false }

    private let defaults: UserDefaults
    /// Only the packaged app checks GitHub; tests and fixtures never do.
    let isEnabled: Bool

    init(defaults: UserDefaults = .standard,
         isEnabled: Bool = Bundle.main.bundleIdentifier == InstalledApp.upkeepBundleIdentifier) {
        self.defaults = defaults
        self.isEnabled = isEnabled
        dismissedVersion = defaults.string(forKey: "selfUpdateDismissedVersion")
    }

    var availableRelease: SelfUpdateRelease? {
        switch phase {
        case let .available(release), let .installing(release): release
        default: nil
        }
    }

    /// The banner shows an available update until the user chooses Later.
    var bannerRelease: SelfUpdateRelease? {
        guard let release = availableRelease else { return nil }
        if case .installing = phase { return release }
        return release.version == dismissedVersion ? nil : release
    }

    var isInstalling: Bool { if case .installing = phase { true } else { false } }

    // MARK: Checking

    func checkAutomatically(now: Date = Date()) {
        guard isEnabled, phase != .checking, !isInstalling else { return }
        if let last = defaults.object(forKey: "selfUpdateLastCheck") as? Date,
           now.timeIntervalSince(last) < Self.automaticInterval { return }
        Task { await check(userInitiated: false) }
    }

    func check(userInitiated: Bool) async {
        guard isEnabled || userInitiated, phase != .checking, !isInstalling else { return }
        let previous = phase
        phase = .checking
        do {
            let release = try await SelfUpdate.latestRelease(includePrereleases: includePrereleases())
            defaults.set(Date(), forKey: "selfUpdateLastCheck")
            if let release {
                phase = .available(release)
                if userInitiated {
                    dismissedVersion = nil
                    defaults.removeObject(forKey: "selfUpdateDismissedVersion")
                    presentAvailable(release)
                } else {
                    notifyOnce(release)
                }
            } else {
                phase = .upToDate(Date())
                if userInitiated { presentUpToDate() }
            }
        } catch {
            phase = userInitiated ? .failed(error.localizedDescription) : previous
            if userInitiated { presentFailure(error.localizedDescription) }
        }
    }

    func dismiss() {
        guard let release = availableRelease else { return }
        dismissedVersion = release.version
        defaults.set(release.version, forKey: "selfUpdateDismissedVersion")
    }

    func openReleasePage() {
        guard let release = availableRelease else {
            NSWorkspace.shared.open(URL(string: "https://github.com/\(SelfUpdate.repository)/releases")!)
            return
        }
        NSWorkspace.shared.open(release.pageURL)
    }

    /// From the Updates list: offer the verified update, checking first if
    /// this session has not found it yet.
    func updateFromList() {
        guard let release = availableRelease else {
            Task { await check(userInitiated: true) }
            return
        }
        guard release.canInstallInPlace else { openReleasePage(); return }
        Task { await install() }
    }

    // MARK: Installing

    func install() async {
        guard let release = availableRelease, !isInstalling else { return }
        guard release.canInstallInPlace else { openReleasePage(); return }
        guard !isBusy() else {
            presentFailure("Finish or stop the current updates first, then install the Upkeep update.")
            return
        }
        phase = .installing(release)
        do {
            try SelfUpdate.checkReplaceable()
            let staged = try await SelfUpdate.stage(release)
            guard !isBusy() else {
                phase = .available(release)
                presentFailure("Another update started. Install the Upkeep update when it finishes.")
                return
            }
            try SelfUpdate.launchInstaller(staged: staged)
            DiagnosticsStore.shared.record(.info, category: .update, "Installing Upkeep update",
                                           metadata: ["From": SelfUpdate.currentVersion, "To": release.version])
            DiagnosticsStore.shared.flush()
            NSApp.terminate(nil)
        } catch {
            phase = .available(release)
            DiagnosticsStore.shared.record(.error, category: .update, "Upkeep update failed",
                                           metadata: ["To": release.version, "Error": error.localizedDescription])
            presentFailure(error.localizedDescription)
        }
    }

    #if DEBUG
    /// Visual QA only (`--ui-fixture-self-update`).
    func showFixtureRelease() {
        phase = .available(SelfUpdateRelease(
            version: "9.9.9", pageURL: URL(string: "https://github.com/\(SelfUpdate.repository)/releases")!,
            notes: "Fixture notes.", archiveURL: URL(string: "https://example.invalid/Upkeep.zip"),
            checksumURL: URL(string: "https://example.invalid/Upkeep.zip.sha256"),
            signatureURL: URL(string: "https://example.invalid/Upkeep.zip.sig"), isPrerelease: false))
    }
    #endif

    // MARK: Presentation

    private func presentAvailable(_ release: SelfUpdateRelease) {
        let alert = NSAlert()
        alert.messageText = "Upkeep \(release.version) is available"
        alert.informativeText = release.canInstallInPlace
            ? "You have version \(SelfUpdate.currentVersion). Upkeep will download and verify the update, then quit and reopen."
            : "You have version \(SelfUpdate.currentVersion). This release must be downloaded from GitHub."
        alert.addButton(withTitle: release.canInstallInPlace ? "Update Now" : "Download…")
        alert.addButton(withTitle: "Release Notes")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if release.canInstallInPlace { Task { await install() } } else { openReleasePage() }
        case .alertSecondButtonReturn:
            openReleasePage()
        default:
            dismiss()
        }
    }

    private func presentUpToDate() {
        let alert = NSAlert()
        alert.messageText = "Upkeep is up to date"
        alert.informativeText = "Version \(SelfUpdate.currentVersion) is the newest version available."
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func presentFailure(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Upkeep could not be updated"
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func notifyOnce(_ release: SelfUpdateRelease) {
        guard notificationsEnabled(), defaults.string(forKey: "selfUpdateNotifiedVersion") != release.version else { return }
        defaults.set(release.version, forKey: "selfUpdateNotifiedVersion")
        let content = UNMutableNotificationContent()
        content.title = "Upkeep \(release.version) is available"
        content.body = "Open Upkeep to update from version \(SelfUpdate.currentVersion)."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "upkeep-self-update", content: content, trigger: nil))
    }
}
