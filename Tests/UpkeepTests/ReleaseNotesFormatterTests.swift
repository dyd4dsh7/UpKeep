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

@Test func releaseNotesShowFencedCodeWithoutFencesOrMarkdown() {
    let text = ReleaseNotesFormatter.attributedString(from: "Audit:\n\n```text\n# not a heading\n- not a bullet\n```\nDone")
    #expect(String(text.characters) == "Audit:\n\n# not a heading\n- not a bullet\nDone")
    let codeRuns = text.runs.filter { $0.inlinePresentationIntent?.contains(.code) == true }
    #expect(codeRuns.map { String(text[$0.range].characters) }.joined() == "# not a heading- not a bullet")
}

@Test func releaseNotesQuoteBlocksGetABarAndKeepTheirFormatting() {
    let text = ReleaseNotesFormatter.attributedString(from: "> ## Heads up\n> Read this.\n>\n> - item\n> > deeper")
    #expect(String(text.characters) == "▎ Heads up\n▎ Read this.\n▎\n▎ • item\n▎ ▎ deeper")
}

@Test func releaseNotesGitHubAlertsBecomeBoldTitles() {
    let text = ReleaseNotesFormatter.attributedString(from: "> [!WARNING]\n> Back up first.")
    #expect(String(text.characters) == "▎ Warning\n▎ Back up first.")
    let boldText = text.runs
        .filter { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
        .map { String(text[$0.range].characters) }
        .joined()
    #expect(boldText == "Warning")
}

@Test func releaseNotesTableRowsBecomeLabelledBullets() throws {
    let notes = """
    | Arch | Mac | Linux |
    |------|:---:|-------|
    | arm64 | [DMG](https://example.com/a.dmg) | |
    | x86 \\| 64 | `a|b` | Tar   Zip |
    After
    """
    let text = ReleaseNotesFormatter.attributedString(from: notes)
    #expect(String(text.characters) == "• arm64 · Mac: DMG\n• x86 | 64 · Mac: a|b · Linux: Tar Zip\nAfter")
    #expect(text.runs.compactMap(\.link) == [try #require(URL(string: "https://example.com/a.dmg"))])
}

@Test func releaseNotesPipesWithoutADelimiterRowAreNotATable() {
    let text = ReleaseNotesFormatter.attributedString(from: "Use a | b\nfor pipes")
    #expect(String(text.characters) == "Use a | b\nfor pipes")
}

@Test func releaseNotesDropMarkdownImagesAndImageOnlyLines() {
    let notes = """
    ![image](https://example.com/shot.png)

    Fixed sync ![icon](https://example.com/i.png) on Wi-Fi.
    Works on ![mac](https://example.com/m.png) ![pc](https://example.com/p.png)  Windows
    - ![screenshot](https://example.com/s.png)
    - Kept
    [![badge](https://example.com/b.svg)](https://example.com)

    > ![chart](https://example.com/c.png)
    Done `![not](an image)`
    """
    let text = ReleaseNotesFormatter.attributedString(from: notes)
    #expect(String(text.characters) == "Fixed sync on Wi-Fi.\nWorks on Windows\n• Kept\n\n▎\nDone ![not](an image)")
    #expect(text.runs.allSatisfy { $0.imageURL == nil })
}

@Test func releaseNotesTableCellsWithOnlyImagesAreSkipped() {
    let notes = """
    | Platform | Badge | Link |
    |---|---|---|
    | Mac | ![ok](https://example.com/ok.svg) | [DMG](https://example.com/a.dmg) |
    | ![x](https://example.com/x.png) | ![y](https://example.com/y.png) | |
    """
    let text = ReleaseNotesFormatter.attributedString(from: notes)
    #expect(String(text.characters) == "• Mac · Link: DMG")
}
