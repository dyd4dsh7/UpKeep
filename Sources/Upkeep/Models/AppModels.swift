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
    var prereleaseChannel: PrereleaseChannel? { VersionComparator.prereleaseChannel(for: installedVersion) }

    init(
        name: String,
        bundleIdentifier: String?,
        installedVersion: String,
        buildVersion: String?,
        url: URL,
        sparkleFeedURL: URL?,
        githubRepository: String?,
        hasAppStoreReceipt: Bool
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
    }
}

enum UpdateSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case appStore = "App Store"
    case sparkle = "Sparkle"
    case homebrew = "Homebrew"
    case github = "GitHub"

    var id: Self { self }
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
    let availableVersion: String
    let source: UpdateSource
    let releaseNotes: String?
    let actionURL: URL?
    let homebrewToken: String?
    let sourcePrereleaseChannel: PrereleaseChannel?
    let requiresHomebrewAdoption: Bool

    var availablePrereleaseChannel: PrereleaseChannel? {
        sourcePrereleaseChannel ?? VersionComparator.prereleaseChannel(for: availableVersion)
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
    var homebrewToken: String? { primaryCandidate.homebrewToken }
    var sourcePrereleaseChannel: PrereleaseChannel? { primaryCandidate.sourcePrereleaseChannel }

    init(
        app: InstalledApp,
        availableVersion: String,
        source: UpdateSource,
        releaseNotes: String?,
        actionURL: URL?,
        homebrewToken: String?,
        sourcePrereleaseChannel: PrereleaseChannel? = nil,
        requiresHomebrewAdoption: Bool = false
    ) {
        self.app = app
        self.candidates = [UpdateCandidate(
            availableVersion: availableVersion,
            source: source,
            releaseNotes: releaseNotes,
            actionURL: actionURL,
            homebrewToken: homebrewToken,
            sourcePrereleaseChannel: sourcePrereleaseChannel,
            requiresHomebrewAdoption: requiresHomebrewAdoption
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
            requiresHomebrewAdoption: candidate.requiresHomebrewAdoption
        )
    }

    private static func preferredCandidates(_ candidates: [UpdateCandidate]) -> [UpdateCandidate] {
        let bestBySource = Dictionary(grouping: candidates, by: \.source).compactMap { _, values in
            values.sorted { left, right in
                if left.requiresHomebrewAdoption != right.requiresHomebrewAdoption {
                    return !left.requiresHomebrewAdoption
                }
                return VersionComparator.compare(left.availableVersion, right.availableVersion) == .orderedDescending
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
        case .homebrew: candidate.requiresHomebrewAdoption ? 4 : 1
        case .sparkle: 2
        case .github: 3
        }
    }

    var availablePrereleaseChannel: PrereleaseChannel? {
        sourcePrereleaseChannel ?? VersionComparator.prereleaseChannel(for: availableVersion)
    }
    var prereleaseChannel: PrereleaseChannel? {
        availablePrereleaseChannel ?? app.prereleaseChannel
    }
    var prereleaseIsInstalled: Bool { availablePrereleaseChannel == nil && app.prereleaseChannel != nil }
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
    let localModelsStatus: ScanStatus
    let failedLocalModelIDs: Set<String>
    let failedLocalModelRuntimes: Set<LocalModelRuntime>
    let homebrewPackages: [HomebrewPackage]
    let adoptableApps: [AdoptableApp]
    let macOSUpdates: [MacOSUpdate]
    let developerPackages: [DeveloperPackage]
    let installedDeveloperManagers: [DeveloperPackageManager]
    let localModels: [LocalLLMModel]
}

enum ScanStatus: Equatable, Sendable {
    case disabled
    case succeeded
    case failed
}

enum ScanWarningSource: String, Codable, Sendable {
    case appStore = "App Store"
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

    init(source: ScanWarningSource, itemNames: [String] = [], affectedItemCount: Int? = nil, message: String) {
        self.source = source
        let uniqueNames = Array(Set(itemNames)).sorted()
        self.itemNames = uniqueNames.prefix(20).map { $0 }
        self.affectedItemCount = max(affectedItemCount ?? uniqueNames.count, uniqueNames.count)
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        self.message = trimmed.count > 600 ? String(trimmed.prefix(600)) + "…" : trimmed
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
    case allApps = "All Apps"
    case adoptable = "Adoptable"
    case appStore = "App Store"
    case sparkle = "Sparkle"
    case homebrewApps = "Homebrew Apps"
    case github = "GitHub"
    case noSource = "No Source"
    case homebrewPackages = "Homebrew"
    case macOSUpdates = "macOS"
    case history = "History"
    case developerPackages = "Developer"
    case localModels = "AI Models"

    var id: Self { self }
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
        variant.flatMap { VersionComparator.prereleaseChannel(for: $0) }
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

    var canRevertDirectly: Bool { originalAppPath != nil && backupPath != nil }
}

enum DeveloperPackageManager: String, Codable, CaseIterable, Identifiable, Sendable {
    case npm = "npm"
    case pnpm = "pnpm"
    case python = "Python"
    case rubyGems = "RubyGems"
    case cargo = "Cargo"
    var id: Self { self }
    var assetName: String {
        switch self {
        case .npm: "npm"
        case .pnpm: "pnpm"
        case .python: "python"
        case .rubyGems: "rubygems"
        case .cargo: "cargo"
        }
    }
    var packageLabel: String {
        switch self {
        case .npm, .pnpm: "JavaScript package"
        case .python: "Python package"
        case .rubyGems: "Ruby gem"
        case .cargo: "Rust crate"
        }
    }
    var homepage: URL? {
        switch self {
        case .npm: URL(string: "https://www.npmjs.com")
        case .pnpm: URL(string: "https://pnpm.io")
        case .python: URL(string: "https://pypi.org")
        case .rubyGems: URL(string: "https://rubygems.org")
        case .cargo: URL(string: "https://crates.io")
        }
    }
}

struct DeveloperPackage: Identifiable, Hashable, Sendable {
    var id: String { "\(manager.rawValue):\(name)" }
    let name: String
    let currentVersion: String
    let latestVersion: String
    let manager: DeveloperPackageManager
    let executablePath: String
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
}
