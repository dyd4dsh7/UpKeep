import AppKit
import Foundation

struct MacOSUpdateClient: Sendable {
    struct Report: Sendable {
        let updates: [MacOSUpdate]
        let currentVersion: String
        let currentBuild: String
        let isRunningBeta: Bool
        let updatesSucceeded: Bool
        let installersSucceeded: Bool
        let warnings: [String]
        static let empty = Report(
            updates: [], currentVersion: "", currentBuild: "", isRunningBeta: false,
            updatesSucceeded: true, installersSucceeded: true, warnings: []
        )
    }

    func scan(includeInstallers: Bool = true) async -> Report {
        await Task.detached(priority: .utility) {
            var warnings: [String] = []
            let updatesResult = commandResult(URL(fileURLWithPath: "/usr/sbin/softwareupdate"), ["--list", "--product-types", "macOS"])
            let installersResult: (data: Data?, error: Error?) = includeInstallers
                ? commandResult(URL(fileURLWithPath: "/usr/sbin/softwareupdate"), ["--list-full-installers"])
                : (Data(), nil)
            if let error = updatesResult.error { warnings.append("Available updates: \(error.localizedDescription)") }
            if let error = installersResult.error { warnings.append("Full installers: \(error.localizedDescription)") }
            let updatesOutput = updatesResult.data ?? Data()
            let installersOutput = installersResult.data ?? Data()
            let updates = parseUpdates(String(data: updatesOutput, encoding: .utf8) ?? "")
            let installers = parseInstallers(String(data: installersOutput, encoding: .utf8) ?? "")
            let version = ProcessInfo.processInfo.operatingSystemVersionString
            let build = shellValue("/usr/bin/sw_vers", ["-buildVersion"])
            let extra = shellValue("/usr/bin/sw_vers", ["-productVersionExtra"])
            return Report(
                updates: updates + installers.filter { installer in
                    !updates.contains(where: { $0.version == installer.version })
                },
                currentVersion: version,
                currentBuild: build,
                isRunningBeta: !extra.isEmpty || version.localizedCaseInsensitiveContains("beta"),
                updatesSucceeded: updatesResult.error == nil,
                installersSucceeded: installersResult.error == nil,
                warnings: warnings
            )
        }.value
    }

    @MainActor
    func openSoftwareUpdateSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

private func parseUpdates(_ output: String) -> [MacOSUpdate] {
    let blocks = output.components(separatedBy: "* Label:").dropFirst()
    return blocks.compactMap { block in
        let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let first = lines.first else { return nil }
        let label = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = lines.dropFirst().joined(separator: " ")
        let title = capture(#"Title:\s*([^,]+)"#, in: detail) ?? label
        let version = capture(#"Version:\s*([^,]+)"#, in: detail) ?? versionFrom(label) ?? "Unknown"
        return MacOSUpdate(
            label: label,
            title: title,
            version: version,
            size: capture(#"Size:\s*([^,]+)"#, in: detail),
            requiresRestart: detail.localizedCaseInsensitiveContains("restart"),
            isBeta: isBetaName(title + " " + label),
            isFullInstaller: false
        )
    }
}

private func parseInstallers(_ output: String) -> [MacOSUpdate] {
    output.split(separator: "\n").compactMap { rawLine in
        let line = String(rawLine)
        guard line.contains("* Title:") else { return nil }
        let title = capture(#"Title:\s*([^,]+)"#, in: line) ?? "macOS"
        guard let version = capture(#"Version:\s*([^,]+)"#, in: line) else { return nil }
        return MacOSUpdate(
            label: "full-installer-\(version)",
            title: title,
            version: version,
            size: capture(#"Size:\s*([^,]+)"#, in: line),
            requiresRestart: true,
            isBeta: isBetaName(title + " " + version),
            isFullInstaller: true
        )
    }
}

private func capture(_ pattern: String, in value: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
          let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
          let range = Range(match.range(at: 1), in: value)
    else { return nil }
    return String(value[range]).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func versionFrom(_ value: String) -> String? {
    capture(#"\b(\d+(?:\.\d+){1,3})\b"#, in: value)
}

private func isBetaName(_ value: String) -> Bool {
    ["beta", "release candidate", " rc", "seed"].contains { value.localizedCaseInsensitiveContains($0) }
}

private func shellValue(_ path: String, _ arguments: [String]) -> String {
    guard let data = try? runCommand(URL(fileURLWithPath: path), arguments) else { return "" }
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

private func runCommand(_ executable: URL, _ arguments: [String]) throws -> Data {
    let process = Process(); let output = Pipe()
    process.executableURL = executable; process.arguments = arguments
    process.standardOutput = output; process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        throw MacOSUpdateError.commandFailed(message?.isEmpty == false ? message! : "Command exited with status \(process.terminationStatus).")
    }
    return data
}

private func commandResult(_ executable: URL, _ arguments: [String]) -> (data: Data?, error: Error?) {
    do { return (try runCommand(executable, arguments), nil) }
    catch { return (nil, error) }
}

private enum MacOSUpdateError: LocalizedError {
    case commandFailed(String)
    var errorDescription: String? {
        if case let .commandFailed(message) = self { return message }
        return nil
    }
}
