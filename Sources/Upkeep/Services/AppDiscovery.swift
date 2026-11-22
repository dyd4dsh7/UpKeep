import CoreServices
import Foundation

enum AppDiscovery {
    static func discover() async -> [InstalledApp] {
        await Task.detached(priority: .userInitiated) {
            discoverSynchronously()
        }.value
    }

    /// Re-reads one application bundle without enumerating either Applications folder.
    static func discover(at url: URL) async -> InstalledApp? {
        await Task.detached(priority: .userInitiated) {
            app(at: url, microsoftRegisteredPaths: microsoftAutoUpdateRegisteredPaths())
        }.value
    }

    private static func discoverSynchronously() -> [InstalledApp] {
        let fileManager = FileManager.default
        let microsoftRegisteredPaths = microsoftAutoUpdateRegisteredPaths()
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]

        var discovered: [InstalledApp] = []
        var seenPaths = Set<String>()

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                guard seenPaths.insert(url.standardizedFileURL.path).inserted,
                      let app = app(at: url, microsoftRegisteredPaths: microsoftRegisteredPaths)
                else { continue }
                discovered.append(app)
            }
        }

        return discovered.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func app(at url: URL, microsoftRegisteredPaths: Set<String>) -> InstalledApp? {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        guard let infoData = try? Data(contentsOf: infoURL, options: .mappedIfSafe),
              let info = try? PropertyListSerialization.propertyList(
                from: infoData,
                options: [],
                format: nil
              ) as? [String: Any]
        else { return nil }
        let dates = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let bundleIdentifier = info["CFBundleIdentifier"] as? String
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let shortVersion = (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String)
            ?? "Unknown"
        let build = info["CFBundleVersion"] as? String
        let feed = sparkleFeedURL(
            info: info,
            bundleIdentifier: bundleIdentifier,
            defaults: .standard
        )
        let electronUpdate = electronUpdateMetadata(at: url)
        let identifier = bundleIdentifier?.lowercased()
        let repository = githubRepository(from: info, feedURL: feed)
            ?? electronUpdate.repository
            ?? trustedGitHubRepository(bundleIdentifier: identifier)
        let receiptURL = url.appendingPathComponent("Contents/_MASReceipt/receipt")
        let hasReceipt = FileManager.default.fileExists(atPath: receiptURL.path)
        let contentsURL = url.appendingPathComponent("Contents", isDirectory: true)
        let hasUpdaterFramework = containsBuiltInUpdaterFramework(in: contentsURL)
        let mozillaUpdate = mozillaUpdateMetadata(
            bundleIdentifier: bundleIdentifier,
            installedVersion: shortVersion
        )
        let chromiumUpdateChannel = chromiumUpdateChannel(bundleIdentifier: bundleIdentifier)
        let braveUpdateChannel = braveUpdateChannel(bundleIdentifier: bundleIdentifier)
        let vendorUpdateProduct = VendorUpdateProduct.product(bundleIdentifier: bundleIdentifier)
        let steamAppID = steamAppID(at: url)
        let management = updateManagement(
            bundleIdentifier: bundleIdentifier,
            appPath: url.standardizedFileURL.path,
            hasReceipt: hasReceipt,
            receiptType: hasReceipt ? appStoreReceiptType(at: url) : nil,
            hasEmbeddedProvisioningProfile: FileManager.default.fileExists(
                atPath: contentsURL.appendingPathComponent("embedded.provisionprofile").path
            ),
            hasSetappFramework: containsSetappFramework(in: contentsURL),
            isSteamLauncher: steamAppID != nil,
            microsoftRegisteredPaths: microsoftRegisteredPaths
        )
        let managedStatus = managedUpdateStatus(
            management: management,
            steamAppID: steamAppID
        )

        return InstalledApp(
            name: name,
            bundleIdentifier: bundleIdentifier,
            installedVersion: shortVersion,
            buildVersion: build,
            url: url,
            sparkleFeedURL: feed,
            githubRepository: repository,
            hasAppStoreReceipt: hasReceipt,
            updateManagement: management,
            hasBuiltInUpdater: feed != nil || electronUpdate.isConfigured
                || hasUpdaterFramework || mozillaUpdate.channel != nil
                || chromiumUpdateChannel != nil || braveUpdateChannel != nil
                || vendorUpdateProduct != nil,
            mozillaUpdateProduct: mozillaUpdate.product,
            mozillaUpdateChannel: mozillaUpdate.channel,
            chromiumUpdateChannel: chromiumUpdateChannel,
            braveUpdateChannel: braveUpdateChannel,
            electronUpdateFeedURL: electronUpdate.feedURL,
            vendorUpdateProduct: vendorUpdateProduct,
            steamAppID: steamAppID,
            managedUpdateStatus: managedStatus,
            installedAt: dates?.creationDate,
            modifiedAt: dates?.contentModificationDate,
            architectures: AppArchitectureInspector.architectures(at: url, info: info)
        )
    }

    static func updateManagement(
        bundleIdentifier: String?,
        appPath: String,
        hasReceipt: Bool,
        receiptType: String?,
        hasEmbeddedProvisioningProfile: Bool,
        hasSetappFramework: Bool,
        isSteamLauncher: Bool = false,
        microsoftRegisteredPaths: Set<String>
    ) -> AppUpdateManagement {
        let identifier = bundleIdentifier?.lowercased() ?? ""
        if identifier.contains("-setapp") || hasSetappFramework { return .setapp }

        if hasReceipt {
            let normalizedReceiptType = receiptType?.lowercased() ?? ""
            if normalizedReceiptType.contains("sandbox")
                || (receiptType == nil && hasEmbeddedProvisioningProfile) {
                return .testFlight
            }
            return .appStore
        }

        if isSteamLauncher || identifier == "com.valvesoftware.steam" { return .steam }
        if identifier == "com.apple.safari" { return .macOS }
        if identifier == "io.tailscale.ipn.macsys" { return .tailscale }
        if identifier == "com.spotify.client" { return .spotify }
        if identifier == "com.hnc.discord" { return .discord }
        if identifier == "com.epicgames.epicgameslauncher" { return .epicGames }
        if identifier == "com.jetbrains.toolbox" { return .jetBrainsToolbox }

        let standardizedPath = URL(fileURLWithPath: appPath).standardizedFileURL.path
        if microsoftRegisteredPaths.contains(standardizedPath) || microsoftAutoUpdateBundleIdentifiers.contains(identifier) {
            return .microsoftAutoUpdate
        }
        if identifier.hasPrefix("com.adobe.") { return .adobeCreativeCloud }
        if standardizedPath.localizedCaseInsensitiveContains("/JetBrains Toolbox/") {
            return .jetBrainsToolbox
        }
        return .direct
    }

    private static func appStoreReceiptType(at url: URL) -> String? {
        guard let item = MDItemCreate(kCFAllocatorDefault, url.path as CFString) else { return nil }
        return MDItemCopyAttribute(item, "kMDItemAppStoreReceiptType" as CFString) as? String
    }

    private static func containsSetappFramework(in contentsURL: URL) -> Bool {
        let candidates = [
            contentsURL.appendingPathComponent("Frameworks/Setapp.framework"),
            contentsURL.appendingPathComponent("Frameworks/Setapp.xcframework"),
            contentsURL.appendingPathComponent("Resources/SetappFramework-Resources.bundle"),
            contentsURL.appendingPathComponent("Resources/setappPublicKey.pem")
        ]
        return candidates.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func containsBuiltInUpdaterFramework(in contentsURL: URL) -> Bool {
        let frameworks = contentsURL.appendingPathComponent("Frameworks", isDirectory: true)
        return ["Sparkle.framework", "Squirrel.framework", "ShipIt.framework"].contains {
            FileManager.default.fileExists(atPath: frameworks.appendingPathComponent($0).path)
        }
    }

    static func mozillaUpdateMetadata(
        bundleIdentifier: String?,
        installedVersion: String
    ) -> (product: MozillaUpdateProduct?, channel: MozillaUpdateChannel?) {
        switch bundleIdentifier?.lowercased() {
        case "org.mozilla.firefox":
            return (.firefox, mozillaChannel(from: installedVersion))
        case "org.mozilla.firefoxdeveloperedition":
            return (.firefox, .developerEdition)
        case "org.mozilla.nightly":
            return (.firefox, .nightly)
        case "org.mozilla.thunderbird", "org.mozilla.thunderbirdbeta", "org.mozilla.thunderbirddaily":
            return (.thunderbird, mozillaChannel(from: installedVersion))
        default:
            return (nil, nil)
        }
    }

    static func mozillaUpdateChannel(
        bundleIdentifier: String?,
        installedVersion: String
    ) -> MozillaUpdateChannel? {
        mozillaUpdateMetadata(
            bundleIdentifier: bundleIdentifier,
            installedVersion: installedVersion
        ).channel
    }

    private static func mozillaChannel(from version: String) -> MozillaUpdateChannel {
        let normalized = version.lowercased()
        if normalized.contains("esr") { return .esr }
        if normalized.contains("a") { return .nightly }
        if normalized.contains("b") { return .developerEdition }
        return .release
    }

    static func chromiumUpdateChannel(bundleIdentifier: String?) -> ChromiumUpdateChannel? {
        switch bundleIdentifier?.lowercased() {
        case "com.google.chrome": .stable
        case "com.google.chrome.beta": .beta
        case "com.google.chrome.dev": .dev
        case "com.google.chrome.canary": .canary
        default: nil
        }
    }

    static func braveUpdateChannel(bundleIdentifier: String?) -> BraveUpdateChannel? {
        switch bundleIdentifier?.lowercased() {
        case "com.brave.browser": .release
        case "com.brave.browser.beta": .beta
        case "com.brave.browser.dev": .dev
        case "com.brave.browser.nightly": .nightly
        default: nil
        }
    }

    private static func steamAppID(at appURL: URL) -> String? {
        let launcher = appURL.appendingPathComponent("Contents/MacOS/run.sh")
        guard let contents = try? String(contentsOf: launcher, encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: #"steam://run/(\d+)"#),
              let match = regex.firstMatch(
                in: contents,
                range: NSRange(contents.startIndex..., in: contents)
              ),
              let range = Range(match.range(at: 1), in: contents)
        else { return nil }
        return String(contents[range])
    }

    /// Each entry was checked against the repository's source (bundle ID) and
    /// its releases (a macOS ZIP or DMG asset).
    private static let trustedGitHubRepositories: [String: String] = [
        "com.github.githubclient": "desktop/desktop",
        "com.electron.ollama": "ollama/ollama",
        "com.microsoft.vscode": "microsoft/vscode",
        "com.microsoft.vscodeinsiders": "microsoft/vscode",
        "com.puremac.app": "momenbasel/PureMac",
        "com.utmapp.utm": "utmapp/UTM",
        "dev.ahmed.blitztree": "ahmedkhaleel2004/blitztree",
        "eu.exelban.stats": "exelban/stats",
        "io.github.marticliment.unigetui": "Devolutions/UniGetUI",
        "rocks.spotifast.spotifast": "crmne/spotifast"
    ]

    /// Sparkle apps that set their feed at runtime instead of in Info.plist.
    /// Each feed URL is declared inside the app bundle itself.
    private static let trustedSparkleFeeds: [String: URL] = [
        // ChatGPT (Codex) packages this as `codexSparkleFeedUrl` in app.asar. Production
        // builds ask a per-installation backend appcast first and use this feed as their
        // fallback; Upkeep uses it because the backend needs the app's installation ID.
        "com.openai.codex": URL(string: "https://persistent.oaistatic.com/codex-app-prod/appcast.xml")!
    ]

    static func trustedSparkleFeedURL(bundleIdentifier: String?) -> URL? {
        bundleIdentifier.flatMap { trustedSparkleFeeds[$0.lowercased()] }
    }

    static func trustedGitHubRepository(bundleIdentifier: String?) -> String? {
        guard let identifier = bundleIdentifier?.lowercased() else { return nil }
        return customGitHubRepository(bundleIdentifier: identifier)
            ?? trustedGitHubRepositories[identifier]
    }

    static func customGitHubRepository(
        bundleIdentifier: String?,
        defaults: UserDefaults = .standard
    ) -> String? {
        guard let identifier = bundleIdentifier?.lowercased(),
              let mappings = defaults.dictionary(forKey: "customGitHubRepositories") as? [String: String]
        else { return nil }
        return mappings[identifier]
    }

    static func sparkleFeedURL(
        info: [String: Any],
        bundleIdentifier: String?,
        defaults: UserDefaults
    ) -> URL? {
        let infoCandidates = [
            info["SUFeedURL"] as? String,
            info["SUSparkleFeedURL"] as? String,
            info["SparkleFeedURL"] as? String,
            (info["Sparkle"] as? [String: Any])?["FeedURL"] as? String
        ]
        let preferenceCandidates: [String?]
        if let bundleIdentifier,
           let domain = defaults.persistentDomain(forName: bundleIdentifier) {
            preferenceCandidates = [
                domain["SUFeedURL"] as? String,
                domain["SUSparkleFeedURL"] as? String,
                domain["SparkleFeedURL"] as? String
            ]
        } else {
            preferenceCandidates = []
        }
        return (infoCandidates + preferenceCandidates)
            .compactMap { $0 }
            .compactMap(URL.init(string:))
            .first { $0.scheme?.lowercased() == "https" }
            ?? trustedSparkleFeedURL(bundleIdentifier: bundleIdentifier)
    }

    private static func managedUpdateStatus(
        management: AppUpdateManagement,
        steamAppID: String?
    ) -> ManagedUpdateStatus? {
        if management == .steam, let steamAppID,
           let status = steamUpdateStatus(appID: steamAppID) {
            return status
        }
        guard management.isExternallyManaged else { return nil }
        return ManagedUpdateStatus(
            state: .managed,
            detail: management.updateExplanation
        )
    }

    static func steamUpdateStatus(
        appID: String,
        applicationSupportURL: URL? = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
    ) -> ManagedUpdateStatus? {
        guard let applicationSupportURL else { return nil }
        let manifest = applicationSupportURL
            .appendingPathComponent("Steam/steamapps/appmanifest_\(appID).acf")
        guard let contents = try? String(contentsOf: manifest, encoding: .utf8) else { return nil }

        func value(_ key: String) -> String? {
            let pattern = "\"\(NSRegularExpression.escapedPattern(for: key))\"\\s+\"([^\"]*)\""
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(
                    in: contents,
                    range: NSRange(contents.startIndex..., in: contents)
                  ),
                  let range = Range(match.range(at: 1), in: contents)
            else { return nil }
            return String(contents[range])
        }

        let flags = Int(value("StateFlags") ?? "") ?? 0
        let downloaded = Double(value("BytesDownloaded") ?? "") ?? 0
        let total = Double(value("BytesToDownload") ?? "") ?? 0
        let progress = total > 0 ? downloaded / total : nil

        if flags & 4096 != 0 {
            return ManagedUpdateStatus(
                state: .downloading,
                detail: "Steam is downloading this update.",
                progress: progress
            )
        }
        if flags & (8 | 32 | 1024 | 2048 | 8192 | 16384) != 0 {
            return ManagedUpdateStatus(
                state: .installing,
                detail: "Steam is preparing or installing this update.",
                progress: progress
            )
        }
        if flags & 16 != 0 {
            return ManagedUpdateStatus(
                state: .queued,
                detail: "The Steam update is paused or queued.",
                progress: progress
            )
        }
        if flags & 2 != 0 {
            return ManagedUpdateStatus(
                state: .queued,
                detail: "Steam reports an update is required."
            )
        }
        return ManagedUpdateStatus(
            state: .managed,
            detail: "Steam reports the installed files are current."
        )
    }

    private static func microsoftAutoUpdateRegisteredPaths() -> Set<String> {
        guard let applications = UserDefaults(suiteName: "com.microsoft.autoupdate2")?
            .dictionary(forKey: "Applications") else { return [] }
        return Set(applications.keys.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
    }

    private static let microsoftAutoUpdateBundleIdentifiers: Set<String> = [
        "com.microsoft.companyportal", "com.microsoft.defender", "com.microsoft.excel",
        "com.microsoft.m365copilot", "com.microsoft.onedrive", "com.microsoft.onenote.mac",
        "com.microsoft.outlook", "com.microsoft.powerpoint", "com.microsoft.quickassist",
        "com.microsoft.rdc.macos", "com.microsoft.remotehelp", "com.microsoft.skypeforbusiness",
        "com.microsoft.teams", "com.microsoft.teams2", "com.microsoft.word"
    ]

    private static func githubRepository(from info: [String: Any], feedURL: URL?) -> String? {
        let keys = ["GitHubRepository", "GithubRepository", "GitHubURL", "GithubURL", "RepositoryURL"]
        for key in keys {
            if let value = info[key] as? String, let repository = parseGitHubRepository(value) {
                return repository
            }
        }
        return feedURL.flatMap { parseGitHubRepository($0.absoluteString) }
    }

    private static func parseGitHubRepository(_ value: String) -> String? {
        let patterns = [
            #"github\.com/([^/]+)/([^/#?]+)"#,
            #"raw\.githubusercontent\.com/([^/]+)/([^/]+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
                  match.numberOfRanges >= 3,
                  let ownerRange = Range(match.range(at: 1), in: value),
                  let repoRange = Range(match.range(at: 2), in: value)
            else { continue }
            let owner = value[ownerRange]
            let repo = value[repoRange].replacingOccurrences(of: ".git", with: "")
            return "\(owner)/\(repo)"
        }
        return nil
    }

    private static func electronUpdateMetadata(
        at appURL: URL
    ) -> (repository: String?, feedURL: URL?, isConfigured: Bool) {
        let resources = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        for filename in ["app-update.yml", "app-update.yaml"] {
            let configURL = resources.appendingPathComponent(filename)
            guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else { continue }
            guard contents.range(of: #"provider:\s*github"#, options: .regularExpression) != nil else {
                return (nil, ElectronUpdateFeed.manifestURL(fromConfig: contents), true)
            }
            let owner = yamlValue(named: "owner", in: contents)
            let repo = yamlValue(named: "repo", in: contents)
            return (owner.flatMap { owner in repo.map { "\(owner)/\($0)" } }, nil, true)
        }
        return (nil, nil, false)
    }

    private static func yamlValue(named key: String, in contents: String) -> String? {
        let pattern = "(?m)^\\s*\(NSRegularExpression.escapedPattern(for: key)):\\s*['\\\"]?([^'\\\"\\s#]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: contents, range: NSRange(contents.startIndex..., in: contents)),
              let range = Range(match.range(at: 1), in: contents)
        else { return nil }
        return String(contents[range])
    }
}
