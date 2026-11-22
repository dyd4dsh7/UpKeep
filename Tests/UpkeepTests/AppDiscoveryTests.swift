import Foundation
import Testing
@testable import Upkeep

@Test func applicationDiscoveryRereadsMetadataAfterInPlaceReplacement() async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("Upkeep-AppDiscovery-\(UUID().uuidString)", isDirectory: true)
    let appURL = root.appendingPathComponent("OpenCode.app", isDirectory: true)
    let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
    let infoURL = contentsURL.appendingPathComponent("Info.plist")
    try fileManager.createDirectory(at: contentsURL, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }

    try writeTestAppInfo(version: "1.17.20", to: infoURL)
    let before = try #require(await AppDiscovery.discover(at: appURL))
    #expect(before.installedVersion == "1.17.20")

    try writeTestAppInfo(version: "1.18.4", to: infoURL)
    let after = try #require(await AppDiscovery.discover(at: appURL))
    #expect(after.installedVersion == "1.18.4")
    #expect(after.bundleIdentifier == "ai.opencode.desktop")
}

@Test func applicationDiscoveryRecognizesElectronUpdaterOwnership() async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("Upkeep-ElectronDiscovery-\(UUID().uuidString)", isDirectory: true)
    let appURL = root.appendingPathComponent("Electron App.app", isDirectory: true)
    let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
    let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
    try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }

    try writeTestAppInfo(version: "1.0.0", to: contentsURL.appendingPathComponent("Info.plist"))
    try """
        provider: github
        owner: example
        repo: electron-app
        """.write(
            to: resourcesURL.appendingPathComponent("app-update.yml"),
            atomically: true,
            encoding: .utf8
        )

    let app = try #require(await AppDiscovery.discover(at: appURL))

    #expect(app.hasBuiltInUpdater)
    #expect(app.githubRepository == "example/electron-app")
    #expect(app.allowsHomebrewAdoption)
}

@Test func applicationDiscoveryReadsElectronGenericProviderFeed() async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("Upkeep-ElectronGeneric-\(UUID().uuidString)", isDirectory: true)
    let appURL = root.appendingPathComponent("Electron App.app", isDirectory: true)
    let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
    let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
    try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }

    try writeTestAppInfo(version: "1.0.0", to: contentsURL.appendingPathComponent("Info.plist"))
    try """
        provider: generic
        url: https://downloads.example.com/desktop
        """.write(
            to: resourcesURL.appendingPathComponent("app-update.yml"),
            atomically: true,
            encoding: .utf8
        )

    let app = try #require(await AppDiscovery.discover(at: appURL))

    #expect(app.hasBuiltInUpdater)
    #expect(app.githubRepository == nil)
    #expect(app.electronUpdateFeedURL?.absoluteString == "https://downloads.example.com/desktop/latest-mac.yml")
}

@Test func applicationDiscoveryRecognizesEmbeddedUpdaterFramework() async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("Upkeep-UpdaterFramework-\(UUID().uuidString)", isDirectory: true)
    let appURL = root.appendingPathComponent("Self Updating.app", isDirectory: true)
    let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
    let squirrelURL = contentsURL.appendingPathComponent(
        "Frameworks/Squirrel.framework",
        isDirectory: true
    )
    try fileManager.createDirectory(at: squirrelURL, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }
    try writeTestAppInfo(version: "1.0.0", to: contentsURL.appendingPathComponent("Info.plist"))

    let app = try #require(await AppDiscovery.discover(at: appURL))

    #expect(app.hasBuiltInUpdater)
    #expect(app.allowsHomebrewAdoption)
}

@Test func applicationDiscoveryRecognizesSteamLauncherShortcuts() async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("Upkeep-SteamShortcut-\(UUID().uuidString)", isDirectory: true)
    let appURL = root.appendingPathComponent("Steam Game.app", isDirectory: true)
    let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
    let executableURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
    try fileManager.createDirectory(at: executableURL, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }
    try writeTestAppInfo(version: "1.0", to: contentsURL.appendingPathComponent("Info.plist"))
    try """
        #!/bin/bash
        open steam://run/245470
        """.write(
            to: executableURL.appendingPathComponent("run.sh"),
            atomically: true,
            encoding: .utf8
        )

    let app = try #require(await AppDiscovery.discover(at: appURL))

    #expect(app.updateManagement == .steam)
    #expect(app.steamAppID == "245470")
    #expect(!app.allowsHomebrewAdoption)
}

private func writeTestAppInfo(version: String, to url: URL) throws {
    let info: [String: Any] = [
        "CFBundleDisplayName": "OpenCode",
        "CFBundleName": "OpenCode",
        "CFBundleIdentifier": "ai.opencode.desktop",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": version,
        "CFBundlePackageType": "APPL"
    ]
    let data = try PropertyListSerialization.data(
        fromPropertyList: info,
        format: .xml,
        options: 0
    )
    try data.write(to: url, options: .atomic)
}

