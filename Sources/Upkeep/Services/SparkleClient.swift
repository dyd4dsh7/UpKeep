import Foundation

struct SparkleClient: Sendable {
    func update(for app: InstalledApp) async throws -> AvailableUpdate? {
        guard let feedURL = app.sparkleFeedURL else { return nil }
        do {
            var request = URLRequest(url: feedURL)
            request.timeoutInterval = 15
            request.setValue("Upkeep/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw UpdateSourceError.invalidResponse }
            guard 200..<300 ~= http.statusCode else { throw UpdateSourceError.httpStatus(http.statusCode) }

            let parser = SparkleFeedParser(data: data, baseURL: feedURL)
            guard let item = parser.parse() else {
                throw UpdateSourceError.malformedData("No valid release entries were found.")
            }
            guard VersionComparator.isNewer(item.version, than: app.installedVersion) else { return nil }

            return AvailableUpdate(
                app: app,
                availableVersion: item.version,
                source: .sparkle,
                releaseNotes: item.releaseNotes,
                actionURL: item.downloadURL ?? feedURL,
                homebrewToken: nil
            )
        } catch { throw UpdateSourceError(error) }
    }
}

struct SparkleFeedItem: Equatable {
    let version: String
    let releaseNotes: String?
    let downloadURL: URL?
}

final class SparkleFeedParser: NSObject, XMLParserDelegate {
    private let data: Data
    private let baseURL: URL
    private var items: [SparkleFeedItem] = []
    private var inItem = false
    private var currentElement = ""
    private var currentText = ""
    private var version: String?
    private var releaseNotes: String?
    private var downloadURL: URL?

    init(data: Data, baseURL: URL) {
        self.data = data
        self.baseURL = baseURL
    }

    func parse() -> SparkleFeedItem? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { return nil }
        return items.max { VersionComparator.compare($0.version, $1.version) == .orderedAscending }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = qName ?? elementName
        currentText = ""
        if elementName == "item" {
            inItem = true
            version = nil
            releaseNotes = nil
            downloadURL = nil
        }
        guard inItem, elementName == "enclosure" else { return }
        version = attributeDict["sparkle:shortVersionString"]
            ?? attributeDict["shortVersionString"]
            ?? attributeDict["sparkle:version"]
            ?? attributeDict["version"]
        if let urlString = attributeDict["url"] {
            downloadURL = URL(string: urlString, relativeTo: baseURL)?.absoluteURL
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inItem { currentText += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard inItem else { return }
        let qualified = qName ?? elementName
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if qualified == "sparkle:shortVersionString" || elementName == "shortVersionString" {
            if !text.isEmpty { version = text }
        } else if elementName == "description" {
            releaseNotes = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        } else if elementName == "item" {
            if let version {
                items.append(SparkleFeedItem(version: version, releaseNotes: releaseNotes, downloadURL: downloadURL))
            }
            inItem = false
        }
        currentElement = ""
        currentText = ""
    }
}
