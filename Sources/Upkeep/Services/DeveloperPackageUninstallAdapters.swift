import Foundation

struct DeveloperPackageUninstallPlan: Sendable {
    let executable: URL
    let arguments: [String]
    let failureMessage: String
}

enum DeveloperPackageUninstallAdapters {
    static func supports(_ package: DeveloperPackage) -> Bool {
        (try? plan(for: package)) != nil
    }

    static func plan(for package: DeveloperPackage) throws -> DeveloperPackageUninstallPlan {
        switch package.manager {
        case .node:
            guard let nvmDirectory = nvmDirectory(for: package.executablePath) else {
                throw AdapterError.requiresManagedInstallation("Node.js", "NVM")
            }
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
        case .bun:
            guard package.name != "Bun" else { throw AdapterError.unsupportedPackage(package.name) }
            return command(package, ["remove", "--global", package.registryIdentifier ?? package.name])
        case .deno:
            throw AdapterError.unsupportedPackage(package.name)
        case .npm:
            guard package.name.lowercased() != "npm" else { throw AdapterError.unsupportedPackage(package.name) }
            return command(package, ["uninstall", "-g", package.name])
        case .pnpm:
            guard package.name.lowercased() != "pnpm" else { throw AdapterError.unsupportedPackage(package.name) }
            return command(package, ["remove", "-g", package.name])
        case .yarn:
            guard package.name != "Yarn" else { throw AdapterError.unsupportedPackage(package.name) }
            return command(package, ["global", "remove", package.name])
        case .vsCode:
            return command(package, ["--uninstall-extension", package.registryIdentifier ?? package.name])
        case .uv:
            if package.registryIdentifier?.hasPrefix("python:") == true {
                return command(package, ["python", "uninstall", package.currentVersion])
            }
            return command(package, ["tool", "uninstall", package.registryIdentifier ?? package.name])
        case .pipx:
            return command(package, ["uninstall", package.registryIdentifier ?? package.name])
        case .python:
            return command(package, ["-m", "pip", "uninstall", "--yes", package.name])
        case .rubyGems:
            return command(package, ["uninstall", package.name, "--version", package.currentVersion, "--executables"])
        case .rustup:
            return command(package, ["toolchain", "uninstall", package.registryIdentifier ?? package.name])
        case .cargo:
            return command(package, ["uninstall", package.registryIdentifier ?? package.name])
        case .githubCLI:
            return command(package, ["extension", "remove", package.registryIdentifier ?? package.name])
        case .go:
            throw AdapterError.unsupportedPackage(package.name)
        case .composer:
            return command(package, ["global", "remove", package.registryIdentifier ?? package.name, "--no-interaction"])
        case .dotnet:
            return command(package, ["tool", "uninstall", "--global", package.registryIdentifier ?? package.name])
        case .macPorts:
            throw AdapterError.unsupportedPackage(package.name)
        case .nix:
            return command(package, ["profile", "remove", package.registryIdentifier ?? package.name])
        case .mise, .asdf:
            throw AdapterError.configurationManaged(package.manager)
        case .volta:
            return command(package, ["uninstall", package.registryIdentifier ?? package.name])
        case .fnm:
            return command(package, ["uninstall", package.currentVersion])
        case .dockerImages:
            // Containers may still use the image; leave removal to Docker.
            throw AdapterError.unsupportedPackage(package.name)
        case .krew:
            return command(package, ["uninstall", package.registryIdentifier ?? package.name])
        case .juliaup:
            return command(package, ["remove", package.registryIdentifier ?? package.name])
        case .opam:
            return command(package, ["remove", "-y", package.registryIdentifier ?? package.name])
        case .dart:
            return command(package, ["pub", "global", "deactivate", package.registryIdentifier ?? package.name])
        case .pixi, .poetry, .flutter, .ghcup, .swiftly, .conda, .sdkman, .claudeCode, .nvm:
            // Shared environments, SDKs and toolchains are removed with the tool itself.
            throw AdapterError.unsupportedPackage(package.name)
        }
    }

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

        var errorDescription: String? {
            switch self {
            case let .unsupportedPackage(name):
                "Upkeep cannot safely uninstall \(name) automatically."
            case let .requiresManagedInstallation(name, manager):
                "\(name) can only be uninstalled automatically when it is managed by \(manager)."
            case let .configurationManaged(manager):
                "\(manager.rawValue) tools must be removed from their configuration before uninstalling."
            }
        }
    }
}
