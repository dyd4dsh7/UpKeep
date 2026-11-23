import Foundation

/// Apps whose publisher runs a public version service. Each mapping and
/// endpoint was checked against the vendor's shipped bundle or build sources.
enum VendorUpdateProduct: Hashable, Sendable {
    case jetBrains(code: String)
    case edge(EdgeUpdateChannel)
    case zoom
    case slack
    case onePassword
    case microsoftAutoUpdate(MicrosoftAutoUpdateRegistration)

    static func product(bundleIdentifier: String?) -> VendorUpdateProduct? {
        guard let identifier = bundleIdentifier?.lowercased() else { return nil }
        if let code = jetBrainsProductCodes[identifier] { return .jetBrains(code: code) }
        switch identifier {
        case "com.microsoft.edgemac": return .edge(.stable)
        case "com.microsoft.edgemac.beta": return .edge(.beta)
        case "com.microsoft.edgemac.dev": return .edge(.dev)
        case "com.microsoft.edgemac.canary": return .edge(.canary)
        case "us.zoom.xos": return .zoom
        case "com.tinyspeck.slackmacgap": return .slack
        case "com.1password.1password": return .onePassword
        default: return nil
        }
    }

    /// Release bundle IDs only; EAP builds append "-EAP" and are not mapped.
    private static let jetBrainsProductCodes: [String: String] = [
        "com.jetbrains.intellij": "IIU",
        "com.jetbrains.intellij.ce": "IIC",
        "com.jetbrains.pycharm": "PCP",
        "com.jetbrains.pycharm.ce": "PCC",
        "com.jetbrains.webstorm": "WS",
        "com.jetbrains.goland": "GO",
        "com.jetbrains.clion": "CL",
        "com.jetbrains.rider": "RD",
        "com.jetbrains.datagrip": "DG",
        "com.jetbrains.rubymine": "RM",
        "com.jetbrains.phpstorm": "PS",
        "com.jetbrains.rustrover": "RR"
    ]

    var publisherName: String {
        switch self {
        case .jetBrains: "JetBrains"
        case .edge: "Microsoft Edge"
        case .zoom: "Zoom"
        case .slack: "Slack"
        case .onePassword: "1Password"
        case .microsoftAutoUpdate: "Microsoft AutoUpdate"
        }
    }
}

/// Microsoft AutoUpdate channels and the manifest folder each one reads.
/// The channel names and IDs were checked against AutoUpdate's preferences and
/// Microsoft's CDN; "InsiderFast", "External" and "InsiderSlow" are older names.
enum MicrosoftAutoUpdateChannel: String, Hashable, Sendable {
    case production = "Current"
    case preview = "Preview"
    case beta = "Beta"

    init(name: String?) {
        switch name?.lowercased() {
        case "beta", "insiderfast": self = .beta
        case "preview", "external", "insiderslow": self = .preview
        default: self = .production
        }
    }

    var manifestFolder: String {
        switch self {
        case .production: "C1297A47-86C4-4C1F-97FA-950631F94777"
        case .preview: "1ac37578-5a24-40fb-892e-b89d85b6dfaa"
        case .beta: "4B2D7701-0A4F-49C8-B4CB-0C2D4043F51F"
        }
    }
}

struct MicrosoftAutoUpdateRegistration: Hashable, Sendable {
    /// Such as MSWD2019 for Word. Nil when AutoUpdate did not record one.
    let applicationID: String?
    let channel: MicrosoftAutoUpdateChannel

    var manifestURL: URL? {
        applicationID.flatMap {
            URL(string: "https://officecdnmac.microsoft.com/pr/\(channel.manifestFolder)/MacAutoupdate/0409\($0).xml")
        }
    }
}

enum EdgeUpdateChannel: String, Hashable, Sendable {
    case stable = "Stable"
    case beta = "Beta"
    case dev = "Dev"
    case canary = "Canary"
}

/// A publisher's newest release. `build` is written the way the app's own
/// CFBundleVersion is, so pending in-app updates can be confirmed later.
struct VendorRelease: Equatable, Sendable {
    let version: String
    let build: String?
}

struct VendorUpdateClient: Sendable {
    static let cacheMaximumAge: TimeInterval = 30 * 60

