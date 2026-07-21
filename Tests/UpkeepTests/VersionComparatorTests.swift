import Foundation
import Testing
@testable import Upkeep

@Test func semanticVersions() {
    #expect(VersionComparator.isNewer("2.0", than: "1.9.9"))
    #expect(VersionComparator.isNewer("1.10", than: "1.9"))
    #expect(VersionComparator.compare("1.0", "1.0.0") == .orderedSame)
    #expect(VersionComparator.compare("001.02.0003", "1.2.3") == .orderedSame)
}

@Test func versionPrefixesAndCalendarVersions() {
    #expect(VersionComparator.isNewer("v4.2.1", than: "4.2"))
    #expect(VersionComparator.compare("Version 4.2", "release-4.2.0") == .orderedSame)
    #expect(VersionComparator.isNewer("2026.10", than: "2026.2"))
    #expect(VersionComparator.isNewer("2026.07.21", than: "2026.07.09"))
}

@Test func prereleaseOrdering() {
    #expect(VersionComparator.isPrerelease("2.0-alpha.1"))
    #expect(VersionComparator.isPrerelease("2.0-rc.1"))
    #expect(VersionComparator.isPrerelease("nightly-2026.07.21"))
    #expect(!VersionComparator.isPrerelease("2.0"))
    #expect(VersionComparator.prereleaseChannel(for: "2.0-alpha.1") == .alpha)
    #expect(VersionComparator.prereleaseChannel(for: "2.0-beta.3") == .beta)
    #expect(VersionComparator.prereleaseChannel(for: "2.0-preview.2") == .preview)
    #expect(VersionComparator.prereleaseChannel(for: "2.0 release candidate 1") == .releaseCandidate)
    #expect(VersionComparator.prereleaseChannel(for: "nightly-2026.07.21") == .nightly)
    #expect(!VersionComparator.isPrerelease("0.144.6-darwin-arm64"))
    #expect(VersionComparator.prereleaseChannel(for: "0.144.6-linux-x64") == nil)
    #expect(VersionComparator.prereleaseChannel(for: "0.144.6-beta.1-darwin-arm64") == .beta)
    #expect(VersionComparator.isNewer("1.0-beta.1", than: "1.0-alpha.9"))
    #expect(VersionComparator.isNewer("1.0-preview2", than: "1.0-beta12"))
    #expect(VersionComparator.isNewer("1.0-rc.1", than: "1.0-preview.9"))
    #expect(VersionComparator.isNewer("1.0", than: "1.0-rc.99"))
    #expect(!VersionComparator.isNewer("2.0-beta", than: "2.0"))
    #expect(VersionComparator.isNewer("3.0b2", than: "3.0b1"))
}

@Test func buildAndHomebrewVersions() {
    #expect(VersionComparator.isNewer("1.2.3,101", than: "1.2.3,99"))
    #expect(VersionComparator.isNewer("openssl@3 3.5.1_2", than: "openssl@3 3.5.1_1"))
    #expect(VersionComparator.compare("1.2.3+build.99", "1.2.3+build.12") == .orderedSame)
    #expect(VersionComparator.compare("1.2.3-arm64", "1.2.3-universal") == .orderedSame)
    #expect(VersionComparator.compare("1.2.3-x86_64", "1.2.3-arm64") == .orderedSame)
    #expect(VersionComparator.compare("1.2.3-macos14", "1.2.3") == .orderedSame)
}

@Test func longNumericComponentsDoNotOverflow() {
    #expect(VersionComparator.isNewer(
        "1.999999999999999999999999999999999999",
        than: "1.999999999999999999999999999999999998"
    ))
}

@Test func unversionedValuesAreConservative() {
    #expect(VersionComparator.compare("latest", "1.0") == .orderedSame)
    #expect(VersionComparator.compare("rolling", "nightly") == .orderedSame)
    #expect(!VersionComparator.isNewer("unknown", than: "1.0"))
    #expect(!VersionComparator.isNewer("", than: "1.0"))
}
