import Foundation

enum DeveloperPackageInstallPlan: Sendable {
    case node
    case command(executable: URL, arguments: [String], failureMessage: String)
}

struct DeveloperPackageInstallAdapter: Sendable {
    let makePlan: @Sendable (DeveloperPackage, String) throws -> DeveloperPackageInstallPlan
}

enum DeveloperPackageInstallAdapters {
    static func plan(
        for package: DeveloperPackage,
        version: String
    ) throws -> DeveloperPackageInstallPlan {
        guard let adapter = adapters[package.manager] else {
            throw AdapterError.unsupported(package.manager)
        }
        return try adapter.makePlan(package, version)
    }

    private static let adapters: [DeveloperPackageManager: DeveloperPackageInstallAdapter] = [
        .node: adapter { _, _ in .node },
        .bun: adapter { package, version in
            if package.name == "Bun" {
                guard version == package.latestVersion else {
                    throw AdapterError.latestVersionOnly("Bun")
                }
                return command(package, ["upgrade"], "Bun update failed")
            }
            return command(package, ["add", "--global", "\(package.name)@\(version)"])
        },
        .deno: adapter { command($0, ["upgrade", "--version", $1]) },
        .npm: adapter { command($0, ["install", "-g", "\($0.name)@\($1)"]) },
        .pnpm: adapter { command($0, ["add", "-g", "\($0.name)@\($1)"]) },
        .yarn: adapter { package, version in
            if package.name == "Yarn" {
                let executable = URL(fileURLWithPath: package.executablePath)
                    .deletingLastPathComponent()
                    .appendingPathComponent("corepack")
                return .command(
                    executable: executable,
                    arguments: ["install", "--global", "yarn@\(version)"],
                    failureMessage: "Yarn update failed"
                )
            }
            return command(package, ["global", "add", "\(package.name)@\(version)"])
        },
        .vsCode: adapter {
            command($0, ["--install-extension", "\($0.registryIdentifier ?? $0.name)@\($1)", "--force"])
        },
        .uv: adapter { package, version in
            if let identifier = package.registryIdentifier, identifier.hasPrefix("python:") {
                let minor = String(identifier.dropFirst("python:".count))
                return command(
                    package,
                    version == package.latestVersion
                        ? ["--preview", "python", "upgrade", minor]
                        : ["python", "install", version]
                )
            }
            return command(package, ["tool", "install", "\(package.registryIdentifier ?? package.name)==\(version)", "--force"])
        },
        .pipx: adapter { command($0, ["install", "\($0.registryIdentifier ?? $0.name)==\($1)", "--force"]) },
        .python: adapter { command($0, ["-m", "pip", "install", "--user", "\($0.name)==\($1)"]) },
        .rubyGems: adapter { command($0, ["install", $0.name, "--version", $1, "--user-install"]) },
        .rustup: adapter { package, version in
            command(
                package,
                version == package.latestVersion
                    ? ["update", package.registryIdentifier ?? package.name]
                    : ["toolchain", "install", version]
            )
        },
        .cargo: adapter { command($0, ["install", $0.name, "--version", $1, "--force"]) },
        .githubCLI: adapter { command($0, ["extension", "install", $0.registryIdentifier ?? $0.name, "--pin", $1, "--force"]) },
        .go: adapter { command($0, ["install", "\($0.name)@\($1)"]) },
        .composer: adapter { command($0, ["global", "require", "\($0.registryIdentifier ?? $0.name):\($1)", "--no-interaction"]) },
        .dotnet: adapter { command($0, ["tool", "update", "--global", $0.registryIdentifier ?? $0.name, "--version", $1]) },
        .macPorts: adapter { package, _ in command(package, ["upgrade", package.registryIdentifier ?? package.name]) },
        .nix: adapter { package, _ in command(package, ["profile", "upgrade", package.registryIdentifier ?? package.name]) },
        .mise: adapter { command($0, ["use", "--global", "\($0.registryIdentifier ?? $0.name)@\($1)"]) },
        .asdf: adapter { package, version in
            let commandText = #""$1" install "$2" "$3" && "$1" set --home "$2" "$3""#
            return .command(
                executable: URL(fileURLWithPath: "/bin/zsh"),
                arguments: [
                    "-c", commandText, "upkeep-asdf", package.executablePath,
                    package.registryIdentifier ?? package.name, version
                ],
                failureMessage: "asdf update failed"
            )
        },
        .volta: adapter { command($0, ["install", "\($0.registryIdentifier ?? $0.name)@\($1)"]) },
        .fnm: adapter { command($0, ["install", $1]) },
        .dockerImages: adapter { package, _ in command(package, ["pull", package.registryIdentifier ?? package.name]) }
    ]

    private static func adapter(
        _ makePlan: @escaping @Sendable (DeveloperPackage, String) throws -> DeveloperPackageInstallPlan
    ) -> DeveloperPackageInstallAdapter {
        DeveloperPackageInstallAdapter(makePlan: makePlan)
    }

    private static func command(
        _ package: DeveloperPackage,
        _ arguments: [String],
        _ failureMessage: String = "Package update failed"
    ) -> DeveloperPackageInstallPlan {
        .command(
            executable: URL(fileURLWithPath: package.executablePath),
            arguments: arguments,
            failureMessage: failureMessage
        )
    }

    enum AdapterError: LocalizedError {
        case unsupported(DeveloperPackageManager)
        case latestVersionOnly(String)

        var errorDescription: String? {
            switch self {
            case let .unsupported(manager): "No install adapter is registered for \(manager.rawValue)."
            case let .latestVersionOnly(name): "\(name) can only upgrade directly to its latest stable release."
            }
        }
    }
}
