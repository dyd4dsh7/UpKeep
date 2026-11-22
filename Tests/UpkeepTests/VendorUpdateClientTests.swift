import Foundation
import Testing
@testable import Upkeep

private func vendorApp(
    _ bundleIdentifier: String,
    version: String,
    build: String? = nil
) -> InstalledApp {
    InstalledApp(
        name: "Vendor App", bundleIdentifier: bundleIdentifier, installedVersion: version,
        buildVersion: build, url: URL(fileURLWithPath: "/Applications/Vendor App.app"),
        sparkleFeedURL: nil, githubRepository: nil, hasAppStoreReceipt: false,
        vendorUpdateProduct: VendorUpdateProduct.product(bundleIdentifier: bundleIdentifier)
    )
}

@Test func vendorProductsMapReleaseBundleIdentifiersOnly() {
    #expect(VendorUpdateProduct.product(bundleIdentifier: "com.jetbrains.intellij") == .jetBrains(code: "IIU"))
    #expect(VendorUpdateProduct.product(bundleIdentifier: "com.jetbrains.WebStorm") == .jetBrains(code: "WS"))
    #expect(VendorUpdateProduct.product(bundleIdentifier: "com.jetbrains.pycharm.ce") == .jetBrains(code: "PCC"))
    #expect(VendorUpdateProduct.product(bundleIdentifier: "com.jetbrains.intellij-EAP") == nil)
    #expect(VendorUpdateProduct.product(bundleIdentifier: "com.microsoft.edgemac") == .edge(.stable))
    #expect(VendorUpdateProduct.product(bundleIdentifier: "com.microsoft.edgemac.Beta") == .edge(.beta))
    #expect(VendorUpdateProduct.product(bundleIdentifier: "us.zoom.xos") == .zoom)
    #expect(VendorUpdateProduct.product(bundleIdentifier: "com.tinyspeck.slackmacgap") == .slack)
    #expect(VendorUpdateProduct.product(bundleIdentifier: "com.1password.1password") == .onePassword)
    #expect(VendorUpdateProduct.product(bundleIdentifier: "com.example.app") == nil)
}

@Test func vendorAppsUseTheDeveloperSourceOnlyWhenInstalledDirectly() {
    let zoom = vendorApp("us.zoom.xos", version: "7.2.5 (90525)")
    #expect(zoom.hasBuiltInUpdater)
    #expect(zoom.usesDeveloperUpdateService)
    #expect(enabledAppUpdateSources(for: zoom, checkAppStore: true, checkSparkle: true, checkGitHub: true)
        .map(\.source) == [.developer])

    let appStoreSlack = InstalledApp(
        name: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap", installedVersion: "4.53.292",
        buildVersion: nil, url: URL(fileURLWithPath: "/Applications/Slack.app"),
        sparkleFeedURL: nil, githubRepository: nil, hasAppStoreReceipt: true,
        vendorUpdateProduct: .slack
    )
    #expect(enabledAppUpdateSources(for: appStoreSlack, checkAppStore: true, checkSparkle: true, checkGitHub: true)
        .map(\.source) == [.appStore])
}

@Test func jetBrainsReleaseKeepsTheInstalledBuildPrefix() throws {
    let data = Data(#"{"IIU":[{"date":"2026-11-05","type":"release","version":"2026.3","build":"263.7307.200"}]}"#.utf8)
    let release = try VendorUpdateClient.jetBrainsRelease(from: data, code: "IIU", installedBuild: "IU-263.6000.10")
    #expect(release == VendorRelease(version: "2026.3", build: "IU-263.7307.200"))
    #expect(try VendorUpdateClient.jetBrainsRelease(from: data, code: "WS", installedBuild: nil) == nil)
}

@Test func jetBrainsComparesBuildsAndConfirmsInstalledPatches() {
    let installed = vendorApp("com.jetbrains.intellij", version: "2026.3", build: "IU-263.6000.10")
    let patch = VendorRelease(version: "2026.3", build: "IU-263.7307.200")
    #expect(VendorUpdateClient.isNewer(patch, than: installed, product: .jetBrains(code: "IIU")))
    #expect(!VendorUpdateClient.isNewer(
        VendorRelease(version: "2026.3", build: "IU-263.6000.10"), than: installed, product: .jetBrains(code: "IIU")
    ))

    let update = AvailableUpdate(
        app: installed, availableVersion: patch.version, source: .developer, releaseNotes: nil,
        actionURL: nil, homebrewToken: nil, requiresInAppInstallation: true, availableBuildVersion: patch.build
    )
    #expect(!update.primaryCandidate.isInstalled(in: installed))
    #expect(update.primaryCandidate.isInstalled(in: vendorApp("com.jetbrains.intellij", version: "2026.3",
        build: "IU-263.7307.200")))
}

