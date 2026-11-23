import Foundation

struct DeveloperPackageUninstallPlan: Sendable {
    enum Action: Sendable, Equatable {
        /// Runs a command as the current user.
        case command(URL, [String])
        /// Runs a command as root after macOS asks for an administrator password.
        case administratorCommand(URL, [String])
        /// Moves files or folders the tool owns to the Trash.
        case trash([String])
        /// Deletes the simulator runtime disk images for one platform and build.
        case simulatorRuntime(xcrun: String, platform: String, build: String)
    }

    let action: Action
    let failureMessage: String

    init(action: Action, failureMessage: String = "Package uninstall failed") {
        self.action = action
        self.failureMessage = failureMessage
    }

    init(executable: URL, arguments: [String], failureMessage: String) {
        self.init(action: .command(executable, arguments), failureMessage: failureMessage)
    }

    var executable: URL {
        switch action {
        case let .command(executable, _), let .administratorCommand(executable, _): executable
        case .trash: URL(fileURLWithPath: "/usr/bin/true")
        case let .simulatorRuntime(xcrun, _, _): URL(fileURLWithPath: xcrun)
        }
    }

    var arguments: [String] {
        switch action {
        case let .command(_, arguments), let .administratorCommand(_, arguments): arguments
        case let .trash(paths): paths
        case let .simulatorRuntime(_, platform, build): ["simctl", "runtime", "delete", platform, build]
        }
    }
}

enum DeveloperPackageUninstallAdapters {
    static func supports(_ package: DeveloperPackage) -> Bool {
        (try? plan(for: package)) != nil
    }

