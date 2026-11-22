import Foundation
import Testing
@testable import Upkeep

@Test func cleanupAdaptersUseSupportedNativeCommands() {
    #expect(cleanupArguments(for: .homebrew) == ["cleanup"])
    #expect(cleanupArguments(for: .npm) == ["cache", "verify"])
    #expect(cleanupArguments(for: .pnpm) == ["store", "prune"])
    #expect(cleanupArguments(for: .uv) == ["cache", "prune"])
}

@Test func cleanupOutputParsesDecimalAndBinarySizes() {
    #expect(cleanupReportedBytes(in: "This operation has freed approximately 1.2GB of disk space.") == 1_200_000_000)
    #expect(cleanupReportedBytes(in: "Removed 38 files (12.5 MiB)") == 13_107_200)
    #expect(cleanupReportedBytes(in: "Content garbage-collected: 4 (2048 bytes)") == 2_048)
}

@Test func cleanupOutputParsesHomebrewDryRunEstimate() {
    #expect(cleanupReportedBytes(in: "Would free: 42.5MB") == 42_500_000)
}

@Test func directorySizeUsesAllocatedFileSize() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PackageCleanupSizeTests.\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data(repeating: 1, count: 8_192).write(to: directory.appendingPathComponent("cache.bin"))

    #expect(try directoryAllocatedSize(at: directory) >= 8_192)
}

@Test func cleanupEstimateOnlyOffersExactCleanupWhenSpaceIsReclaimable() {
    let target = PackageCleanupTarget(kind: .homebrew, executablePath: "/opt/homebrew/bin/brew")
    let empty = PackageCleanupEstimate(target: target, bytes: 0, basis: .reclaimable)
    let reclaimable = PackageCleanupEstimate(target: target, bytes: 2_000_000, basis: .reclaimable)

    #expect(!empty.shouldOfferCleanup)
    #expect(empty.dialogTitle == "Nothing to Clean")
    #expect(reclaimable.shouldOfferCleanup)
    #expect(reclaimable.confirmationMessage.contains("Estimated cleanup size:"))
}

@Test func unrecognisedHomebrewDryRunDoesNotClaimNothingToClean() {
    let target = PackageCleanupTarget(kind: .homebrew, executablePath: "/fixture/brew")
    let unknown = homebrewCleanupEstimate(target: target, output: "Warning: cleanup output changed")
    #expect(unknown.basis == .unavailable)
    #expect(unknown.shouldOfferCleanup)
    #expect(unknown.dialogTitle != "Nothing to Clean")
    #expect(unknown.confirmationMessage.contains("unavailable"))
    #expect(homebrewCleanupEstimate(target: target, output: "").basis == .unavailable)
    #expect(homebrewCleanupEstimate(target: target, output: "Would free: 0 bytes").basis == .reclaimable)
    #expect(homebrewCleanupEstimate(target: target, output: "Would free: 42 bytes").bytes == 42)
}

@Test func cacheFootprintIsNotPresentedAsCleanupEstimate() {
    let target = PackageCleanupTarget(kind: .npm, executablePath: "/usr/local/bin/npm")
    let estimate = PackageCleanupEstimate(target: target, bytes: 2_000_000, basis: .cacheFootprintOnly)

    #expect(estimate.shouldOfferCleanup)
    #expect(estimate.dialogTitle == "Clean Up npm Cache?")
    #expect(estimate.confirmationMessage.contains("Cleanup estimate unavailable"))
    #expect(estimate.confirmationMessage.contains("not the amount cleanup will remove"))
}

@Test func cleanupConfirmationPreservesEstimateUncertaintyAndRemovalWarning() {
    let target = PackageCleanupTarget(kind: .npm, executablePath: "/fixture/npm")
    for basis in [PackageCleanupEstimateBasis.unavailable, .cacheFootprintOnly] {
        let estimate = PackageCleanupEstimate(target: target, bytes: 2_000_000, basis: basis)
        #expect(estimate.cleanupConfirmationMessage.contains("unavailable"))
        #expect(estimate.cleanupConfirmationMessage.contains("cannot be undone"))
        #expect(estimate.cleanupConfirmationMessage.contains("npm"))
        #expect(!estimate.cleanupConfirmationMessage.contains("Homebrew"))
    }
    let measured = PackageCleanupEstimate(target: target, bytes: 2_000_000, basis: .reclaimable)
    #expect(measured.cleanupConfirmationMessage.contains("Estimated cleanup size:"))
    #expect(measured.cleanupConfirmationMessage.contains("cannot be undone"))
}

@Test func cleanupOutputIgnoresUnrelatedVersionNumbers() {
    #expect(cleanupReportedBytes(in: "Homebrew 5.0.1 is current") == nil)
}

