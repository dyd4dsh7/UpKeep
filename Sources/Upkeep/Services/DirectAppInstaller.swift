import Foundation

protocol DirectAppInstalling: Sendable {
    func install(update: AvailableUpdate) async throws
}

struct DirectAppInstaller: DirectAppInstalling, Sendable {
    func install(update: AvailableUpdate) async throws {
        guard let downloadURL = update.directInstallURL else {
            throw InstallError.unsupportedDownload
        }
        try await Task.detached(priority: .userInitiated) {
            try await installSynchronouslyDownloaded(
                update: update,
                downloadURL: downloadURL
            )
        }.value
    }

    private func installSynchronouslyDownloaded(
        update: AvailableUpdate,
        downloadURL: URL
    ) async throws {
        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("Upkeep-Install-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }

        var request = URLRequest(url: downloadURL)
        request.timeoutInterval = 120
        let (temporaryDownload, response) = try await PublisherHTTPClient.download(for: request)
        defer { try? fileManager.removeItem(at: temporaryDownload) }
        guard 200..<300 ~= response.statusCode else {
            throw InstallError.downloadFailed
        }
        let archive = workspace.appendingPathComponent(
            "Update.\(downloadURL.pathExtension.lowercased())"
        )
        try fileManager.moveItem(at: temporaryDownload, to: archive)

        var mountedRoot: URL?
        var mountedDiskImage = false
        defer {
            if mountedDiskImage, let mountedRoot {
                try? run("/usr/bin/hdiutil", ["detach", mountedRoot.path, "-force"])
            }
        }
        let extractedRoot: URL
        switch downloadURL.pathExtension.lowercased() {
        case "zip":
            try ZIPArchiveInspector.validate(archive)
            extractedRoot = workspace.appendingPathComponent("Expanded", isDirectory: true)
            try fileManager.createDirectory(at: extractedRoot, withIntermediateDirectories: true)
            try run("/usr/bin/ditto", ["-x", "-k", archive.path, extractedRoot.path])
        case "dmg":
            extractedRoot = workspace.appendingPathComponent("Mounted", isDirectory: true)
            mountedRoot = extractedRoot
            try fileManager.createDirectory(at: extractedRoot, withIntermediateDirectories: true)
            try run("/usr/bin/hdiutil", [
                "attach", archive.path, "-nobrowse", "-readonly", "-mountpoint", extractedRoot.path
            ])
            mountedDiskImage = true
        default:
            throw InstallError.unsupportedDownload
        }

        let replacement = try matchingApplication(
            under: extractedRoot,
            bundleIdentifier: update.app.bundleIdentifier
        )
        try replace(update.app.url, with: replacement, for: update)
    }

    private func matchingApplication(
        under root: URL,
        bundleIdentifier: String?
    ) throws -> URL {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
            throw InstallError.missingBundleIdentifier
        }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { throw InstallError.applicationNotFound }

        var matches: [URL] = []
        for case let candidate as URL in enumerator
        where candidate.pathExtension.lowercased() == "app" {
            if Bundle(url: candidate)?.bundleIdentifier == bundleIdentifier {
                matches.append(candidate)
            }
        }
        guard matches.count == 1, let match = matches.first else {
            throw matches.isEmpty
                ? InstallError.applicationNotFound
                : InstallError.ambiguousApplication
        }
        return match
    }

    private func validate(_ replacement: URL, for update: AvailableUpdate) throws {
        guard let bundle = Bundle(url: replacement),
              bundle.bundleIdentifier == update.app.bundleIdentifier
        else { throw InstallError.bundleIdentifierMismatch }
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard let version,
              VersionComparator.compare(version, update.app.installedVersion) == .orderedDescending,
              VersionComparator.compare(version, update.availableVersion) == .orderedSame
        else { throw InstallError.versionMismatch }
        try run("/usr/bin/codesign", ["--verify", "--strict", replacement.path])
        try run("/usr/bin/codesign", ["--verify", "--strict", update.app.url.path])
        guard try signingIdentity(for: replacement) == signingIdentity(for: update.app.url) else {
            throw InstallError.signingIdentityMismatch
        }
    }

    private func replace(_ installed: URL, with replacement: URL, for update: AvailableUpdate) throws {
        let fileManager = FileManager.default
        let staged = installed.deletingLastPathComponent()
            .appendingPathComponent(".Upkeep-\(UUID().uuidString)-\(installed.lastPathComponent)")
        defer { try? fileManager.removeItem(at: staged) }
        do {
            try StagedReplacementTransaction.perform(
                replacement: replacement,
                staged: staged,
                installed: installed,
                copy: { try fileManager.copyItem(at: $0, to: $1) },
                validate: { try validate($0, for: update) },
                replace: { _ = try fileManager.replaceItemAt($0, withItemAt: $1) }
            )
        } catch let error as InstallError {
            throw error
        } catch {
            throw InstallError.couldNotReplace(error.localizedDescription)
        }
    }

    private func run(_ executable: String, _ arguments: [String]) throws {
        _ = try command(executable, arguments)
    }

    private func command(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        do { try process.run() }
        catch { throw InstallError.commandFailed(error.localizedDescription) }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw InstallError.commandFailed(message ?? executable)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func signingIdentity(for application: URL) throws -> String {
        let output = try command("/usr/bin/codesign", [
            "-d", "--verbose=4", application.path
        ])
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        if let team = lines.first(where: { $0.hasPrefix("TeamIdentifier=") }),
           team != "TeamIdentifier=not set" {
            return team
        }
        guard let authority = lines.first(where: { $0.hasPrefix("Authority=") }) else {
            throw InstallError.missingSigningIdentity
        }
        return authority
    }

    enum InstallError: LocalizedError {
        case unsupportedDownload
        case downloadFailed
        case missingBundleIdentifier
        case applicationNotFound
        case ambiguousApplication
        case bundleIdentifierMismatch
        case versionMismatch
        case missingSigningIdentity
        case signingIdentityMismatch
        case commandFailed(String)
        case couldNotReplace(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedDownload:
                "This release does not provide a supported macOS app archive."
            case .downloadFailed:
                "The publisher download did not complete successfully."
            case .missingBundleIdentifier:
                "Upkeep cannot safely replace an app without a bundle identifier."
            case .applicationNotFound:
                "The download did not contain the expected application."
            case .ambiguousApplication:
                "The download contained more than one matching application."
            case .bundleIdentifierMismatch:
                "The downloaded app does not match the installed app."
            case .versionMismatch:
                "The downloaded app’s version does not match the advertised update."
            case .missingSigningIdentity:
                "The app publisher’s signing identity could not be verified."
            case .signingIdentityMismatch:
                "The downloaded app was signed by a different publisher."
            case let .commandFailed(message):
                "The downloaded update could not be verified or unpacked: \(message)"
            case let .couldNotReplace(message):
                "macOS blocked the app replacement: \(message). Allow Upkeep in Privacy & Security → App Management, then try again."
            }
        }
    }
}

enum StagedReplacementTransaction {
    static func perform(
        replacement: URL,
        staged: URL,
        installed: URL,
        copy: (URL, URL) throws -> Void,
        validate: (URL) throws -> Void,
        replace: (URL, URL) throws -> Void
    ) throws {
        try copy(replacement, staged)
        try validate(staged)
        try replace(installed, staged)
    }
}