    static func plan(for package: DeveloperPackage) throws -> DeveloperPackageUninstallPlan {
        let identifier = package.registryIdentifier ?? package.name
        switch package.manager {
        case .node:
            if let nvmDirectory = nvmDirectory(for: package.executablePath) {
                return DeveloperPackageUninstallPlan(
                    executable: URL(fileURLWithPath: "/bin/zsh"),
                    arguments: [
                        "-c",
                        #"source "$1/nvm.sh" && nvm uninstall "$2""#,
                        "upkeep-node-uninstall",
                        nvmDirectory,
                        package.currentVersion
                    ],
                    failureMessage: "Node.js uninstall failed"
                )
            }
            if let plan = homebrewPlan(for: package.executablePath) { return plan }
            if package.executablePath == "/usr/local/bin/node", installerReceiptExists("org.nodejs.node.pkg") {
                // Files the nodejs.org installer places, per its uninstall instructions.
                let paths = ["bin/node", "bin/npm", "bin/npx", "bin/corepack", "lib/node_modules/npm",
                             "lib/node_modules/corepack", "include/node", "share/doc/node",
                             "share/man/man1/node.1", "share/systemtap/tapset/node.stp"].map { "/usr/local/" + $0 }
                return removeInstalledPackage(paths: paths, receipt: "org.nodejs.node.pkg")
            }
            throw AdapterError.unknownInstallation(package.name)
        case .bun:
            guard package.name == "Bun" else {
                return command(package, ["remove", "--global", identifier])
            }
            if let plan = homebrewPlan(for: package.executablePath) { return plan }
            if let home = installFolder(package.executablePath, suffix: "/.bun/bin/bun", folder: "/.bun") {
                return DeveloperPackageUninstallPlan(action: .trash([home]))
            }
            throw AdapterError.unknownInstallation(package.name)
        case .deno:
            if let plan = homebrewPlan(for: package.executablePath) { return plan }
            if let home = installFolder(package.executablePath, suffix: "/.deno/bin/deno", folder: "/.deno") {
                return DeveloperPackageUninstallPlan(action: .trash([home]))
            }
            throw AdapterError.unknownInstallation(package.name)
        case .npm:
            return command(package, ["uninstall", "-g", package.name])
        case .pnpm:
            return command(package, ["remove", "-g", package.name])
        case .yarn:
            guard package.name == "Yarn" else { return command(package, ["global", "remove", package.name]) }
            if let plan = homebrewPlan(for: package.executablePath) { return plan }
            let resolved = URL(fileURLWithPath: package.executablePath).resolvingSymlinksInPath().path
            let folder = URL(fileURLWithPath: package.executablePath).deletingLastPathComponent()
            if resolved.contains("/node_modules/corepack/") {
                return DeveloperPackageUninstallPlan(
                    executable: folder.appendingPathComponent("corepack"), arguments: ["disable", "yarn"],
                    failureMessage: "Yarn uninstall failed")
            }
            if resolved.contains("/node_modules/yarn/"),
               FileManager.default.isExecutableFile(atPath: folder.appendingPathComponent("npm").path) {
                return DeveloperPackageUninstallPlan(
                    executable: folder.appendingPathComponent("npm"), arguments: ["uninstall", "-g", "yarn"],
                    failureMessage: "Yarn uninstall failed")
            }
            throw AdapterError.unknownInstallation(package.name)
        case .vsCode:
            return command(package, ["--uninstall-extension", identifier])
        case .uv:
            if package.registryIdentifier?.hasPrefix("python:") == true {
                return command(package, ["python", "uninstall", package.currentVersion])
            }
            return command(package, ["tool", "uninstall", identifier])
        case .pipx:
            return command(package, ["uninstall", identifier])
        case .python:
            return command(package, ["-m", "pip", "uninstall", "--yes", package.name])
        case .rubyGems:
            return command(package, ["uninstall", package.name, "--version", package.currentVersion, "--executables"])
        case .rustup:
            return command(package, ["toolchain", "uninstall", identifier])
        case .cargo:
            return command(package, ["uninstall", identifier])
        case .githubCLI:
            return command(package, ["extension", "remove", identifier])
        case .go:
            if package.registryIdentifier == "go-runtime" {
                if let plan = homebrewPlan(for: package.executablePath) { return plan }
                if package.executablePath.hasPrefix("/usr/local/go/"), installerReceiptExists("org.golang.go.pkg") {
                    return removeInstalledPackage(paths: ["/usr/local/go", "/etc/paths.d/go"], receipt: "org.golang.go.pkg")
                }
                throw AdapterError.unknownInstallation(package.name)
            }
            // Go has no uninstall command: find the binary in GOBIN (or GOPATH/bin)
            // whose build info names this package, and move it to the Trash.
            return DeveloperPackageUninstallPlan(
                executable: URL(fileURLWithPath: "/bin/zsh"),
                arguments: ["-c", goToolRemovalScript, "upkeep-go-uninstall", package.executablePath, package.name],
                failureMessage: "No installed binary was found for \(package.name)."
            )
        case .composer:
            return command(package, ["global", "remove", identifier, "--no-interaction"])
        case .dotnet:
            return command(package, ["tool", "uninstall", "--global", identifier])
        case .macPorts:
            return DeveloperPackageUninstallPlan(
                action: .administratorCommand(URL(fileURLWithPath: package.executablePath), ["uninstall", identifier]))
        case .nix:
            return command(package, ["profile", "remove", identifier])
        case .mise:
            return command(package, ["uninstall", "\(identifier)@\(package.currentVersion)"])
        case .asdf:
            return command(package, ["uninstall", identifier, package.currentVersion])
        case .volta:
            return command(package, ["uninstall", identifier])
        case .fnm:
            return command(package, ["uninstall", package.currentVersion])
        case .dockerImages:
            // Without --force, Docker refuses while a container still uses the image.
            return command(package, ["image", "rm", identifier])
        case .krew:
            return command(package, ["uninstall", identifier])
        case .juliaup:
            return command(package, ["remove", identifier])
        case .opam:
            return command(package, ["remove", "-y", identifier])
        case .dart:
            return command(package, ["pub", "global", "deactivate", identifier])
        case .pyenv, .rbenv:
            return command(package, ["uninstall", "-f", package.currentVersion])
        case .azureCLI:
            return command(package, ["extension", "remove", "--name", identifier])
        case .pixi:
            let parts = identifier.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { throw AdapterError.unsupportedPackage(package.name) }
            if parts[0] == parts[1] { return command(package, ["global", "uninstall", parts[0]]) }
            return command(package, ["global", "remove", "--environment", parts[0], parts[1]])
        case .poetry:
            // Only a folder dedicated to Poetry, never a broad POETRY_HOME such as the home folder.
            guard let home = installFolder(package.executablePath, suffix: "/venv/bin/poetry", folder: ""),
                  URL(fileURLWithPath: home).lastPathComponent.lowercased().contains("poetry"),
                  home != NSHomeDirectory()
            else {
                throw AdapterError.unknownInstallation(package.name)
            }
            var paths = [home]
            if let link = linkedLauncher("/.local/bin/poetry", pointingInto: home) { paths.append(link) }
            return DeveloperPackageUninstallPlan(action: .trash(paths))
        case .flutter:
            if let plan = homebrewPlan(for: package.executablePath) { return plan }
            guard let root = installFolder(package.executablePath, suffix: "/bin/flutter", folder: ""),
                  URL(fileURLWithPath: root).lastPathComponent == "flutter",
                  FileManager.default.fileExists(atPath: root + "/packages/flutter_tools")
            else { throw AdapterError.unknownInstallation(package.name) }
            return DeveloperPackageUninstallPlan(action: .trash([root]))
        case .ghcup:
            return command(package, ["rm", identifier, package.currentVersion])
        case .swiftly:
            return command(package, ["uninstall", identifier, "--assume-yes"])
        case .conda:
            // Removing these from the base environment would break conda itself.
            guard !["conda", "python"].contains(package.name) else { throw AdapterError.unsupportedPackage(package.name) }
            return command(package, ["remove", "-n", "base", "-y", package.name])
        case .sdkman:
            return DeveloperPackageUninstallPlan(
                executable: URL(fileURLWithPath: "/bin/bash"),
                arguments: ["-c", #"source "$1" && sdk uninstall "$2" "$3" --force < /dev/null"#,
                            "upkeep-sdkman-uninstall", package.executablePath, identifier, package.currentVersion],
                failureMessage: "SDKMAN uninstall failed"
            )
        case .claudeCode:
            if let plan = homebrewPlan(for: package.executablePath) { return plan }
            guard let home = installFolder(package.executablePath, suffix: "/.local/bin/claude", folder: "") else {
                throw AdapterError.unknownInstallation(package.name)
            }
            // The native installer's launcher and its versions folder.
            return DeveloperPackageUninstallPlan(action: .trash([package.executablePath, home + "/.local/share/claude"]))
        case .nvm:
            let directory = package.installationContext
                ?? URL(fileURLWithPath: package.executablePath).deletingLastPathComponent().path
            guard FileManager.default.fileExists(atPath: directory + "/nvm.sh") else {
                throw AdapterError.unknownInstallation(package.name)
            }
            return DeveloperPackageUninstallPlan(action: .trash([directory]))
        case .googleCloud:
            if let plan = homebrewPlan(for: package.executablePath) { return plan }
            let root = URL(fileURLWithPath: package.executablePath).resolvingSymlinksInPath()
                .deletingLastPathComponent().deletingLastPathComponent()
            guard root.lastPathComponent == "google-cloud-sdk", root.path.hasPrefix(NSHomeDirectory() + "/") else {
                throw AdapterError.unknownInstallation(package.name)
            }
            return DeveloperPackageUninstallPlan(action: .trash([root.path]))
        case .xcodeSimulators:
            return DeveloperPackageUninstallPlan(
                action: .simulatorRuntime(xcrun: package.executablePath, platform: identifier, build: package.currentVersion),
                failureMessage: "Simulator runtime uninstall failed")
        }
    }

