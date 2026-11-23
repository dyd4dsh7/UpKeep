import Foundation

/// `upkeep://` links for scripts, Shortcuts' "Open URL" action and other apps.
/// Links only open views or start a check; installing always needs a click in
/// Upkeep, so a web page cannot change the Mac through a link.
///
///     upkeep://updates            upkeep://check
///     upkeep://applications       upkeep://review
///     upkeep://homebrew           upkeep://search?q=firefox
///     upkeep://developer, models, macos, history, cve, adoptable
enum UpkeepLink: Equatable {
    case show(SidebarDestination)
    case check
    case review
    case search(String)

    static let scheme = "upkeep"

    static let destinations: [String: SidebarDestination] = [
        "updates": .updates,
        "applications": .allApps, "apps": .allApps,
        "adoptable": .adoptable,
        "homebrew": .homebrewPackages,
        "developer": .developerPackages, "packages": .developerPackages,
        "models": .localModels, "ai-models": .localModels,
        "macos": .macOSUpdates,
        "history": .history,
        "cve": .cveChecker, "security": .cveChecker
    ]

    init?(_ url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        // Both upkeep://check and upkeep:check name the same action.
        let name = (url.host() ?? url.path(percentEncoded: false))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        switch name {
        case "", "open": self = .show(.updates)
        case "check": self = .check
        case "review": self = .review
        case "search":
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "q" || $0.name == "query" }?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !query.isEmpty else { return nil }
            self = .search(String(query.prefix(200)))
        default:
            guard let destination = Self.destinations[name] else { return nil }
            self = .show(destination)
        }
    }
}

@MainActor
extension UpkeepStore {
    func open(_ link: UpkeepLink) {
        switch link {
        case let .show(destination):
            navigation.searchText = ""
            navigation.selection = destination
            openMainWindow()
        case .check:
            showUpdates()
            Task { await scan() }
        case .review:
            showBatchReview()
        case let .search(query):
            openMainWindow()
            navigation.searchText = query
        }
    }
}
