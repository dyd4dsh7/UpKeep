import Testing
@testable import Upkeep

@Test func semanticVersions() {
    #expect(VersionComparator.isNewer("2.0", than: "1.9.9"))
    #expect(VersionComparator.isNewer("1.10", than: "1.9"))
    #expect(!VersionComparator.isNewer("1.0", than: "1.0.0"))
}

@Test func versionPrefixesAndBuildComponents() {
    #expect(VersionComparator.isNewer("v4.2.1", than: "4.2"))
    #expect(VersionComparator.isNewer("2026.10", than: "2026.2"))
}
