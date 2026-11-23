import Foundation
import Testing
@testable import Upkeep

// AutoUpdate registrations as stored in com.microsoft.autoupdate2 on a real Mac:
// Office follows the global Beta channel, Teams pins Preview.
@Test func microsoftRegistrationsUseEachAppsChannel() {
    let registrations = AppDiscovery.microsoftAutoUpdateRegistrations(applications: [
        "/Applications/Microsoft Word.app": ["Application ID": "MSWD2019", "LCID": 1033],
        "/Applications/Microsoft Teams.app": ["Application ID": "TEAMS21", "ChannelName": "Preview"],
        "/Applications/Odd.app": ["Application ID": "../etc/passwd"]
    ], globalChannel: "Beta")
    #expect(registrations["/Applications/Microsoft Word.app"] == MicrosoftAutoUpdateRegistration(applicationID: "MSWD2019", channel: .beta))
    #expect(registrations["/Applications/Microsoft Teams.app"]?.channel == .preview)
    #expect(registrations["/Applications/Odd.app"]?.applicationID == nil)
    #expect(registrations["/Applications/Microsoft Word.app"]?.manifestURL?.absoluteString
        == "https://officecdnmac.microsoft.com/pr/4B2D7701-0A4F-49C8-B4CB-0C2D4043F51F/MacAutoupdate/0409MSWD2019.xml")
    #expect(MicrosoftAutoUpdateChannel(name: nil) == .production)
    #expect(MicrosoftAutoUpdateChannel(name: "InsiderFast") == .beta)
    #expect(MicrosoftAutoUpdateChannel(name: "External") == .preview)
}

private func manifest(_ entries: [[String: Any]]) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: entries, format: .xml, options: 0)
}

@Test func microsoftManifestsGiveTheNewestCompatibleBuild() throws {
    let data = try manifest([
        ["Update Version": "16.117.26111815", "Baseline Version": "16.116.26103101", "Minimum OS": "14.0"],
        ["Update Version": "16.117.26111815", "Baseline Version": "16.117.26110901", "Minimum OS": "14.0"],
        ["Update Version": "16.118.26120101", "Baseline Version": "16.117.26111815", "Minimum OS": "99.0"],
        ["Update Version": "16.119.26121501", "Baseline Version": "16.117.26111815", "Architecture": "x86_64_only"]
    ])
    let release = try VendorUpdateClient.microsoftAutoUpdateRelease(from: data, installedVersion: "16.117",
        operatingSystem: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))
    #expect(release == VendorRelease(version: "16.117", build: "16.117.26111815"))

    let teams = try VendorUpdateClient.microsoftAutoUpdateRelease(
        from: try manifest([["Update Version": "26304.1206.5384.1209", "Architecture": "arm64e"]]),
        installedVersion: "26304.1206.5384.1209")
    #expect(teams?.version == "26304.1206.5384.1209")
    #expect(throws: UpdateSourceError.self) {
        try VendorUpdateClient.microsoftAutoUpdateRelease(from: Data("<plist><dict/></plist>".utf8), installedVersion: "1")
    }
}

@Test func microsoftUpdatesCompareBuildsAndOpenAutoUpdate() {
    let registration = MicrosoftAutoUpdateRegistration(applicationID: "MSWD2019", channel: .beta)
    let word = InstalledApp(name: "Microsoft Word", bundleIdentifier: "com.microsoft.Word", installedVersion: "16.117",
        buildVersion: "16.117.26111815", url: URL(fileURLWithPath: "/Applications/Microsoft Word.app"),
        sparkleFeedURL: nil, githubRepository: nil, hasAppStoreReceipt: false,
        updateManagement: .microsoftAutoUpdate, vendorUpdateProduct: .microsoftAutoUpdate(registration))
    #expect(enabledAppUpdateSources(for: word, checkAppStore: true, checkSparkle: true, checkGitHub: true).map(\.source) == [.developer])
    let unregistered = InstalledApp(name: "Microsoft Word", bundleIdentifier: "com.microsoft.Word", installedVersion: "16.117",
        buildVersion: nil, url: URL(fileURLWithPath: "/Applications/Microsoft Word.app"),
        sparkleFeedURL: nil, githubRepository: nil, hasAppStoreReceipt: false, updateManagement: .microsoftAutoUpdate)
    #expect(enabledAppUpdateSources(for: unregistered, checkAppStore: true, checkSparkle: true, checkGitHub: true).isEmpty)

    let newer = VendorRelease(version: "16.118", build: "16.118.26120101")
    #expect(VendorUpdateClient.isNewer(newer, than: word, product: .microsoftAutoUpdate(registration)))
    #expect(!VendorUpdateClient.isNewer(VendorRelease(version: "16.117", build: "16.117.26111815"), than: word,
        product: .microsoftAutoUpdate(registration)))

    let update = AvailableUpdate(app: word, availableVersion: newer.version, source: .developer, releaseNotes: nil,
        actionURL: URL(fileURLWithPath: VendorUpdateClient.microsoftAutoUpdateApplication), homebrewToken: nil,
        availableBuildVersion: newer.build, usesBuildVersionOnly: true)
    #expect(update.actionTitle == "Open Microsoft AutoUpdate")
    #expect(update.externalActionURL?.lastPathComponent == "Microsoft AutoUpdate.app")
    #expect(!update.canInstallDirectly)
    #expect(update.primaryCandidate.isNewer(than: word))
    let updated = InstalledApp(name: "Microsoft Word", bundleIdentifier: "com.microsoft.Word", installedVersion: "16.118",
        buildVersion: "16.118.26120101", url: word.url, sparkleFeedURL: nil, githubRepository: nil,
        hasAppStoreReceipt: false, updateManagement: .microsoftAutoUpdate)
    #expect(update.primaryCandidate.isInstalled(in: updated))
}

