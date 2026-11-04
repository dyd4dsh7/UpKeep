import Foundation

/// Curated identities, never inferred from display names or arbitrary repository mappings.
struct CVEProduct: Hashable, Sendable {
    let vendor: String
    let product: String
    let version: String

    var cpeName: String { "cpe:2.3:a:\(vendor):\(product):\(version):*:*:*:*:mac_os_x:*:*" }

    static let bundleProducts: [String: (String, String)] = [
        "com.google.Chrome": ("google", "chrome"),
        "org.mozilla.firefox": ("mozilla", "firefox"),
        "org.mozilla.thunderbird": ("mozilla", "thunderbird"),
        "com.apple.Safari": ("apple", "safari"),
        "org.videolan.vlc": ("videolan", "vlc_media_player"),
        "com.microsoft.VSCode": ("microsoft", "visual_studio_code")
    ]
    static let caskBundles: [String: String] = [
        "google-chrome": "com.google.Chrome", "firefox": "org.mozilla.firefox",
        "thunderbird": "org.mozilla.thunderbird", "vlc": "org.videolan.vlc",
        "visual-studio-code": "com.microsoft.VSCode"
    ]

    init?(bundleID: String?, version: String) {
        guard let bundleID, let identity = Self.bundleProducts[bundleID],
              version.range(of: #"^[0-9]+(?:\.[0-9]+)*$"#, options: .regularExpression) != nil else { return nil }
        vendor = identity.0
        product = identity.1
        self.version = version
    }
}

struct CVEInventoryItem: Identifiable, Hashable, Sendable {
    enum Target: Hashable, Sendable {
        case developer(DeveloperPackage)
        case formula(name: String, version: String)
        case nvd(CVEProduct)
    }
    let id: String
    let name: String
    let version: String
    let origin: String
    let target: Target?
    let coverage: String

    init(_ package: DeveloperPackage) {
        id = "developer|\(package.id)"; name = package.name; version = package.currentVersion
        origin = "Developer · \(package.manager.rawValue)"
        target = CVEPackageQuery(package) == nil ? nil : .developer(package)
        coverage = target == nil ? "No supported registry identity or installed version." : "OSV registry advisories"
    }

    init(_ app: InstalledApp) {
        id = "app|\(app.id)"; name = app.name; version = app.installedVersion; origin = "Installed app"
        target = CVEProduct(bundleID: app.bundleIdentifier, version: version).map(Target.nvd)
        coverage = target == nil ? "No curated product mapping or supported installed version."
            : "NVD product/version matches; review platform and configuration applicability."
    }

    init(_ package: HomebrewPackage) {
        id = "brew|\(package.id)"; name = package.displayName; version = package.installedVersion
        origin = "Homebrew \(package.kind.rawValue.lowercased())"
        if package.kind == .formula, package.tap == "homebrew/core", package.versionScheme == 0,
           HomebrewAdvisoryVersion.isSupported(version) {
            target = .formula(name: package.token, version: version)
            coverage = "Homebrew advisory feed, including formula revisions; feed coverage is limited."
        } else if package.kind == .cask, package.tap == "homebrew/cask",
                  let bundle = CVEProduct.caskBundles[package.token],
                  let product = CVEProduct(bundleID: bundle, version: String(version.split(separator: ",").first ?? "")) {
            target = .nvd(product)
            coverage = "NVD product/version matches from the Homebrew receipt; refresh app inventory to verify the bundle version."
        } else {
            target = nil
            coverage = "Tap identity, version format, or product mapping is not covered. Refresh Homebrew inventory if tap identity is missing."
        }
    }
}

struct CVEInventoryResult: Identifiable, Sendable {
    let item: CVEInventoryItem
    let advisories: [CVEAdvisory]
    let failure: String?
    var id: String { item.id }
    var supported: Bool { item.target != nil }
    var advisoryGroups: [CVEAdvisoryGroup] { CVEAdvisoryGroup.grouped(advisories) }
    var sortPriority: Int {
        if !advisories.isEmpty { return 0 }
        if supported && failure != nil { return 1 }
        return supported ? 2 : 3
    }
    var status: String {
        if !supported { return "Not covered" }
        if failure != nil { return "Check incomplete" }
        if advisories.isEmpty { return "No known advisories returned" }
        let count = advisoryGroups.count
        if case .nvd? = item.target { return "\(count) potential CVE\(count == 1 ? "" : "s")" }
        return "\(count) advisor\(count == 1 ? "y" : "ies")"
    }
}
