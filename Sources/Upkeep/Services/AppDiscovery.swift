import CoreServices
import Foundation

enum AppDiscovery {
    static func discover() async -> [InstalledApp] {
        await Task.detached(priority: .userInitiated) {
            discoverSynchronously()
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
        guard let bundle = Bundle(url: url) else { return nil }
        let dates = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let info = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let shortVersion = (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String)
            ?? "Unknown"
        let build = info["CFBundleVersion"] as? String
        let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:))
        let repository = githubRepository(from: info, feedURL: feed)
            ?? electronGitHubRepository(at: url)
        let receiptURL = url.appendingPathComponent("Contents/_MASReceipt/receipt")
        let hasReceipt = FileManager.default.fileExists(atPath: receiptURL.path)
        let contentsURL = url.appendingPathComponent("Contents", isDirectory: true)
        let management = updateManagement(
            bundleIdentifier: bundle.bundleIdentifier,
            appPath: url.standardizedFileURL.path,
            hasReceipt: hasReceipt,
            receiptType: hasReceipt ? appStoreReceiptType(at: url) : nil,
            hasEmbeddedProvisioningProfile: FileManager.default.fileExists(
                atPath: contentsURL.appendingPathComponent("embedded.provisionprofile").path
            ),
            hasSetappFramework: containsSetappFramework(in: contentsURL),
            microsoftRegisteredPaths: microsoftRegisteredPaths
        )

        return InstalledApp(
            name: name,
            bundleIdentifier: bundle.bundleIdentifier,
            installedVersion: shortVersion,
            buildVersion: build,
            url: url,
            sparkleFeedURL: feed,
            githubRepository: repository,
            hasAppStoreReceipt: hasReceipt,
            updateManagement: management,
            installedAt: dates?.creationDate,
            modifiedAt: dates?.contentModificationDate
        )
    }

    static func updateManagement(
        bundleIdentifier: String?,
        appPath: String,
        hasReceipt: Bool,
        receiptType: String?,
        hasEmbeddedProvisioningProfile: Bool,
        hasSetappFramework: Bool,
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

        let standardizedPath = URL(fileURLWithPath: appPath).standardizedFileURL.path
        if microsoftRegisteredPaths.contains(standardizedPath) || microsoftAutoUpdateBundleIdentifiers.contains(identifier) {
            return .microsoftAutoUpdate
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

    private static func electronGitHubRepository(at appURL: URL) -> String? {
        let resources = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        for filename in ["app-update.yml", "app-update.yaml"] {
            let configURL = resources.appendingPathComponent(filename)
            guard let contents = try? String(contentsOf: configURL, encoding: .utf8),
                  contents.range(of: #"provider:\s*github"#, options: .regularExpression) != nil
            else { continue }
            let owner = yamlValue(named: "owner", in: contents)
            let repo = yamlValue(named: "repo", in: contents)
            if let owner, let repo { return "\(owner)/\(repo)" }
        }
        return nil
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