    /// `brew uninstall` when the executable resolves into a Homebrew Cellar or Caskroom.
    static func homebrewPlan(for executablePath: String) -> DeveloperPackageUninstallPlan? {
        let resolved = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath().path
        for (marker, isCask) in [("/Cellar/", false), ("/Caskroom/", true)] {
            guard let range = resolved.range(of: marker) else { continue }
            let prefix = String(resolved[..<range.lowerBound])
            guard let token = resolved[range.upperBound...].split(separator: "/").first.map(String.init),
                  ["/opt/homebrew", "/usr/local", "/usr/local/Homebrew"].contains(prefix) || prefix.hasSuffix("/homebrew")
            else { continue }
            let brew = (prefix == "/usr/local/Homebrew" ? "/usr/local" : prefix) + "/bin/brew"
            return DeveloperPackageUninstallPlan(
                action: .command(URL(fileURLWithPath: brew), ["uninstall"] + (isCask ? ["--cask"] : []) + [token]),
                failureMessage: "Homebrew uninstall failed")
        }
        return nil
    }

    private static func installerReceiptExists(_ identifier: String) -> Bool {
        FileManager.default.fileExists(atPath: "/var/db/receipts/\(identifier).bom")
    }

    private static func removeInstalledPackage(paths: [String], receipt: String) -> DeveloperPackageUninstallPlan {
        DeveloperPackageUninstallPlan(
            action: .administratorCommand(URL(fileURLWithPath: "/bin/sh"), [
                "-c", #"receipt="$1"; shift; /bin/rm -rf -- "$@" && /usr/sbin/pkgutil --forget "$receipt" >/dev/null 2>&1; exit 0"#,
                "upkeep-uninstall", receipt
            ] + paths),
            failureMessage: "Uninstall failed")
    }

