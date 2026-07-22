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
    #expect(item.buildVersion == nil)
    #expect(item.downloadURL?.absoluteString == "https://example.com/app-3.zip")
    #expect(item.installationType == .application)
}

@Test func preservesVersionsDeclaredBeforeEnclosure() throws {
    let xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
      <channel>
        <item>
          <sparkle:version>9727</sparkle:version>
          <sparkle:shortVersionString>2.4.2</sparkle:shortVersionString>
          <enclosure url="https://example.com/app.zip" />
        </item>
      </channel>
    </rss>
    """
    let parser = SparkleFeedParser(
        data: try #require(xml.data(using: .utf8)),
        baseURL: try #require(URL(string: "https://example.com/appcast.xml"))
    )

    let item = try #require(parser.parse())
    #expect(item.version == "2.4.2")
    #expect(item.buildVersion == "9727")
    #expect(item.downloadURL?.absoluteString == "https://example.com/app.zip")
}

@Test func recognizesSparklePackageInstallers() throws {
    let xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
      <channel>
        <item><enclosure url="https://example.com/app.pkg" sparkle:shortVersionString="3.0" /></item>
      </channel>
    </rss>
    """
    let parser = SparkleFeedParser(
        data: try #require(xml.data(using: .utf8)),
        baseURL: try #require(URL(string: "https://example.com/appcast.xml"))
    )

    #expect(parser.parse()?.installationType == .package)
}

@Test func recognizesArchivedSparklePackageInstallers() throws {
    let xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
      <channel>
        <item><enclosure url="https://example.com/app.zip" sparkle:shortVersionString="3.0" sparkle:installationType="package" /></item>
      </channel>
    </rss>
    """
    let parser = SparkleFeedParser(
        data: try #require(xml.data(using: .utf8)),
        baseURL: try #require(URL(string: "https://example.com/appcast.xml"))
    )

    #expect(parser.parse()?.installationType == .package)
}

@Test func parsesMarketingAndBuildVersions() throws {
    let xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
      <channel>
        <item><enclosure url="https://example.com/app-100.zip" sparkle:shortVersionString="2.0" sparkle:version="100" /></item>
        <item><enclosure url="https://example.com/app-101.zip" sparkle:shortVersionString="2.0" sparkle:version="101" /></item>
      </channel>
    </rss>
    """
    let parser = SparkleFeedParser(
        data: try #require(xml.data(using: .utf8)),
        baseURL: try #require(URL(string: "https://example.com/appcast.xml"))
    )

    let item = try #require(parser.parse())
    #expect(item.version == "2.0")
    #expect(item.buildVersion == "101")
    #expect(item.hasMarketingVersion)
}

@Test func filtersPrereleaseAppcastItemsWhenDisabled() throws {
    let xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
      <channel>
        <item><enclosure url="https://example.com/stable.zip" sparkle:shortVersionString="1.9" /></item>
        <item><enclosure url="https://example.com/beta.zip" sparkle:shortVersionString="2.0-beta.1" /></item>
      </channel>
    </rss>
    """
    let parser = SparkleFeedParser(
        data: try #require(xml.data(using: .utf8)),
        baseURL: try #require(URL(string: "https://example.com/appcast.xml"))
    )

    #expect(parser.parse(includePrereleases: false)?.version == "1.9")
    #expect(parser.parse(includePrereleases: true)?.version == "2.0-beta.1")
}

@Test func filtersSparkleDeclaredChannelWithStableLookingVersion() throws {
    let xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
      <channel>
        <item><enclosure url="https://example.com/stable.zip" sparkle:shortVersionString="1.9" /></item>
        <item>
          <sparkle:channel>beta</sparkle:channel>
          <enclosure url="https://example.com/beta.zip" sparkle:shortVersionString="2.0" />
        </item>
      </channel>
    </rss>
    """
    let parser = SparkleFeedParser(
        data: try #require(xml.data(using: .utf8)),
        baseURL: try #require(URL(string: "https://example.com/appcast.xml"))
    )

    #expect(parser.parse(includePrereleases: false)?.version == "1.9")
    let beta = try #require(parser.parse(includePrereleases: true))
    #expect(beta.version == "2.0")
    #expect(beta.prereleaseChannel == .beta)
}

@Test func prereleaseOnlySparkleFeedIsNotMalformedWhenFiltered() throws {
    let xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
      <channel>
        <item><enclosure url="https://example.com/beta.zip" sparkle:shortVersionString="2.0-beta.1" /></item>
      </channel>
    </rss>
    """
    let parser = SparkleFeedParser(
        data: try #require(xml.data(using: .utf8)),
        baseURL: try #require(URL(string: "https://example.com/appcast.xml"))
    )

    #expect(parser.parse(includePrereleases: false) == nil)
    #expect(parser.hasParsedItems)
}

@Test func parsesCDATAReleaseNotes() throws {
    let xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
      <channel>
        <item>
          <description><![CDATA[<p>Important fixes & improvements.</p>]]></description>
          <enclosure url="https://example.com/app.zip" sparkle:shortVersionString="2.0" />
        </item>
      </channel>
    </rss>
    """
    let parser = SparkleFeedParser(
        data: try #require(xml.data(using: .utf8)),
        baseURL: try #require(URL(string: "https://example.com/appcast.xml"))
    )

    #expect(try #require(parser.parse()).releaseNotes == "Important fixes & improvements.")
}