@Test func updaterOwnershipAllowsOnlyDirectDeveloperDownloadsToBeAdopted() {
    func app(
        management: AppUpdateManagement,
        hasBuiltInUpdater: Bool = false
    ) -> InstalledApp {
        InstalledApp(
            name: "Example",
            bundleIdentifier: "com.example.app",
            installedVersion: "1.0",
            buildVersion: nil,
            url: URL(fileURLWithPath: "/Applications/Example.app"),
            sparkleFeedURL: nil,
            githubRepository: nil,
            hasAppStoreReceipt: management == .appStore,
            updateManagement: management,
            hasBuiltInUpdater: hasBuiltInUpdater
        )
    }

    #expect(app(management: .direct).allowsHomebrewAdoption)
    #expect(app(management: .direct, hasBuiltInUpdater: true).allowsHomebrewAdoption)
    #expect(!app(management: .appStore).allowsHomebrewAdoption)
    #expect(!app(management: .testFlight).allowsHomebrewAdoption)
    #expect(!app(management: .setapp).allowsHomebrewAdoption)
    #expect(!app(management: .microsoftAutoUpdate).allowsHomebrewAdoption)
}

@Test func classifiesProductionAndTestFlightReceiptsSeparately() {
    let production = AppDiscovery.updateManagement(
        bundleIdentifier: "com.example.app",
        appPath: "/Applications/Example.app",
        hasReceipt: true,
        receiptType: "Production",
        hasEmbeddedProvisioningProfile: false,
        hasSetappFramework: false,
        microsoftRegisteredPaths: []
    )
    let testFlight = AppDiscovery.updateManagement(
        bundleIdentifier: "com.example.app",
        appPath: "/Applications/Example Beta.app",
        hasReceipt: true,
        receiptType: "Sandbox",
        hasEmbeddedProvisioningProfile: true,
        hasSetappFramework: false,
        microsoftRegisteredPaths: []
    )
    let productionWithEmbeddedProfile = AppDiscovery.updateManagement(
        bundleIdentifier: "com.example.app",
        appPath: "/Applications/Example.app",
        hasReceipt: true,
        receiptType: "Production",
        hasEmbeddedProvisioningProfile: true,
        hasSetappFramework: false,
        microsoftRegisteredPaths: []
    )

    #expect(production == .appStore)
    #expect(testFlight == .testFlight)
    #expect(productionWithEmbeddedProfile == .appStore)
}

@Test func classifiesSetappByBundleIdentifierOrFramework() {
    let identifierMatch = AppDiscovery.updateManagement(
        bundleIdentifier: "com.example.app-setapp",
        appPath: "/Applications/Example.app",
        hasReceipt: false,
        receiptType: nil,
        hasEmbeddedProvisioningProfile: false,
        hasSetappFramework: false,
        microsoftRegisteredPaths: []
    )
    let frameworkMatch = AppDiscovery.updateManagement(
        bundleIdentifier: "com.example.app",
        appPath: "/Applications/Example.app",
        hasReceipt: false,
        receiptType: nil,
        hasEmbeddedProvisioningProfile: false,
        hasSetappFramework: true,
        microsoftRegisteredPaths: []
    )

    #expect(identifierMatch == .setapp)
    #expect(frameworkMatch == .setapp)
}

@Test func microsoftAutoUpdateUsesRegistrationWithoutMisclassifyingVSCode() {
    let registered = AppDiscovery.updateManagement(
        bundleIdentifier: "com.microsoft.custom",
        appPath: "/Applications/Microsoft Custom.app",
        hasReceipt: false,
        receiptType: nil,
        hasEmbeddedProvisioningProfile: false,
        hasSetappFramework: false,
        microsoftRegisteredPaths: ["/Applications/Microsoft Custom.app"]
    )
    let visualStudioCode = AppDiscovery.updateManagement(
        bundleIdentifier: "com.microsoft.VSCode",
        appPath: "/Applications/Visual Studio Code.app",
        hasReceipt: false,
        receiptType: nil,
        hasEmbeddedProvisioningProfile: false,
        hasSetappFramework: false,
        microsoftRegisteredPaths: []
    )

    #expect(registered == .microsoftAutoUpdate)
    #expect(visualStudioCode == .direct)
}

@Test func classifiesKnownExternalUpdaterManagers() {
    func management(
        identifier: String?,
        path: String = "/Applications/Example.app"
    ) -> AppUpdateManagement {
        AppDiscovery.updateManagement(
            bundleIdentifier: identifier,
            appPath: path,
            hasReceipt: false,
            receiptType: nil,
            hasEmbeddedProvisioningProfile: false,
            hasSetappFramework: false,
            microsoftRegisteredPaths: []
        )
    }

    #expect(management(identifier: "com.valvesoftware.steam") == .steam)
    #expect(management(identifier: "com.spotify.client") == .spotify)
    #expect(management(identifier: "com.hnc.Discord") == .discord)
    #expect(management(identifier: "com.epicgames.EpicGamesLauncher") == .epicGames)
    #expect(management(identifier: "com.adobe.Photoshop") == .adobeCreativeCloud)
    #expect(management(identifier: "com.jetbrains.toolbox") == .jetBrainsToolbox)
    #expect(management(
        identifier: "com.jetbrains.intellij",
        path: "/Users/example/Applications/JetBrains Toolbox/IntelliJ IDEA.app"
    ) == .jetBrainsToolbox)
}

