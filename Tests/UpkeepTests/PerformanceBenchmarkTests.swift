import Combine
import Foundation
import Testing
@testable import Upkeep

/// Opt-in benchmark for the repeated version comparisons used by update
/// merging, sorting, prerelease classification, and update-list rendering.
@Test func repeatedVersionComparisonBenchmark() {
    guard ProcessInfo.processInfo.environment["UPKEEP_SCANNER_BENCHMARK"] == "versions" else { return }

    let pairs = [
        ("2.0.0", "1.9.9"),
        ("2026.10.4", "2026.9.18"),
        ("v4.2.1", "4.2"),
        ("3.0b12", "3.0b2"),
        ("1.0-rc.4", "1.0-beta.12"),
        ("openssl@3 3.5.1_2", "openssl@3 3.5.1_1"),
        ("0.144.6-darwin-arm64", "0.144.5-darwin-arm64"),
        ("1.2.3+build.99", "1.2.3+build.12")
    ]
    let iterations = 25_000
    let clock = ContinuousClock()
    let started = clock.now
    var descendingCount = 0

    for _ in 0..<iterations {
        for pair in pairs where VersionComparator.compare(pair.0, pair.1) == .orderedDescending {
            descendingCount += 1
        }
    }

    let elapsed = started.duration(to: clock.now)
    #expect(descendingCount == iterations * 7)
    print(
        "VERSION_COMPARISON_BENCHMARK elapsed=\(elapsed) "
            + "comparisons=\(iterations * pairs.count) descending=\(descendingCount)"
    )
}

/// Opt-in local benchmark for the bundle enumeration and metadata inspection
/// performed at startup and at the beginning of every full update scan.
@Test func applicationDiscoveryBenchmark() async {
    guard ProcessInfo.processInfo.environment["UPKEEP_SCANNER_BENCHMARK"] == "discovery" else { return }

    let clock = ContinuousClock()
    for iteration in 1...3 {
        let started = clock.now
        let apps = await AppDiscovery.discover()
        let elapsed = started.duration(to: clock.now)

        #expect(!apps.isEmpty)
        print(
            "APPLICATION_DISCOVERY_BENCHMARK iteration=\(iteration) "
                + "elapsed=\(elapsed) apps=\(apps.count)"
        )
    }
}

/// Opt-in benchmark for the root observation bridge used by the SwiftUI view
/// tree. The notification count is the primary invalidation-fan-out metric.
@MainActor
@Test func rootObservationFanoutBenchmark() async {
    guard ProcessInfo.processInfo.environment["UPKEEP_SCANNER_BENCHMARK"] == "observation" else { return }

    let store = UpkeepStore()
    var notifications = 0
    let subscription = store.objectWillChange.sink { notifications += 1 }
    let clock = ContinuousClock()
    let started = clock.now

    for index in 0..<10_000 {
        store.navigation.searchText = "query-\(index)"
    }

    let mutationElapsed = started.duration(to: clock.now)
    try? await Task.sleep(for: .milliseconds(20))
    withExtendedLifetime(subscription) {}
    print(
        "ROOT_OBSERVATION_BENCHMARK elapsed=\(mutationElapsed) "
            + "mutations=10000 notifications=\(notifications)"
    )
}

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

