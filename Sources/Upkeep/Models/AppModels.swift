import Foundation

struct InstalledApp: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let bundleIdentifier: String?
    let installedVersion: String
    let buildVersion: String?
    let url: URL
    let sparkleFeedURL: URL?
    let githubRepository: String?
    let hasAppStoreReceipt: Bool
    let updateManagement: AppUpdateManagement
    let hasBuiltInUpdater: Bool
    let mozillaUpdateProduct: MozillaUpdateProduct?
    let mozillaUpdateChannel: MozillaUpdateChannel?
    let chromiumUpdateChannel: ChromiumUpdateChannel?
    let braveUpdateChannel: BraveUpdateChannel?
    /// `latest-mac.yml` for Electron apps using electron-updater's generic provider.
    let electronUpdateFeedURL: URL?
    let vendorUpdateProduct: VendorUpdateProduct?
    let steamAppID: String?
    let managedUpdateStatus: ManagedUpdateStatus?
    let installedAt: Date?
    let modifiedAt: Date?
    let architectures: [String]
    var architecture: AppArchitecture { AppArchitecture(architectures: architectures) }
    var needsAppleSiliconMigration: Bool {
        architecture.needsMigration(onAppleSilicon: AppArchitectureInspector.isAppleSilicon)
    }
    var prereleaseChannel: PrereleaseChannel? { VersionComparator.prereleaseChannel(for: installedVersion) }
    /// Checked through a publisher's own version service (the `.developer` source).
    var usesDeveloperUpdateService: Bool {
        mozillaUpdateChannel != nil || chromiumUpdateChannel != nil
            || braveUpdateChannel != nil || electronUpdateFeedURL != nil
            || vendorUpdateProduct != nil
    }

    init(
        name: String,
        bundleIdentifier: String?,
        installedVersion: String,
        buildVersion: String?,
        url: URL,
        sparkleFeedURL: URL?,
        githubRepository: String?,
        hasAppStoreReceipt: Bool,
        updateManagement: AppUpdateManagement? = nil,
        hasBuiltInUpdater: Bool? = nil,
        mozillaUpdateProduct: MozillaUpdateProduct? = nil,
        mozillaUpdateChannel: MozillaUpdateChannel? = nil,
        chromiumUpdateChannel: ChromiumUpdateChannel? = nil,
        braveUpdateChannel: BraveUpdateChannel? = nil,
        electronUpdateFeedURL: URL? = nil,
        vendorUpdateProduct: VendorUpdateProduct? = nil,
        steamAppID: String? = nil,
        managedUpdateStatus: ManagedUpdateStatus? = nil,
        installedAt: Date? = nil,
        modifiedAt: Date? = nil,
        architectures: [String] = []
    ) {
        self.id = bundleIdentifier.map { "\($0)|\(url.path)" } ?? url.path
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.installedVersion = installedVersion
        self.buildVersion = buildVersion
        self.url = url
        self.sparkleFeedURL = sparkleFeedURL
        self.githubRepository = githubRepository
        self.hasAppStoreReceipt = hasAppStoreReceipt
        self.updateManagement = updateManagement ?? (hasAppStoreReceipt ? .appStore : .direct)
        self.hasBuiltInUpdater = hasBuiltInUpdater ?? (
            sparkleFeedURL != nil || mozillaUpdateChannel != nil
                || chromiumUpdateChannel != nil || braveUpdateChannel != nil
                || electronUpdateFeedURL != nil || vendorUpdateProduct != nil
        )
        self.mozillaUpdateProduct = mozillaUpdateChannel == nil
            ? nil
            : (mozillaUpdateProduct ?? .firefox)
        self.mozillaUpdateChannel = mozillaUpdateChannel
        self.chromiumUpdateChannel = chromiumUpdateChannel
        self.braveUpdateChannel = braveUpdateChannel
        self.electronUpdateFeedURL = electronUpdateFeedURL
        self.vendorUpdateProduct = vendorUpdateProduct
        self.steamAppID = steamAppID
        self.managedUpdateStatus = managedUpdateStatus
        self.installedAt = installedAt
        self.modifiedAt = modifiedAt
        self.architectures = architectures
    }

    var updateExclusionKey: String {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return "app|bundle|\(bundleIdentifier.lowercased())"
        }
        return "app|path|\(url.standardizedFileURL.path)"
    }

    /// Adoption is an explicit ownership change. Direct developer downloads
    /// remain eligible even when they embed an updater; the Homebrew catalog
    /// separately excludes casks that declare `auto_updates`.
    var allowsHomebrewAdoption: Bool {
        updateManagement == .direct
    }

    func replacingGitHubRepository(_ repository: String?) -> InstalledApp {
        InstalledApp(
            name: name,
            bundleIdentifier: bundleIdentifier,
            installedVersion: installedVersion,
            buildVersion: buildVersion,
            url: url,
            sparkleFeedURL: sparkleFeedURL,
            githubRepository: repository,
            hasAppStoreReceipt: hasAppStoreReceipt,
            updateManagement: updateManagement,
            hasBuiltInUpdater: hasBuiltInUpdater,
            mozillaUpdateProduct: mozillaUpdateProduct,
            mozillaUpdateChannel: mozillaUpdateChannel,
            chromiumUpdateChannel: chromiumUpdateChannel,
            braveUpdateChannel: braveUpdateChannel,
            electronUpdateFeedURL: electronUpdateFeedURL,
            vendorUpdateProduct: vendorUpdateProduct,
            steamAppID: steamAppID,
            managedUpdateStatus: managedUpdateStatus,
            installedAt: installedAt,
            modifiedAt: modifiedAt,
            architectures: architectures
        )
    }
}

