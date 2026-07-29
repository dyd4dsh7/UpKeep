import Foundation
import Testing
@testable import Upkeep

@Test func verifiedPublisherArchivesInstallDirectlyInUpkeep() {
    let app = directUpdateApp()
    let update = AvailableUpdate(
        app: app,
        availableVersion: "1.1.0",
        source: .sparkle,
        releaseNotes: nil,
        actionURL: URL(string: "https://example.com/Example-1.1.0.zip"),
        homebrewToken: nil
    )

    #expect(update.canInstallDirectly)
    #expect(update.actionTitle == "Update")
    #expect(update.actionDescription == "Download, verify, and install with Upkeep")
    #expect(BatchUpdateItem.application(update).riskGroup == .automatic)
    #expect(!BatchUpdateItem.application(update).opensExternalUpdater)
}

@Test func webPagesAndPackageInstallersRemainExternalActions() {
    let app = directUpdateApp()
    let webRelease = AvailableUpdate(
        app: app,
        availableVersion: "2.0.0",
        source: .github,
        releaseNotes: nil,
        actionURL: URL(string: "https://github.com/example/example/releases/tag/v2.0.0"),
        homebrewToken: nil
    )
    let package = AvailableUpdate(
        app: app,
        availableVersion: "2.0.0",
        source: .sparkle,
        releaseNotes: nil,
        actionURL: URL(string: "https://example.com/Example.pkg"),
        homebrewToken: nil,
        requiresInAppInstallation: true
    )

    #expect(!webRelease.canInstallDirectly)
    #expect(BatchUpdateItem.application(webRelease).opensExternalUpdater)
    #expect(!package.canInstallDirectly)
    #expect(package.actionTitle == "Open App")
}

@Test func githubChoosesAMatchingMacArchiveForTheCurrentArchitecture() throws {
    let app = directUpdateApp(repository: "example/example")
    let currentArchitecture = {
        #if arch(arm64)
        "arm64"
        #else
        "x64"
        #endif
    }()
    let otherArchitecture = {
        #if arch(arm64)
        "x64"
        #else
        "arm64"
        #endif
    }()
    let release = GitHubClient.Release(
        tagName: "v2.0.0",
        htmlUrl: "https://github.com/example/example/releases/tag/v2.0.0",
        body: nil,
        prerelease: false,
        draft: false,
        assets: [
            .init(
                name: "example-darwin-\(currentArchitecture).zip",
                browserDownloadUrl: "https://example.com/cli.zip"
            ),
            .init(
                name: "example-\(otherArchitecture).dmg",
                browserDownloadUrl: "https://example.com/wrong.dmg"
            ),
            .init(
                name: "example-desktop-macos-\(currentArchitecture).dmg",
                browserDownloadUrl: "https://example.com/correct.dmg"
            ),
            .init(
                name: "example-linux-\(currentArchitecture).zip",
                browserDownloadUrl: "https://example.com/linux.zip"
            )
        ]
    )

    let asset = try #require(GitHubClient.installableAsset(in: release, for: app))
    #expect(asset.downloadURL?.absoluteString == "https://example.com/correct.dmg")
}

private func directUpdateApp(repository: String? = nil) -> InstalledApp {
    InstalledApp(
        name: "Example",
        bundleIdentifier: "com.example.app",
        installedVersion: "1.0.0",
        buildVersion: nil,
        url: URL(fileURLWithPath: "/Applications/Example.app"),
        sparkleFeedURL: nil,
        githubRepository: repository,
        hasAppStoreReceipt: false
    )
}
