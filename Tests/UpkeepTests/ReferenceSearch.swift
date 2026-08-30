import Foundation
@testable import Upkeep

struct ReferenceSearchResults {
    let apps: [InstalledApp]
    let adoptableApps: [AdoptableApp]
    let homebrewPackages: [HomebrewPackage]
    let developerPackages: [DeveloperPackage]
    let models: [LocalLLMModel]
    let macOSUpdates: [MacOSUpdate]
    let history: [UpdateRecord]

    var isEmpty: Bool {
        apps.isEmpty && adoptableApps.isEmpty && homebrewPackages.isEmpty
            && developerPackages.isEmpty && models.isEmpty && macOSUpdates.isEmpty
            && history.isEmpty
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

/// Frozen pre-optimization search behavior for differential regression checks.
/// Keep independent of the production matcher to detect field/order regressions.
@MainActor
struct ReferenceSearch {
    let store: UpkeepStore

    private var query: String {
        store.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchingApps: [InstalledApp] {
        store.apps.filter { app in
            matches(app.name, app.bundleIdentifier, app.installedVersion, app.url.path,
                    app.updateManagement.rawValue, store.sources(for: app).map(\.rawValue).joined(separator: " "))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var matchingAdoptableApps: [AdoptableApp] {
        store.adoptableApps.filter { matches($0.app.name, $0.caskToken, $0.caskVersion) }
            .sorted { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending }
    }

    private var matchingHomebrewPackages: [HomebrewPackage] {
        store.homebrewPackages.filter {
            matches($0.displayName, $0.token, $0.description, $0.kind.rawValue,
                    $0.installedVersion, $0.currentVersion, $0.dependencies.joined(separator: " "))
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

    var results: ReferenceSearchResults {
        ReferenceSearchResults(
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
