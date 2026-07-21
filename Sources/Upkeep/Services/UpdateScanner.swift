import Foundation

struct UpdateScanner: Sendable {
    func scan(settings: ScanSettings) async -> ScanReport {
        async let installedApps = AppDiscovery.discover()
        async let brewInventory = scopedResult(enabled: settings.checkHomebrew) {
            try await HomebrewClient().inventory(includePrereleases: settings.includePrereleaseUpdates)
        }
        async let macOSReport = settings.checkMacOS ? MacOSUpdateClient().scan() : MacOSUpdateClient.Report.empty
        async let developerReport = DeveloperPackageClient().scan(
            enabledManagers: settings.enabledDeveloperManagers,
            includePrereleases: settings.includePrereleaseUpdates
        )
        async let localModels = settings.checkLocalModels ? LocalModelClient().scan() : LocalModelClient.Report.empty
        let (apps, brewResult, systemReport, devReport, modelReport) = await (installedApps, brewInventory, macOSReport, developerReport, localModels)

        var warnings: [ScanWarning] = []
        let packages: [HomebrewPackage]
        let homebrewInventoryStatus: ScanStatus
        switch brewResult {
        case .disabled:
            packages = []
            homebrewInventoryStatus = .disabled
        case let .success(value):
            packages = value
            homebrewInventoryStatus = .succeeded
        case let .failure(error):
            packages = []
            homebrewInventoryStatus = .failed
            warnings.append(scanWarning(.homebrew, error: error))
        }

        var updates: [AvailableUpdate] = []
        var failedAppIDs = Set<String>()
        await withTaskGroup(of: AppCheckResult.self) { group in
            for app in apps {
                group.addTask { await checkApp(app, settings: settings) }
            }
            for await check in group {
                if let update = check.update { updates.append(update) }
                if !check.warnings.isEmpty { failedAppIDs.insert(check.appID) }
                warnings.append(contentsOf: check.warnings)
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

        let adoptable: [AdoptableApp]
        let homebrewCatalogStatus: ScanStatus
        if !settings.checkHomebrew {
            adoptable = []
            homebrewCatalogStatus = .disabled
        } else if homebrewInventoryStatus == .failed {
            adoptable = []
            homebrewCatalogStatus = .failed
        } else {
            do {
                adoptable = try await HomebrewClient().adoptableApps(from: apps, excluding: packages).filter {
                    settings.includePrereleaseUpdates || !VersionComparator.isPrerelease($0.caskVersion)
                }
                homebrewCatalogStatus = .succeeded
            } catch {
                adoptable = []
                homebrewCatalogStatus = .failed
                warnings.append(scanWarning(.homebrew, error: error, prefix: "Cask catalog: "))
            }
        }
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

        warnings.append(contentsOf: systemReport.warnings.map {
            ScanWarning(source: .macOS, message: $0)
        })
        warnings.append(contentsOf: devReport.warnings.map {
            ScanWarning(source: .developerPackages, message: $0)
        })
        warnings.append(contentsOf: modelReport.warnings.map {
            ScanWarning(source: .localModels, message: $0)
        })

        return ScanReport(
            apps: apps,
            updates: updates.sorted { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending },
            checkedAt: Date(),
            warnings: aggregate(warnings),
            failedAppIDs: failedAppIDs,
            homebrewInventoryStatus: homebrewInventoryStatus,
            homebrewCatalogStatus: homebrewCatalogStatus,
            macOSUpdatesStatus: status(enabled: settings.checkMacOS, succeeded: systemReport.updatesSucceeded),
            macOSInstallersStatus: status(enabled: settings.checkMacOS, succeeded: systemReport.installersSucceeded),
            failedDeveloperManagers: devReport.failedManagers,
            localModelsStatus: settings.checkLocalModels ? .succeeded : .disabled,
            failedLocalModelIDs: modelReport.failedModelIDs,
            failedLocalModelRuntimes: modelReport.failedRuntimes,
            homebrewPackages: packages,
            adoptableApps: adoptable,
            macOSUpdates: systemReport.updates.filter { settings.includePrereleaseUpdates || !$0.isBeta },
            developerPackages: devReport.packages,
            installedDeveloperManagers: devReport.installedManagers,
            localModels: modelReport.models
        )
    }

    private struct AppCheckResult: Sendable {
        let appID: String
        let update: AvailableUpdate?
        let warnings: [ScanWarning]
    }

    private func checkApp(_ app: InstalledApp, settings: ScanSettings) async -> AppCheckResult {
        var warnings: [ScanWarning] = []
        if settings.checkAppStore, app.hasAppStoreReceipt {
            do {
                if let update = try await AppStoreClient().update(for: app) {
                    return AppCheckResult(appID: app.id, update: update, warnings: warnings)
                }
            } catch { warnings.append(scanWarning(.appStore, error: error, itemName: app.name)) }
        }
        if settings.checkSparkle, app.sparkleFeedURL != nil {
            do {
                if let update = try await SparkleClient().update(
                    for: app, includePrereleases: settings.includePrereleaseUpdates
                ) {
                    return AppCheckResult(appID: app.id, update: update, warnings: warnings)
                }
            } catch { warnings.append(scanWarning(.sparkle, error: error, itemName: app.name)) }
        }
        if settings.checkGitHub, app.sparkleFeedURL == nil, app.githubRepository != nil {
            do {
                if let update = try await GitHubClient().update(
                    for: app, includePrereleases: settings.includePrereleaseUpdates
                ) {
                    return AppCheckResult(appID: app.id, update: update, warnings: warnings)
                }
            } catch { warnings.append(scanWarning(.github, error: error, itemName: app.name)) }
        }
        return AppCheckResult(appID: app.id, update: nil, warnings: warnings)
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

private enum ScopedResult<Value: Sendable>: Sendable {
    case disabled
    case success(Value)
    case failure(UpdateSourceError)
}

private func scopedResult<T: Sendable>(
    enabled: Bool,
    operation: @Sendable () async throws -> T
) async -> ScopedResult<T> {
    guard enabled else { return .disabled }
    do { return .success(try await operation()) }
    catch { return .failure(UpdateSourceError(error)) }
}

private func status(enabled: Bool, succeeded: Bool) -> ScanStatus {
    guard enabled else { return .disabled }
    return succeeded ? .succeeded : .failed
}

private func scanWarning(
    _ source: ScanWarningSource,
    error: Error,
    itemName: String? = nil,
    prefix: String = ""
) -> ScanWarning {
    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    return ScanWarning(source: source, itemNames: itemName.map { [$0] } ?? [], message: prefix + message)
}

private func aggregate(_ warnings: [ScanWarning]) -> [ScanWarning] {
    struct Key: Hashable { let source: ScanWarningSource; let message: String }
    var grouped: [Key: [String]] = [:]
    for warning in warnings {
        grouped[Key(source: warning.source, message: warning.message), default: []].append(contentsOf: warning.itemNames)
    }
    return grouped.map { key, names in
        let uniqueNames = Array(Set(names))
        return ScanWarning(source: key.source, itemNames: uniqueNames, affectedItemCount: uniqueNames.count, message: key.message)
    }.sorted {
        if $0.source.rawValue != $1.source.rawValue { return $0.source.rawValue < $1.source.rawValue }
        return $0.message < $1.message
    }
}
