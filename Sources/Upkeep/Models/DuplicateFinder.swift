import Foundation

/// One installed copy in a duplicate group.
enum DuplicateMember: Identifiable, Hashable, Sendable {
    case app(InstalledApp)
    case developer(DeveloperPackage)
    case homebrew(HomebrewPackage)

    var id: String {
        switch self {
        case let .app(app): "app|\(app.id)"
        case let .developer(package): "developer|\(package.id)"
        case let .homebrew(package): "homebrew|\(package.id)"
        }
    }

    var name: String {
        switch self {
        case let .app(app): app.name
        case let .developer(package): package.name
        case let .homebrew(package): package.displayName
        }
    }

    var version: String {
        switch self {
        case let .app(app): app.installedVersion
        case let .developer(package): package.currentVersion
        case let .homebrew(package): package.installedVersion
        }
    }

    /// Where this copy lives, in the words a person would use.
    var location: String {
        switch self {
        case let .app(app):
            return app.url.deletingLastPathComponent().path
                .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        case let .developer(package):
            return [package.manager.rawValue, package.installationContext].compactMap { $0 }.joined(separator: " · ")
        case let .homebrew(package):
            return "Homebrew \(package.kind.rawValue.lowercased())"
        }
    }

    /// What sets this copy apart from the others, such as "Applications",
    /// "Homebrew’s npm" or "NVM Node 24.22.1".
    var place: String {
        switch self {
        case let .app(app):
            let folder = app.url.deletingLastPathComponent()
            return folder.path == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
                ? "Your Applications folder" : FileManager.default.displayName(atPath: folder.path)
        case let .developer(package):
            if let context = package.installationContext { return context }
            let path = package.executablePath
            if path.hasPrefix("/opt/homebrew/") || path.hasPrefix("/usr/local/") { return "Homebrew’s \(package.manager.rawValue)" }
            return package.manager.rawValue
        case let .homebrew(package):
            return "Homebrew \(package.kind.rawValue.lowercased())"
        }
    }

    /// Where the copy is on disk, with the home folder shortened to ~.
    var path: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let raw: String
        switch self {
        case let .app(app): raw = app.url.path
        case let .developer(package): raw = URL(fileURLWithPath: package.executablePath).deletingLastPathComponent().path
        case let .homebrew(package): raw = "brew \(package.kind == .cask ? "--cask " : "")\(package.token)"
        }
        return raw.hasPrefix(home) ? "~" + raw.dropFirst(home.count) : raw
    }

    /// What removing this copy does, for the confirmation message.
    var removalDescription: String {
        switch self {
        case let .app(app): "\(app.name) in \(location) is moved to the Trash"
        case let .developer(package): "\(package.name) \(package.currentVersion) (\(location)) is uninstalled"
        case let .homebrew(package): "Homebrew uninstalls \(package.token)"
        }
    }
}

struct DuplicateGroup: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case appCopies
        case packageCopies
        case runtimeVersions
        case twoInstallers

        var title: String {
            switch self {
            case .appCopies: "Apps in more than one place"
            case .packageCopies: "Tools installed more than once"
            case .runtimeVersions: "Runtime versions"
            case .twoInstallers: "Tools from two installers"
            }
        }

        var explanation: String {
            switch self {
            case .appCopies:
                "Keeping one copy avoids opening or updating the wrong one."
            case .packageCopies:
                "Only one copy runs when you type its name in Terminal; the others take up space and fall behind."
            case .runtimeVersions:
                "Projects can need a particular version, so remove only versions you no longer use."
            case .twoInstallers:
                "Keeping one makes it clear which version runs and which installer updates it."
            }
        }
    }

    /// Stable across scans, so "Not a Duplicate" is remembered.
    let id: String
    let kind: Kind
    let title: String
    let members: [DuplicateMember]

    /// The copy with the highest version.
    /// The first copy with the highest version, when copies share it.
    var newestID: String? {
        members.reduce(nil as DuplicateMember?) { best, member in
            guard let best else { return member }
            return VersionComparator.compare(member.version, best.version) == .orderedDescending ? member : best
        }?.id
    }
}

enum DuplicateFinder {
    /// JavaScript, Cargo, Go and similar tools install global commands; two
    /// copies of one are true duplicates. Python and Ruby packages belong to
    /// separate environments and are left out.
    static let globalToolManagers: Set<DeveloperPackageManager> = [.npm, .pnpm, .yarn, .cargo, .go, .pipx, .composer, .dotnet]

    /// Managers whose entries are runtime or toolchain versions.
    static let runtimeManagers: Set<DeveloperPackageManager> = [.node, .rustup, .pyenv, .rbenv, .swiftly, .juliaup,
                                                               .ghcup, .sdkman, .mise, .asdf, .volta, .fnm]

    /// Installed with every Node.js version, so one per version is expected.
    static let bundledPackages: Set<String> = ["npm", "corepack"]

