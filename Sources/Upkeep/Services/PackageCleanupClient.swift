import Foundation

enum PackageCleanupKind: String, CaseIterable, Sendable {
    case homebrew = "Homebrew"
    case npm
    case pnpm
    case uv

    var commandDescription: String {
        switch self {
        case .homebrew: "brew cleanup"
        case .npm: "npm cache verify"
        case .pnpm: "pnpm store prune"
        case .uv: "uv cache prune"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .homebrew:
            "Homebrew will remove stale locks, outdated downloads, and old installed formula versions."
        case .npm:
            "npm will verify its cache and garbage-collect unneeded data. Packages will be downloaded again if needed."
        case .pnpm:
            "pnpm will remove packages that are not referenced by any project. They will be downloaded again if needed."
        case .uv:
            "uv will remove unused cache entries and disposable centralized project environments. They will be recreated if needed."
        }
    }
}

struct PackageCleanupTarget: Identifiable, Hashable, Sendable {
    let kind: PackageCleanupKind
    let executablePath: String

    var id: String { "\(kind.rawValue):\(executablePath)" }
    var title: String { kind.rawValue }
    var commandDescription: String { kind.commandDescription }

    static func available(
        homebrewURL: URL?,
        installedManagers: [DeveloperPackageManager],
        packages: [DeveloperPackage]
    ) -> [PackageCleanupTarget] {
        var targets: [PackageCleanupTarget] = []
        if let homebrewURL {
            targets.append(PackageCleanupTarget(kind: .homebrew, executablePath: homebrewURL.path))
        }

        let supportedManagers: [(DeveloperPackageManager, PackageCleanupKind)] = [
            (.npm, .npm), (.pnpm, .pnpm), (.uv, .uv)
        ]
        for (manager, kind) in supportedManagers where installedManagers.contains(manager) {
            let packagePath = packages.first { $0.manager == manager }?.executablePath
            if let executablePath = packagePath ?? detectedCleanupExecutable(for: manager) {
                targets.append(PackageCleanupTarget(kind: kind, executablePath: executablePath))
            }
        }
        return targets
    }
}

struct PackageCleanupResult: Identifiable, Equatable, Sendable {
    let id = UUID()
    let target: PackageCleanupTarget
    let bytesFreed: Int64

    var title: String { "\(target.title) Cleanup Complete" }
    var message: String {
        guard bytesFreed > 0 else { return "No reclaimable files were found." }
        return "Freed \(ByteCountFormatter.string(fromByteCount: bytesFreed, countStyle: .file)) of disk space."
    }
}

enum PackageCleanupEstimateBasis: Equatable, Sendable {
    case reclaimable
    case cacheFootprintOnly
}

struct PackageCleanupEstimate: Identifiable, Equatable, Sendable {
    let id = UUID()
    let target: PackageCleanupTarget
    let bytes: Int64
    let basis: PackageCleanupEstimateBasis

    var shouldOfferCleanup: Bool {
        basis == .cacheFootprintOnly || bytes > 0
    }

    var dialogTitle: String {
        shouldOfferCleanup ? "Clean Up \(target.kind.cleanupSubject)?" : "Nothing to Clean"
    }

    var confirmationMessage: String {
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        switch basis {
        case .reclaimable:
            if bytes == 0 {
                return "Homebrew's dry run found no files that can currently be removed."
            }
            return "Estimated cleanup size: \(size)."
        case .cacheFootprintOnly:
            return "Cleanup estimate unavailable. \(target.kind.cleanupSubject) currently uses \(size), but that is its total footprint—not the amount cleanup will remove."
        }
    }
}

extension PackageCleanupKind {
    var cleanupSubject: String {
        switch self {
        case .homebrew: "Homebrew"
        case .npm: "npm Cache"
        case .pnpm: "pnpm Store"
        case .uv: "uv Cache"
        }
    }
}

struct PackageCleanupClient: Sendable {
    func scan(_ target: PackageCleanupTarget) async throws -> PackageCleanupEstimate {
        let executable = URL(fileURLWithPath: target.executablePath)
        switch target.kind {
        case .homebrew:
            let result = await captureDeveloperCommandAsync(
                executable,
                ["cleanup", "--dry-run"],
                qos: .userInitiated
            )
            guard result.status == 0 else { throw scanError(target, result.data) }
            let output = String(data: result.data, encoding: .utf8) ?? ""
            return PackageCleanupEstimate(
                target: target,
                bytes: cleanupReportedBytes(in: output) ?? 0,
                basis: .reclaimable
            )
        case .npm:
            return try await directoryEstimate(target, arguments: ["config", "get", "cache"])
        case .pnpm:
            return try await directoryEstimate(target, arguments: ["store", "path"])
        case .uv:
            return try await directoryEstimate(target, arguments: ["cache", "dir"])
        }
    }

