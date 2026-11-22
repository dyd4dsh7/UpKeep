import Foundation

enum UpdateCheckState: Equatable {
    case notChecked, checking, disabled, failed, partial, complete

    var title: String {
        switch self {
        case .notChecked: "Not checked yet"
        case .checking: "Checking for updates…"
        case .disabled: "Update checking is disabled"
        case .failed: "Update check failed"
        case .partial: "Some update checks failed"
        case .complete: "No updates found"
        }
    }

    var detail: String {
        switch self {
        case .notChecked: "Check for updates to compare installed versions with their sources."
        case .checking: "Results will appear when the enabled sources finish checking."
        case .disabled: "Enable update sources in Settings to check for new versions."
        case .failed: "Upkeep could not verify whether updates are available. Try again when the sources are reachable."
        case .partial: "Results may be incomplete. Previously known updates are retained where possible."
        case .complete: "Enabled update sources reported no newer versions."
        }
    }

    var symbol: String {
        switch self {
        case .notChecked: "questionmark.circle"
        case .checking: "arrow.clockwise"
        case .disabled: "pause.circle"
        case .failed, .partial: "exclamationmark.triangle"
        case .complete: "checkmark.seal.fill"
        }
    }

    /// `lastChecked` survives relaunch but results do not, so before this
    /// session's first check the date must not read as current results.
    func title(lastChecked: Date?) -> String {
        self == .notChecked && lastChecked != nil ? "Not checked this session" : title
    }

    func detail(lastChecked: Date?) -> String {
        guard self == .notChecked, let lastChecked else { return detail }
        return "Last checked \(lastChecked.formatted(date: .abbreviated, time: .shortened)). Results from earlier sessions aren’t kept — check now to load current updates."
    }

    static func completed(report: ScanReport, settings: ScanSettings) -> Self {
        guard !report.warnings.isEmpty else { return .complete }
        var succeeded = [report.homebrewInventoryStatus, report.homebrewCatalogStatus,
                         report.macOSUpdatesStatus].contains(.succeeded)
        if settings.includeAdvancedSources && report.macOSInstallersStatus == .succeeded { succeeded = true }
        succeeded = succeeded || report.apps.contains { app in
            enabledAppUpdateSources(for: app, checkAppStore: settings.checkAppStore,
                                    checkSparkle: settings.checkSparkle, checkGitHub: settings.checkGitHub)
                .contains { !(report.failedAppSources[app.id] ?? []).contains($0.source) }
        }
        succeeded = succeeded || report.installedDeveloperManagers.contains { !report.failedDeveloperManagers.contains($0) }
        succeeded = succeeded || report.localModels.contains {
            !report.failedLocalModelIDs.contains($0.id) && !report.failedLocalModelRuntimes.contains($0.runtime)
        }
        return succeeded ? .partial : .failed
    }
}

@MainActor
extension UpkeepStore {
    var updateCheckState: UpdateCheckState {
        let scanSettings = settings.scanSettings
        let enabled = scanSettings.checkAppStore || scanSettings.checkSparkle || scanSettings.checkGitHub
            || scanSettings.checkHomebrew || scanSettings.checkMacOS || scanSettings.checkLocalModels
            || !scanSettings.enabledDeveloperManagers.isEmpty
        guard enabled else { return .disabled }
        if isScanning { return .checking }
        if !scanWarnings.isEmpty {
            return scanState.completedCheckState == .failed ? .failed : .partial
        }
        return scanState.completedCheckState ?? .notChecked
    }

    var macOSCheckState: UpdateCheckState {
        guard settings.checkMacOS else { return .disabled }
        if isScanning { return .checking }
        switch scanState.macOSStatus {
        case .none, .disabled: return .notChecked
        case .failed: return .failed
        case .succeeded: return .complete
        }
    }
}
