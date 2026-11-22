import CryptoKit
import Foundation
import Testing
@testable import Upkeep

private func releasesJSON(_ entries: [(tag: String, prerelease: Bool, draft: Bool, assets: [String])]) -> Data {
    let items = entries.map { entry in
        let assets = entry.assets.map {
            #"{"name":"\#($0)","browser_download_url":"https://github.com/dyd4dsh7/UpKeep/releases/download/\#(entry.tag)/\#($0)"}"#
        }.joined(separator: ",")
        return #"{"tag_name":"\#(entry.tag)","html_url":"https://github.com/dyd4dsh7/UpKeep/releases/tag/\#(entry.tag)","body":"Notes","prerelease":\#(entry.prerelease),"draft":\#(entry.draft),"assets":[\#(assets)]}"#
    }
    return Data("[\(items.joined(separator: ","))]".utf8)
}

private let signedAssets = ["Upkeep.zip", "Upkeep.zip.sha256", "Upkeep.zip.sig"]

@Test func selfUpdatePicksTheNewestStableRelease() throws {
    let data = releasesJSON([
        ("v0.26.0-beta.1", true, false, signedAssets),
        ("v0.25.6", false, true, signedAssets),
        ("v0.25.5", false, false, signedAssets),
        ("v0.25.4", false, false, ["Upkeep.zip"])
    ])
    let release = try #require(try SelfUpdate.newestRelease(in: data, newerThan: "0.25.4", includePrereleases: false))
    #expect(release.version == "0.25.5", "Drafts and prereleases are skipped")
    #expect(release.canInstallInPlace)
    #expect(release.archiveURL?.lastPathComponent == "Upkeep.zip")

    let beta = try #require(try SelfUpdate.newestRelease(in: data, newerThan: "0.25.4", includePrereleases: true))
    #expect(beta.version == "0.26.0-beta.1" && beta.isPrerelease)

    #expect(try SelfUpdate.newestRelease(in: data, newerThan: "0.25.5", includePrereleases: false) == nil)
}

@Test func unsignedReleasesFallBackToTheReleasePage() throws {
    let data = releasesJSON([("v0.25.5", false, false, ["Upkeep.zip", "Upkeep.zip.sha256"])])
    let release = try #require(try SelfUpdate.newestRelease(in: data, newerThan: "0.25.4", includePrereleases: false))
    #expect(!release.canInstallInPlace)
    #expect(release.pageURL.absoluteString.hasSuffix("/v0.25.5"))
}

@Test func archiveMustMatchChecksumAndReleaseSignature() throws {
    let key = Curve25519.Signing.PrivateKey()
    let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
    let archive = Data("archive bytes".utf8)
    let checksum = SelfUpdate.sha256(of: archive) + "  Upkeep.zip\n"
    let signature = try key.signature(for: archive).base64EncodedString()

    try SelfUpdate.verifyArchive(archive, checksumFile: checksum, signature: signature, publicKey: publicKey)

    #expect(throws: SelfUpdateError.checksumMismatch) {
        try SelfUpdate.verifyArchive(Data("tampered".utf8), checksumFile: checksum, signature: signature, publicKey: publicKey)
    }
    let otherKey = Curve25519.Signing.PrivateKey()
    let wrongSignature = try otherKey.signature(for: archive).base64EncodedString()
    #expect(throws: SelfUpdateError.signatureInvalid) {
        try SelfUpdate.verifyArchive(archive, checksumFile: checksum, signature: wrongSignature, publicKey: publicKey)
    }
    #expect(SelfUpdate.checksum(fromChecksumFile: "not-a-hash Upkeep.zip") == nil)
    #expect(!SelfUpdate.publicKey.isEmpty && Data(base64Encoded: SelfUpdate.publicKey)?.count == 32)
}

private func fixtureApp(in root: URL, identifier: String = InstalledApp.upkeepBundleIdentifier, version: String) throws -> URL {
    let app = root.appendingPathComponent("Upkeep-\(UUID().uuidString).app")
    let contents = app.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
    let plist: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleShortVersionString": version,
                                "CFBundleExecutable": "Upkeep", "CFBundlePackageType": "APPL"]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: contents.appendingPathComponent("Info.plist"))
    // A real executable so the architecture check reads its slices.
    try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/echo"), to: contents.appendingPathComponent("MacOS/Upkeep"))
    return app
}

@Test func stagedAppMustBeNewerUpkeepForThisMac() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("SelfUpdate-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    try SelfUpdate.validateStagedApp(try fixtureApp(in: root, version: "0.25.5"), release: "0.25.5", installedVersion: "0.25.4")
    #expect(throws: SelfUpdateError.bundleIdentifierMismatch) {
        try SelfUpdate.validateStagedApp(try fixtureApp(in: root, identifier: "com.example.other", version: "0.25.5"),
                                         release: "0.25.5", installedVersion: "0.25.4")
    }
    #expect(throws: SelfUpdateError.versionMismatch(expected: "0.25.5", found: "0.25.3")) {
        try SelfUpdate.validateStagedApp(try fixtureApp(in: root, version: "0.25.3"), release: "0.25.5", installedVersion: "0.25.4")
    }
    #expect(throws: SelfUpdateError.notNewer) {
        try SelfUpdate.validateStagedApp(try fixtureApp(in: root, version: "0.25.4"), release: "0.25.4", installedVersion: "0.25.4")
    }
}