private func makeWrappedIOSApp(
    named name: String,
    in root: URL,
    storeMetadata: Bool,
    provisioningProfile: Bool = false
) throws -> URL {
    let fileManager = FileManager.default
    let outer = root.appendingPathComponent("\(name).app", isDirectory: true)
    let wrapper = outer.appendingPathComponent("Wrapper", isDirectory: true)
    let inner = wrapper.appendingPathComponent("\(name).app", isDirectory: true)
    try fileManager.createDirectory(at: inner, withIntermediateDirectories: true)
    let info: [String: Any] = [
        "CFBundleDisplayName": name, "CFBundleIdentifier": "com.example.\(name.lowercased())",
        "CFBundleShortVersionString": "7.149.1", "CFBundleVersion": "7.149.1.4",
        "CFBundleExecutable": name, "UIDeviceFamily": [1, 2]
    ]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: inner.appendingPathComponent("Info.plist"))
    // A thin arm64 Mach-O header: MH_MAGIC_64 and CPU_TYPE_ARM64, little-endian.
    try Data([0xcf, 0xfa, 0xed, 0xfe, 0x0c, 0x00, 0x00, 0x01] + Array(repeating: 0, count: 24))
        .write(to: inner.appendingPathComponent(name))
    try fileManager.createSymbolicLink(at: outer.appendingPathComponent("WrappedBundle"),
        withDestinationURL: URL(fileURLWithPath: "Wrapper/\(name).app"))
    if storeMetadata {
        try PropertyListSerialization.data(fromPropertyList: ["itemId": 570060128], format: .xml, options: 0)
            .write(to: wrapper.appendingPathComponent("iTunesMetadata.plist"))
    }
    if provisioningProfile { try Data().write(to: inner.appendingPathComponent("embedded.mobileprovision")) }
    return outer
}

@Test func applicationDiscoveryFindsAppStoreIPhoneAndIPadApps() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Upkeep-WrappedApps-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let outer = try makeWrappedIOSApp(named: "Duolingo", in: root, storeMetadata: true)

    let app = try #require(await AppDiscovery.discover(at: outer))

    #expect(app.isWrappedIOSApp)
    #expect(app.name == "Duolingo")
    #expect(app.bundleIdentifier == "com.example.duolingo")
    #expect(app.installedVersion == "7.149.1")
    #expect(app.buildVersion == "7.149.1.4")
    #expect(app.url.standardizedFileURL == outer.standardizedFileURL)
    #expect(app.updateManagement == .appStore)
    #expect(app.hasAppStoreReceipt)
    #expect(app.architectures == ["arm64"])
    #expect(!app.allowsHomebrewAdoption)
    #expect(enabledAppUpdateSources(for: app, checkAppStore: true, checkSparkle: true, checkGitHub: true)
        .map(\.source) == [.appStore])
}

@Test func wrappedAppsWithoutStoreMetadataHaveNoUpdateSource() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Upkeep-WrappedApps-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let sideloaded = try #require(await AppDiscovery.discover(
        at: try makeWrappedIOSApp(named: "Sideloaded", in: root, storeMetadata: false)))
    #expect(sideloaded.updateManagement == .direct)
    #expect(!sideloaded.allowsHomebrewAdoption)
    #expect(!UpdateScanner.allowsHomebrewCandidate(for: sideloaded))
    #expect(enabledAppUpdateSources(for: sideloaded, checkAppStore: true, checkSparkle: true, checkGitHub: true).isEmpty)

    let beta = try #require(await AppDiscovery.discover(
        at: try makeWrappedIOSApp(named: "Beta", in: root, storeMetadata: true, provisioningProfile: true)))
    #expect(beta.updateManagement == .testFlight)
}

@Test func wrappedBundleDetectionIgnoresMacBundles() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Upkeep-WrappedApps-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let outer = try makeWrappedIOSApp(named: "Maps", in: root, storeMetadata: true)
    #expect(AppDiscovery.wrappedIOSBundle(at: outer)?.lastPathComponent == "Maps.app")
    // A normal Mac bundle is never treated as wrapped.
    let mac = root.appendingPathComponent("Mac.app/Contents", isDirectory: true)
    try FileManager.default.createDirectory(at: mac, withIntermediateDirectories: true)
    try Data("<plist><dict/></plist>".utf8).write(to: mac.appendingPathComponent("Info.plist"))
    #expect(AppDiscovery.wrappedIOSBundle(at: root.appendingPathComponent("Mac.app")) == nil)
}