@MainActor
@Test func storeUsesInjectedCleanupManager() async {
    let suiteName = "PackageCleanupTests.\(UUID().uuidString)"
    let defaults = UserDefaults(testSuiteName: suiteName)!
    defer { defaults.removeTestDomain(forName: suiteName) }
    let cleanup = RecordingCleanupManager()
    let store = UpkeepStore(
        settings: AppSettings(defaults: defaults),
        dependencies: UpkeepDependencies(
            scanner: CleanupEmptyScanner(),
            homebrew: HomebrewClient(),
            developerPackages: DeveloperPackageClient(),
            packageCleanup: cleanup,
            localModels: LocalModelClient(),
            history: TestUpdateHistory()
        )
    )
    let target = PackageCleanupTarget(kind: .pnpm, executablePath: "/usr/local/bin/pnpm")

    let estimate = await store.scanCleanup(target)
    let result = await store.cleanUp(target)

    #expect(estimate?.bytes == 8_192)
    #expect(result?.bytesFreed == 4_096)
    #expect(await cleanup.scannedTargets == [target])
    #expect(await cleanup.targets == [target])
}

private struct CleanupEmptyScanner: UpdateScanning {
    func scan(settings: ScanSettings) async -> ScanReport { .empty }
    func scan(app: InstalledApp, settings: ScanSettings) async -> UpdateScanner.TargetedAppReport { .empty }
}

private actor RecordingCleanupManager: PackageCleanupManaging {
    private(set) var scannedTargets: [PackageCleanupTarget] = []
    private(set) var targets: [PackageCleanupTarget] = []

    func scan(_ target: PackageCleanupTarget) async throws -> PackageCleanupEstimate {
        scannedTargets.append(target)
        return PackageCleanupEstimate(target: target, bytes: 8_192, basis: .cacheFootprintOnly)
    }

    func cleanup(_ target: PackageCleanupTarget) async throws -> PackageCleanupResult {
        targets.append(target)
        return PackageCleanupResult(target: target, bytesFreed: 4_096)
    }
}

@Test func cleanupEstimateRejectsOverflowingByteCounts() {
    #expect(cleanupReportedBytes(in: "Would free 999999999999999999999999999999 TB") == nil)
    #expect(cleanupReportedBytes(in: "Freed 1.5 GB") == 1_500_000_000)
}

@MainActor
@Test func cleanupSheetReceivesErrorsWithoutPresentingGlobalAlert() async {
    let suiteName = "PackageCleanupErrors.\(UUID().uuidString)"
    let defaults = UserDefaults(testSuiteName: suiteName)!
    defer { defaults.removeTestDomain(forName: suiteName) }
    let store = UpkeepStore(
        settings: AppSettings(defaults: defaults),
        dependencies: UpkeepDependencies(
            scanner: CleanupEmptyScanner(), homebrew: HomebrewClient(),
            developerPackages: DeveloperPackageClient(), packageCleanup: FailingCleanupManager(),
            localModels: LocalModelClient(), history: TestUpdateHistory()
        )
    )
    let target = PackageCleanupTarget(kind: .npm, executablePath: "/usr/local/bin/npm")
    var message: String?
    let estimate = await store.scanCleanup(target, onError: { message = $0 })
    #expect(estimate == nil)
    #expect(message == "Test cleanup failure")
    #expect(store.errorMessage == nil)
    #expect(!store.isWorking(.packageCleanup(target.id)))
    message = nil
    let result = await store.cleanUp(target, onError: { message = $0 })
    #expect(result == nil)
    #expect(message == "Test cleanup failure")
    #expect(store.errorMessage == nil)
    #expect(!store.isWorking(.packageCleanup(target.id)))
    _ = await store.scanCleanup(target)
    #expect(store.errorMessage == "Test cleanup failure")
}

private struct FailingCleanupManager: PackageCleanupManaging {
    func scan(_ target: PackageCleanupTarget) async throws -> PackageCleanupEstimate {
        throw PackageCleanupClient.CleanupError.failed("Test cleanup failure")
    }
    func cleanup(_ target: PackageCleanupTarget) async throws -> PackageCleanupResult {
        throw PackageCleanupClient.CleanupError.failed("Test cleanup failure")
    }
}

@Test func cleanupMeasurementsRequireBothScopedReadings() {
    let target = PackageCleanupTarget(kind: .npm, executablePath: "/usr/local/bin/npm")
    for (before, after): (Int64?, Int64?) in [(nil, 100), (100, nil), (nil, nil)] {
        let result = cleanupMeasurement(target: target, reported: nil, before: before, after: after)
        #expect(result.measurement == .unknown)
        #expect(result.bytesFreed == 0)
        #expect(result.message.contains("could not be measured"))
    }
    let scoped = cleanupMeasurement(target: target, reported: nil, before: 300, after: 100)
    #expect(scoped.bytesFreed == 200)
    #expect(scoped.measurement == .cacheEstimate)
    #expect(scoped.message.contains("estimate"))
    #expect(cleanupMeasurement(target: target, reported: 42, before: nil, after: nil).measurement == .reported)
    #expect(cleanupMeasurement(target: target, reported: nil, before: 100, after: 300).bytesFreed == 0)
}