/// Opt-in benchmark for decoding and validating the maximum retained
/// diagnostics history during application startup.
@Test func diagnosticsLoadBenchmark() throws {
    guard ProcessInfo.processInfo.environment["UPKEEP_SCANNER_BENCHMARK"] == "diagnostics" else { return }

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("upkeep-diagnostics-benchmark-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directory.appendingPathComponent("diagnostics.json")
    defer { try? FileManager.default.removeItem(at: directory) }

    let entries = (0..<2_000).map { index in
        DiagnosticEntry(
            level: .info,
            category: .source,
            message: "Application source request \(index) completed",
            metadata: [
                "Item": "Application \(index)",
                "Duration": "125 ms",
                "Result": "Current"
            ]
        )
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try encoder.encode(entries).write(to: fileURL)

    let clock = ContinuousClock()
    for iteration in 1...3 {
        let started = clock.now
        let loaded = DiagnosticsStore(fileURL: fileURL).entries()
        let elapsed = started.duration(to: clock.now)
        #expect(loaded.count == entries.count)
        print(
            "DIAGNOSTICS_LOAD_BENCHMARK iteration=\(iteration) "
                + "elapsed=\(elapsed) entries=\(loaded.count)"
        )
    }
}

/// Opt-in benchmark for the cross-list lookups used by sidebar counts, app
/// source badges, Homebrew mapping, inspectors, and the global search results.
@MainActor
@Test func libraryProjectionBenchmark() {
    guard ProcessInfo.processInfo.environment["UPKEEP_SCANNER_BENCHMARK"] == "library" else { return }

    let itemCount = 2_000
    let apps = (0..<itemCount).map { index in
        InstalledApp(
            name: "Benchmark App \(index)",
            bundleIdentifier: "nz.test.benchmark.\(index)",
            installedVersion: "1.0.0",
            buildVersion: nil,
            url: URL(fileURLWithPath: "/Applications/Benchmark App \(index).app"),
            sparkleFeedURL: index.isMultiple(of: 3) ? URL(string: "https://example.com/\(index).xml") : nil,
            githubRepository: index.isMultiple(of: 5) ? "example/app-\(index)" : nil,
            hasAppStoreReceipt: false
        )
    }
    let packages = (0..<itemCount).map { index in
        HomebrewPackage(
            token: "benchmark-app-\(index)",
            displayName: "Benchmark App \(index)",
            description: nil,
            homepage: nil,
            license: nil,
            installedVersion: "1.0.0",
            currentVersion: "1.0.1",
            kind: .cask,
            isOutdated: true,
            isDependency: false,
            dependencies: []
        )
    }
    let updates = stride(from: 0, to: itemCount, by: 2).map { index in
        AvailableUpdate(
            app: apps[index],
            availableVersion: "1.0.1",
            source: .github,
            releaseNotes: nil,
            actionURL: nil,
            homebrewToken: nil
        )
    }
    let store = UpkeepStore()
    store.apps = apps
    store.homebrewPackages = packages
    store.updates = updates

    let clock = ContinuousClock()
    for iteration in 1...3 {
        let started = clock.now
        var checksum = 0
        checksum += store.applications(for: .homebrewApps).count
        checksum += store.applications(for: .noSource).count
        for app in apps {
            checksum += store.sources(for: app).count
            checksum += store.homebrewPackage(for: app) == nil ? 0 : 1
        }
        for package in packages {
            checksum += store.homebrewPackageApp(for: package) == nil ? 0 : 1
        }
        let elapsed = started.duration(to: clock.now)
        #expect(checksum > itemCount * 3)
        print(
            "LIBRARY_PROJECTION_BENCHMARK iteration=\(iteration) "
                + "elapsed=\(elapsed) apps=\(apps.count) packages=\(packages.count) updates=\(updates.count) "
                + "checksum=\(checksum)"
        )
    }
}

@MainActor
@Test func libraryProjectionIndexesTrackCollectionChanges() {
    let store = UpkeepStore()
    let app = benchmarkApp(index: 1, name: "Widget Desktop")
    let earlierMatch = benchmarkPackage(index: 1, token: "widget", name: "Widget")
    let laterMatch = benchmarkPackage(index: 2, token: "widget-app", name: "Widget App")

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

    store.homebrewPackages = [benchmarkPackage(index: 3, token: "other", name: "Other")]
    #expect(store.homebrewPackage(for: app) == nil)

    store.apps = []
    store.adoptableApps = []
    store.developerPackages = []
    store.localModels = []
    #expect(store.app(forID: app.id) == nil)
    #expect(store.adoptableApp(forID: adoptable.id) == nil)
    #expect(store.developerPackage(forID: developerPackage.id) == nil)
    #expect(store.localModel(forID: model.id) == nil)

    store.updates = [benchmarkUpdate(app: app, source: .github)]
    #expect(store.source(for: app) == .github)
    store.updates = [benchmarkUpdate(app: app, source: .sparkle)]
    #expect(store.source(for: app) == .sparkle)
}

private func benchmarkApp(index: Int, name: String) -> InstalledApp {
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

private func benchmarkPackage(index: Int, token: String, name: String) -> HomebrewPackage {
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
        dependencies: ["benchmark-\(index)"]
    )
}

private func benchmarkUpdate(app: InstalledApp, source: UpdateSource) -> AvailableUpdate {
    AvailableUpdate(
        app: app,
        availableVersion: "1.0.1",
        source: source,
        releaseNotes: nil,
        actionURL: nil,
        homebrewToken: nil
    )
}