    /// The folder that ends with `folder`, when `executablePath` ends with `suffix`.
    private static func installFolder(_ executablePath: String, suffix: String, folder: String) -> String? {
        guard executablePath.hasSuffix(suffix) else { return nil }
        let base = String(executablePath.dropLast(suffix.count))
        guard !base.isEmpty else { return nil }
        return base + folder
    }

    private static func linkedLauncher(_ homeRelativePath: String, pointingInto folder: String) -> String? {
        let link = NSHomeDirectory() + homeRelativePath
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: link) else { return nil }
        let resolved = URL(fileURLWithPath: destination, relativeTo: URL(fileURLWithPath: link).deletingLastPathComponent())
            .standardizedFileURL.path
        return resolved.hasPrefix(folder + "/") ? link : nil
    }

    private static let goToolRemovalScript = #"""
        go="$1"; target="$2"
        bin="$("$go" env GOBIN)"
        [ -z "$bin" ] && bin="$("$go" env GOPATH | cut -d: -f1)/bin"
        [ "$bin" = "/bin" ] && bin="$HOME/go/bin"
        for file in "$bin"/*(N); do
            [ -f "$file" ] || continue
            if "$go" version -m "$file" 2>/dev/null | awk '$1 == "path" { print $2; exit }' | grep -qxF -- "$target"; then
                mv -- "$file" "$HOME/.Trash/$(basename "$file") $(date +%Y%m%d%H%M%S)" && exit 0
            fi
        done
        exit 1
        """#

    private static func command(
        _ package: DeveloperPackage,
        _ arguments: [String],
        _ failureMessage: String = "Package uninstall failed"
    ) -> DeveloperPackageUninstallPlan {
        DeveloperPackageUninstallPlan(
            executable: URL(fileURLWithPath: package.executablePath),
            arguments: arguments,
            failureMessage: failureMessage
        )
    }

    enum AdapterError: LocalizedError {
        case unsupportedPackage(String)
        case requiresManagedInstallation(String, String)
        case configurationManaged(DeveloperPackageManager)
        case unknownInstallation(String)

        var errorDescription: String? {
            switch self {
            case let .unsupportedPackage(name):
                "Upkeep cannot safely uninstall \(name) automatically."
            case let .requiresManagedInstallation(name, manager):
                "\(name) can only be uninstalled automatically when it is managed by \(manager)."
            case let .configurationManaged(manager):
                "\(manager.rawValue) tools must be removed from their configuration before uninstalling."
            case let .unknownInstallation(name):
                "Upkeep cannot tell how \(name) was installed, so it cannot uninstall it safely."
            }
        }
    }
}
