import Foundation

struct SparkleClient: Sendable {
    func update(for app: InstalledApp, includePrereleases: Bool = false) async throws -> AvailableUpdate? {
        guard let feedURL = app.sparkleFeedURL else { return nil }
        do {
            var request = URLRequest(url: feedURL)
            request.timeoutInterval = 15
            request.setValue("Upkeep/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw UpdateSourceError.invalidResponse }
            guard 200..<300 ~= http.statusCode else { throw UpdateSourceError.httpStatus(http.statusCode) }

            let parser = SparkleFeedParser(data: data, baseURL: feedURL)
            guard let item = parser.parse(includePrereleases: includePrereleases) else {
                if parser.hasParsedItems { return nil }
                throw UpdateSourceError.malformedData("No valid release entries were found.")
            }
            guard item.isNewer(than: app) else { return nil }

            return AvailableUpdate(
                app: app,
                availableVersion: item.version,
                source: .sparkle,
                releaseNotes: item.releaseNotes,
                actionURL: item.downloadURL ?? feedURL,
                homebrewToken: nil,
                sourcePrereleaseChannel: item.prereleaseChannel,
                requiresInAppInstallation: item.installationType == .package
            )
        } catch { throw UpdateSourceError(error) }
    }
}

enum SparkleInstallationType: String, Equatable, Sendable {
    case application
    case package
}

struct SparkleFeedItem: Equatable {
    let version: String
    let buildVersion: String?
    let hasMarketingVersion: Bool
    let sourcePrereleaseChannel: PrereleaseChannel?
    let releaseNotes: String?
    let downloadURL: URL?
    let installationType: SparkleInstallationType

    var prereleaseChannel: PrereleaseChannel? {
        sourcePrereleaseChannel ?? VersionComparator.prereleaseChannel(for: version)
    }

    func isNewer(than app: InstalledApp) -> Bool {
        if hasMarketingVersion {
            let marketingComparison = VersionComparator.compare(version, app.installedVersion)
            if marketingComparison != .orderedSame { return marketingComparison == .orderedDescending }
        }
        guard let buildVersion else { return false }
        return VersionComparator.isNewer(buildVersion, than: app.buildVersion ?? app.installedVersion)
    }
}

final class SparkleFeedParser: NSObject, XMLParserDelegate {
    private let data: Data
    private let baseURL: URL
    private var items: [SparkleFeedItem] = []
    private var inItem = false
    private var currentElement = ""
    private var currentText = ""
    private var version: String?
    private var buildVersion: String?
    private var hasMarketingVersion = false
    private var sourcePrereleaseChannel: PrereleaseChannel?
    private var releaseNotes: String?
    private var downloadURL: URL?
    private var installationType: SparkleInstallationType = .application
    private(set) var hasParsedItems = false

    init(data: Data, baseURL: URL) {
        self.data = data
        self.baseURL = baseURL
    }

    func parse(includePrereleases: Bool = true) -> SparkleFeedItem? {
        items.removeAll(keepingCapacity: true)
        hasParsedItems = false
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { return nil }
        return items
            .filter { includePrereleases || $0.prereleaseChannel == nil }
            .max { left, right in
                let versionComparison = VersionComparator.compare(left.version, right.version)
                if versionComparison != .orderedSame { return versionComparison == .orderedAscending }
                guard let leftBuild = left.buildVersion, let rightBuild = right.buildVersion else {
                    return left.buildVersion == nil && right.buildVersion != nil
                }
                return VersionComparator.compare(leftBuild, rightBuild) == .orderedAscending
            }
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
            buildVersion = nil
            hasMarketingVersion = false
            sourcePrereleaseChannel = nil
            releaseNotes = nil
            downloadURL = nil
            installationType = .application
        }
        guard inItem, elementName == "enclosure" else { return }
        let shortVersion = attributeDict["sparkle:shortVersionString"]
            ?? attributeDict["shortVersionString"]
        buildVersion = attributeDict["sparkle:version"] ?? attributeDict["version"]
        if let channel = attributeDict["sparkle:channel"] ?? attributeDict["channel"] {
            sourcePrereleaseChannel = VersionComparator.prereleaseChannel(for: channel)
        }
        version = shortVersion ?? buildVersion
        hasMarketingVersion = shortVersion != nil
        if let urlString = attributeDict["url"] {
            downloadURL = URL(string: urlString, relativeTo: baseURL)?.absoluteURL
        }
        let declaredInstallationType = attributeDict["sparkle:installationType"]
            ?? attributeDict["installationType"]
        let extensionName = downloadURL?.pathExtension.lowercased()
        if declaredInstallationType?.lowercased().contains("package") == true
            || extensionName == "pkg" || extensionName == "mpkg" {
            installationType = .package
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inItem { currentText += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard inItem else { return }
        currentText += String(decoding: CDATABlock, as: UTF8.self)
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
            if !text.isEmpty {
                version = text
                hasMarketingVersion = true
            }
        } else if qualified == "sparkle:version" || elementName == "version" {
            if !text.isEmpty {
                buildVersion = text
                if version == nil { version = text }
            }
        } else if qualified == "sparkle:channel" || elementName == "channel" {
            if !text.isEmpty { sourcePrereleaseChannel = VersionComparator.prereleaseChannel(for: text) }
        } else if elementName == "description" {
            releaseNotes = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        } else if elementName == "item" {
            if let version {
                items.append(SparkleFeedItem(
                    version: version,
                    buildVersion: buildVersion,
                    hasMarketingVersion: hasMarketingVersion,
                    sourcePrereleaseChannel: sourcePrereleaseChannel,
                    releaseNotes: releaseNotes,
                    downloadURL: downloadURL,
                    installationType: installationType
                ))
                hasParsedItems = true
            }
            inItem = false
        }
        currentElement = ""
        currentText = ""
    }
}