@Test func installHelperReplacesTheAppAndKeepsABackup() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("SelfUpdateInstall-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let target = root.appendingPathComponent("Applications/Upkeep.app")
    let staged = root.appendingPathComponent("Staged/Upkeep.app")
    let backup = root.appendingPathComponent("Backup/Upkeep.app")
    for (url, marker) in [(target, "old"), (staged, "new")] {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: url.appendingPathComponent("marker"))
    }
    // Waits on an already-exited process, so the helper proceeds at once.
    let finished = Process()
    finished.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    try finished.run(); finished.waitUntilExit()

    let helper = try SelfUpdate.launchInstaller(staged: staged, target: target, backup: backup,
                                                waitingFor: finished.processIdentifier, relaunch: false)
    helper.waitUntilExit()
    #expect(helper.terminationStatus == 0)
    #expect(String(decoding: try Data(contentsOf: target.appendingPathComponent("marker")), as: UTF8.self) == "new")
    #expect(String(decoding: try Data(contentsOf: backup.appendingPathComponent("marker")), as: UTF8.self) == "old")
    #expect(!FileManager.default.fileExists(atPath: staged.path))
}

@Test func translocatedOrReadOnlyCopiesAreNotReplaced() throws {
    #expect(throws: SelfUpdateError.translocated) {
        try SelfUpdate.checkReplaceable(URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/Upkeep.app"))
    }
    #expect(throws: SelfUpdateError.self) {
        try SelfUpdate.checkReplaceable(URL(fileURLWithPath: "/System/Applications/Upkeep.app"))
    }
}

@MainActor
@Test func selfUpdateControllerStaysOfflineOutsideThePackagedApp() async throws {
    let suite = "UpkeepTests.SelfUpdate.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let controller = SelfUpdateController(defaults: defaults, isEnabled: false)
    controller.checkAutomatically()
    #expect(controller.phase == .idle)
    #expect(controller.bannerRelease == nil)
}

/// End-to-end check of a packaged release against the app's built-in key:
/// UPKEEP_SELF_UPDATE_ARCHIVE=outputs/Upkeep.zip swift test --filter packagedReleasePassesSelfUpdateVerification
@Test func packagedReleasePassesSelfUpdateVerification() async throws {
    guard let path = ProcessInfo.processInfo.environment["UPKEEP_SELF_UPDATE_ARCHIVE"] else { return }
    let archive = URL(fileURLWithPath: path)
    let checksum = try String(contentsOf: archive.appendingPathExtension("sha256"), encoding: .utf8)
    let signature = try String(contentsOf: archive.appendingPathExtension("sig"), encoding: .utf8)
    try SelfUpdate.verifyArchive(try Data(contentsOf: archive), checksumFile: checksum, signature: signature)
    try ZIPArchiveInspector.validate(archive)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("SelfUpdateE2E-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    #expect(try await CommandRunner.run(URL(fileURLWithPath: "/usr/bin/ditto"), ["-x", "-k", archive.path, root.path], timeout: 60).status == 0)
    let app = root.appendingPathComponent("Upkeep.app")
    let version = try #require(Bundle(url: app)?.infoDictionary?["CFBundleShortVersionString"] as? String)
    try SelfUpdate.validateStagedApp(app, release: version, installedVersion: "0.0.1")
    #expect(try await CommandRunner.run(URL(fileURLWithPath: "/usr/bin/codesign"), ["--verify", "--deep", "--strict", app.path], timeout: 60).status == 0)
}

@Test func installHelperWaitsForUpkeepToQuit() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("SelfUpdateWait-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let target = root.appendingPathComponent("Applications/Upkeep.app")
    let staged = root.appendingPathComponent("Staged/Upkeep.app")
    for (url, marker) in [(target, "old"), (staged, "new")] {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: url.appendingPathComponent("marker"))
    }
    let running = Process()
    running.executableURL = URL(fileURLWithPath: "/bin/sleep")
    running.arguments = ["1"]
    try running.run()
    let helper = try SelfUpdate.launchInstaller(staged: staged, target: target,
                                                backup: root.appendingPathComponent("Backup/Upkeep.app"),
                                                waitingFor: running.processIdentifier, relaunch: false)
    try await Task.sleep(for: .milliseconds(300))
    #expect(String(decoding: try Data(contentsOf: target.appendingPathComponent("marker")), as: UTF8.self) == "old",
            "Nothing is replaced while Upkeep is still running")
    running.waitUntilExit()
    helper.waitUntilExit()
    #expect(helper.terminationStatus == 0)
    #expect(String(decoding: try Data(contentsOf: target.appendingPathComponent("marker")), as: UTF8.self) == "new")
}