@Test func zoomComparesItsBuildAndShowsItsDisplayVersion() throws {
    let data = Data(#"""
        {"status":true,"result":{"downloadVO":{"zoom":{"version":"7.2.6.91000","displayVersion":"7.2.6 (91000)",
        "packageName":"zoomusInstallerFull.pkg"}}}}
        """#.utf8)
    let release = try #require(try VendorUpdateClient.zoomRelease(from: data))
    #expect(release == VendorRelease(version: "7.2.6 (91000)", build: "7.2.6.91000"))

    let installed = vendorApp("us.zoom.xos", version: "7.2.5 (90525)", build: "7.2.5.90525")
    #expect(VendorUpdateClient.isNewer(release, than: installed, product: .zoom))
    let update = AvailableUpdate(
        app: installed, availableVersion: release.version, source: .developer, releaseNotes: nil,
        actionURL: nil, homebrewToken: nil, requiresInAppInstallation: true, availableBuildVersion: release.build
    )
    #expect(update.primaryCandidate.isNewer(than: installed))
    #expect(update.primaryCandidate.isInstalled(in: vendorApp("us.zoom.xos", version: "7.2.6 (91000)",
        build: "7.2.6.91000")))
}

@Test func edgeTakesTheNewestMacReleaseForItsChannel() throws {
    let data = Data(#"""
        [{"Product":"Stable","Releases":[
          {"ReleaseId":1,"Platform":"MacOS","Architecture":"universal","ProductVersion":"152.0.4191.53"},
          {"ReleaseId":2,"Platform":"MacOS","Architecture":"universal","ProductVersion":"158.0.4370.33"},
          {"ReleaseId":3,"Platform":"Windows","Architecture":"x64","ProductVersion":"159.0.1.1"}]},
         {"Product":"Beta","Releases":[
          {"ReleaseId":4,"Platform":"MacOS","Architecture":"universal","ProductVersion":"159.0.4402.13"}]}]
        """#.utf8)
    #expect(try VendorUpdateClient.edgeRelease(from: data, channel: .stable)?.version == "158.0.4370.33")
    #expect(try VendorUpdateClient.edgeRelease(from: data, channel: .beta)?.version == "159.0.4402.13")
    #expect(try VendorUpdateClient.edgeRelease(from: data, channel: .canary) == nil)
}

@Test func slackAndOnePasswordParseTheirReleaseServices() throws {
    let slack = Data(#"{"ok":true,"version":"4.53.292","platform":"darwin","arch":"universal"}"#.utf8)
    #expect(try VendorUpdateClient.slackRelease(from: slack)?.version == "4.53.292")
    #expect(throws: UpdateSourceError.self) {
        try VendorUpdateClient.slackRelease(from: Data(#"{"ok":false,"error":"invalid_arch"}"#.utf8))
    }

    let feed = Data("""
        <rss><channel><title>1Password for Mac - 1Password Releases</title>
        <item><title>1Password for Mac 8.7.0</title></item>
        <item><title>1Password for Mac 8.12.46</title></item>
        <item><title>1Password for Mac 8.12.9</title></item>
        </channel></rss>
        """.utf8)
    #expect(try VendorUpdateClient.onePasswordRelease(from: feed)?.version == "8.12.46")
}
