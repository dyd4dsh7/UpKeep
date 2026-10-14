import Foundation

enum ScanProgressEvent: Sendable {
    case discovered([InstalledApp])
    case homebrewInventory([HomebrewPackage])
    case macOS(MacOSUpdateClient.Report, includeInstallers: Bool, includePrereleases: Bool)
    case developerPackages(DeveloperPackageClient.Report, managers: Set<DeveloperPackageManager>)
    case localModels(LocalModelClient.Report, runtimes: Set<LocalModelRuntime> = Set(LocalModelRuntime.allCases))
    case appSource(appID: String, source: UpdateSource, update: AvailableUpdate?, warning: ScanWarning?, completed: Int, total: Int)
}

typealias ScanProgressReporter = @Sendable (ScanProgressEvent) async -> Void

struct ScanProgress: Sendable {
    let completed: Int
    let total: Int
    let lastSource: UpdateSource
}
