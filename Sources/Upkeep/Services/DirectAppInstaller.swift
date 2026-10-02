import Foundation

protocol DirectAppInstalling: Sendable {
    func install(update: AvailableUpdate) async throws
    func install(update: AvailableUpdate, progress: @escaping UpdateProgressReporter) async throws
}

extension DirectAppInstalling {
    func install(update: AvailableUpdate, progress: @escaping UpdateProgressReporter) async throws {
        await progress(.installing)
        try await install(update: update)
    }
}

struct DirectAppInstaller: DirectAppInstalling, Sendable {
    private var cancellation: CommandRunner.Cancellation?
    init() {}
    func install(update: AvailableUpdate) async throws {
        try await install(update: update, progress: { _ in })
    }

    func install(update: AvailableUpdate, progress: @escaping UpdateProgressReporter) async throws {
        guard let downloadURL = update.directInstallURL else {
            throw InstallError.unsupportedDownload
        }
        let cancellation = CommandRunner.Cancellation()
        var worker = self
        worker.cancellation = cancellation
        let installer = worker
        let commandLog = OperationCommandLogContext.current
        let task = Task.detached(priority: .userInitiated) {
            try await OperationCommandLogContext.$current.withValue(commandLog) {
                try await installer.installSynchronouslyDownloaded(
                update: update,
                downloadURL: downloadURL,
                progress: progress
                )
            }
        }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            cancellation.cancel()
            task.cancel()
        }
    }

    private func installSynchronouslyDownloaded(
        update: AvailableUpdate,
        downloadURL: URL,
        progress: @escaping UpdateProgressReporter
    ) async throws {
        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("Upkeep-Install-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }

        var request = URLRequest(url: downloadURL)
        request.timeoutInterval = 120
        await progress(.downloading)
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
        do {
            await progress(.preparing)
            let extractedRoot: URL
            switch downloadURL.pathExtension.lowercased() {
            case "zip":
                try ZIPArchiveInspector.validate(archive)
                extractedRoot = workspace.appendingPathComponent("Expanded", isDirectory: true)
                try fileManager.createDirectory(at: extractedRoot, withIntermediateDirectories: true)
                try await run("/usr/bin/ditto", ["-x", "-k", archive.path, extractedRoot.path], purpose: .mutation)
            case "dmg":
                extractedRoot = workspace.appendingPathComponent("Mounted", isDirectory: true)
                mountedRoot = extractedRoot
                try fileManager.createDirectory(at: extractedRoot, withIntermediateDirectories: true)
                mountedDiskImage = true
                try await run("/usr/bin/hdiutil", [
                    "attach", archive.path, "-nobrowse", "-readonly", "-mountpoint", extractedRoot.path
                ], purpose: .mutation)
            default:
                throw InstallError.unsupportedDownload
            }

            let replacement = try matchingApplication(
                under: extractedRoot,
                bundleIdentifier: update.app.bundleIdentifier
            )
            await progress(.installing)
            try cancellation?.check()
            try await replace(update.app.url, with: replacement, for: update)
        } catch {
            if mountedDiskImage, let mountedRoot { await detach(mountedRoot) }
            throw error
        }
        if mountedDiskImage, let mountedRoot { await detach(mountedRoot) }
    }

    private func detach(_ mountedRoot: URL) async {
        // Cleanup must finish even when the installation task was cancelled.
        let log = OperationCommandLogContext.current
        await Task.detached(priority: .utility) {
            await OperationCommandLogContext.$current.withValue(log) {
                _ = try? await CommandRunner.run(URL(fileURLWithPath: "/usr/bin/hdiutil"),
                    ["detach", mountedRoot.path, "-force"], timeout: 30)
            }
        }.value
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

    private func validate(_ replacement: URL, for update: AvailableUpdate) async throws {
        guard let bundle = Bundle(url: replacement),
              bundle.bundleIdentifier == update.app.bundleIdentifier
        else { throw InstallError.bundleIdentifierMismatch }
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        try Self.validateVersion(version: version, build: build, update: update)
        try AppCompatibility.current.validateBundle(at: replacement)
        try await run("/usr/bin/codesign", ["--verify", "--strict", replacement.path])
        try await run("/usr/bin/codesign", ["--verify", "--strict", update.app.url.path])
        let replacementIdentity = try await signingIdentity(for: replacement)
        let installedIdentity = try await signingIdentity(for: update.app.url)
        guard replacementIdentity == installedIdentity else {
            throw InstallError.signingIdentityMismatch
        }
    }

    static func validateVersion(version: String?, build: String?, update: AvailableUpdate) throws {
        guard let version,
              update.primaryCandidate.isNewer(than: update.app),
              update.primaryCandidate.matchesDownload(version: version, build: build)
        else { throw InstallError.versionMismatch }
    }

    private func replace(_ installed: URL, with replacement: URL, for update: AvailableUpdate) async throws {
        let fileManager = FileManager.default
        let staged = installed.deletingLastPathComponent()
            .appendingPathComponent(".Upkeep-\(UUID().uuidString)-\(installed.lastPathComponent)")
        defer { try? fileManager.removeItem(at: staged) }
        do {
            try await StagedReplacementTransaction.performAsync(
                replacement: replacement,
                staged: staged,
                installed: installed,
                copy: { try fileManager.copyItem(at: $0, to: $1) },
                validate: { try await validate($0, for: update) },
                replace: {
                    try cancellation?.check()
                    _ = try fileManager.replaceItemAt($0, withItemAt: $1)
                }
            )
        } catch let error as InstallError {
            throw error
        } catch {
            throw InstallError.couldNotReplace(error.localizedDescription)
        }
    }

    private func run(_ executable: String, _ arguments: [String], purpose: CommandRunner.Purpose = .inventory) async throws {
        _ = try await command(executable, arguments, purpose: purpose)
    }

    private func command(_ executable: String, _ arguments: [String], purpose: CommandRunner.Purpose = .inventory) async throws -> String {
        let result: CommandRunner.Result
        do {
            result = try await CommandRunner.run(URL(fileURLWithPath: executable), arguments,
                timeout: CommandRunner.deadline(for: arguments, purpose: purpose),
                maximumOutputBytes: 16 * 1_024 * 1_024)
        } catch { throw InstallError.commandFailed(error.localizedDescription) }
        guard result.status == 0 else {
            let message = String(data: result.output, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw InstallError.commandFailed(message ?? executable)
        }
        return String(data: result.output, encoding: .utf8) ?? ""
    }

    private func signingIdentity(for application: URL) async throws -> String {
        let output = try await command("/usr/bin/codesign", [
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
    static func performAsync(
        replacement: URL, staged: URL, installed: URL,
        copy: (URL, URL) throws -> Void,
        validate: (URL) async throws -> Void,
        replace: (URL, URL) throws -> Void
    ) async throws {
        try Task.checkCancellation()
        try copy(replacement, staged)
        try await validate(staged)
        try Task.checkCancellation()
        try replace(installed, staged)
    }

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
