import Foundation

struct SparkleClient: Sendable {
    func update(for app: InstalledApp, includePrereleases: Bool = false) async throws -> AvailableUpdate? {
        guard let feedURL = app.sparkleFeedURL else { return nil }
        do {
            let data = try await Self.appcastData(from: feedURL)

            let parser = SparkleFeedParser(data: data, baseURL: feedURL)
            // An installed prerelease keeps its channel, like GitHub and Electron feeds.
            let followsPrereleases = includePrereleases || VersionComparator.isPrerelease(app.installedVersion)
            guard let item = parser.parse(includePrereleases: followsPrereleases) else {
                if parser.hasParsedItems { return nil }
                throw UpdateSourceError.malformedData("No valid release entries were found.")
            }
            guard item.isNewer(than: app) else { return nil }

            return item.availableUpdate(for: app, fallbackURL: feedURL)
        } catch { throw UpdateSourceError(error) }
    }

    /// Appcasts change rarely; repeat scans within this window reuse the
    /// cached response, matching how GitHub release metadata is cached.
    static let appcastCacheMaximumAge: TimeInterval = 10 * 60

    static func appcastCacheKey(for feedURL: URL) -> String { "sparkle-" + feedURL.absoluteString }

    private static func appcastData(from feedURL: URL) async throws -> Data {
        try await PublisherResponseCache.shared.data(
            for: appcastCacheKey(for: feedURL),
            maximumAge: appcastCacheMaximumAge
        ) {
            var request = URLRequest(url: feedURL)
            request.timeoutInterval = 15
            request.setValue("Upkeep/1.0", forHTTPHeaderField: "User-Agent")
            let (data, http) = try await PublisherHTTPClient.data(for: request)
            // Only successful responses reach the cache.
            guard 200..<300 ~= http.statusCode else { throw UpdateSourceError.httpStatus(http.statusCode) }
            return data
        }
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
    let hasEdSignature: Bool
    let minimumSystemVersion: String?
    let maximumSystemVersion: String?
    let hardwareRequirements: String?

    func availableUpdate(for app: InstalledApp, fallbackURL: URL) -> AvailableUpdate {
        AvailableUpdate(
            app: app, availableVersion: version, source: .sparkle,
            releaseNotes: releaseNotes, actionURL: downloadURL ?? fallbackURL,
            homebrewToken: nil, sourcePrereleaseChannel: prereleaseChannel,
            requiresInAppInstallation: installationType == .package,
            verification: hasEdSignature ? .sparkleSignature : .publisherFeed,
            availableBuildVersion: buildVersion, usesBuildVersionOnly: !hasMarketingVersion
        )
    }

    var prereleaseChannel: PrereleaseChannel? {
        sourcePrereleaseChannel ?? VersionComparator.prereleaseChannel(for: version)
    }

    func isNewer(than app: InstalledApp) -> Bool {
        // Sparkle compares sparkle:version with CFBundleVersion when both exist.
        if let buildVersion, !buildVersion.isEmpty, let installedBuild = app.buildVersion, !installedBuild.isEmpty {
            return VersionComparator.isNewer(buildVersion, than: installedBuild)
        }
        if hasMarketingVersion {
            let marketingComparison = VersionComparator.compare(version, app.installedVersion)
            if marketingComparison != .orderedSame { return marketingComparison == .orderedDescending }
        }
        guard let buildVersion else { return false }
        return VersionComparator.isNewer(buildVersion, than: app.buildVersion ?? app.installedVersion)
    }
}

final class SparkleFeedParser: XMLTextParser {
    private static let maximumItems = 1_000
    private static let maximumFieldCharacters = 256_000
    private let data: Data
    private let baseURL: URL
    private var items: [SparkleFeedItem] = []
    private var inItem = false
    private var deltaDepth = 0
    private var currentElement = ""
    private var currentText = ""
    private var version: String?
    private var buildVersion: String?
    private var hasMarketingVersion = false
    private var sourcePrereleaseChannel: PrereleaseChannel?
    private var releaseNotes: String?
    private var descriptionIsMarkdown = false
    private var downloadURL: URL?
    private var installationType: SparkleInstallationType = .application
    private var hasEdSignature = false
    private var minimumSystemVersion: String?
    private var maximumSystemVersion: String?
    private var hardwareRequirements: String?
    private(set) var hasParsedItems = false

    init(data: Data, baseURL: URL) {
        self.data = data
        self.baseURL = baseURL
    }

