import Foundation
import Testing
@testable import Upkeep

@Test func identifiesFirefoxReleaseChannels() {
    #expect(AppDiscovery.mozillaUpdateChannel(
        bundleIdentifier: "org.mozilla.firefox",
        installedVersion: "153.0"
    ) == .release)
    #expect(AppDiscovery.mozillaUpdateChannel(
        bundleIdentifier: "org.mozilla.firefox",
        installedVersion: "140.12.0esr"
    ) == .esr)
    #expect(AppDiscovery.mozillaUpdateChannel(
        bundleIdentifier: "org.mozilla.firefoxdeveloperedition",
        installedVersion: "154.0b1"
    ) == .developerEdition)
    #expect(AppDiscovery.mozillaUpdateChannel(
        bundleIdentifier: "org.mozilla.nightly",
        installedVersion: "155.0a1"
    ) == .nightly)
    #expect(AppDiscovery.mozillaUpdateChannel(
        bundleIdentifier: "org.mozilla.thunderbird",
        installedVersion: "140.0"
    ) == .release)
    #expect(AppDiscovery.mozillaUpdateMetadata(
        bundleIdentifier: "org.mozilla.thunderbird",
        installedVersion: "140.13.0esr"
    ).product == .thunderbird)
}

@Test func selectsThunderbirdVersions() {
    let versions = [
        "LATEST_THUNDERBIRD_VERSION": "153.0",
        "LATEST_THUNDERBIRD_DEVEL_VERSION": "154.0b1",
        "LATEST_THUNDERBIRD_NIGHTLY_VERSION": "155.0a1",
        "THUNDERBIRD_ESR": "140.13.0esr",
        "THUNDERBIRD_ESR_NEXT": "153.0esr"
    ]

    #expect(MozillaUpdateClient.latestVersion(
        for: .release,
        product: .thunderbird,
        installedVersion: "152.0",
        versions: versions
    ) == "153.0")
    #expect(MozillaUpdateClient.latestVersion(
        for: .esr,
        product: .thunderbird,
        installedVersion: "140.12.0esr",
        versions: versions
    ) == "140.13.0esr")
}

@Test func selectsBraveVersionsByNamedChannel() {
    let releases = [
        MozillaUpdateClient.BraveRelease(
            tagName: "v1.94.93", name: "Nightly v1.94.93 (Chromium 151)",
            prerelease: true, draft: false
        ),
        MozillaUpdateClient.BraveRelease(
            tagName: "v1.93.125", name: "Beta v1.93.125 (Chromium 151)",
            prerelease: false, draft: false
        ),
        MozillaUpdateClient.BraveRelease(
            tagName: "v1.93.126", name: "Release v1.93.126 (Chromium 151)",
            prerelease: true, draft: false
        ),
        MozillaUpdateClient.BraveRelease(
            tagName: "v1.92.143", name: "Release v1.92.143 (Chromium 150)",
            prerelease: false, draft: false
        )
    ]

    #expect(MozillaUpdateClient.newestBraveRelease(
        for: .release, releases: releases
    )?.tagName == "v1.92.143")
    #expect(MozillaUpdateClient.newestBraveRelease(
        for: .beta, releases: releases
    )?.tagName == "v1.93.125")
    #expect(MozillaUpdateClient.braveProductVersion("150.1.92.141") == "1.92.141")
    #expect(MozillaUpdateClient.braveBundleVersion(
        productVersion: "1.92.143",
        releaseName: "Release v1.92.143 (Chromium 150.0.7871.182)"
    ) == "150.1.92.143")
}

@Test func detectsChromiumAndBraveChannels() {
    #expect(AppDiscovery.chromiumUpdateChannel(
        bundleIdentifier: "com.google.Chrome"
    ) == .stable)
    #expect(AppDiscovery.chromiumUpdateChannel(
        bundleIdentifier: "com.google.Chrome.canary"
    ) == .canary)
    #expect(AppDiscovery.braveUpdateChannel(
        bundleIdentifier: "com.brave.Browser"
    ) == .release)
    #expect(AppDiscovery.braveUpdateChannel(
        bundleIdentifier: "com.brave.Browser.nightly"
    ) == .nightly)
}

@Test func trustedGitHubMappingsCoverUpdaterBundlesWithoutMetadata() {
    #expect(AppDiscovery.trustedGitHubRepository(
        bundleIdentifier: "com.github.GitHubClient"
    ) == "desktop/desktop")
    #expect(AppDiscovery.trustedGitHubRepository(
        bundleIdentifier: "com.electron.ollama"
    ) == "ollama/ollama")
    #expect(AppDiscovery.trustedGitHubRepository(
        bundleIdentifier: "com.microsoft.VSCode"
    ) == "microsoft/vscode")
    #expect(AppDiscovery.trustedGitHubRepository(
        bundleIdentifier: "com.hnc.Discord"
    ) == nil)
}

@Test func selectsLatestVersionForEachMozillaChannel() {
    let versions = [
        "LATEST_FIREFOX_VERSION": "153.0",
        "FIREFOX_DEVEDITION": "154.0b1",
        "FIREFOX_NIGHTLY": "155.0a1",
        "FIREFOX_ESR": "140.13.0esr",
        "FIREFOX_ESR115": "115.38.0esr",
        "FIREFOX_ESR_NEXT": "153.0esr"
    ]

    #expect(MozillaUpdateClient.latestVersion(
        for: .release, installedVersion: "152.0.6", versions: versions
    ) == "153.0")
    #expect(MozillaUpdateClient.latestVersion(
        for: .developerEdition, installedVersion: "153.0b9", versions: versions
    ) == "154.0b1")
    #expect(MozillaUpdateClient.latestVersion(
        for: .nightly, installedVersion: "154.0a1", versions: versions
    ) == "155.0a1")
    #expect(MozillaUpdateClient.latestVersion(
        for: .esr, installedVersion: "140.12.0esr", versions: versions
    ) == "140.13.0esr")
    #expect(MozillaUpdateClient.latestVersion(
        for: .esr, installedVersion: "115.37.0esr", versions: versions
    ) == "115.38.0esr")
}
