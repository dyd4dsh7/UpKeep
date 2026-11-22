import Combine
import Foundation
import Testing
@testable import Upkeep

@MainActor
@Test func rootObservationCoalescesSynchronousChildChanges() async {
    let store = UpkeepStore()
    var notifications = 0
    let subscription = store.objectWillChange.sink { notifications += 1 }

    store.navigation.searchText = "one"
    store.navigation.searchText = "two"
    store.scanState.errorMessage = "Example"
    try? await Task.sleep(for: .milliseconds(10))

    withExtendedLifetime(subscription) {}
    #expect(notifications == 1)
    #expect(store.searchText == "two")
    #expect(store.errorMessage == "Example")
}

@MainActor
@Test func libraryProjectionIndexesTrackCollectionChanges() {
    let store = UpkeepStore()
    let app = projectionApp(index: 1, name: "Widget Desktop")
    let earlierMatch = projectionPackage(index: 1, token: "widget", name: "Widget")
    let laterMatch = projectionPackage(index: 2, token: "widget-app", name: "Widget App")

    store.apps = [app]
    store.homebrewPackages = [earlierMatch, laterMatch]
    #expect(store.app(forID: app.id)?.id == app.id)
    #expect(store.homebrewPackage(forID: earlierMatch.id)?.id == earlierMatch.id)
    #expect(store.homebrewPackage(for: app)?.id == earlierMatch.id)
    #expect(store.homebrewPackageApp(for: laterMatch)?.id == app.id)

    let adoptable = AdoptableApp(app: app, caskToken: "widget", caskVersion: "1.0.1")
    store.adoptableApps = [adoptable]
    #expect(store.adoptableApp(forID: adoptable.id)?.id == adoptable.id)
    #expect(store.adoptableApp(for: app)?.id == adoptable.id)

    let developerPackage = DeveloperPackage(
        name: "widget-cli",
        currentVersion: "1.0.0",
        latestVersion: "1.0.1",
        manager: .npm,
        executablePath: "/usr/local/bin/npm"
    )
    store.developerPackages = [developerPackage]
    #expect(store.developerPackage(forID: developerPackage.id)?.id == developerPackage.id)

    let model = LocalLLMModel(
        id: "ollama:widget",
        name: "Widget",
        variant: nil,
        runtime: .ollama,
        installedRevision: "sha-old",
        latestRevision: "sha-new",
        sizeBytes: nil,
        modifiedAt: nil,
        homepage: nil,
        executablePath: nil,
        updateReference: "widget:latest",
        isOutdated: true
    )
    store.localModels = [model]
    #expect(store.localModel(forID: model.id)?.id == model.id)

    store.homebrewPackages = [projectionPackage(index: 3, token: "other", name: "Other")]
    #expect(store.homebrewPackage(for: app) == nil)

    store.apps = []
    store.adoptableApps = []
    store.developerPackages = []
    store.localModels = []
    #expect(store.app(forID: app.id) == nil)
    #expect(store.adoptableApp(forID: adoptable.id) == nil)
    #expect(store.developerPackage(forID: developerPackage.id) == nil)
    #expect(store.localModel(forID: model.id) == nil)

    store.updates = [projectionUpdate(app: app, source: .github)]
    #expect(store.source(for: app) == .github)
    store.updates = [projectionUpdate(app: app, source: .sparkle)]
    #expect(store.source(for: app) == .sparkle)
}

private func projectionApp(index: Int, name: String) -> InstalledApp {
    InstalledApp(
        name: name,
        bundleIdentifier: "nz.test.projection.\(index)",
        installedVersion: "1.0.0",
        buildVersion: nil,
        url: URL(fileURLWithPath: "/Applications/\(name).app"),
        sparkleFeedURL: nil,
        githubRepository: nil,
        hasAppStoreReceipt: false
    )
}

private func projectionPackage(index: Int, token: String, name: String) -> HomebrewPackage {
    HomebrewPackage(
        token: token,
        displayName: name,
        description: nil,
        homepage: nil,
        license: nil,
        installedVersion: "1.0.0",
        currentVersion: "1.0.1",
        kind: .cask,
        isOutdated: true,
        isDependency: false,
        dependencies: ["projection-\(index)"]
    )
}

private func projectionUpdate(app: InstalledApp, source: UpdateSource) -> AvailableUpdate {
    AvailableUpdate(
        app: app,
        availableVersion: "1.0.1",
        source: source,
        releaseNotes: nil,
        actionURL: nil,
        homebrewToken: nil
    )
}
