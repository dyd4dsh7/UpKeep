import Foundation

enum SearchScope: String, CaseIterable, Identifiable {
    case all = "All Sources"
    case apps = "Applications"
    case adoptable = "Homebrew Adoption"
    case homebrew = "Homebrew Packages"
    case developer = "Developer Packages"
    case models = "AI Models"
    case macOS = "macOS"
    case history = "Update History"

    var id: Self { self }
}

enum SearchResultSelection: Hashable {
    case application(String)
    case adoptable(String)
    case homebrew(String)
    case developer(String)
    case model(String)
    case macOS(String)
    case history(UUID)
}

enum InventoryReveal: Equatable {
    case macOS(String)
    case history(UUID)

    var destination: SidebarDestination {
        switch self {
        case .macOS: .macOSUpdates
        case .history: .history
        }
    }
}

struct GlobalSearchResults {
    let apps: [InstalledApp]
    let adoptableApps: [AdoptableApp]
    let homebrewPackages: [HomebrewPackage]
    let developerPackages: [DeveloperPackage]
    let models: [LocalLLMModel]
    let macOSUpdates: [MacOSUpdate]
    let history: [UpdateRecord]

    var count: Int {
        apps.count + adoptableApps.count + homebrewPackages.count + developerPackages.count
            + models.count + macOSUpdates.count + history.count
    }

    var isEmpty: Bool { count == 0 }

    func inScope(_ scope: SearchScope) -> GlobalSearchResults {
        guard scope != .all else { return self }
        return GlobalSearchResults(
            apps: scope == .apps ? apps : [],
            adoptableApps: scope == .adoptable ? adoptableApps : [],
            homebrewPackages: scope == .homebrew ? homebrewPackages : [],
            developerPackages: scope == .developer ? developerPackages : [],
            models: scope == .models ? models : [],
            macOSUpdates: scope == .macOS ? macOSUpdates : [],
            history: scope == .history ? history : []
        )
    }

    func contains(_ selection: SearchResultSelection) -> Bool {
        switch selection {
        case let .application(id): apps.contains { $0.id == id }
        case let .adoptable(id): adoptableApps.contains { $0.id == id }
        case let .homebrew(id): homebrewPackages.contains { $0.id == id }
        case let .developer(id): developerPackages.contains { $0.id == id }
        case let .model(id): models.contains { $0.id == id }
        case let .macOS(id): macOSUpdates.contains { $0.id == id }
        case let .history(id): history.contains { $0.id == id }
        }
    }

    var identity: String {
        [
            apps.map(\.id),
            adoptableApps.map(\.id),
            homebrewPackages.map(\.id),
            developerPackages.map(\.id),
            models.map(\.id),
            macOSUpdates.map(\.id),
            history.map { $0.id.uuidString }
        ].flatMap { $0 }.joined(separator: "|")
    }
}

/// A fresh search projection of the current inventory; does not retain cached results.
@MainActor
struct GlobalSearch {
    private let store: UpkeepStore
    private let query: String

    init(store: UpkeepStore) {
        self.store = store
        // One normalization per projection, rather than once per candidate field.
        query = store.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchingApps: [InstalledApp] {
        store.apps.filter { app in
            matches(app.name, app.bundleIdentifier, app.installedVersion)
                || matches(app.url.path, app.updateManagement.rawValue)
                // Source detection involves library lookups. Only do it if needed.
                || matches(store.sources(for: app).map(\.rawValue).joined(separator: " "))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var matchingAdoptableApps: [AdoptableApp] {
        store.adoptableApps.filter { matches($0.app.name, $0.caskToken, $0.caskVersion) }
            .sorted { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending }
    }

    private var matchingHomebrewPackages: [HomebrewPackage] {
        store.homebrewPackages.filter {
            matches($0.displayName, $0.token, $0.description, $0.kind.rawValue,
                    $0.installedVersion, $0.currentVersion)
                // Keep the joined string: queries can span dependency boundaries.
                || matches($0.dependencies.joined(separator: " "))
        }.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var matchingDeveloperPackages: [DeveloperPackage] {
        store.developerPackages.filter {
            matches($0.name, $0.manager.rawValue, $0.currentVersion, $0.latestVersion, $0.executablePath)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var matchingModels: [LocalLLMModel] {
        store.localModels.filter {
            matches($0.name, $0.variant, $0.runtime.rawValue, $0.installedRevision, $0.latestRevision)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var matchingMacOSUpdates: [MacOSUpdate] {
        store.macOSUpdates.filter { matches($0.title, $0.label, $0.version, $0.size) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var matchingHistory: [UpdateRecord] {
        store.updateHistory.filter {
            matches($0.name, $0.kind.rawValue, $0.fromVersion, $0.toVersion, $0.recoveryNote)
        }.sorted { $0.date > $1.date }
    }

    var results: GlobalSearchResults {
        GlobalSearchResults(
            apps: matchingApps,
            adoptableApps: matchingAdoptableApps,
            homebrewPackages: matchingHomebrewPackages,
            developerPackages: matchingDeveloperPackages,
            models: matchingModels,
            macOSUpdates: matchingMacOSUpdates,
            history: matchingHistory
        )
    }

    private func matches(_ values: String?...) -> Bool {
        values.contains { $0?.localizedCaseInsensitiveContains(query) == true }
    }

}
