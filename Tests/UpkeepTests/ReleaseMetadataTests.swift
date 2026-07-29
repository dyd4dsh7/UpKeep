import Foundation
import Testing
@testable import Upkeep

@Test func appBundleDeclaresCanonicalSelfUpdateRepository() throws {
    let testFile = URL(fileURLWithPath: #filePath)
    let projectRoot = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let infoURL = projectRoot.appendingPathComponent("Support/Info.plist")
    let data = try Data(contentsOf: infoURL)
    let info = try #require(
        PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    )

    #expect(info["RepositoryURL"] as? String == "https://github.com/dyd4dsh7/UpKeep")
}

@Test func updateSourceDescriptionsStateWhatWasActuallyVerified() {
    #expect(UpdateSource.appStore.confidenceDetail == "Apple-managed distribution")
    #expect(UpdateSource.homebrew.confidenceDetail == "Homebrew-managed package")
    #expect(UpdateSource.sparkle.confidenceDetail.contains("Developer-published"))
    #expect(UpdateSource.github.confidenceDetail.contains("Matched"))
}