    func update(for app: InstalledApp, product: VendorUpdateProduct) async throws -> AvailableUpdate? {
        do {
            guard let release = try await latestRelease(for: product, app: app),
                  Self.isNewer(release, than: app, product: product)
            else { return nil }
            if case let .microsoftAutoUpdate(registration) = product {
                // AutoUpdate installs the update; the build number confirms it afterwards.
                return AvailableUpdate(
                    app: app,
                    availableVersion: release.version,
                    source: .developer,
                    releaseNotes: "Available from Microsoft AutoUpdate (\(registration.channel.rawValue) channel).",
                    actionURL: URL(fileURLWithPath: Self.microsoftAutoUpdateApplication),
                    homebrewToken: nil,
                    availableBuildVersion: release.build,
                    usesBuildVersionOnly: true
                )
            }
            return AvailableUpdate(
                app: app,
                availableVersion: release.version,
                source: .developer,
                releaseNotes: "Available from the \(product.publisherName) update service.",
                actionURL: nil,
                homebrewToken: nil,
                requiresInAppInstallation: true,
                availableBuildVersion: release.build
            )
        } catch let error as UpdateSourceError {
            throw error
        } catch {
            throw UpdateSourceError(error)
        }
    }

    static let microsoftAutoUpdateApplication = "/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app"

    static func isNewer(_ release: VendorRelease, than app: InstalledApp, product: VendorUpdateProduct) -> Bool {
        switch product {
        case .jetBrains, .zoom, .microsoftAutoUpdate:
            // Marketing strings carry annotations ("7.2.5 (90525)") or omit patch
            // builds; the build number is exact for both.
            if let build = release.build, let installed = app.buildVersion {
                return VersionComparator.isNewer(numericBuild(build), than: numericBuild(installed))
            }
            return VersionComparator.isNewer(release.version, than: app.installedVersion)
        case .edge, .slack, .onePassword:
            return VersionComparator.isNewer(release.version, than: app.installedVersion)
        }
    }

    /// "IU-263.7307.200" → "263.7307.200".
    static func numericBuild(_ build: String) -> String {
        guard let first = build.firstIndex(where: \.isNumber) else { return build }
        return String(build[first...])
    }

    private func latestRelease(for product: VendorUpdateProduct, app: InstalledApp) async throws -> VendorRelease? {
        switch product {
        case let .jetBrains(code):
            let url = URL(string: "https://data.services.jetbrains.com/products/releases?code=\(code)&latest=true&type=release")!
            return try Self.jetBrainsRelease(from: await fetch(url, key: "jetbrains-\(code)"), code: code,
                installedBuild: app.buildVersion)
        case let .edge(channel):
            let url = URL(string: "https://edgeupdates.microsoft.com/api/products")!
            return try Self.edgeRelease(from: await fetch(url, key: "edge-products"), channel: channel)
        case .zoom:
            let url = URL(string: "https://zoom.us/rest/download?os=mac")!
            return try Self.zoomRelease(from: await fetch(url, key: "zoom-mac"))
        case .slack:
            let url = URL(string: "https://slack.com/api/desktop.latestRelease?arch=universal&variant=dmg")!
            return try Self.slackRelease(from: await fetch(url, key: "slack-mac"))
        case .onePassword:
            let url = URL(string: "https://releases.1password.com/mac/stable/index.xml")!
            return try Self.onePasswordRelease(from: await fetch(url, key: "1password-mac-stable"))
        case let .microsoftAutoUpdate(registration):
            guard let url = registration.manifestURL else { return nil }
            return try Self.microsoftAutoUpdateRelease(
                from: await fetch(url, key: "mau-\(registration.channel.manifestFolder)-\(registration.applicationID ?? "")"),
                installedVersion: app.installedVersion
            )
        }
    }

    private func fetch(_ url: URL, key: String) async throws -> Data {
        try await PublisherResponseCache.shared.data(for: "vendor-" + key, maximumAge: Self.cacheMaximumAge) {
            try await PublisherHTTPClient.data(from: url)
        }
    }

    // MARK: - Parsers

    static func jetBrainsRelease(from data: Data, code: String, installedBuild: String?) throws -> VendorRelease? {
        struct Release: Decodable { let version: String; let build: String? }
        let releases = try JSONDecoder().decode([String: [Release]].self, from: data)
        guard let release = releases[code]?.first else { return nil }
        // CFBundleVersion is "<product code>-<build>"; keep the installed prefix.
        let prefix = installedBuild.flatMap { installed -> String? in
            guard let dash = installed.firstIndex(of: "-"),
                  installed[..<dash].allSatisfy(\.isLetter) else { return nil }
            return String(installed[...dash])
        } ?? ""
        return VendorRelease(version: release.version, build: release.build.map { prefix + $0 })
    }

