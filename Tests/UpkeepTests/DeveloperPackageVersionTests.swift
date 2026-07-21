import Testing
@testable import Upkeep

@Test func stableVersionMenuFiltersPrereleasesButKeepsInstalledPrerelease() {
    let package = DeveloperPackage(
        name: "example",
        currentVersion: "1.1.0-beta.1",
        latestVersion: "1.0.5",
        manager: .npm,
        executablePath: "/example/npm"
    )
    let versions = selectableDeveloperPackageVersions(
        discovered: [
            "1.2.0-alpha.2", "1.1.0-beta.1", "1.0.5",
            "1.0.5-darwin-arm64", "1.0.4"
        ],
        package: package,
        includePrereleases: false
    )

    #expect(versions.contains("1.1.0-beta.1"))
    #expect(versions.contains("1.0.5"))
    #expect(versions.contains("1.0.4"))
    #expect(!versions.contains("1.2.0-alpha.2"))
    #expect(!versions.contains("1.0.5-darwin-arm64"))
    #expect(package.prereleaseChannel == .beta)
}

@Test func prereleaseVersionMenuIncludesAllPublishedChannels() {
    let package = DeveloperPackage(
        name: "example",
        currentVersion: "1.0.4",
        latestVersion: "1.0.5",
        manager: .pnpm,
        executablePath: "/example/pnpm"
    )
    let versions = selectableDeveloperPackageVersions(
        discovered: ["1.2.0-alpha.2", "1.0.5-darwin-arm64", "1.0.5"],
        package: package,
        includePrereleases: true
    )

    #expect(versions.contains("1.2.0-alpha.2"))
    #expect(versions.contains("1.0.5-darwin-arm64"))
}

@Test func canonicalVersionSortsAheadOfEquivalentPlatformBuilds() {
    let versions = [
        "0.144.6-darwin-arm64", "0.144.6-linux-x64", "0.144.6"
    ].sorted(by: VersionComparator.newestFirst)

    #expect(versions.first == "0.144.6")
}