enum MozillaUpdateProduct: String, Hashable, Sendable {
    case firefox
    case thunderbird
}

enum MozillaUpdateChannel: String, Hashable, Sendable {
    case release
    case developerEdition
    case nightly
    case esr
}

enum ChromiumUpdateChannel: String, Hashable, Sendable {
    case stable
    case beta
    case dev
    case canary
}

enum BraveUpdateChannel: String, Hashable, Sendable {
    case release
    case beta
    case dev
    case nightly
}

enum AppUpdateManagement: String, Codable, Hashable, Sendable {
    case direct = "Developer"
    case appStore = "App Store"
    case testFlight = "TestFlight"
    case setapp = "Setapp"
    case microsoftAutoUpdate = "Microsoft AutoUpdate"
    case steam = "Steam"
    case adobeCreativeCloud = "Adobe Creative Cloud"
    case jetBrainsToolbox = "JetBrains Toolbox"
    case spotify = "Spotify"
    case discord = "Discord"
    case epicGames = "Epic Games"
    case tailscale = "Tailscale"
    case macOS = "macOS"

    var isExternallyManaged: Bool {
        switch self {
        case .testFlight, .setapp, .microsoftAutoUpdate, .steam,
             .adobeCreativeCloud, .jetBrainsToolbox, .spotify, .discord, .epicGames,
             .tailscale, .macOS:
            true
        case .direct, .appStore: false
        }
    }

    var actionTitle: String {
        switch self {
        case .testFlight: "Open TestFlight"
        case .setapp: "Open Setapp"
        case .microsoftAutoUpdate: "Open Microsoft AutoUpdate"
        case .steam: "Open Steam Downloads"
        case .adobeCreativeCloud: "Open Adobe Creative Cloud"
        case .jetBrainsToolbox: "Open JetBrains Toolbox"
        case .spotify: "Open Spotify"
        case .discord: "Open Discord"
        case .epicGames: "Open Epic Games"
        case .tailscale: "Open Tailscale"
        case .macOS: "Open Software Update"
        case .appStore: "Open App Store"
        case .direct: "Open App"
        }
    }

    var systemImage: String {
        switch self {
        case .testFlight: "paperplane.fill"
        case .setapp: "square.stack.3d.up.fill"
        case .microsoftAutoUpdate: "arrow.triangle.2.circlepath"
        case .steam: "gamecontroller.fill"
        case .adobeCreativeCloud: "cloud.fill"
        case .jetBrainsToolbox: "shippingbox.fill"
        case .spotify: "music.note"
        case .discord: "bubble.left.and.bubble.right.fill"
        case .epicGames: "gamecontroller.fill"
        case .tailscale: "network"
        case .macOS: "gear.badge"
        case .appStore: "storefront.fill"
        case .direct: "arrow.up.forward.app"
        }
    }

    var updateExplanation: String {
        switch self {
        case .testFlight: "This beta is updated through TestFlight, not the Mac App Store."
        case .setapp: "This edition is managed and updated by Setapp."
        case .microsoftAutoUpdate: "This installation is managed by Microsoft AutoUpdate."
        case .steam: "This app or game is installed and updated through Steam."
        case .adobeCreativeCloud: "This app is managed by Adobe Creative Cloud."
        case .jetBrainsToolbox: "This app is managed by JetBrains Toolbox."
        case .spotify: "Spotify manages updates through its built-in updater."
        case .discord: "Discord manages updates through its built-in updater."
        case .epicGames: "This app or game is managed by Epic Games Launcher."
        case .tailscale: "This standalone edition uses Tailscale’s built-in updater."
        case .macOS: "This Apple app is updated as part of macOS."
        case .appStore: "This app is updated through the Mac App Store."
        case .direct: "This app is updated by its developer."
        }
    }
}

struct ManagedUpdateStatus: Hashable, Sendable {
    enum State: String, Hashable, Sendable {
        case managed = "Managed"
        case queued = "Queued"
        case downloading = "Downloading"
        case installing = "Installing"
    }

    let state: State
    let detail: String
    let progress: Double?

    init(state: State, detail: String, progress: Double? = nil) {
        self.state = state
        self.detail = detail
        self.progress = progress.map { min(max($0, 0), 1) }
    }
}

enum ReleaseVerification: String, Hashable, Sendable {
    case platformManaged = "Platform-managed"
    case packageManager = "Package-manager verified"
    case publisherFeed = "Publisher feed"
    case sparkleSignature = "Sparkle signature declared"
    case repositoryMatch = "Repository matched"
}

