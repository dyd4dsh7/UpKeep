import AppKit
import Foundation

/// Works out which copy in a duplicate group is the one in use: for tools,
/// the copy whose command comes first on the PATH Terminal uses; for apps,
/// the copy macOS opens by default.
enum ActiveInstallations {
    static func activeIDs(
        in groups: [DuplicateGroup],
        path: [String],
        defaultApp: (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
        commandDirectory: (DuplicateMember) -> String? = { commandDirectory(for: $0) }
    ) -> Set<String> {
        let order = Dictionary(path.enumerated().map { (normalized($0.element), $0.offset) }, uniquingKeysWith: { first, _ in first })
        var active = Set<String>()
        for group in groups {
            if group.kind == .appCopies {
                guard case let .app(first)? = group.members.first, let bundleID = first.bundleIdentifier,
                      let opened = defaultApp(bundleID)?.standardizedFileURL else { continue }
                if let member = group.members.first(where: {
                    if case let .app(app) = $0 { return app.url.standardizedFileURL == opened } else { return false }
                }) { active.insert(member.id) }
                continue
            }
            let ranked = group.members.compactMap { member -> (DuplicateMember, Int)? in
                guard let directory = commandDirectory(member), let index = order[normalized(directory)] else { return nil }
                return (member, index)
            }.sorted { $0.1 < $1.1 }
            // Two copies in one folder can't be told apart by PATH order.
            guard let first = ranked.first, ranked.dropFirst().first?.1 != first.1 else { continue }
            active.insert(first.0.id)
        }
        return active
    }

    /// The folder a copy puts its command in, only when that folder really
    /// holds a command from this copy.
    static func commandDirectory(for member: DuplicateMember, fileManager: FileManager = .default) -> String? {
        switch member {
        case .app:
            return nil
        case let .developer(package):
            let directory = URL(fileURLWithPath: package.executablePath).deletingLastPathComponent().path
            switch package.manager {
            case .npm:
                // npm links each global package's commands next to npm itself.
                return containsLink(in: directory, into: "/node_modules/\(package.name)/", fileManager: fileManager) ? directory : nil
            case let manager where DuplicateFinder.runtimeManagers.contains(manager):
                return fileManager.isExecutableFile(atPath: package.executablePath) ? directory : nil
            default:
                return nil
            }
        case let .homebrew(formula):
            for prefix in ["/opt/homebrew", "/usr/local"] {
                let directory = prefix + "/bin"
                if containsLink(in: directory, into: "/Cellar/\(formula.token)/", fileManager: fileManager) { return directory }
            }
            return nil
        }
    }

    private static func containsLink(in directory: String, into marker: String, fileManager: FileManager) -> Bool {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory) else { return false }
        return names.contains { name in
            let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
            return url.resolvingSymlinksInPath().path.contains(marker)
        }
    }

    private static func normalized(_ directory: String) -> String {
        URL(fileURLWithPath: directory).standardizedFileURL.path
    }
}

/// The PATH an interactive Terminal shell gets, including what nvm, pyenv
/// and similar tools add in shell startup files. Apps launched from the Dock
/// get a much shorter PATH, so it is read from the user's shell.
actor LoginShellPath {
    static let shared = LoginShellPath()
    static let lifetime: TimeInterval = 10 * 60
    private var cached: (directories: [String], date: Date)?

    func directories() async -> [String] {
        if let cached, Date().timeIntervalSince(cached.date) < Self.lifetime { return cached.directories }
        let directories = await Self.read()
        cached = (directories, Date())
        return directories
    }

    private static func read() async -> [String] {
        let configured = ProcessInfo.processInfo.environment["SHELL"] ?? ""
        let shell = ["zsh", "bash"].contains(URL(fileURLWithPath: configured).lastPathComponent) ? configured : "/bin/zsh"
        guard let result = try? await CommandRunner.run(URL(fileURLWithPath: shell),
                                                        ["-lic", #"printf 'UPKEEP_PATH=%s\n' "$PATH""#], timeout: 10),
              result.status == 0 else { return [] }
        return parse(String(decoding: result.output, as: UTF8.self))
    }

    /// Startup files can print their own output; only the marked line counts.
    static func parse(_ output: String) -> [String] {
        guard let line = output.split(separator: "\n").last(where: { $0.hasPrefix("UPKEEP_PATH=") }) else { return [] }
        return line.dropFirst("UPKEEP_PATH=".count).split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
    }
}
