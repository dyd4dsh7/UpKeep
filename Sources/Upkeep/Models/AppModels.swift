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

enum UpdateSource: String, Codable, Sendable {
    case appStore = "App Store"
    case sparkle = "Sparkle"
    case homebrew = "Homebrew"
    case github = "GitHub"
}

struct AvailableUpdate: Identifiable, Hashable, Sendable {
    var id: String { app.id }
    let app: InstalledApp
    let availableVersion: String
    let source: UpdateSource
    let releaseNotes: String?
    let actionURL: URL?
    let homebrewToken: String?
}

struct ScanReport: Sendable {
    let apps: [InstalledApp]
    let updates: [AvailableUpdate]
    let checkedAt: Date
    let warnings: [String]
    let homebrewPackages: [HomebrewPackage]
    let adoptableApps: [AdoptableApp]
    let macOSUpdates: [MacOSUpdate]
    let developerPackages: [DeveloperPackage]
    let installedDeveloperManagers: [DeveloperPackageManager]
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
    case changelog = "Changelog"

    var id: Self { self }
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
}

struct AdoptableApp: Identifiable, Hashable, Sendable {
    var id: String { app.id }
    let app: InstalledApp
    let caskToken: String
    let caskVersion: String
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
}

enum UpdateRecordKind: String, Codable, Sendable {
    case app = "App"
    case homebrew = "Homebrew"
    case macOS = "macOS"
    case developer = "Developer"
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
}
