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

@Test func cacheFootprintIsNotPresentedAsCleanupEstimate() {
    let target = PackageCleanupTarget(kind: .npm, executablePath: "/usr/local/bin/npm")
    let estimate = PackageCleanupEstimate(target: target, bytes: 2_000_000, basis: .cacheFootprintOnly)

    #expect(estimate.shouldOfferCleanup)
    #expect(estimate.dialogTitle == "Clean Up npm Cache?")
    #expect(estimate.confirmationMessage.contains("Cleanup estimate unavailable"))
    #expect(estimate.confirmationMessage.contains("not the amount cleanup will remove"))
}

@Test func cleanupOutputIgnoresUnrelatedVersionNumbers() {
    #expect(cleanupReportedBytes(in: "Homebrew 5.0.1 is current") == nil)
}

@MainActor
@Test func storeUsesInjectedCleanupManager() async {
    let suiteName = "PackageCleanupTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
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
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
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
