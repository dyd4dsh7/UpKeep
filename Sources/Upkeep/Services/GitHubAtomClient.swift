import Foundation

struct GitHubAtomEntry: Equatable, Sendable {
    let tagName: String
    let title: String
    let htmlURL: String
    let content: String?
}

enum GitHubAtomClient {
    static func entries(repository: String) async throws -> [GitHubAtomEntry] {
        guard let url = URL(string: "https://github.com/\(repository)/releases.atom") else {
            return []
        }
        let data = try await PublisherResponseCache.shared.data(
            for: "github-atom-\(repository.lowercased())",
            maximumAge: 30 * 60
        ) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("application/atom+xml", forHTTPHeaderField: "Accept")
            request.setValue("Upkeep/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw UpdateSourceError.invalidResponse
            }
            guard http.statusCode == 200 else {
                throw UpdateSourceError.httpStatus(http.statusCode)
            }
            return data
        }
        return try entries(data: data)
    }

    static func entries(data: Data) throws -> [GitHubAtomEntry] {
        let parser = GitHubAtomParser(data: data)
        guard parser.parse() else {
            throw UpdateSourceError.malformedData("GitHub’s release feed could not be read.")
        }
        return parser.entries
    }
}

private final class GitHubAtomParser: NSObject, XMLParserDelegate {
    private let data: Data
    private(set) var entries: [GitHubAtomEntry] = []
    private var inEntry = false
    private var currentElement = ""
    private var currentText = ""
    private var title = ""
    private var content = ""
    private var htmlURL = ""

    init(data: Data) {
        self.data = data
    }

    func parse() -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser.parse()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        currentText = ""
        if elementName == "entry" {
            inEntry = true
            title = ""
            content = ""
            htmlURL = ""
        } else if inEntry, elementName == "link",
                  attributeDict["rel"] == "alternate" {
            htmlURL = attributeDict["href"] ?? ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inEntry { currentText += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if inEntry { currentText += String(decoding: CDATABlock, as: UTF8.self) }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard inEntry else { return }
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if elementName == "title" {
            title = text
        } else if elementName == "content" {
            content = text.replacingOccurrences(
                of: "<[^>]+>",
                with: "",
                options: .regularExpression
            )
        } else if elementName == "entry" {
            let tagName = URL(string: htmlURL)?.lastPathComponent.removingPercentEncoding
                ?? title
            if !tagName.isEmpty, !htmlURL.isEmpty {
                entries.append(GitHubAtomEntry(
                    tagName: tagName,
                    title: title,
                    htmlURL: htmlURL,
                    content: content.isEmpty ? nil : content
                ))
            }
            inEntry = false
        }
        currentText = ""
        currentElement = ""
    }
}