enum UpdateSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case appStore = "App Store"
    case developer = "Developer"
    case sparkle = "Sparkle"
    case homebrew = "Homebrew"
    case github = "GitHub"

    var id: Self { self }

    var confidenceDetail: String {
        switch self {
        case .appStore: "Apple-managed distribution"
        case .developer: "Developer-published update service"
        case .sparkle: "Developer-published update feed"
        case .homebrew: "Homebrew-managed package"
        case .github: "Matched GitHub repository"
        }
    }
}

enum PrereleaseChannel: String, Codable, Hashable, Sendable {
    case development = "DEV"
    case nightly = "NIGHTLY"
    case snapshot = "SNAPSHOT"
    case alpha = "ALPHA"
    case beta = "BETA"
    case preview = "PREVIEW"
    case releaseCandidate = "RC"
    case prerelease = "PRERELEASE"
}

struct UpdateCandidate: Identifiable, Hashable, Sendable {
    var id: UpdateSource { source }
    let availableBuildVersion: String?
    let usesBuildVersionOnly: Bool
    let availableVersion: String
    let source: UpdateSource
    let releaseNotes: String?
    let actionURL: URL?
    let homebrewToken: String?
    let sourcePrereleaseChannel: PrereleaseChannel?
    let requiresHomebrewAdoption: Bool
    let requiresInAppInstallation: Bool
    let verification: ReleaseVerification

    init(
        availableVersion: String,
        source: UpdateSource,
        releaseNotes: String?,
        actionURL: URL?,
        homebrewToken: String?,
        sourcePrereleaseChannel: PrereleaseChannel?,
        requiresHomebrewAdoption: Bool,
        requiresInAppInstallation: Bool = false,
        verification: ReleaseVerification? = nil,
        availableBuildVersion: String? = nil,
        usesBuildVersionOnly: Bool = false
    ) {
        self.availableVersion = availableVersion
        self.availableBuildVersion = availableBuildVersion
        self.usesBuildVersionOnly = usesBuildVersionOnly
        self.source = source
        self.releaseNotes = releaseNotes
        self.actionURL = actionURL
        self.homebrewToken = homebrewToken
        self.sourcePrereleaseChannel = sourcePrereleaseChannel
        self.requiresHomebrewAdoption = requiresHomebrewAdoption
        self.requiresInAppInstallation = requiresInAppInstallation
        self.verification = verification ?? Self.defaultVerification(for: source)
    }

    private static func defaultVerification(for source: UpdateSource) -> ReleaseVerification {
        switch source {
        case .appStore: .platformManaged
        case .homebrew: .packageManager
        case .developer: .publisherFeed
        case .sparkle: .publisherFeed
        case .github: .repositoryMatch
        }
    }

    var availablePrereleaseChannel: PrereleaseChannel? {
        sourcePrereleaseChannel ?? VersionComparator.prereleaseChannel(for: availableVersion)
    }

    var actionTitle: String {
        if requiresHomebrewAdoption { return "Update & Adopt" }
        if requiresInAppInstallation { return "Open App" }
        return switch source {
        case .homebrew: "Update"
        case .appStore: "Open App Store"
        case .developer: "Open App"
        case .sparkle: "Download"
        case .github: "View Release"
        }
    }
}

struct AvailableUpdate: Identifiable, Hashable, Sendable {
    var id: String { app.id }
    let app: InstalledApp
    let candidates: [UpdateCandidate]

    var primaryCandidate: UpdateCandidate { candidates[0] }
    var availableVersion: String { primaryCandidate.availableVersion }
    var source: UpdateSource { primaryCandidate.source }
    var releaseNotes: String? { primaryCandidate.releaseNotes }
    var actionURL: URL? { primaryCandidate.actionURL }
    var homebrewToken: String? { app.isUpkeep ? nil : primaryCandidate.homebrewToken }
    var sourcePrereleaseChannel: PrereleaseChannel? { primaryCandidate.sourcePrereleaseChannel }

    init(
        app: InstalledApp,
        availableVersion: String,
        source: UpdateSource,
        releaseNotes: String?,
        actionURL: URL?,
        homebrewToken: String?,
        sourcePrereleaseChannel: PrereleaseChannel? = nil,
        requiresHomebrewAdoption: Bool = false,
        requiresInAppInstallation: Bool = false,
        verification: ReleaseVerification? = nil,
        availableBuildVersion: String? = nil,
        usesBuildVersionOnly: Bool = false
    ) {
        self.app = app
        self.candidates = [UpdateCandidate(
            availableVersion: availableVersion,
            source: source,
            releaseNotes: releaseNotes,
            actionURL: actionURL,
            homebrewToken: homebrewToken,
            sourcePrereleaseChannel: sourcePrereleaseChannel,
            requiresHomebrewAdoption: requiresHomebrewAdoption,
            requiresInAppInstallation: requiresInAppInstallation,
            verification: verification,
            availableBuildVersion: availableBuildVersion,
            usesBuildVersionOnly: usesBuildVersionOnly
        )]
    }

