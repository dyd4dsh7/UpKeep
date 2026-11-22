import Foundation

enum AppUpdateSource: Sendable {
    case appStore
    case developer
    case sparkle
    case github

    var source: UpdateSource {
        switch self {
        case .appStore: .appStore
        case .developer: .developer
        case .sparkle: .sparkle
        case .github: .github
        }
    }
}

func enabledAppUpdateSources(
    for app: InstalledApp,
    checkAppStore: Bool,
    checkSparkle: Bool,
    checkGitHub: Bool
) -> [AppUpdateSource] {
    switch app.updateManagement {
    case .appStore:
        return checkAppStore ? [.appStore] : []
    case .direct:
        var sources: [AppUpdateSource] = []
        if app.usesDeveloperUpdateService { sources.append(.developer) }
        if checkSparkle, app.sparkleFeedURL != nil { sources.append(.sparkle) }
        if checkGitHub, app.githubRepository != nil { sources.append(.github) }
        return sources
    case .testFlight, .setapp, .microsoftAutoUpdate, .steam,
         .adobeCreativeCloud, .jetBrainsToolbox, .spotify, .discord, .epicGames,
         .tailscale, .macOS:
        return []
    }
}

struct UpdateScanner: Sendable {
    private let dependencies: UpdateScannerDependencies

    init(dependencies: UpdateScannerDependencies = .live) {
        self.dependencies = dependencies
    }

    func homebrewInventory(includePrereleases: Bool) async throws -> [HomebrewPackage] {
        try await dependencies.homebrew.inventory(includePrereleases: includePrereleases)
    }

    func macOS(scope: MacOSScanScope) async throws -> MacOSUpdateClient.Report {
        try await dependencies.macOS.scan(scope: scope)
    }

    func homebrewCatalog() async throws -> [CatalogCask] {
        try await dependencies.homebrew.caskCatalog()
    }

    struct TargetedAppReport: Sendable {
        let updates: [AvailableUpdate]
        let failedSources: Set<UpdateSource>
        let warnings: [ScanWarning]

        static let empty = TargetedAppReport(updates: [], failedSources: [], warnings: [])
    }

    /// Checks only the sources declared by one application. Homebrew candidates are
    /// refreshed separately by token in `UpkeepStore`.
    func scan(app: InstalledApp, settings: ScanSettings) async -> TargetedAppReport {
        let result = await checkApp(app, settings: settings)
        return TargetedAppReport(
            updates: result.updates,
            failedSources: result.failedSources,
            warnings: result.warnings
        )
    }

    private func scanModelSources(settings: ScanSettings, progress: @escaping ScanProgressReporter) async -> LocalModelClient.Report {
        guard settings.checkLocalModels else { return .empty }
        let report = await dependencies.localModels.scan { report, runtimes in
            await progress(.localModels(report, runtimes: runtimes))
        }
        return report
    }

    private func scanDeveloperSources(settings: ScanSettings, progress: @escaping ScanProgressReporter) async -> DeveloperPackageClient.Report {
        guard !settings.enabledDeveloperManagers.isEmpty else { return .empty }
        let report = await dependencies.developerPackages.scan(enabledManagers: settings.enabledDeveloperManagers,
            includePrereleases: settings.includePrereleaseUpdates) { report, managers in
                await progress(.developerPackages(report, managers: managers))
            }
        return report
    }

    private func scanSystem(settings: ScanSettings, progress: @escaping ScanProgressReporter) async -> MacOSUpdateClient.Report {
        guard settings.checkMacOS else { return .empty }
        let report = await dependencies.macOS.scan(includeInstallers: settings.includeAdvancedSources)
        await progress(.macOS(report, includeInstallers: settings.includeAdvancedSources,
            includePrereleases: settings.includePrereleaseUpdates))
        return report
    }

    func scan(settings: ScanSettings) async -> ScanReport {
        await scan(settings: settings, progress: { _ in })
    }