    func cleanup(_ target: PackageCleanupTarget) async throws -> PackageCleanupResult {
        let executable = URL(fileURLWithPath: target.executablePath)
        let before = availableCapacity(for: executable)
        let result = await captureDeveloperCommandAsync(
            executable,
            cleanupArguments(for: target.kind),
            qos: .userInitiated
        )
        guard result.status == 0 else {
            let output = String(data: result.data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw CleanupError.failed(
                output?.isEmpty == false ? output! : "\(target.title) cleanup failed."
            )
        }

        let output = String(data: result.data, encoding: .utf8) ?? ""
        let measuredBytes = max(0, (availableCapacity(for: executable) ?? 0) - (before ?? 0))
        let bytesFreed = cleanupReportedBytes(in: output) ?? measuredBytes
        return PackageCleanupResult(target: target, bytesFreed: bytesFreed)
    }

    private func directoryEstimate(
        _ target: PackageCleanupTarget,
        arguments: [String]
    ) async throws -> PackageCleanupEstimate {
        let result = await captureDeveloperCommandAsync(
            URL(fileURLWithPath: target.executablePath),
            arguments,
            qos: .userInitiated
        )
        guard result.status == 0 else { throw scanError(target, result.data) }
        let path = (String(data: result.data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { throw CleanupError.failed("\(target.title) did not report its cache location.") }
        return PackageCleanupEstimate(
            target: target,
            bytes: try directoryAllocatedSize(at: URL(fileURLWithPath: path)),
            basis: .cacheFootprintOnly
        )
    }

    private func scanError(_ target: PackageCleanupTarget, _ data: Data) -> CleanupError {
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .failed(output?.isEmpty == false ? output! : "\(target.title) cleanup scan failed.")
    }

    enum CleanupError: LocalizedError {
        case failed(String)

        var errorDescription: String? {
            if case let .failed(message) = self { return message }
            return nil
        }
    }
}

func cleanupArguments(for kind: PackageCleanupKind) -> [String] {
    switch kind {
    case .homebrew: ["cleanup"]
    case .npm: ["cache", "verify"]
    case .pnpm: ["store", "prune"]
    case .uv: ["cache", "prune"]
    }
}

func cleanupReportedBytes(in output: String) -> Int64? {
    let relevantLines = output.split(separator: "\n").filter { line in
        let value = line.lowercased()
        return value.contains("freed") || value.contains("would free") || value.contains("removed") ||
            value.contains("reclaimed") || value.contains("garbage-collected")
    }
    let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(bytes?|[kmgt]i?b)\b"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
    let values = relevantLines.flatMap { line -> [Int64] in
        let value = String(line)
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap { match in
            guard let numberRange = Range(match.range(at: 1), in: value),
                  let unitRange = Range(match.range(at: 2), in: value),
                  let number = Double(value[numberRange]) else { return nil }
            let unit = value[unitRange].lowercased()
            let multiplier: Double = switch unit {
            case "kb": 1_000
            case "kib": 1_024
            case "mb": 1_000_000
            case "mib": 1_048_576
            case "gb": 1_000_000_000
            case "gib": 1_073_741_824
            case "tb": 1_000_000_000_000
            case "tib": 1_099_511_627_776
            default: 1
            }
            let bytes = number * multiplier
            guard bytes.isFinite, bytes >= 0, bytes < Double(Int64.max) else { return nil }
            return Int64(bytes)
        }
    }
    return values.max()
}

func directoryAllocatedSize(at directory: URL, fileManager: FileManager = .default) throws -> Int64 {
    guard let enumerator = fileManager.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey],
        options: [.skipsPackageDescendants]
    ) else { return 0 }

    var bytes: Int64 = 0
    var visited = 0
    for case let fileURL as URL in enumerator {
        visited += 1
        if visited.isMultiple(of: 256) { try Task.checkCancellation() }
        let values = try fileURL.resourceValues(forKeys: [
            .isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey
        ])
        guard values.isRegularFile == true else { continue }
        bytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }
    return bytes
}

private func availableCapacity(for executable: URL) -> Int64? {
    try? executable.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        .volumeAvailableCapacityForImportantUsage
}

private func detectedCleanupExecutable(for manager: DeveloperPackageManager) -> String? {
    let fileManager = FileManager.default
    let home = fileManager.homeDirectoryForCurrentUser
    let name: String
    let extra: [String]
    switch manager {
    case .npm, .pnpm:
        name = manager.assetName
        let nvmRoot = home.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        let nvmVersions = (try? fileManager.contentsOfDirectory(at: nvmRoot, includingPropertiesForKeys: nil)) ?? []
        extra = nvmVersions.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
            .map { $0.appendingPathComponent("bin/\(name)").path }
            + [home.appendingPathComponent("Library/pnpm/\(name)").path]
    case .uv:
        name = "uv"
        extra = [home.appendingPathComponent(".local/bin/uv").path]
    default:
        return nil
    }
    return (extra + ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"])
        .first { fileManager.isExecutableFile(atPath: $0) }
}
