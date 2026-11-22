import CryptoKit
import Foundation

/// A published Upkeep release that is newer than the running copy.
struct SelfUpdateRelease: Equatable, Sendable {
    let version: String
    let pageURL: URL
    let notes: String?
    let archiveURL: URL?
    let checksumURL: URL?
    let signatureURL: URL?
    let isPrerelease: Bool

    /// One-click install needs the archive, its checksum, and its signature.
    var canInstallInPlace: Bool { archiveURL != nil && checksumURL != nil && signatureURL != nil }
}

enum SelfUpdateError: LocalizedError, Equatable {
    case notInstallable
    case checksumMismatch
    case signatureInvalid
    case applicationNotFound
    case bundleIdentifierMismatch
    case versionMismatch(expected: String, found: String)
    case notNewer
    case architectureUnsupported
    case codeSignatureInvalid
    case locationNotWritable(String)
    case translocated
    case downloadFailed(Int)

    var errorDescription: String? {
        switch self {
        case .notInstallable: "This release has no signed download. Download it from GitHub instead."
        case .checksumMismatch: "The download did not match its published checksum, so it was not installed."
        case .signatureInvalid: "The download is not signed by Upkeep's release key, so it was not installed."
        case .applicationNotFound: "The download does not contain Upkeep.app."
        case .bundleIdentifierMismatch: "The downloaded app is not Upkeep, so it was not installed."
        case let .versionMismatch(expected, found): "The download contains version \(found), not \(expected)."
        case .notNewer: "The download is not newer than the installed Upkeep."
        case .architectureUnsupported: "The download does not support this Mac's processor."
        case .codeSignatureInvalid: "The downloaded app's code signature is not valid."
        case let .locationNotWritable(path): "Upkeep cannot replace itself at \(path). Move Upkeep to Applications, or update it manually."
        case .translocated: "macOS is running Upkeep from a temporary location. Move Upkeep to Applications, open it from there, and try again."
        case let .downloadFailed(status): "The download failed (HTTP \(status))."
        }
    }
}

enum SelfUpdate {
    static let repository = "dyd4dsh7/UpKeep"
    /// Public half of the Ed25519 key that signs release archives
    /// (`scripts/update-signing.swift`). Changing it means existing copies can
    /// no longer verify new releases and must be updated manually once.
    static let publicKey = "2tOzb22V/EMTEtHPnq0l3hLYZ8f78PE3JsEZIzAMAYA="
    static let archiveName = "Upkeep.zip"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: Release lookup

    static func latestRelease(includePrereleases: Bool) async throws -> SelfUpdateRelease? {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=20") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Upkeep/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await PublisherHTTPClient.data(for: request)
        guard response.statusCode == 200 else { throw UpdateSourceError.httpStatus(response.statusCode) }
        return try newestRelease(in: data, newerThan: currentVersion, includePrereleases: includePrereleases)
    }

    /// Picks the newest non-draft release newer than `installed` from a GitHub
    /// releases response. Prereleases are considered only when requested.
    static func newestRelease(in data: Data, newerThan installed: String, includePrereleases: Bool) throws -> SelfUpdateRelease? {
        let releases = try JSONDecoder().decode([GitHubClient.Release].self, from: data)
        let candidates = releases.compactMap { release -> (String, GitHubClient.Release)? in
            guard release.draft != true else { return nil }
            let version = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let isPrerelease = release.prerelease == true || VersionComparator.isPrerelease(version)
            guard includePrereleases || !isPrerelease, VersionComparator.isNewer(version, than: installed) else { return nil }
            return (version, release)
        }
        guard let (version, release) = candidates.max(by: { VersionComparator.compare($0.0, $1.0) == .orderedAscending }),
              let page = URL(string: release.htmlUrl) else { return nil }
        func asset(_ name: String) -> URL? {
            release.assets.first { $0.name == name }?.downloadURL.flatMap { $0.scheme == "https" ? $0 : nil }
        }
        return SelfUpdateRelease(
            version: version, pageURL: page, notes: release.body,
            archiveURL: asset(archiveName), checksumURL: asset(archiveName + ".sha256"),
            signatureURL: asset(archiveName + ".sig"),
            isPrerelease: release.prerelease == true || VersionComparator.isPrerelease(version)
        )
    }

    // MARK: Verification

