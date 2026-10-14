import Foundation

@MainActor
extension UpkeepStore {
    func recordAppSourceChecks(app: InstalledApp, settings scanSettings: ScanSettings,
                               failed: Set<UpdateSource>, warnings: [ScanWarning], at date: Date) {
        settings.recordSourceAttempts(appSourceAttempts(app: app, settings: scanSettings, failed: failed, warnings: warnings), at: date)
    }

    private func appSourceAttempts(app: InstalledApp, settings scanSettings: ScanSettings,
                                   failed: Set<UpdateSource>, warnings: [ScanWarning]) -> [String: String] {
        var attempts: [String: String] = [:]
        let sources = enabledAppUpdateSources(for: app, checkAppStore: scanSettings.checkAppStore,
            checkSparkle: scanSettings.checkSparkle, checkGitHub: scanSettings.checkGitHub)
            .map(\.source).filter { scanSettings.appSourceFilter?.contains($0) ?? true }
        for source in sources {
            let warning = warnings.first {
                $0.source == source.warningSource && ($0.itemNamesByID.map { $0[app.id] != nil } ?? $0.itemNames.contains(app.name))
            } ?? warnings.first {
                $0.source == source.warningSource && $0.affectedItemCount == 0 && $0.itemNames.isEmpty
            }
            let failure = failed.contains(source)
                ? warning?.detail ?? "This source could not be verified."
                : nil
            attempts["app|\(app.id)|\(source.rawValue)"] = failure ?? ""
        }
        return attempts
    }

    func recordScanFreshness(_ report: ScanReport, settings scanSettings: ScanSettings, protecting keys: Set<String> = []) {
        var attempts: [String: String] = [:]
        for app in report.apps {
            attempts.merge(appSourceAttempts(app: app, settings: scanSettings,
                failed: report.failedAppSources[app.id] ?? [], warnings: report.warnings)) { _, latest in latest }
        }
        for (key, status) in [("homebrew.inventory", report.homebrewInventoryStatus),
                              ("homebrew.catalog", report.homebrewCatalogStatus),
                              ("macos.updates", report.macOSUpdatesStatus),
                              ("macos.installers", report.macOSInstallersStatus)] where status != .disabled {
            attempts[key] = status == .failed ? "The source check failed. See source details." : ""
        }
        for manager in Set(report.installedDeveloperManagers).union(report.failedDeveloperManagers) {
            let failed = report.failedDeveloperManagers.contains(manager)
                || report.developerPackages.contains { $0.manager == manager && report.failedDeveloperExecutablePaths.contains($0.executablePath) }
                || (!report.failedDeveloperExecutablePaths.isEmpty
                    && report.warnings.contains { $0.source == .developerPackages && $0.itemNames.contains(manager.rawValue) })
            attempts["developer|\(manager.rawValue)"] = failed ? "Some packages in this environment could not be verified." : ""
        }
        for model in report.localModels where !keys.contains("model.runtime|\(model.runtime.rawValue)") {
            attempts["model|\(model.id)"] = report.failedLocalModelIDs.contains(model.id) || report.failedLocalModelRuntimes.contains(model.runtime)
                ? "The model source could not be verified." : ""
        }
        for runtime in LocalModelRuntime.allCases where scanSettings.checkLocalModels {
            attempts["model.runtime|\(runtime.rawValue)"] = report.failedLocalModelRuntimes.contains(runtime)
                ? "This runtime could not be checked." : ""
        }
        settings.recordSourceAttempts(attempts.filter { !keys.contains($0.key) }, at: report.checkedAt)
    }
}