    /// `isHomebrewInstalled` resolves symlinks such as /opt/homebrew/bin/node
    /// into Homebrew's Cellar.
    static func groups(
        apps: [InstalledApp], developerPackages: [DeveloperPackage], homebrewPackages: [HomebrewPackage],
        isHomebrewInstalled: (String) -> Bool = { DeveloperPackageUninstallAdapters.homebrewPlan(for: $0) != nil }
    ) -> [DuplicateGroup] {
        var groups: [DuplicateGroup] = []

        let appsByID = Dictionary(grouping: apps.filter { !$0.isUpkeep }) { $0.bundleIdentifier?.lowercased() ?? "" }
        for (bundleID, copies) in appsByID where !bundleID.isEmpty && copies.count > 1 {
            let sorted = copies.sorted { $0.url.path < $1.url.path }
            groups.append(DuplicateGroup(id: "app:\(bundleID)", kind: .appCopies,
                                         title: sorted[0].name, members: sorted.map(DuplicateMember.app)))
        }

        let tools = developerPackages.filter {
            globalToolManagers.contains($0.manager) && !bundledPackages.contains($0.name.lowercased()) && !isSelfEntry($0)
        }
        // npm, pnpm and Yarn install into the same global command namespace.
        let toolsByName = Dictionary(grouping: tools) { package in
            "\(family(of: package.manager)):\(package.name.lowercased())"
        }
        for (key, copies) in toolsByName where copies.count > 1 {
            groups.append(DuplicateGroup(id: "package:\(key)", kind: .packageCopies, title: copies[0].name,
                                         members: sortedByLocation(copies).map(DuplicateMember.developer)))
        }

        let formulae = homebrewPackages.filter { $0.kind == .formula && !$0.isDependency }
        let runtimes = developerPackages.filter { runtimeManagers.contains($0.manager) }
        let runtimesByName = Dictionary(grouping: runtimes) { "\($0.manager.rawValue):\($0.name.lowercased())" }
        for (key, versions) in runtimesByName {
            let sorted = versions.sorted { VersionComparator.compare($0.currentVersion, $1.currentVersion) == .orderedDescending }
            var members = sorted.map(DuplicateMember.developer)
            // Homebrew's Node.js belongs with the other Node.js versions, unless
            // it is already listed as one of them.
            if sorted[0].manager == .node, !sorted.contains(where: { isHomebrewInstalled($0.executablePath) }) {
                members += formulae.filter { homebrewBaseName($0.token) == "node" }.map(DuplicateMember.homebrew)
            }
            guard members.count > 1 else { continue }
            groups.append(DuplicateGroup(id: "versions:\(key)", kind: .runtimeVersions,
                                         title: sorted[0].name, members: members))
        }

        for formula in formulae {
            let token = homebrewBaseName(formula.token)
            let matches = developerPackages.filter { package in
                switch package.manager {
                case .deno: return token == "deno"
                case .bun: return token == "bun"
                case let manager where globalToolManagers.contains(manager):
                    return package.name.lowercased() == token && !bundledPackages.contains(token)
                default: return false
                }
            }
            // Homebrew's own Deno or Bun also appears as a runtime; it is this
            // formula, not a second install. Global packages run by Homebrew's
            // npm are separate installs and still count.
            .filter { package in
                ![.deno, .bun].contains(package.manager) || !isHomebrewInstalled(package.executablePath)
            }
            guard !matches.isEmpty else { continue }
            groups.append(DuplicateGroup(id: "tools:\(formula.token)", kind: .twoInstallers, title: formula.displayName,
                                         members: [.homebrew(formula)] + sortedByLocation(matches).map(DuplicateMember.developer)))
        }

        let order: [DuplicateGroup.Kind] = [.appCopies, .packageCopies, .twoInstallers, .runtimeVersions]
        return groups.sorted {
            let left = order.firstIndex(of: $0.kind) ?? 0, right = order.firstIndex(of: $1.kind) ?? 0
            return left != right ? left < right : $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    /// pnpm and Yarn list themselves as a package. That may be the same
    /// install npm already lists, so removing it as a copy could remove the
    /// only one.
    static func isSelfEntry(_ package: DeveloperPackage) -> Bool {
        switch package.manager {
        case .pnpm: package.name.lowercased() == "pnpm"
        case .yarn: package.name.lowercased() == "yarn"
        default: false
        }
    }

    static func family(of manager: DeveloperPackageManager) -> String {
        [.npm, .pnpm, .yarn].contains(manager) ? "javascript" : manager.rawValue
    }

    /// "python@3.12" and "node@22" are versions of "python" and "node".
    static func homebrewBaseName(_ token: String) -> String {
        String(token.split(separator: "@").first ?? Substring(token)).lowercased()
    }

    private static func sortedByLocation(_ packages: [DeveloperPackage]) -> [DeveloperPackage] {
        packages.sorted { ($0.installationContext ?? $0.executablePath) < ($1.installationContext ?? $1.executablePath) }
    }
}