    init(app: InstalledApp, candidates: [UpdateCandidate]) {
        precondition(!candidates.isEmpty, "An available update requires at least one source candidate.")
        self.app = app
        self.candidates = Self.preferredCandidates(candidates)
    }

    static func merging(_ updates: [AvailableUpdate]) -> AvailableUpdate? {
        guard let app = updates.first?.app else { return nil }
        return AvailableUpdate(app: app, candidates: updates.flatMap(\.candidates))
    }

    func selecting(_ candidate: UpdateCandidate) -> AvailableUpdate {
        AvailableUpdate(
            app: app,
            availableVersion: candidate.availableVersion,
            source: candidate.source,
            releaseNotes: candidate.releaseNotes,
            actionURL: candidate.actionURL,
            homebrewToken: candidate.homebrewToken,
            sourcePrereleaseChannel: candidate.sourcePrereleaseChannel,
            requiresHomebrewAdoption: candidate.requiresHomebrewAdoption,
            requiresInAppInstallation: candidate.requiresInAppInstallation,
            verification: candidate.verification,
            availableBuildVersion: candidate.availableBuildVersion,
            usesBuildVersionOnly: candidate.usesBuildVersionOnly
        )
    }

    private static func preferredCandidates(_ candidates: [UpdateCandidate]) -> [UpdateCandidate] {
        let bestBySource = Dictionary(grouping: candidates, by: \.source).compactMap { _, values in
            values.sorted { left, right in
                if left.requiresHomebrewAdoption != right.requiresHomebrewAdoption {
                    return !left.requiresHomebrewAdoption
                }
                let order = VersionComparator.compare(left.availableVersion, right.availableVersion)
                if order != .orderedSame { return order == .orderedDescending }
                return VersionComparator.isNewer(left.availableBuildVersion ?? "", than: right.availableBuildVersion ?? "")
            }.first
        }
        return bestBySource.sorted { left, right in
            let leftRank = sourceRank(left)
            let rightRank = sourceRank(right)
            if leftRank != rightRank { return leftRank < rightRank }
            return left.source.rawValue < right.source.rawValue
        }
    }

    private static func sourceRank(_ candidate: UpdateCandidate) -> Int {
        switch candidate.source {
        case .appStore: 0
        case .homebrew: candidate.requiresHomebrewAdoption ? 5 : 1
        case .developer: 2
        case .sparkle: 3
        case .github: 4
        }
    }

    var availablePrereleaseChannel: PrereleaseChannel? {
        sourcePrereleaseChannel ?? VersionComparator.prereleaseChannel(for: availableVersion)
    }
    var prereleaseChannel: PrereleaseChannel? {
        availablePrereleaseChannel ?? app.prereleaseChannel
    }
    var prereleaseIsInstalled: Bool { availablePrereleaseChannel == nil && app.prereleaseChannel != nil }
    var requiresInAppInstallation: Bool { !app.isUpkeep && primaryCandidate.requiresInAppInstallation }
    var directInstallURL: URL? {
        guard !app.isUpkeep, !requiresInAppInstallation,
              source == .sparkle || source == .github,
              let actionURL,
              actionURL.scheme?.lowercased() == "https",
              ["zip", "dmg"].contains(actionURL.pathExtension.lowercased())
        else { return nil }
        return actionURL
    }
    var canInstallDirectly: Bool { directInstallURL != nil }

    var actionTitle: String {
        if app.isUpkeep { return "Update…" }
        if canInstallDirectly { return "Update" }
        return primaryCandidate.actionTitle
    }

    var actionDescription: String {
        if app.isUpkeep { return "Download and verify the signed release, then quit, replace, and reopen Upkeep" }
        if canInstallDirectly { return "Download, verify, and install with Upkeep" }
        if requiresInAppInstallation { return "Open the app to run its built-in updater" }
        return switch source {
        case .homebrew: "Install with Homebrew"
        case .appStore: "Open in the App Store"
        case .developer: "Open the app's built-in updater"
        case .sparkle: "Open the developer download"
        case .github: "Open the GitHub release"
        }
    }
}

enum BatchUpdateItem: Identifiable, Hashable, Sendable {
    case application(AvailableUpdate)
    case homebrew(HomebrewPackage)
    case developer(DeveloperPackage)
    case model(LocalLLMModel)

    var id: String {
        switch self {
        case let .application(update): "app|\(update.id)"
        case let .homebrew(package): "homebrew|\(package.id)"
        case let .developer(package): "developer|\(package.id)"
        case let .model(model): "model|\(model.id)"
        }
    }

    var name: String {
        switch self {
        case let .application(update): update.app.name
        case let .homebrew(package): package.displayName
        case let .developer(package): package.name
        case let .model(model): model.name
        }
    }

    var currentVersion: String {
        switch self {
        case let .application(update): update.app.installedVersion
        case let .homebrew(package): package.installedVersion
        case let .developer(package): package.currentVersion
        case let .model(model): model.installedRevision
        }
    }