    func scan(settings: ScanSettings, progress: @escaping ScanProgressReporter) async -> ScanReport {
        let scanStartedAt = Date()
        DiagnosticsStore.shared.recordBuffered(.info, category: .scan, "Update scan started", metadata: [
            "App Store": settings.checkAppStore.description,
            "Sparkle": settings.checkSparkle.description,
            "Homebrew": settings.checkHomebrew.description,
            "GitHub": settings.checkGitHub.description,
            "macOS": settings.checkMacOS.description,
            "AI models": settings.checkLocalModels.description,
            "Prereleases": settings.includePrereleaseUpdates.description,
            "Advanced sources": settings.includeAdvancedSources.description
        ])
        async let installedApps = dependencies.applicationDiscovery.discover()
        async let brewInventory = scopedResult(enabled: settings.checkHomebrew) {
            let packages = try await dependencies.homebrew.inventory(includePrereleases: settings.includePrereleaseUpdates)
            await progress(.homebrewInventory(packages))
            return packages
        }
        async let brewCatalog = scopedResult(enabled: settings.checkHomebrew && settings.includeAdvancedSources) {
            try await dependencies.homebrew.caskCatalog()
        }
        async let macOSReport = scanSystem(settings: settings, progress: progress)
        async let developerReport = scanDeveloperSources(settings: settings, progress: progress)
        async let localModels = scanModelSources(settings: settings, progress: progress)

        // App source checks only depend on discovery, so do not hold them behind
        // Homebrew, softwareupdate, developer-manager, or model scans.
        let apps = await installedApps
        await progress(.discovered(apps))
        async let appChecks = checkApps(apps, settings: settings, progress: progress)
        let brewResult = await brewInventory

        var warnings: [ScanWarning] = []
        var packages: [HomebrewPackage]
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
            warnings.append(scanWarning(.homebrew, error: error, prefix: "Installed packages: "))
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

        let (applicationResult, catalogResult, systemReport, devReport, modelReport) = await (
            appChecks, brewCatalog, macOSReport, developerReport, localModels
        )
        var updates = applicationResult.updates
        let failedAppSources = applicationResult.failedSources
        warnings.append(contentsOf: applicationResult.warnings)

        let appsByProductName = Self.appsByProductName(apps)
        packages = packages.map { package in
            guard let app = Self.app(for: package, in: appsByProductName) else { return package }
            return package.reconciled(with: app)
        }
        for package in packages where package.kind == .cask && package.isOutdated {
            guard let app = Self.app(for: package, in: appsByProductName),
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
        switch catalogResult {
        case .disabled:
            adoptable = []
            homebrewCatalogStatus = .disabled
        case let .success(catalog):
            if homebrewInventoryStatus == .failed {
                adoptable = []
                homebrewCatalogStatus = .failed
            } else {
                adoptable = dependencies.homebrew.adoptableApps(
                    from: apps.filter(\.allowsHomebrewAdoption),
                    catalog: catalog,
                    excluding: packages
                ).filter {
                    settings.includePrereleaseUpdates || !VersionComparator.isPrerelease($0.caskVersion)
                }
                homebrewCatalogStatus = .succeeded
            }
        case let .failure(error):
            adoptable = []
            homebrewCatalogStatus = .failed
            if homebrewInventoryStatus != .failed {
                warnings.append(scanWarning(.homebrew, error: error, prefix: "Cask catalog: "))
            }
        }
        for item in adoptable where Self.caskIsNewer(item.caskVersion, than: item.app) {
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
        warnings.append(contentsOf: devReport.scanWarnings)
        warnings.append(contentsOf: modelReport.scanWarnings)
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
            failedDeveloperExecutablePaths: devReport.failedExecutablePaths,
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
        for warning in report.warnings {
            DiagnosticsStore.shared.recordBuffered(
                .warning,
                category: .source,
                warning.title,
                metadata: [
                    "Source": warning.source.rawValue,
                    "Details": warning.detail,
                    "Affected items": "\(warning.affectedItemCount)"
                ]
            )
        }
        DiagnosticsStore.shared.record(
            warnings.isEmpty ? .info : .warning,
            category: .scan,
            "Update scan completed",
            metadata: [
                "Duration": formattedDiagnosticDuration(since: scanStartedAt),
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

    private struct ApplicationCheckResults: Sendable {
        let updates: [AvailableUpdate]
        let failedSources: [String: Set<UpdateSource>]
        let warnings: [ScanWarning]
    }

    private struct AppSourceCheckResult: Sendable {
        let appID: String
        let source: UpdateSource
        let update: AvailableUpdate?
        let warning: ScanWarning?
    }

    private func checkApps(_ apps: [InstalledApp], settings: ScanSettings, progress: @escaping ScanProgressReporter) async -> ApplicationCheckResults {
        await withTaskGroup(of: [AppSourceCheckResult].self) { group in
            var appStoreApps: [InstalledApp] = []
            var total = 0
            for app in apps {
                for source in enabledSources(for: app, settings: settings) {
                    total += 1
                    // App Store lookups are batched into a few iTunes requests.
                    if source == .appStore {
                        appStoreApps.append(app)
                        continue
                    }
                    group.addTask {
                        [await checkSource(
                            app: app,
                            appSource: source,
                            includePrereleases: settings.includePrereleaseUpdates
                        )]
                    }
                }
            }
            if !appStoreApps.isEmpty {
                let batchedApps = appStoreApps
                group.addTask { await checkAppStoreBatch(batchedApps) }
            }
            var updates: [AvailableUpdate] = []
            var failedSources: [String: Set<UpdateSource>] = [:]
            var warnings: [ScanWarning] = []
            var completed = 0
            for await batch in group {
                for result in batch {
                    if let update = result.update { updates.append(update) }
                    if let warning = result.warning {
                        failedSources[result.appID, default: []].insert(result.source)
                        warnings.append(warning)
                    }
                    completed += 1
                    await progress(.appSource(appID: result.appID, source: result.source,
                        update: result.update, warning: result.warning, completed: completed, total: total))
                }
            }
            return ApplicationCheckResults(
                updates: updates,
                failedSources: failedSources,
                warnings: warnings
            )
        }
    }

    private func checkApp(_ app: InstalledApp, settings: ScanSettings) async -> AppCheckResult {
        var updates: [AvailableUpdate] = []
        var failedSources = Set<UpdateSource>()
        var warnings: [ScanWarning] = []
        await withTaskGroup(of: AppSourceCheckResult.self) { group in
            for source in enabledSources(for: app, settings: settings) {
                group.addTask {
                    await checkSource(
                        app: app,
                        appSource: source,
                        includePrereleases: settings.includePrereleaseUpdates
                    )
                }
            }
            for await result in group {
                if let update = result.update { updates.append(update) }
                if let warning = result.warning {
                    failedSources.insert(result.source)
                    warnings.append(warning)
                }
            }
        }
        return AppCheckResult(appID: app.id, updates: updates, failedSources: failedSources, warnings: warnings)
    }

    private func enabledSources(for app: InstalledApp, settings: ScanSettings) -> [AppUpdateSource] {
        enabledAppUpdateSources(
            for: app,
            checkAppStore: settings.checkAppStore,
            checkSparkle: settings.checkSparkle,
            checkGitHub: settings.checkGitHub
        ).filter { settings.appSourceFilter?.contains($0.source) ?? true }
    }

    private func checkAppStoreBatch(_ apps: [InstalledApp]) async -> [AppSourceCheckResult] {
        let startedAt = Date()
        let outcomes = await dependencies.appStore.updates(for: apps)
        return apps.map { app in
            switch outcomes[app.id] ?? .success(nil) {
            case .success(let update):
                recordAppSourceCheck(app: app, source: .appStore, update: update, startedAt: startedAt)
                return AppSourceCheckResult(appID: app.id, source: .appStore, update: update, warning: nil)
            case .failure(let error):
                recordAppSourceFailure(app: app, source: .appStore, error: error, startedAt: startedAt)
                return AppSourceCheckResult(
                    appID: app.id,
                    source: .appStore,
                    update: nil,
                    warning: scanWarning(.appStore, error: error, itemName: app.name, itemID: app.id)
                )
            }
        }
    }

    private func checkSource(
        app: InstalledApp,
        appSource: AppUpdateSource,
        includePrereleases: Bool
    ) async -> AppSourceCheckResult {
        let source = appSource.source
        let startedAt = Date()
        do {
            let update: AvailableUpdate?
            switch appSource {
            case .appStore:
                update = try await dependencies.appStore.update(for: app)
            case .developer:
                update = try await dependencies.mozilla.update(
                    for: app,
                    includePrereleases: includePrereleases
                )
            case .sparkle:
                update = try await dependencies.sparkle.update(
                    for: app,
                    includePrereleases: includePrereleases
                )
            case .github:
                update = try await dependencies.github.update(
                    for: app,
                    includePrereleases: includePrereleases
                )
            }
            recordAppSourceCheck(app: app, source: source, update: update, startedAt: startedAt)
            return AppSourceCheckResult(appID: app.id, source: source, update: update, warning: nil)
        } catch {
            recordAppSourceFailure(app: app, source: source, error: error, startedAt: startedAt)
            return AppSourceCheckResult(
                appID: app.id,
                source: source,
                update: nil,
                warning: scanWarning(source.warningSource, error: error, itemName: app.name, itemID: app.id)
            )
        }
    }

    /// First app (by name order) for each product name variant, matching the
    /// app details' cask lookup.
    static func appsByProductName(_ apps: [InstalledApp]) -> [String: InstalledApp] {
        var index: [String: InstalledApp] = [:]
        for app in apps {
            for name in homebrewProductNameVariants(app.name) where index[name] == nil { index[name] = app }
        }
        return index
    }

    static func app(for package: HomebrewPackage, in appsByProductName: [String: InstalledApp]) -> InstalledApp? {
        guard package.kind == .cask else { return nil }
        // Prefer the cask's own app bundle names, then its display name and token.
        let artifactNames = package.appArtifactNames
            .flatMap { homebrewProductNameVariants(($0 as NSString).deletingPathExtension) }
        let otherNames = homebrewProductNameVariants(package.displayName)
            .union(homebrewProductNameVariants(package.token))
        return (artifactNames + otherNames.sorted()).lazy.compactMap { appsByProductName[$0] }.first
    }

    static func allowsHomebrewCandidate(for app: InstalledApp) -> Bool {
        app.updateManagement == .direct && !app.isWrappedIOSApp
    }

    static func caskIsNewer(_ candidate: String, than app: InstalledApp) -> Bool {
        let parts = candidate.split(separator: ",", maxSplits: 1).map(String.init)
        guard let rawBase = parts.first else { return false }
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

extension UpdateSource {
    var warningSource: ScanWarningSource {
        switch self {
        case .appStore: .appStore
        case .developer: .developer
        case .sparkle: .sparkle
        case .homebrew: .homebrew
        case .github: .github
        }
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
        "Duration": formattedDiagnosticDuration(since: startedAt),
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
    var metadata = [
        "Item": app.name,
        "Installed": app.installedVersion,
        "Duration": formattedDiagnosticDuration(since: startedAt),
        "Error": error.localizedDescription
    ]
    if source == .sparkle, let host = app.sparkleFeedURL?.host {
        metadata["Publisher host"] = host
    }
    DiagnosticsStore.shared.recordBuffered(.error, category: .source, "\(source.rawValue) request failed", metadata: metadata)
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
    itemID: String? = nil,
    prefix: String = ""
) -> ScanWarning {
    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    let ownership = itemID.flatMap { id in itemName.map { [id: $0] } }
    return ScanWarning(source: source, itemNames: itemName.map { [$0] } ?? [], itemNamesByID: ownership, message: prefix + message)
}

private func aggregate(_ warnings: [ScanWarning]) -> [ScanWarning] {
    struct Key: Hashable { let source: ScanWarningSource; let message: String }
    var grouped: [Key: [String]] = [:]
    var ownership: [Key: [String: String]] = [:]
    for warning in warnings {
        let key = Key(source: warning.source, message: warning.message)
        grouped[key, default: []].append(contentsOf: warning.itemNames)
        if let items = warning.itemNamesByID { ownership[key, default: [:]].merge(items) { _, latest in latest } }
    }
    return grouped.map { key, names in
        let uniqueNames = Array(Set(names))
        return ScanWarning(source: key.source, itemNames: uniqueNames, affectedItemCount: max(uniqueNames.count, ownership[key]?.count ?? 0), itemNamesByID: ownership[key], message: key.message)
    }.sorted {
        if $0.source.rawValue != $1.source.rawValue { return $0.source.rawValue < $1.source.rawValue }
        return $0.message < $1.message
    }
}
