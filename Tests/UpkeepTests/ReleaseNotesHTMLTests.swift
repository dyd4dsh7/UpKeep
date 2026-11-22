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

@Test func githubMarkdownWithHTMLConvertsTagsAndKeepsMarkdown() {
    let body = "## Changes\r\n\r\n- Fix <b>sync</b><br>\r\n  on Wi-Fi\r\n- Faster `<br>` parsing\r\n\r\n"
        + "<details>\r\n<summary>Full log</summary>\r\n\r\n* one\r\n* two\r\n</details>\r\n\r\n"
        + "<p align=\"center\"><img src=\"https://example.com/x.png\" width=\"200\"></p>\r\n"
        + "See <https://example.com> and <a href=\"https://example.com/pr/1\">#1</a>."
    #expect(ReleaseNotesHTML.markdown(fromMarkdownWithHTML: body) == """
    ## Changes

    - Fix **sync**
      on Wi-Fi
    - Faster `<br>` parsing

    **Full log**

    * one
    * two

    See <https://example.com> and [#1](<https://example.com/pr/1>).
    """)
}

@Test func githubMarkdownWithHTMLLeavesFencedCodeAlone() {
    let body = "<p>Example:</p>\n\n```html\n<div>kept</div>\n```\nDone<br>"
    #expect(ReleaseNotesHTML.markdown(fromMarkdownWithHTML: body)
        == "Example:\n\n```html\n<div>kept</div>\n```\nDone")
}

@Test func githubMarkdownWithoutHTMLIsUnchanged() {
    let body = "## Fixes\r\n\r\n- See <https://example.com>\r\n- 2 < 3"
    #expect(ReleaseNotesHTML.markdown(fromMarkdownWithHTML: body) == body)
}

@Test func releaseNotesTreatCRLFAsOneLineBreak() {
    let text = ReleaseNotesFormatter.attributedString(from: "## Fixes\r\n\r\n- One\r\n- Two")
    #expect(String(text.characters) == "Fixes\n\n• One\n• Two")
}

@Test func githubAtomContentKeepsReleaseStructure() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <entry>
        <link rel="alternate" type="text/html" href="https://github.com/owner/app/releases/tag/v2.0"/>
        <title>v2.0</title>
        <content type="html">&lt;h2&gt;Fixes&lt;/h2&gt;
    &lt;ul&gt;
    &lt;li&gt;One&lt;/li&gt;
    &lt;li&gt;Two &amp;amp; three&lt;/li&gt;
    &lt;/ul&gt;</content>
      </entry>
    </feed>
    """
    let entries = try GitHubAtomClient.entries(data: try #require(xml.data(using: .utf8)))
    #expect(entries.first?.content == "## Fixes\n\n- One\n- Two & three")
}

@Test func detailsAloneCountsAsHTML() {
    let body = "# Changelog\r\n <details>\r\n <summary>Changelog</summary>\r\n\r\n- One\r\n</details>"
    #expect(ReleaseNotesHTML.isHTML(body))
    #expect(ReleaseNotesHTML.markdown(fromMarkdownWithHTML: body) == "# Changelog\n\n**Changelog**\n\n- One")
}

@Test func githubTableRowsKeepLineBreakTagsOnOneLine() {
    let body = "| Platform | Notes |\n|---|---|\n| Mac | Fast<br>Native |\n\nDone<br>"
    #expect(ReleaseNotesHTML.markdown(fromMarkdownWithHTML: body)
        == "| Platform | Notes |\n|---|---|\n| Mac | Fast Native |\n\nDone")
}