    static func checksum(fromChecksumFile text: String) -> String? {
        guard let token = text.split(whereSeparator: \.isWhitespace).first?.lowercased(),
              token.count == 64, token.allSatisfy(\.isHexDigit) else { return nil }
        return token
    }

    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func isValidSignature(_ signatureBase64: String, for data: Data, publicKey: String = publicKey) -> Bool {
        guard let keyData = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let signature = Data(base64Encoded: signatureBase64.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return key.isValidSignature(signature, for: data)
    }

    /// Checks an archive against its published checksum and release signature.
    static func verifyArchive(_ archive: Data, checksumFile: String, signature: String,
                              publicKey: String = publicKey) throws {
        guard let expected = checksum(fromChecksumFile: checksumFile), expected == sha256(of: archive) else {
            throw SelfUpdateError.checksumMismatch
        }
        guard isValidSignature(signature, for: archive, publicKey: publicKey) else { throw SelfUpdateError.signatureInvalid }
    }

    /// Validates an extracted Upkeep.app before it may replace the running copy.
    static func validateStagedApp(_ app: URL, release version: String, installedVersion: String,
                                  bundleIdentifier: String = InstalledApp.upkeepBundleIdentifier) throws {
        guard let bundle = Bundle(url: app), let info = bundle.infoDictionary else { throw SelfUpdateError.applicationNotFound }
        guard info["CFBundleIdentifier"] as? String == bundleIdentifier else { throw SelfUpdateError.bundleIdentifierMismatch }
        let found = info["CFBundleShortVersionString"] as? String ?? ""
        guard VersionComparator.compare(found, version) == .orderedSame else {
            throw SelfUpdateError.versionMismatch(expected: version, found: found)
        }
        guard VersionComparator.isNewer(found, than: installedVersion) else { throw SelfUpdateError.notNewer }
        #if arch(arm64)
        let required = NSBundleExecutableArchitectureARM64
        #else
        let required = NSBundleExecutableArchitectureX86_64
        #endif
        guard bundle.executableArchitectures?.contains(NSNumber(value: required)) == true else {
            throw SelfUpdateError.architectureUnsupported
        }
    }

    /// Whether the running copy can be replaced in place.
    static func checkReplaceable(_ app: URL = Bundle.main.bundleURL) throws {
        if app.path.contains("/AppTranslocation/") { throw SelfUpdateError.translocated }
        let parent = app.deletingLastPathComponent().path
        guard FileManager.default.isWritableFile(atPath: parent), FileManager.default.isWritableFile(atPath: app.path) else {
            throw SelfUpdateError.locationNotWritable(parent)
        }
    }

    // MARK: Download and stage

    /// Downloads, verifies, and extracts a release. Returns the staged Upkeep.app.
    static func stage(_ release: SelfUpdateRelease) async throws -> URL {
        guard release.canInstallInPlace, let archiveURL = release.archiveURL,
              let checksumURL = release.checksumURL, let signatureURL = release.signatureURL else {
            throw SelfUpdateError.notInstallable
        }
        let fileManager = FileManager.default
        let root = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let checksumText = String(decoding: try await small(checksumURL), as: UTF8.self)
        let signature = String(decoding: try await small(signatureURL), as: UTF8.self)
        var request = URLRequest(url: archiveURL)
        request.timeoutInterval = 300
        request.setValue("Upkeep/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (download, response) = try await PublisherHTTPClient.download(for: request, maximumBytes: 512 * 1_024 * 1_024)
        defer { try? fileManager.removeItem(at: download) }
        guard 200..<300 ~= response.statusCode else { throw SelfUpdateError.downloadFailed(response.statusCode) }
        let archive = root.appendingPathComponent(archiveName)
        try fileManager.moveItem(at: download, to: archive)
        try verifyArchive(try Data(contentsOf: archive, options: .alwaysMapped), checksumFile: checksumText, signature: signature)

        try ZIPArchiveInspector.validate(archive)
        let expanded = root.appendingPathComponent("Expanded", isDirectory: true)
        try fileManager.createDirectory(at: expanded, withIntermediateDirectories: true)
        let unzip = try await CommandRunner.run(URL(fileURLWithPath: "/usr/bin/ditto"), ["-x", "-k", archive.path, expanded.path], timeout: 120)
        guard unzip.status == 0 else { throw SelfUpdateError.applicationNotFound }
        let app = expanded.appendingPathComponent("Upkeep.app", isDirectory: true)
        guard fileManager.fileExists(atPath: app.path) else { throw SelfUpdateError.applicationNotFound }
        try validateStagedApp(app, release: release.version, installedVersion: currentVersion)
        let codesign = try await CommandRunner.run(URL(fileURLWithPath: "/usr/bin/codesign"),
                                                   ["--verify", "--deep", "--strict", app.path], timeout: 60)
        guard codesign.status == 0 else { throw SelfUpdateError.codeSignatureInvalid }
        return app
    }

    private static func small(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await PublisherHTTPClient.data(for: request, maximumBytes: 64 * 1_024)
        guard 200..<300 ~= response.statusCode else { throw SelfUpdateError.downloadFailed(response.statusCode) }
        return data
    }

    static var stagingRoot: URL {
        (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("\(InstalledApp.upkeepBundleIdentifier)/SelfUpdate", isDirectory: true)
    }

    static var backupURL: URL {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Upkeep/Self Update Backup/Upkeep.app", isDirectory: true)
    }

    // MARK: Install

    /// Waits for `pid` to exit, moves `target` to `backup`, copies `staged` into
    /// place, and relaunches it. If the copy fails, the backup is restored.
    /// Paths arrive as arguments, never interpolated into the script.
    static let installScript = """
    #!/bin/sh
    pid="$1"; staged="$2"; target="$3"; backup="$4"; relaunch="$5"
    waited=0
    while kill -0 "$pid" 2>/dev/null; do
        sleep 0.2; waited=$((waited + 1))
        [ "$waited" -gt 300 ] && exit 1
    done
    mkdir -p "$(dirname "$backup")" && rm -rf "$backup"
    if mv "$target" "$backup"; then
        if /usr/bin/ditto "$staged" "$target"; then
            rm -rf "$staged"
            [ "$relaunch" = "1" ] && /usr/bin/open "$target"
            exit 0
        fi
        rm -rf "$target"
        mv "$backup" "$target"
    fi
    [ "$relaunch" = "1" ] && /usr/bin/open "$target"
    exit 1
    """

    /// Starts the detached install helper. The caller then quits Upkeep.
    @discardableResult
    static func launchInstaller(staged: URL, target: URL = Bundle.main.bundleURL, backup: URL = backupURL,
                                waitingFor pid: Int32 = ProcessInfo.processInfo.processIdentifier,
                                relaunch: Bool = true) throws -> Process {
        let script = stagingRoot.appendingPathComponent("install-\(UUID().uuidString).sh")
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        try Data(installScript.utf8).write(to: script, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(pid), staged.path, target.path, backup.path, relaunch ? "1" : "0"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }
}
