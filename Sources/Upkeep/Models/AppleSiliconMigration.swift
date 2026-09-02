import Foundation

enum AppleSiliconMigrationSource: Equatable {
    case updateManager
    case homebrew(URL)
    case releases(URL)
    case builtInUpdater
    case developerWebsite

    static func resolve(app: InstalledApp, homebrewToken: String?) -> Self {
        if app.updateManagement != .direct { return .updateManager }
        if let token = homebrewToken,
           let url = URL(string: "https://formulae.brew.sh/cask/\(token)") {
            return .homebrew(url)
        }
        if let repository = app.githubRepository,
           let url = URL(string: "https://github.com/\(repository)/releases") {
            return .releases(url)
        }
        if app.hasBuiltInUpdater { return .builtInUpdater }
        return .developerWebsite
    }
}

enum AppleSiliconVerification: Equatable {
    case native
    case stillIntel
    case unknown
    case missing
    case differentApp

    static func result(original: InstalledApp, installed: InstalledApp?) -> Self {
        guard let installed else { return .missing }
        guard let identifier = original.bundleIdentifier, !identifier.isEmpty else { return .unknown }
        guard installed.bundleIdentifier == original.bundleIdentifier,
              installed.url.standardizedFileURL == original.url.standardizedFileURL
        else { return .differentApp }
        if installed.architecture.supportsAppleSilicon { return .native }
        return installed.architecture == .intel ? .stillIntel : .unknown
    }

    var message: String {
        switch self {
        case .native: "Apple Silicon support verified. The installed app’s main executable includes native ARM code. Quit and reopen the app to use the replacement."
        case .stillIntel: "The installed app is still Intel-only. Install the Apple Silicon or Universal edition, then check again. If the developer does not offer one, this app cannot be migrated yet."
        case .unknown: "Upkeep could not read the installed app’s architecture. Apple Silicon support has not been verified."
        case .missing: "The app was not found at its original location. Finish installing it there, then check again."
        case .differentApp: "The app at this location has a different identity. Upkeep cannot verify this migration."
        }
    }
}