    var availableVersion: String {
        switch self {
        case let .application(update): update.availableVersion
        case let .homebrew(package): package.currentVersion
        case let .developer(package): package.latestVersion
        case let .model(model): model.latestRevision
        }
    }

    var actionDescription: String {
        switch self {
        case let .application(update): update.actionDescription
        case let .homebrew(package): "Upgrade \(package.kind.rawValue.lowercased()) with Homebrew"
        case let .developer(package): "Install with \(package.manager.rawValue)"
        case let .model(model): "Pull with \(model.runtime.rawValue)"
        }
    }

    var opensExternalUpdater: Bool {
        if case let .application(update) = self {
            return update.homebrewToken == nil && !update.canInstallDirectly
        }
        return false
    }

    var mayRequireAdministratorPassword: Bool {
        switch self {
        case let .application(update): update.homebrewToken != nil
        case let .homebrew(package): package.kind == .cask
        case .developer, .model: false
        }
    }
}

struct BatchUpdateResult: Identifiable, Hashable, Sendable {
    enum Outcome: String, Hashable, Sendable {
        case updated = "Updated"
        case opened = "Action Required"
        case failed = "Failed"
        case notStarted = "Not Started"
    }

    let item: BatchUpdateItem
    let outcome: Outcome
    let detail: String
    var warning: String? = nil
    var id: String { item.id }
}

struct BatchUpdateSummary: Hashable, Sendable {
    let results: [BatchUpdateResult]

    var updatedCount: Int { results.count { $0.outcome == .updated } }
    var openedCount: Int { results.count { $0.outcome == .opened } }
    var failedCount: Int { results.count { $0.outcome == .failed } }
    var notStartedCount: Int { results.count { $0.outcome == .notStarted } }
}

struct BatchUpdateProgress: Equatable, Sendable {
    let completed: Int
    let total: Int
    let itemName: String
}

struct ScanReport: Sendable {
    let apps: [InstalledApp]
    let updates: [AvailableUpdate]
    let checkedAt: Date
    let warnings: [ScanWarning]
    let failedAppSources: [String: Set<UpdateSource>]
    let homebrewInventoryStatus: ScanStatus
    let homebrewCatalogStatus: ScanStatus
    let macOSUpdatesStatus: ScanStatus
    let macOSInstallersStatus: ScanStatus
    let failedDeveloperManagers: Set<DeveloperPackageManager>
    let failedDeveloperExecutablePaths: Set<String>
    let localModelsStatus: ScanStatus
    let failedLocalModelIDs: Set<String>
    let failedLocalModelRuntimes: Set<LocalModelRuntime>
    let homebrewPackages: [HomebrewPackage]
    let adoptableApps: [AdoptableApp]
    let macOSUpdates: [MacOSUpdate]
    let developerPackages: [DeveloperPackage]
    let installedDeveloperManagers: [DeveloperPackageManager]
    let localModels: [LocalLLMModel]

    static let empty = ScanReport(
        apps: [], updates: [], checkedAt: Date(), warnings: [], failedAppSources: [:],
        homebrewInventoryStatus: .disabled, homebrewCatalogStatus: .disabled,
        macOSUpdatesStatus: .disabled, macOSInstallersStatus: .disabled,
        failedDeveloperManagers: [], failedDeveloperExecutablePaths: [],
        localModelsStatus: .disabled, failedLocalModelIDs: [], failedLocalModelRuntimes: [],
        homebrewPackages: [], adoptableApps: [], macOSUpdates: [], developerPackages: [],
        installedDeveloperManagers: [], localModels: []
    )
}

enum ScanStatus: Equatable, Sendable {
    case disabled
    case succeeded
    case failed
}

enum ScanWarningSource: String, Codable, Sendable {
    case appStore = "App Store"
    case developer = "Developer"
    case sparkle = "Sparkle"
    case github = "GitHub"
    case homebrew = "Homebrew"
    case macOS = "macOS"
    case developerPackages = "Developer Packages"
    case localModels = "AI Models"
}

struct ScanWarning: Identifiable, Hashable, Codable, Sendable {
    let source: ScanWarningSource
    let itemNames: [String]
    let affectedItemCount: Int
    let message: String
    let itemNamesByID: [String: String]?

    init(source: ScanWarningSource, itemNames: [String] = [], affectedItemCount: Int? = nil,
         itemNamesByID: [String: String]? = nil, message: String) {
        self.source = source
        let uniqueNames = Array(Set(itemNames)).sorted()
        self.itemNames = uniqueNames.prefix(20).map { $0 }
        self.itemNamesByID = itemNamesByID
        self.affectedItemCount = max(affectedItemCount ?? uniqueNames.count, uniqueNames.count, itemNamesByID?.count ?? 0)
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        self.message = trimmed.count > 600 ? String(trimmed.prefix(600)) + "…" : trimmed
    }