@Test func claudeCodeNativeInstallsReadTheirLinkAndChannel() throws {
    #expect(claudeCodeNativeVersion(linkTarget: "/Users/me/.local/share/claude/versions/2.1.330") == "2.1.330")
    #expect(claudeCodeNativeVersion(linkTarget: "/opt/homebrew/Caskroom/claude-code/2.1.330/claude") == nil)
    #expect(claudeCodeUpdateChannel(settings: nil) == "latest")
    #expect(claudeCodeUpdateChannel(settings: Data(#"{"model":"opus"}"#.utf8)) == "latest")
    #expect(claudeCodeUpdateChannel(settings: Data(#"{"autoUpdatesChannel":"stable"}"#.utf8)) == "stable")

    let fileManager = FileManager.default
    let home = fileManager.temporaryDirectory.appendingPathComponent("Upkeep-Claude-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: home) }
    let versions = home.appendingPathComponent(".local/share/claude/versions", isDirectory: true)
    try fileManager.createDirectory(at: versions, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: home.appendingPathComponent(".local/bin"), withIntermediateDirectories: true)
    try Data().write(to: versions.appendingPathComponent("2.1.330"))
    #expect(claudeCodeNativeLauncher(home: home) == nil)
    try fileManager.createSymbolicLink(atPath: home.appendingPathComponent(".local/bin/claude").path,
        withDestinationPath: versions.appendingPathComponent("2.1.330").path)
    #expect(claudeCodeNativeLauncher(home: home) == home.appendingPathComponent(".local/bin/claude").path)

    let package = DeveloperPackage(name: "Claude Code", currentVersion: "2.1.323", latestVersion: "2.1.330",
        manager: .claudeCode, executablePath: "/x/claude", registryIdentifier: "claude-code")
    guard case let .command(_, arguments, _) = try DeveloperPackageInstallAdapters.plan(for: package, version: "2.1.330") else {
        Issue.record("Expected a claude command")
        return
    }
    #expect(arguments == ["install", "2.1.330"])
}

@Test func appNamesDropInvisibleFormatCharacters() {
    // WhatsApp's real CFBundleDisplayName starts with U+200E LEFT-TO-RIGHT MARK.
    #expect(AppDiscovery.displayName(info: ["CFBundleDisplayName": "\u{200E}WhatsApp"], fallback: "x") == "WhatsApp")
    #expect(AppDiscovery.displayName(info: ["CFBundleDisplayName": "\u{200E}", "CFBundleName": "Fallback"], fallback: "x") == "Fallback")
    #expect(AppDiscovery.displayName(info: [:], fallback: "Folder Name") == "Folder Name")
}

@Test func appleUtilitiesAndClaudeHelperAreManaged() {
    func management(_ identifier: String, _ path: String) -> AppUpdateManagement {
        AppDiscovery.updateManagement(bundleIdentifier: identifier, appPath: path, hasReceipt: false, receiptType: nil,
            hasEmbeddedProvisioningProfile: false, hasSetappFramework: false, microsoftRegisteredPaths: [])
    }
    #expect(management("com.apple.appleseed.FeedbackAssistant", "/Applications/Utilities/Feedback Assistant.app") == .macOS)
    // An Apple app downloaded outside macOS, such as Xcode from developer.apple.com, stays direct.
    #expect(management("com.apple.dt.Xcode", "/Applications/Xcode-beta.app") == .direct)
    #expect(management("com.anthropic.claude-code-url-handler", "/Users/me/Applications/Claude Code URL Handler.app") == .claudeCode)
    #expect(AppUpdateManagement.claudeCode.isExternallyManaged)
}