    static func edgeRelease(from data: Data, channel: EdgeUpdateChannel) throws -> VendorRelease? {
        struct Product: Decodable {
            struct Release: Decodable {
                let platform: String
                let productVersion: String
                enum CodingKeys: String, CodingKey {
                    case platform = "Platform"
                    case productVersion = "ProductVersion"
                }
            }
            let product: String
            let releases: [Release]
            enum CodingKeys: String, CodingKey {
                case product = "Product"
                case releases = "Releases"
            }
        }
        let products = try JSONDecoder().decode([Product].self, from: data)
        return products
            .first { $0.product == channel.rawValue }?
            .releases
            .filter { $0.platform == "MacOS" }
            .map(\.productVersion)
            .max { VersionComparator.compare($0, $1) == .orderedAscending }
            .map { VendorRelease(version: $0, build: nil) }
    }

    /// Zoom's `version` ("7.2.5.90525") matches CFBundleVersion and its
    /// `displayVersion` ("7.2.5 (90525)") matches CFBundleShortVersionString.
    static func zoomRelease(from data: Data) throws -> VendorRelease? {
        struct Response: Decodable {
            struct Result: Decodable {
                struct Downloads: Decodable {
                    struct Package: Decodable { let version: String; let displayVersion: String? }
                    let zoom: Package?
                }
                let downloadVO: Downloads?
            }
            let result: Result?
        }
        guard let package = try JSONDecoder().decode(Response.self, from: data).result?.downloadVO?.zoom,
              package.version.contains(where: \.isNumber) else { return nil }
        return VendorRelease(version: package.displayVersion ?? package.version, build: package.version)
    }

    static func slackRelease(from data: Data) throws -> VendorRelease? {
        struct Response: Decodable { let ok: Bool; let version: String? }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.ok, let version = response.version else {
            throw UpdateSourceError.malformedData("Slack did not return a release version.")
        }
        return VendorRelease(version: version, build: nil)
    }

    /// A Microsoft AutoUpdate manifest: a plist array with one entry per
    /// baseline build, each naming the "Update Version" it moves to. Entries
    /// for another architecture or a newer macOS are skipped.
    static func microsoftAutoUpdateRelease(
        from data: Data,
        installedVersion: String,
        operatingSystem: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) throws -> VendorRelease? {
        guard let entries = try PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else {
            throw UpdateSourceError.malformedData("The Microsoft AutoUpdate manifest is not a list.")
        }
        #if arch(arm64)
        let architectures: Set<String> = ["arm64", "arm64e", "universal"]
        #else
        let architectures: Set<String> = ["x86_64", "universal"]
        #endif
        let system = "\(operatingSystem.majorVersion).\(operatingSystem.minorVersion).\(operatingSystem.patchVersion)"
        let builds = entries.compactMap { entry -> String? in
            if let architecture = (entry["Architecture"] as? String)?.lowercased(), !architectures.contains(architecture) {
                return nil
            }
            if let minimum = entry["Minimum OS"] as? String, VersionComparator.isNewer(minimum, than: system) { return nil }
            return entry["Update Version"] as? String
        }
        guard let build = builds.max(by: { VersionComparator.compare($0, $1) == .orderedAscending }) else { return nil }
        // Show as many components as the app's own version: Word "16.117", Teams in full.
        let count = max(1, installedVersion.split(separator: ".").count)
        let version = build.split(separator: ".").prefix(count).joined(separator: ".")
        return VendorRelease(version: version, build: build)
    }

    /// The stable feed lists every release, oldest first.
    static func onePasswordRelease(from data: Data) throws -> VendorRelease? {
        guard let feed = String(data: data, encoding: .utf8) else {
            throw UpdateSourceError.malformedData("The 1Password release feed is not text.")
        }
        let regex = try NSRegularExpression(pattern: #"<title>1Password for Mac (\d+(?:\.\d+)+)</title>"#)
        return regex.matches(in: feed, range: NSRange(feed.startIndex..., in: feed))
            .compactMap { Range($0.range(at: 1), in: feed).map { String(feed[$0]) } }
            .max { VersionComparator.compare($0, $1) == .orderedAscending }
            .map { VendorRelease(version: $0, build: nil) }
    }
}