    func removingItems(ids: Set<String>) -> ScanWarning? {
        guard let ownership = itemNamesByID else { return self }
        let remaining = ownership.filter { !ids.contains($0.key) }
        guard !remaining.isEmpty else { return nil }
        return ScanWarning(source: source, itemNames: Array(remaining.values),
                           affectedItemCount: remaining.count, itemNamesByID: remaining, message: message)
    }

    var id: String { "\(source.rawValue)|\(message)" }
    var title: String {
        affectedItemCount == 0 ? source.rawValue : "\(source.rawValue) · \(affectedItemCount) item\(affectedItemCount == 1 ? "" : "s")"
    }
    var detail: String {
        guard affectedItemCount > 0, !itemNames.isEmpty else { return message }
        let shown = itemNames.prefix(3).joined(separator: ", ")
        let remainder = affectedItemCount - min(itemNames.count, 3)
        return message + " Affected: " + shown + (remainder > 0 ? " and \(remainder) more." : ".")
    }
}

enum SidebarDestination: String, CaseIterable, Identifiable {
    case updates = "Updates"
    case allApps = "Applications"
    case adoptable = "Adoptable"
    case appStore = "App Store"
    case testFlight = "TestFlight"
    case setapp = "Setapp"
    case microsoftAutoUpdate = "Microsoft AutoUpdate"
    case steam = "Steam"
    case otherUpdaters = "Other Updaters"
    case sparkle = "Sparkle"
    case homebrewApps = "Homebrew Apps"
    case github = "GitHub"
    case noSource = "No Source"
    case homebrewPackages = "Homebrew"
    case macOSUpdates = "macOS"
    case history = "History"
    case cveChecker = "CVE Checker"
    case developerPackages = "Developer"
    case localModels = "AI Models"

    var id: Self { self }

    /// Bundled third-party logo for source pages that represent a tool.
    var logoName: String? {
        switch self {
        case .sparkle: "sparkle"
        case .github: "github"
        case .homebrewApps: "homebrew"
        default: nil
        }
    }

    /// Apps whose own icon represents this source. The icon is read from the
    /// installed app at runtime, never bundled, so it is not redistributed.
    var installedAppPaths: [String] {
        switch self {
        case .appStore: ["/System/Applications/App Store.app"]
        case .testFlight: ["/Applications/TestFlight.app"]
        case .setapp: ["/Applications/Setapp.app", NSHomeDirectory() + "/Applications/Setapp.app"]
        case .microsoftAutoUpdate: ["/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app"]
        case .steam: ["/Applications/Steam.app", NSHomeDirectory() + "/Applications/Steam.app"]
        default: []
        }
    }

    var systemImage: String {
        switch self {
        case .updates: "arrow.down.circle"
        case .allApps: "square.grid.2x2"
        case .adoptable: "arrow.down.app"
        case .appStore: "storefront"
        case .testFlight: "paperplane"
        case .setapp: "square.stack.3d.up"
        case .microsoftAutoUpdate: "arrow.triangle.2.circlepath"
        case .steam: "gamecontroller"
        case .otherUpdaters: "arrow.triangle.2.circlepath.circle"
        case .sparkle: "wand.and.stars"
        case .homebrewApps: "shippingbox"
        case .github: "chevron.left.forwardslash.chevron.right"
        case .noSource: "questionmark.app"
        case .homebrewPackages: "terminal"
        case .macOSUpdates: "apple.logo"
        case .cveChecker: "shield.lefthalf.filled"
        case .history: "clock.arrow.circlepath"
        case .developerPackages: "curlybraces.square"
        case .localModels: "brain.head.profile"
        }
    }

    var headerSystemImage: String {
        switch self {
        case .updates: "arrow.down.circle.fill"
        case .allApps: "square.grid.2x2.fill"
        case .adoptable: "arrow.down.app.fill"
        case .appStore: "storefront.fill"
        case .testFlight: "paperplane.fill"
        case .setapp: "square.stack.3d.up.fill"
        case .microsoftAutoUpdate: "arrow.triangle.2.circlepath"
        case .steam: "gamecontroller.fill"
        case .otherUpdaters: "arrow.triangle.2.circlepath.circle.fill"
        case .sparkle: "wand.and.stars.inverse"
        case .homebrewApps: "shippingbox.fill"
        case .github: "chevron.left.forwardslash.chevron.right"
        case .noSource: "questionmark.app.fill"
        case .homebrewPackages: "terminal.fill"
        case .macOSUpdates: "apple.logo"
        case .cveChecker: "shield.lefthalf.filled"
        case .history: "clock.arrow.circlepath"
        case .developerPackages: "curlybraces.square.fill"
        case .localModels: "brain.head.profile.fill"
        }
    }
}

enum LocalModelRuntime: String, Codable, CaseIterable, Identifiable, Sendable {
    case ollama = "Ollama"
    case lmStudio = "LM Studio"
    var id: Self { self }
    var systemImage: String {
        switch self {
        case .ollama: "circle.hexagongrid.fill"
        case .lmStudio: "brain.head.profile.fill"
        }
    }
    var assetName: String {
        switch self {
        case .ollama: "ollama"
        case .lmStudio: "lmstudio"
        }
    }
}

