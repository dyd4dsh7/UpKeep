import Foundation
import Testing
@testable import Upkeep

@Test func parsesNewestAppcastItem() throws {
    let xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
      <channel>
        <item><enclosure url="https://example.com/app-2.zip" sparkle:shortVersionString="2.0" /></item>
        <item><enclosure url="https://example.com/app-3.zip" sparkle:shortVersionString="3.0" /></item>
      </channel>
    </rss>
    """
    let parser = SparkleFeedParser(
        data: try #require(xml.data(using: .utf8)),
        baseURL: try #require(URL(string: "https://example.com/appcast.xml"))
    )
    let item = try #require(parser.parse())
    #expect(item.version == "3.0")
    #expect(item.downloadURL?.absoluteString == "https://example.com/app-3.zip")
}
