import Foundation
import Testing
@testable import Upkeep

@Test func releaseNotesHeadingsBecomeBoldWithoutMarkers() {
    let text = ReleaseNotesFormatter.attributedString(
        from: "# What's New in TablePro 0.87.0\n\nRead-Only mode holds on more engines."
    )
    #expect(String(text.characters) == "What's New in TablePro 0.87.0\n\nRead-Only mode holds on more engines.")
    let headingRun = text.runs.first
    #expect(headingRun?.inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
}

@Test func releaseNotesClosedHeadingsDropTrailingMarkers() {
    let text = ReleaseNotesFormatter.attributedString(from: "## Fixes ##")
    #expect(String(text.characters) == "Fixes")
}

@Test func releaseNotesListItemsBecomeBullets() {
    let text = ReleaseNotesFormatter.attributedString(from: "- First\n* Second\n  + Nested")
    #expect(String(text.characters) == "• First\n• Second\n    • Nested")
}

@Test func releaseNotesInlineMarkdownIsRenderedAndBoldTextIsNotABullet() {
    let text = ReleaseNotesFormatter.attributedString(from: "**Fixed** a crash in `sync`")
    #expect(String(text.characters) == "Fixed a crash in sync")
}

@Test func releaseNotesKeepOnlyWebLinks() throws {
    let text = ReleaseNotesFormatter.attributedString(
        from: "[Docs](https://example.com/docs) and [Run](file:///tmp/run.sh)"
    )
    #expect(String(text.characters) == "Docs and Run")
    let links = text.runs.compactMap(\.link)
    #expect(links == [try #require(URL(string: "https://example.com/docs"))])
}

@Test func releaseNotesCollapseBlankLinesAndRules() {
    let text = ReleaseNotesFormatter.attributedString(from: "\n\nOne\n\n\n---\n\nTwo\n\n")
    #expect(String(text.characters) == "One\n\nTwo")
}

@Test func releaseNotesPlainTextIsUnchanged() {
    let notes = "Bug fixes and performance improvements.\nVersion 2 adds sync."
    #expect(String(ReleaseNotesFormatter.attributedString(from: notes).characters) == notes)
}
