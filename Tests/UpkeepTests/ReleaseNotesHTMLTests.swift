import Foundation
import Testing
@testable import Upkeep

private func rendered(_ html: String) -> String {
    String(ReleaseNotesFormatter.attributedString(from: ReleaseNotesHTML.markdown(fromHTML: html)).characters)
}

@Test func htmlReleaseNotesKeepHeadingsParagraphsAndLists() {
    let html = """
    <h2>What&#39;s New</h2>
    <ul>
      <li>Faster <b>sync</b></li>
      <li>Fixes &amp; tweaks</li>
    </ul>
    <p>Thanks!</p>
    """
    #expect(ReleaseNotesHTML.markdown(fromHTML: html)
        == "## What's New\n\n- Faster **sync**\n- Fixes & tweaks\n\nThanks!")
    #expect(rendered(html) == "What's New\n\n• Faster sync\n• Fixes & tweaks\n\nThanks!")
}

@Test func htmlReleaseNotesCollapseSourceWhitespaceAndKeepLineBreaks() {
    #expect(ReleaseNotesHTML.markdown(fromHTML: "<p>\n  Line   one<br>Line two\n</p><p>Next</p>")
        == "Line one\nLine two\n\nNext")
}

@Test func htmlReleaseNotesNumberOrderedListsAndIndentNestedLists() {
    let html = "<ol><li>First</li><li>Second<ul><li>Detail</li></ul></li></ol>"
    #expect(ReleaseNotesHTML.markdown(fromHTML: html) == "1. First\n2. Second\n  - Detail")
    #expect(rendered(html) == "1. First\n2. Second\n    • Detail")
}

@Test func htmlReleaseNotesKeepOnlyWebLinks() throws {
    let html = """
    <p><a href="https://example.com/notes?a=1&amp;b=2">Notes</a> and <a href="javascript:alert(1)">this</a></p>
    """
    #expect(ReleaseNotesHTML.markdown(fromHTML: html) == "[Notes](<https://example.com/notes?a=1&b=2>) and this")
    let text = ReleaseNotesFormatter.attributedString(from: ReleaseNotesHTML.markdown(fromHTML: html))
    #expect(String(text.characters) == "Notes and this")
    #expect(text.runs.compactMap(\.link) == [try #require(URL(string: "https://example.com/notes?a=1&b=2"))])
}

@Test func htmlReleaseNotesKeepLiteralMarkdownCharacters() {
    #expect(rendered("<p>Use *args, C# and snake_case [beta] &lt;b&gt;</p>")
        == "Use *args, C# and snake_case [beta] <b>")
}

@Test func htmlReleaseNotesMoveSpacesOutsideEmphasisAndDropEmptyElements() {
    #expect(ReleaseNotesHTML.markdown(fromHTML: "<p><b>New: </b>Thing<i> </i>done</p>")
        == "**New:** Thing done")
}

@Test func htmlReleaseNotesCloseEmphasisAcrossLineBreaks() {
    #expect(ReleaseNotesHTML.markdown(fromHTML: "<b>One<br>Two</b>") == "**One**\n**Two**")
}

@Test func htmlReleaseNotesDropScriptsStylesAndComments() {
    let html = "<style>p { color: red }</style><!-- hidden --><p>Visible</p><script>alert(1)</script>"
    #expect(ReleaseNotesHTML.markdown(fromHTML: html) == "Visible")
}

@Test func plainTextAndMarkdownAreNotTreatedAsHTML() {
    #expect(!ReleaseNotesHTML.isHTML("Fixed a crash when 2 < 3"))
    #expect(!ReleaseNotesHTML.isHTML("See <https://example.com> for details"))
    #expect(ReleaseNotesHTML.isHTML("<P>Fixed</P>"))
}

@Test func sparkleFeedConvertsHTMLAndKeepsDeclaredMarkdown() throws {
    func notes(_ description: String) throws -> String? {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel><item>
            \(description)
            <enclosure url="https://example.com/app.zip" sparkle:shortVersionString="2.0" />
          </item></channel>
        </rss>
        """
        let parser = SparkleFeedParser(
            data: try #require(xml.data(using: .utf8)),
            baseURL: try #require(URL(string: "https://example.com/appcast.xml"))
        )
        return try #require(parser.parse()).releaseNotes
    }
    #expect(try notes("<description><![CDATA[<h2>Fixes</h2><ul><li>One</li><li>Two</li></ul>]]></description>")
        == "## Fixes\n\n- One\n- Two")
    #expect(try notes("<description sparkle:format=\"markdown\"><![CDATA[# Fixes\n\n- One <b>raw</b>]]></description>")
        == "# Fixes\n\n- One <b>raw</b>")
}
