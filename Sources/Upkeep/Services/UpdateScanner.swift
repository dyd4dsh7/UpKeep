import Foundation

struct UpdateScanner: Sendable {
    func scan(settings: ScanSettings) async -> ScanReport {
        let scanStartedAt = Date()
        DiagnosticsStore.shared.recordBuffered(.info, category: .scan, "Update scan started", metadata: [
            "App Store": settings.checkAppStore.description,
            "Sparkle": settings.checkSparkle.description,
            "Homebrew": settings.checkHomebrew.description,
            "GitHub": settings.checkGitHub.description,
            "macOS": settings.checkMacOS.description,
            "AI models": settings.checkLocalModels.description,
            "Prereleases": settings.includePrereleaseUpdates.description
        ])
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
        DiagnosticsStore.shared.recordBuffered(
            homebrewInventoryStatus == .failed ? .error : .info,
            category: .source,
            "Homebrew inventory \(diagnosticDescription(homebrewInventoryStatus))",
            metadata: ["Packages": "\(packages.count)"]
        )
        DiagnosticsStore.shared.recordBuffered(.info, category: .source, "Application discovery completed", metadata: [
            "Applications": "\(apps.count)"
        ])

        var updates: [AvailableUpdate] = []
        var failedAppSources: [String: Set<UpdateSource>] = [:]
        await withTaskGroup(of: AppCheckResult.self) { group in
            for app in apps {
                group.addTask { await checkApp(app, settings: settings) }
            }
            for await check in group {
                updates.append(contentsOf: check.updates)
                if !check.failedSources.isEmpty {
                    failedAppSources[check.appID] = check.failedSources
                }
                warnings.append(contentsOf: check.warnings)
            }
        }

        let normalizedApps = Dictionary(grouping: apps) { normalize($0.name) }
        for package in packages where package.kind == .cask && package.isOutdated {
            let caskName = normalize(package.displayName)
            guard let app = normalizedApps[caskName]?.first ?? normalizedApps[normalize(package.token)]?.first,
                  Self.allowsHomebrewCandidate(for: app)
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
                adoptable = try await HomebrewClient().adoptableApps(
                    from: apps.filter { !$0.updateManagement.isExternallyManaged },
                    excluding: packages
                ).filter {
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
            updates.append(AvailableUpdate(
                app: item.app,
                availableVersion: item.caskVersion,
                source: .homebrew,
                releaseNotes: "A newer version is available from Homebrew. Updating will move this app under Homebrew management.",
                actionURL: nil,
                homebrewToken: item.caskToken,
                requiresHomebrewAdoption: true
            ))
        }

        let consolidatedUpdates = Dictionary(grouping: updates, by: { $0.app.id })
            .values
            .compactMap(AvailableUpdate.merging)

        for update in consolidatedUpdates {
            for candidate in update.candidates {
                DiagnosticsStore.shared.recordBuffered(.info, category: .comparison, "Newer version detected", metadata: [
                    "Item": update.app.name,
                    "Installed": update.app.installedVersion,
                    "Available": candidate.availableVersion,
                    "Source": candidate.source.rawValue
                ])
            }
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
        DiagnosticsStore.shared.recordBuffered(
            homebrewCatalogStatus == .failed ? .error : .info,
            category: .source,
            "Homebrew cask catalog \(diagnosticDescription(homebrewCatalogStatus))",
            metadata: ["Adoptable applications": "\(adoptable.count)"]
        )
        DiagnosticsStore.shared.recordBuffered(
            systemReport.warnings.isEmpty ? .info : .warning,
            category: .source,
            "macOS update sources completed",
            metadata: [
                "Updates status": diagnosticDescription(status(enabled: settings.checkMacOS, succeeded: systemReport.updatesSucceeded)),
                "Installers status": diagnosticDescription(status(enabled: settings.checkMacOS, succeeded: systemReport.installersSucceeded)),
                "Results": "\(systemReport.updates.count)",
                "Warnings": "\(systemReport.warnings.count)"
            ]
        )
        DiagnosticsStore.shared.recordBuffered(
            devReport.warnings.isEmpty ? .info : .warning,
            category: .source,
            "Developer package sources completed",
            metadata: [
                "Managers": devReport.installedManagers.map(\.rawValue).sorted().joined(separator: ", "),
                "Packages": "\(devReport.packages.count)",
                "Failed managers": "\(devReport.failedManagers.count)"
            ]
        )
        DiagnosticsStore.shared.recordBuffered(
            modelReport.warnings.isEmpty ? .info : .warning,
            category: .source,
            "AI model sources completed",
            metadata: [
                "Models": "\(modelReport.models.count)",
                "Failed models": "\(modelReport.failedModelIDs.count)",
                "Failed runtimes": "\(modelReport.failedRuntimes.count)"
            ]
        )

        let report = ScanReport(
            apps: apps,
            updates: consolidatedUpdates.sorted { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending },
            checkedAt: Date(),
            warnings: aggregate(warnings),
            failedAppSources: failedAppSources,
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
        DiagnosticsStore.shared.record(
            warnings.isEmpty ? .info : .warning,
            category: .scan,
            "Update scan completed",
            metadata: [
                "Duration": diagnosticDuration(since: scanStartedAt),
                "Applications": "\(apps.count)",
                "Application updates": "\(consolidatedUpdates.count)",
                "Homebrew packages": "\(packages.count)",
                "Developer packages": "\(devReport.packages.count)",
                "AI models": "\(modelReport.models.count)",
                "Warnings": "\(report.warnings.count)"
            ]
        )
        return report
    }

    private struct AppCheckResult: Sendable {
        let appID: String
        let updates: [AvailableUpdate]
        let failedSources: Set<UpdateSource>
        let warnings: [ScanWarning]
    }

    private func checkApp(_ app: InstalledApp, settings: ScanSettings) async -> AppCheckResult {
        var updates: [AvailableUpdate] = []
        var failedSources = Set<UpdateSource>()
        var warnings: [ScanWarning] = []
        guard !app.updateManagement.isExternallyManaged else {
            return AppCheckResult(appID: app.id, updates: [], failedSources: [], warnings: [])
        }
        if settings.checkAppStore, app.updateManagement == .appStore {
            let startedAt = Date()
            do {
                if let update = try await AppStoreClient().update(for: app) {
                    updates.append(update)
                }
                recordAppSourceCheck(app: app, source: .appStore, update: updates.last(where: { $0.source == .appStore }), startedAt: startedAt)
            } catch {
                failedSources.insert(.appStore)
                warnings.append(scanWarning(.appStore, error: error, itemName: app.name))
                recordAppSourceFailure(app: app, source: .appStore, error: error, startedAt: startedAt)
            }
        }
        if settings.checkSparkle, app.sparkleFeedURL != nil {
            let startedAt = Date()
            do {
                if let update = try await SparkleClient().update(
                    for: app, includePrereleases: settings.includePrereleaseUpdates
                ) {
                    updates.append(update)
                }
                recordAppSourceCheck(app: app, source: .sparkle, update: updates.last(where: { $0.source == .sparkle }), startedAt: startedAt)
            } catch {
                failedSources.insert(.sparkle)
                warnings.append(scanWarning(.sparkle, error: error, itemName: app.name))
                recordAppSourceFailure(app: app, source: .sparkle, error: error, startedAt: startedAt)
            }
        }
        if settings.checkGitHub, app.githubRepository != nil {
            let startedAt = Date()
            do {
                if let update = try await GitHubClient().update(
                    for: app, includePrereleases: settings.includePrereleaseUpdates
                ) {
                    updates.append(update)
                }
                recordAppSourceCheck(app: app, source: .github, update: updates.last(where: { $0.source == .github }), startedAt: startedAt)
            } catch {
                failedSources.insert(.github)
                warnings.append(scanWarning(.github, error: error, itemName: app.name))
                recordAppSourceFailure(app: app, source: .github, error: error, startedAt: startedAt)
            }
        }
        return AppCheckResult(appID: app.id, updates: updates, failedSources: failedSources, warnings: warnings)
    }

    private func normalize(_ value: String) -> String {
        value.lowercased().filter(\.isLetter)
    }

    static func allowsHomebrewCandidate(for app: InstalledApp) -> Bool {
        !app.updateManagement.isExternallyManaged
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

private func recordAppSourceCheck(
    app: InstalledApp,
    source: UpdateSource,
    update: AvailableUpdate?,
    startedAt: Date
) {
    var metadata = [
        "Item": app.name,
        "Installed": app.installedVersion,
        "Duration": diagnosticDuration(since: startedAt),
        "Result": update == nil ? "Current" : "Update available"
    ]
    if let update { metadata["Available"] = update.availableVersion }
    DiagnosticsStore.shared.recordBuffered(.info, category: .source, "\(source.rawValue) request completed", metadata: metadata)
}

private func recordAppSourceFailure(
    app: InstalledApp,
    source: UpdateSource,
    error: Error,
    startedAt: Date
) {
    DiagnosticsStore.shared.recordBuffered(.error, category: .source, "\(source.rawValue) request failed", metadata: [
        "Item": app.name,
        "Installed": app.installedVersion,
        "Duration": diagnosticDuration(since: startedAt),
        "Error": error.localizedDescription
    ])
}

private func diagnosticDuration(since date: Date) -> String {
    String(format: "%.0f ms", Date().timeIntervalSince(date) * 1_000)
}

private func diagnosticDescription(_ status: ScanStatus) -> String {
    switch status {
    case .disabled: "disabled"
    case .succeeded: "completed"
    case .failed: "failed"
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