struct LocalLLMModel: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let variant: String?
    let runtime: LocalModelRuntime
    let installedRevision: String
    let latestRevision: String
    let sizeBytes: Int64?
    let modifiedAt: Date?
    let homepage: URL?
    let executablePath: String?
    let updateReference: String
    let isOutdated: Bool
    var prereleaseChannel: PrereleaseChannel? {
        ModelReleaseChannel.detect(in: variant)
    }
}

enum HomebrewPackageKind: String, Codable, Sendable {
    case formula = "Formula"
    case cask = "Cask"
}

struct HomebrewPackage: Identifiable, Hashable, Sendable {
    var id: String { "\(kind.rawValue):\(token)" }
    let token: String
    let displayName: String
    let description: String?
    let homepage: URL?
    let license: String?
    let installedVersion: String
    let currentVersion: String
    let kind: HomebrewPackageKind
    let isOutdated: Bool
    let isDependency: Bool
    let dependencies: [String]
    var versionScheme: Int = 0
    var tap: String? = nil
    var exclusionVersion: String {
        versionScheme == 0 ? currentVersion : "scheme:\(versionScheme)|\(currentVersion)"
    }
    var isRevisionUpdate: Bool {
        kind == .formula && installedVersion.split(separator: "_").first == currentVersion.split(separator: "_").first
            && installedVersion != currentVersion
    }
    var availablePrereleaseChannel: PrereleaseChannel? {
        VersionComparator.prereleaseChannel(for: currentVersion)
    }
    var prereleaseChannel: PrereleaseChannel? {
        availablePrereleaseChannel
            ?? VersionComparator.prereleaseChannel(for: installedVersion)
    }
    var prereleaseIsInstalled: Bool {
        availablePrereleaseChannel == nil && VersionComparator.isPrerelease(installedVersion)
    }
}

struct AdoptableApp: Identifiable, Hashable, Sendable {
    var id: String { app.id }
    let app: InstalledApp
    let caskToken: String
    let caskVersion: String
    var prereleaseChannel: PrereleaseChannel? { VersionComparator.prereleaseChannel(for: caskVersion) }
}

struct MacOSUpdate: Identifiable, Hashable, Sendable {
    var id: String { label }
    let label: String
    let title: String
    let version: String
    let size: String?
    let requiresRestart: Bool
    let isBeta: Bool
    let isFullInstaller: Bool
    var prereleaseChannel: PrereleaseChannel? {
        VersionComparator.prereleaseChannel(for: "\(title) \(label) \(version)")
            ?? (isBeta ? .beta : nil)
    }
}

enum UpdateRecordKind: String, Codable, Sendable {
    case app = "App"
    case homebrew = "Homebrew"
    case macOS = "macOS"
    case developer = "Developer"
    case model = "AI Model"

    var systemImage: String {
        switch self {
        case .app: "app"
        case .homebrew: "shippingbox"
        case .macOS: "apple.logo"
        case .developer: "chevron.left.forwardslash.chevron.right"
        case .model: "brain.head.profile"
        }
    }

}

struct UpdateRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let date: Date
    let name: String
    let fromVersion: String
    let toVersion: String
    let kind: UpdateRecordKind
    let originalAppPath: String?
    let backupPath: String?
    let recoveryNote: String?
    var fromBuildVersion: String? = nil
    var toBuildVersion: String? = nil

    var fromVersionLabel: String { versionLabel(fromVersion, build: fromBuildVersion) }
    var toVersionLabel: String { versionLabel(toVersion, build: toBuildVersion) }

    private func versionLabel(_ version: String, build: String?) -> String {
        guard let build, !build.isEmpty else { return version }
        return "\(version) (build \(build))"
    }

    var canRevertDirectly: Bool {
        originalAppPath != nil && backupPath.map(FileManager.default.fileExists(atPath:)) == true
    }
}

