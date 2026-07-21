import Foundation

struct UpdateScanner: Sendable {
    func scan(settings: ScanSettings) async -> ScanReport {
        async let installedApps = AppDiscovery.discover()
        async let brewInventory = settings.checkHomebrew ? HomebrewClient().inventory() : []
        async let macOSReport = settings.checkMacOS ? MacOSUpdateClient().scan() : MacOSUpdateClient.Report.empty
        async let developerReport = DeveloperPackageClient().scan(enabledManagers: settings.enabledDeveloperManagers)
        let (apps, packages, systemReport, devReport) = await (installedApps, brewInventory, macOSReport, developerReport)

        var updates: [AvailableUpdate] = []
        await withTaskGroup(of: AvailableUpdate?.self) { group in
            for app in apps {
                group.addTask {
                    if settings.checkAppStore, let update = await AppStoreClient().update(for: app) { return update }
                    if settings.checkSparkle, let update = await SparkleClient().update(for: app) { return update }
                    if settings.checkGitHub { return await GitHubClient().update(for: app) }
                    return nil
                }
            }
            for await update in group {
                if let update { updates.append(update) }
            }
        }

        let normalizedApps = Dictionary(grouping: apps) { normalize($0.name) }
        for package in packages where package.kind == .cask && package.isOutdated {
            let caskName = normalize(package.displayName)
            guard let app = normalizedApps[caskName]?.first ?? normalizedApps[normalize(package.token)]?.first,
                  !updates.contains(where: { $0.app.id == app.id })
            else { continue }
            updates.append(AvailableUpdate(
                app: app,
                availableVersion: package.currentVersion,
                source: .homebrew,
                releaseNotes: nil,
                actionURL: nil,
                homebrewToken: package.token
            ))
        }

        let adoptable = settings.checkHomebrew ? await HomebrewClient().adoptableApps(from: apps, excluding: packages) : []
        for item in adoptable where caskIsNewer(item.caskVersion, than: item.app) {
            guard !updates.contains(where: { $0.app.id == item.app.id }) else { continue }
            updates.append(AvailableUpdate(
                app: item.app,
                availableVersion: item.caskVersion,
                source: .homebrew,
                releaseNotes: "A newer version is available from Homebrew. Updating will move this app under Homebrew management.",
                actionURL: nil,
                homebrewToken: item.caskToken
            ))
        }

        return ScanReport(
            apps: apps,
            updates: updates.sorted { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending },
            checkedAt: Date(),
            warnings: [],
            homebrewPackages: packages,
            adoptableApps: adoptable,
            macOSUpdates: systemReport.updates.filter { settings.includeBetas || !$0.isBeta },
            developerPackages: devReport.packages,
            installedDeveloperManagers: devReport.installedManagers
        )
    }

    private func normalize(_ value: String) -> String {
        value.lowercased().filter(\.isLetter)
    }

    private func caskIsNewer(_ candidate: String, than app: InstalledApp) -> Bool {
        let parts = candidate.split(separator: ",", maxSplits: 1).map(String.init)
        let rawBase = parts[0]
        let hyphenParts = rawBase.split(separator: "-", maxSplits: 1).map(String.init)
        let baseVersion: String
        if hyphenParts.count == 2, hyphenParts[1].contains(where: \.isLetter) {
            baseVersion = hyphenParts[0]
        } else {
            baseVersion = rawBase
        }
        if VersionComparator.isNewer(baseVersion, than: app.installedVersion) { return true }
        guard VersionComparator.compare(baseVersion, app.installedVersion) == .orderedSame,
              parts.count == 2,
              let installedBuild = app.buildVersion
        else { return false }
        return VersionComparator.isNewer(parts[1], than: installedBuild)
    }
}
