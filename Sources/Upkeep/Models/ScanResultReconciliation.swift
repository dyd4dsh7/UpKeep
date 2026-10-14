import Foundation

/// Pure source-result policies; failed scopes retain their previous inventory.
enum ScanResultReconciliation {
    static func macOS(_ report: ScanReport, previous: [MacOSUpdate]) -> [MacOSUpdate] {
        let currentUpdates = report.macOSUpdates.filter { !$0.isFullInstaller }
        let currentInstallers = report.macOSUpdates.filter(\.isFullInstaller)
        let updatesPart: [MacOSUpdate] = report.macOSUpdatesStatus == .failed
            ? previous.filter { !$0.isFullInstaller }
            : currentUpdates
        let installersPart: [MacOSUpdate] = report.macOSInstallersStatus == .failed
            ? previous.filter(\.isFullInstaller)
            : currentInstallers
        return updatesPart + installersPart
    }

    static func developer(_ report: ScanReport, previous: [DeveloperPackage]) -> [DeveloperPackage] {
        developerPackages(
            fresh: report.developerPackages,
            previous: previous,
            failedManagers: report.failedDeveloperManagers,
            failedExecutablePaths: report.failedDeveloperExecutablePaths
        ).sorted(by: developerOrder)
    }

    static func models(_ report: ScanReport, previous: [LocalLLMModel]) -> [LocalLLMModel] {
        guard report.localModelsStatus != .disabled else { return [] }
        var merged = Dictionary(report.localModels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for retained in previous where report.failedLocalModelIDs.contains(retained.id)
            || report.failedLocalModelRuntimes.contains(retained.runtime) {
            merged[retained.id] = retained
        }
        return merged.values.sorted(by: modelOrder)
    }

    static func developerOrder(_ lhs: DeveloperPackage, _ rhs: DeveloperPackage) -> Bool {
        if lhs.manager != rhs.manager { return lhs.manager.rawValue < rhs.manager.rawValue }
        let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return (lhs.installationContext ?? lhs.executablePath).localizedStandardCompare(rhs.installationContext ?? rhs.executablePath) == .orderedAscending
    }

    static func modelOrder(_ lhs: LocalLLMModel, _ rhs: LocalLLMModel) -> Bool {
        if lhs.runtime != rhs.runtime { return lhs.runtime.rawValue < rhs.runtime.rawValue }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    static func developerPackages(
        fresh: [DeveloperPackage],
        previous: [DeveloperPackage],
        failedManagers: Set<DeveloperPackageManager>,
        failedExecutablePaths: Set<String>
    ) -> [DeveloperPackage] {
        let retained = previous.filter {
            failedManagers.contains($0.manager) || failedExecutablePaths.contains($0.executablePath)
        }
        let acceptedFresh = fresh.filter { !failedManagers.contains($0.manager) }
        return Dictionary(grouping: retained + acceptedFresh, by: \.id).compactMap { $0.value.first }
    }
}