@Test func unrelatedDiskActivityDoesNotBecomeRecoveredCacheSpace() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ScopedCleanup.\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = root.appendingPathComponent("cache")
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    try Data(repeating: 65, count: 8_192).write(to: cache.appendingPathComponent("retained"))
    let unrelated = root.appendingPathComponent("unrelated-download")
    try Data(repeating: 66, count: 1_048_576).write(to: unrelated)
    let before = try directoryAllocatedSize(at: cache)
    try FileManager.default.removeItem(at: unrelated)
    let after = try directoryAllocatedSize(at: cache)
    #expect(before == after)
    let result = cleanupMeasurement(target: PackageCleanupTarget(kind: .npm, executablePath: "/fixture/npm"),
                                    reported: nil, before: before, after: after)
    #expect(result.bytesFreed == 0)
    #expect(result.measurement == .cacheEstimate)
    #expect(result.message.contains("Other cache activity may affect this estimate"))
}

@MainActor
@Test func cleanupSharesInstallReservationsButNotIndependentManagers() async {
    let suite = "CleanupReservations.\(UUID().uuidString)"
    let defaults = UserDefaults(testSuiteName: suite)!
    defer { defaults.removeTestDomain(forName: suite) }
    let cleanup = RecordingCleanupManager()
    let store = UpkeepStore(settings: AppSettings(defaults: defaults), dependencies: UpkeepDependencies(
        scanner: CleanupEmptyScanner(), homebrew: HomebrewClient(), developerPackages: DeveloperPackageClient(),
        packageCleanup: cleanup, localModels: LocalModelClient(), history: TestUpdateHistory()))
    let npm = PackageCleanupTarget(kind: .npm, executablePath: "/usr/local/bin/npm")
    let uv = PackageCleanupTarget(kind: .uv, executablePath: "/usr/local/bin/uv")
    let pnpm = PackageCleanupTarget(kind: .pnpm, executablePath: "/usr/local/bin/pnpm")
    #expect(!store.mutationTargets(for: npm).isDisjoint(with: store.mutationTargets(for: pnpm)))
    await store.mutationCoordinator.withAccess(to: store.mutationTargets(for: npm), otherwise: ()) {
        await MutationContext.$owner.withValue(nil) {
            #expect(await store.cleanUp(pnpm) == nil)
        }
    }
    // A separate owner must not inherit the task-local reservation owner.
    await store.mutationCoordinator.withAccess(to: [.packageEnvironment("npm")], otherwise: ()) {
        await MutationContext.$owner.withValue(nil) {
            #expect(await store.cleanUp(npm) == nil)
            #expect(await store.cleanUp(uv) != nil)
        }
    }
    #expect(await cleanup.targets == [uv])
    let package = HomebrewPackage(token: "example", displayName: "Example", description: nil, homepage: nil,
        license: nil, installedVersion: "1", currentVersion: "2", kind: .formula, isOutdated: true,
        isDependency: false, dependencies: [])
    #expect(!store.mutationTargets(for: .homebrew(package)).isDisjoint(with:
        store.mutationTargets(for: PackageCleanupTarget(kind: .homebrew, executablePath: "/opt/homebrew/bin/brew"))))
}
@Test func missingCacheDirectoryIsUnavailableRatherThanZeroBytes() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("missing-cache-\(UUID().uuidString)")
    #expect(throws: (any Error).self) { try directoryAllocatedSize(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(try directoryAllocatedSize(at: directory) == 0)
}

@MainActor
@Test(arguments: PackageCleanupKind.allCases)
func everySupportedCleanupRefusesAnInstallReservationAndWorksAfterRelease(kind: PackageCleanupKind) async throws {
    let suite = "CleanupInstallMatrix-\(UUID())"
    let defaults = try #require(UserDefaults(testSuiteName: suite))
    defer { defaults.removeTestDomain(forName: suite) }
    let cleanup = RecordingCleanupManager()
    let store = UpkeepStore(settings: AppSettings(defaults: defaults), dependencies: UpkeepDependencies(
        scanner: CleanupEmptyScanner(), homebrew: HomebrewClient(), developerPackages: DeveloperPackageClient(),
        packageCleanup: cleanup, localModels: LocalModelClient(), history: TestUpdateHistory()))
    let target = PackageCleanupTarget(kind: kind, executablePath: "/fixture/bin/\(kind.rawValue)")
    let installTargets: Set<MutationTarget>
    if kind == .homebrew {
        let package = HomebrewPackage(token: "fixture", displayName: "Fixture", description: nil, homepage: nil,
            license: nil, installedVersion: "1", currentVersion: "2", kind: .formula, isOutdated: true,
            isDependency: false, dependencies: [])
        installTargets = store.mutationTargets(for: .homebrew(package))
    } else {
        let manager: DeveloperPackageManager = kind == .npm ? .npm : kind == .pnpm ? .pnpm : .uv
        let package = DeveloperPackage(name: "fixture", currentVersion: "1", latestVersion: "2", manager: manager,
                                       executablePath: "/fixture/other-wrapper/\(manager.assetName)")
        installTargets = store.mutationTargets(for: .developer(package))
    }
    await store.mutationCoordinator.withAccess(to: installTargets, otherwise: ()) {
        await MutationContext.$owner.withValue(nil) { #expect(await store.cleanUp(target) == nil) }
    }
    #expect(await cleanup.targets.isEmpty)
    #expect(await store.cleanUp(target) != nil)
    #expect(await cleanup.targets == [target])
}
