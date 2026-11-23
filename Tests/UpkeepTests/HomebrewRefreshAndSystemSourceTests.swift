import Foundation
import Testing
@testable import Upkeep

@Test func brewEnvFilesParseLikeHomebrew() {
    let values = HomebrewSettings.parseBrewEnv("""
        # Homebrew settings
        HOMEBREW_NO_AUTO_UPDATE=1
        export HOMEBREW_AUTO_UPDATE_SECS="7200"
        HOMEBREW_NO_ENV_HINTS = 1
        not a setting
        """)
    #expect(values["HOMEBREW_NO_AUTO_UPDATE"] == "1")
    #expect(values["HOMEBREW_AUTO_UPDATE_SECS"] == "7200")
    #expect(values["HOMEBREW_NO_ENV_HINTS"] == "1")
}

@Test func homebrewRefreshHonoursOptOutAndInterval() throws {
    let fileManager = FileManager.default
    let home = fileManager.temporaryDirectory.appendingPathComponent("Upkeep-BrewEnv-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: home) }
    let brew = URL(fileURLWithPath: "/nonexistent-prefix/bin/brew")

    let defaults = HomebrewSettings.load(brew: brew, environment: [:], home: home)
    #expect(!defaults.autoUpdateDisabled)
    #expect(defaults.autoUpdateInterval == HomebrewCatalogRefresh.defaultInterval)

    // `brew update --auto-update` ignores this opt-out, so Upkeep must honour it.
    #expect(HomebrewSettings.load(brew: brew, environment: ["HOMEBREW_NO_AUTO_UPDATE": "1"], home: home).autoUpdateDisabled)

    try fileManager.createDirectory(at: home.appendingPathComponent(".homebrew"), withIntermediateDirectories: true)
    try "HOMEBREW_NO_AUTO_UPDATE=1\nHOMEBREW_AUTO_UPDATE_SECS=600\n"
        .write(to: home.appendingPathComponent(".homebrew/brew.env"), atomically: true, encoding: .utf8)
    let fromFile = HomebrewSettings.load(brew: brew, environment: [:], home: home)
    #expect(fromFile.autoUpdateDisabled)
    #expect(fromFile.autoUpdateInterval == 600)
    // The environment takes precedence over brew.env.
    #expect(HomebrewSettings.load(brew: brew, environment: ["HOMEBREW_AUTO_UPDATE_SECS": "30"], home: home).autoUpdateInterval == 30)
}

@Test func softwareUpdateListsEveryProductType() {
    #expect(MacOSUpdateClient.updateListingArguments == ["--list"])
    let updates = parseSoftwareUpdateList("""
        Software Update Tool

        Finding available software
        Software Update found the following new or updated software:
        * Label: Command Line Tools for Xcode-26.2
        \tTitle: Command Line Tools for Xcode, Version: 26.2, Size: 922475KiB, Recommended: YES,
        * Label: Safari26.2TahoeAuto-26.2
        \tTitle: Safari, Version: 26.2, Size: 199877KiB, Recommended: YES,
        * Label: macOS Tahoe 26.2-25C56
        \tTitle: macOS Tahoe 26.2, Version: 26.2, Size: 3412345KiB, Recommended: YES, Action: restart,
        """)
    #expect(updates.map(\.title) == ["Command Line Tools for Xcode", "Safari", "macOS Tahoe 26.2"])
    #expect(updates.map(\.requiresRestart) == [false, false, true])
}

@Test func nvmReadsItsVersionAndUpdatesWithGit() throws {
    #expect(nvmVersion(packageJSON: Data(#"{"name":"nvm","version":"0.39.0"}"#.utf8)) == "0.39.0")
    #expect(nvmVersion(packageJSON: Data("{}".utf8)) == nil)
    let nvm = DeveloperPackage(name: "nvm", currentVersion: "0.39.0", latestVersion: "0.41.0", manager: .nvm,
        executablePath: "/Users/me/.nvm/nvm.sh", registryIdentifier: "nvm-sh/nvm")
    guard realGitExecutable() != nil else { return }
    guard case let .command(executable, arguments, _) = try DeveloperPackageInstallAdapters.plan(for: nvm, version: "0.41.0") else {
        Issue.record("Expected a git command")
        return
    }
    #expect(executable.path == "/bin/bash")
    #expect(arguments.suffix(2) == ["/Users/me/.nvm", "0.41.0"])
    #expect(!arguments.contains("/usr/bin/git"))
}
