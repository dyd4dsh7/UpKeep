import Foundation
import Testing
@testable import Upkeep

// Shapes from `brew info --json=v2 --installed` on a real Mac: Homebrew reports
// auto-updating casks as current even when the cask is newer.
private let inventory = #"""
{"formulae":[],"casks":[
 {"token":"discord","name":["Discord"],"desc":null,"homepage":"https://discord.com/","version":"0.0.423","outdated":false,
  "installed":"0.0.416","auto_updates":true,"tap":"homebrew/cask","artifacts":[{"app":["Discord.app"]},{"zap":[{"trash":["~/Library/Caches/com.hnc.Discord"]}]}]},
 {"token":"docker-desktop","name":["Docker Desktop"],"desc":null,"homepage":"https://www.docker.com/","version":"4.99.0,245822","outdated":false,
  "installed":"4.93.0,240920","auto_updates":true,"tap":"homebrew/cask","artifacts":[{"app":["Docker.app"]},{"binary":["$APPDIR/Docker.app/Contents/Resources/bin/docker"]}]},
 {"token":"bruno","name":["Bruno"],"desc":null,"homepage":null,"version":"4.3.0","outdated":false,
  "installed":"4.2.1","auto_updates":true,"tap":"homebrew/cask","artifacts":[{"app":["Bruno.app"]}]},
 {"token":"beta-tool","name":["Beta Tool"],"desc":null,"homepage":null,"version":"2.0.0-beta.1","outdated":false,
  "installed":"1.0.0","auto_updates":true,"tap":"homebrew/cask","artifacts":[{"app":["Beta Tool.app"]}]},
 {"token":"utm","name":["UTM"],"desc":null,"homepage":null,"version":"5.0.9-2","outdated":true,
  "installed":"5.0.8","auto_updates":null,"tap":"homebrew/cask","artifacts":[{"app":["UTM.app"]}]}
]}
"""#

private func app(_ name: String, _ version: String, build: String? = nil) -> InstalledApp {
    InstalledApp(name: name, bundleIdentifier: "com.example.\(name.lowercased())", installedVersion: version,
        buildVersion: build, url: URL(fileURLWithPath: "/Applications/\(name).app"),
        sparkleFeedURL: nil, githubRepository: nil, hasAppStoreReceipt: false)
}

@Test func caskInventoryRecordsAutoUpdatesAndAppBundles() throws {
    let packages = Dictionary(uniqueKeysWithValues: try decodeHomebrewInventory(Data(inventory.utf8)).map { ($0.token, $0) })
    #expect(packages["discord"]?.autoUpdates == true)
    #expect(packages["discord"]?.isOutdated == false)
    #expect(packages["docker-desktop"]?.appArtifactNames == ["Docker.app"])
    #expect(packages["utm"]?.autoUpdates == false)
    // Prerelease cask versions are only compared when prereleases are included.
    #expect(packages["beta-tool"]?.autoUpdates == false)
    let withPrereleases = try decodeHomebrewInventory(Data(inventory.utf8), includePrereleases: true)
    #expect(withPrereleases.first { $0.token == "beta-tool" }?.autoUpdates == true)
}

@Test func autoUpdatingCasksCompareWithTheInstalledApp() throws {
    let packages = Dictionary(uniqueKeysWithValues: try decodeHomebrewInventory(Data(inventory.utf8)).map { ($0.token, $0) })
    let discord = try #require(packages["discord"])

    // The app updated itself to the cask version: current, with its real version.
    let current = discord.reconciled(with: app("Discord", "0.0.423"))
    #expect(!current.isOutdated)
    #expect(current.installedVersion == "0.0.423")

    // The app is behind the cask, which `brew outdated` alone would not report.
    let behind = discord.reconciled(with: app("Discord", "0.0.410"))
    #expect(behind.isOutdated)
    #expect(behind.installedVersion == "0.0.410")

    // Docker updated itself past the cask's recorded and current versions.
    let docker = try #require(packages["docker-desktop"])
    #expect(!docker.reconciled(with: app("Docker", "4.100.0", build: "246961")).isOutdated)
    // Same marketing version, older build than the cask's "version,build".
    #expect(docker.reconciled(with: app("Docker", "4.99.0", build: "240000")).isOutdated)
}

@Test func casksMatchTheirAppBundleNames() throws {
    let packages = Dictionary(uniqueKeysWithValues: try decodeHomebrewInventory(Data(inventory.utf8)).map { ($0.token, $0) })
    let index = UpdateScanner.appsByProductName([app("Docker", "4.100.0"), app("Discord", "0.0.423"), app("Postman", "1")])
    #expect(UpdateScanner.app(for: try #require(packages["docker-desktop"]), in: index)?.name == "Docker")
    #expect(UpdateScanner.app(for: try #require(packages["discord"]), in: index)?.name == "Discord")
    // A cask whose app is not installed has nothing to compare, so Homebrew's answer stands.
    #expect(UpdateScanner.app(for: try #require(packages["bruno"]), in: index) == nil)
    #expect(try #require(packages["bruno"]).isOutdated == false)
}