enum DeveloperPackageManager: String, Codable, CaseIterable, Identifiable, Sendable {
    case node = "Node.js"
    case bun = "Bun"
    case deno = "Deno"
    case npm = "npm"
    case pnpm = "pnpm"
    case yarn = "Yarn"
    case vsCode = "VS Code Extensions"
    case uv = "uv"
    case pipx = "pipx"
    case python = "Python"
    case rubyGems = "RubyGems"
    case rustup = "Rustup"
    case cargo = "Cargo"
    case githubCLI = "GitHub CLI"
    case go = "Go Tools"
    case composer = "Composer"
    case dotnet = ".NET Tools"
    case macPorts = "MacPorts"
    case nix = "Nix"
    case mise = "mise"
    case asdf = "asdf"
    case volta = "Volta"
    case fnm = "fnm"
    var id: Self { self }
    var belongsToJavaScriptEcosystem: Bool {
        switch self {
        case .node, .bun, .deno, .npm, .pnpm, .yarn, .volta, .fnm: true
        case .vsCode, .uv, .pipx, .python, .rubyGems, .rustup, .cargo,
             .githubCLI, .go, .composer, .dotnet, .macPorts, .nix, .mise, .asdf: false
        }
    }
    var assetName: String {
        switch self {
        case .node: "node"
        case .bun: "bun"
        case .deno: "deno"
        case .npm: "npm"
        case .pnpm: "pnpm"
        case .yarn: "yarn"
        case .vsCode: "vscode"
        case .uv: "uv"
        case .pipx: "pipx"
        case .python: "python"
        case .rubyGems: "rubygems"
        case .rustup: "rustup"
        case .cargo: "cargo"
        case .githubCLI: "github"
        case .go: "go"
        case .composer: "composer"
        case .dotnet: "dotnet"
        case .macPorts: "macports"
        case .nix: "nix"
        case .mise: "mise"
        case .asdf: "asdf"
        case .volta: "volta"
        case .fnm: "fnm"
        }
    }
    var packageLabel: String {
        switch self {
        case .node: "JavaScript runtime"
        case .bun: "JavaScript runtime and toolkit"
        case .deno: "JavaScript runtime"
        case .npm, .pnpm: "JavaScript package"
        case .yarn: "JavaScript package manager"
        case .vsCode: "Editor extension"
        case .uv: "uv-managed Python tool"
        case .pipx: "pipx-managed Python tool"
        case .python: "Python package"
        case .rubyGems: "Ruby gem"
        case .rustup: "Rust toolchain"
        case .cargo: "Rust crate"
        case .githubCLI: "GitHub CLI extension"
        case .go: "Go command"
        case .composer: "Composer package"
        case .dotnet: ".NET global tool"
        case .macPorts: "MacPorts port"
        case .nix: "Nix profile package"
        case .mise, .asdf: "Managed developer tool"
        case .volta, .fnm: "Managed JavaScript runtime"
        }
    }
    var homepage: URL? {
        switch self {
        case .node: URL(string: "https://nodejs.org")
        case .bun: URL(string: "https://bun.com")
        case .deno: URL(string: "https://deno.com")
        case .npm: URL(string: "https://www.npmjs.com")
        case .pnpm: URL(string: "https://pnpm.io")
        case .yarn: URL(string: "https://yarnpkg.com")
        case .vsCode: URL(string: "https://marketplace.visualstudio.com/vscode")
        case .uv: URL(string: "https://docs.astral.sh/uv")
        case .pipx: URL(string: "https://pipx.pypa.io")
        case .python: URL(string: "https://pypi.org")
        case .rubyGems: URL(string: "https://rubygems.org")
        case .rustup: URL(string: "https://rustup.rs")
        case .cargo: URL(string: "https://crates.io")
        case .githubCLI: URL(string: "https://cli.github.com/manual/gh_extension")
        case .go: URL(string: "https://pkg.go.dev")
        case .composer: URL(string: "https://packagist.org")
        case .dotnet: URL(string: "https://www.nuget.org")
        case .macPorts: URL(string: "https://www.macports.org")
        case .nix: URL(string: "https://nixos.org")
        case .mise: URL(string: "https://mise.jdx.dev")
        case .asdf: URL(string: "https://asdf-vm.com")
        case .volta: URL(string: "https://volta.sh")
        case .fnm: URL(string: "https://github.com/Schniz/fnm")
        }
    }
}

struct DeveloperPackage: Identifiable, Hashable, Sendable {
    var id: String { "\(manager.rawValue):\(name):\(installationContext ?? executablePath)" }
    let name: String
    let currentVersion: String
    let latestVersion: String
    let manager: DeveloperPackageManager
    let executablePath: String
    let registryIdentifier: String?
    let installationContext: String?
    let canUpdateAutomatically: Bool

    init(
        name: String,
        currentVersion: String,
        latestVersion: String,
        manager: DeveloperPackageManager,
        executablePath: String,
        registryIdentifier: String? = nil,
        installationContext: String? = nil,
        canUpdateAutomatically: Bool = true
    ) {
        self.name = name
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.manager = manager
        self.executablePath = executablePath
        self.registryIdentifier = registryIdentifier
        self.installationContext = installationContext
        self.canUpdateAutomatically = canUpdateAutomatically
    }
    var isOutdated: Bool { VersionComparator.isNewer(latestVersion, than: currentVersion) }
    var availablePrereleaseChannel: PrereleaseChannel? {
        VersionComparator.prereleaseChannel(for: latestVersion)
    }
    var prereleaseChannel: PrereleaseChannel? {
        availablePrereleaseChannel
            ?? VersionComparator.prereleaseChannel(for: currentVersion)
    }
    var prereleaseIsInstalled: Bool {
        availablePrereleaseChannel == nil && VersionComparator.isPrerelease(currentVersion)
    }

    func replacingLatestVersion(with version: String) -> DeveloperPackage {
        DeveloperPackage(
            name: name,
            currentVersion: currentVersion,
            latestVersion: version,
            manager: manager,
            executablePath: executablePath,
            registryIdentifier: registryIdentifier,
            installationContext: installationContext,
            canUpdateAutomatically: canUpdateAutomatically
        )
    }
}