    func parse(includePrereleases: Bool = true, compatibility: AppCompatibility = .current) -> SparkleFeedItem? {
        items.removeAll(keepingCapacity: true)
        hasParsedItems = false
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            hasParsedItems = false
            return nil
        }
        return items
            .filter { includePrereleases || $0.prereleaseChannel == nil }
            .filter { compatibility.permits(minimum: $0.minimumSystemVersion,
                                            maximum: $0.maximumSystemVersion,
                                            hardware: $0.hardwareRequirements) }
            .max { left, right in
                if let leftBuild = left.buildVersion, let rightBuild = right.buildVersion {
                    let buildComparison = VersionComparator.compare(leftBuild, rightBuild)
                    if buildComparison != .orderedSame { return buildComparison == .orderedAscending }
                }
                let versionComparison = VersionComparator.compare(left.version, right.version)
                if versionComparison != .orderedSame { return versionComparison == .orderedAscending }
                return left.buildVersion == nil && right.buildVersion != nil
            }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "sparkle:deltas" || elementName == "deltas" || deltaDepth > 0 {
            deltaDepth += 1
            return
        }
        currentElement = qName ?? elementName
        currentText = ""
        if elementName == "description" {
            // Sparkle 2 lets feeds declare Markdown release notes; otherwise they are HTML.
            let format = attributeDict["sparkle:format"] ?? attributeDict["format"]
            descriptionIsMarkdown = format?.lowercased() == "markdown"
        }
        if elementName == "item" {
            inItem = true
            version = nil
            buildVersion = nil
            hasMarketingVersion = false
            sourcePrereleaseChannel = nil
            releaseNotes = nil
            downloadURL = nil
            installationType = .application
            hasEdSignature = false
            minimumSystemVersion = nil
            maximumSystemVersion = nil
            hardwareRequirements = nil
        }
        guard inItem, elementName == "enclosure" else { return }
        let shortVersion = attributeDict["sparkle:shortVersionString"]
            ?? attributeDict["shortVersionString"]
        let enclosureBuildVersion = attributeDict["sparkle:version"] ?? attributeDict["version"]
        if let enclosureBuildVersion { buildVersion = enclosureBuildVersion }
        if let channel = attributeDict["sparkle:channel"] ?? attributeDict["channel"] {
            sourcePrereleaseChannel = Self.channel(named: channel) ?? sourcePrereleaseChannel
        }
        if let shortVersion, !shortVersion.isEmpty {
            version = Self.marketingVersion(shortVersion, build: enclosureBuildVersion ?? buildVersion)
            hasMarketingVersion = true
        } else if version == nil, let enclosureBuildVersion {
            version = enclosureBuildVersion
        }
        if let urlString = attributeDict["url"] {
            downloadURL = URL(string: urlString, relativeTo: baseURL)?.absoluteURL
        }
        hasEdSignature = !(attributeDict["sparkle:edSignature"]
            ?? attributeDict["edSignature"]
            ?? "").isEmpty
        let declaredInstallationType = attributeDict["sparkle:installationType"]
            ?? attributeDict["installationType"]
        let extensionName = downloadURL?.pathExtension.lowercased()
        if declaredInstallationType?.lowercased().contains("package") == true
            || extensionName == "pkg" || extensionName == "mpkg" {
            installationType = .package
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if deltaDepth > 0 {
            deltaDepth -= 1
            return
        }
        guard inItem else { return }
        let qualified = qName ?? elementName
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let localName = qualified.split(separator: ":").last.map(String.init) ?? elementName
        if localName == "minimumSystemVersion" {
            minimumSystemVersion = text
        } else if localName == "maximumSystemVersion" {
            maximumSystemVersion = text
        } else if localName == "hardwareRequirements" {
            hardwareRequirements = text
        } else if qualified == "sparkle:shortVersionString" || elementName == "shortVersionString" {
            if !text.isEmpty {
                version = Self.marketingVersion(text, build: buildVersion)
                hasMarketingVersion = true
            }
        } else if qualified == "sparkle:version" || elementName == "version" {
            if !text.isEmpty {
                buildVersion = text
                if version == nil { version = text }
            }
        } else if qualified == "sparkle:channel" || elementName == "channel" {
            if let channel = Self.channel(named: text) { sourcePrereleaseChannel = channel }
        } else if elementName == "description" {
            releaseNotes = !descriptionIsMarkdown && ReleaseNotesHTML.isHTML(text)
                ? ReleaseNotesHTML.markdown(fromHTML: text)
                : text
        } else if elementName == "item" {
            guard items.count < Self.maximumItems else {
                parser.abortParsing()
                return
            }
            if let version {
                items.append(SparkleFeedItem(
                    version: version,
                    buildVersion: buildVersion,
                    hasMarketingVersion: hasMarketingVersion,
                    sourcePrereleaseChannel: sourcePrereleaseChannel,
                    releaseNotes: releaseNotes,
                    downloadURL: downloadURL,
                    installationType: installationType,
                    hasEdSignature: hasEdSignature,
                    minimumSystemVersion: minimumSystemVersion,
                    maximumSystemVersion: maximumSystemVersion,
                    hardwareRequirements: hardwareRequirements
                ))
                hasParsedItems = true
            }
            inItem = false
        }
        currentElement = ""
        currentText = ""
    }

    /// Sparkle offers items on any named channel only to users who opt in.
    /// Unknown names such as "canary" or "insider" are therefore prereleases.
    static func channel(named rawName: String) -> PrereleaseChannel? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty, !["default", "release", "stable", "production"].contains(name) else { return nil }
        return VersionComparator.prereleaseChannel(for: name) ?? .prerelease
    }

    /// Some feeds annotate shortVersionString with the build, e.g. "1.4.2 (812)".
    static func marketingVersion(_ value: String, build: String?) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(")"), let open = trimmed.lastIndex(of: "(") else { return trimmed }
        let annotation = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)]
            .trimmingCharacters(in: .whitespaces).lowercased()
        let normalizedBuild = build?.trimmingCharacters(in: .whitespaces).lowercased()
        let isBuildAnnotation = annotation == normalizedBuild
            || annotation.hasPrefix("build") || annotation.allSatisfy(\.isNumber)
        let base = trimmed[..<open].trimmingCharacters(in: .whitespaces)
        return isBuildAnnotation && base.contains(where: \.isNumber) ? base : trimmed
    }

    override func appendXMLText(_ string: String, parser: XMLParser) {
        guard inItem, deltaDepth == 0 else { return }
        guard string.count <= Self.maximumFieldCharacters,
              currentText.count <= Self.maximumFieldCharacters - string.count else {
            parser.abortParsing()
            return
        }
        currentText += string
    }
}
