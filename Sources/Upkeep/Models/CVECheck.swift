import Foundation

struct CVEPackageQuery: Hashable, Sendable {
    let name: String
    let ecosystem: String
    let version: String

    init?(_ package: DeveloperPackage) {
        var identifier = package.registryIdentifier ?? package.name
        if package.manager == .yarn, package.name == "Yarn" {
            // Modern Yarn is not published as the npm yarn package.
            guard package.currentVersion.hasPrefix("1.") else { return nil }
            identifier = "yarn"
        }
        switch package.manager {
        case .npm, .pnpm, .yarn: ecosystem = "npm"
        case .python, .pipx: ecosystem = "PyPI"
        case .uv:
            guard !identifier.hasPrefix("python:") else { return nil }
            ecosystem = "PyPI"
        case .rubyGems: ecosystem = "RubyGems"
        case .cargo: ecosystem = "crates.io"
        case .composer: ecosystem = "Packagist"
        case .dotnet: ecosystem = "NuGet"
        case .go:
            guard package.registryIdentifier != nil, identifier != "go-runtime" else { return nil }
            ecosystem = "Go"
        default: return nil
        }
        name = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        version = package.currentVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !version.isEmpty,
              !["unknown", "latest", "current", "n/a", "(devel)"].contains(version.lowercased()),
              version.contains(where: \.isNumber) else { return nil }
    }
}

struct CVEAdvisory: Decodable, Identifiable, Sendable {
    let id: String
    let aliases: [String]?
    let summary: String?
    let withdrawn: String?
    let upstream: [String]?
    let sourceURL: URL?
    let severity: [CVEOSVSeverity]?
    let affected: [CVEAffectedPackage]?
    let database_specific: CVEDatabaseMetadata?
    let sourceRatings: [CVESeverityRating]?

    init(id: String, aliases: [String]? = nil, summary: String? = nil, withdrawn: String? = nil,
         upstream: [String]? = nil, sourceURL: URL? = nil,
         severity: [CVEOSVSeverity]? = nil, affected: [CVEAffectedPackage]? = nil,
         databaseSpecific: CVEDatabaseMetadata? = nil, sourceRatings: [CVESeverityRating]? = nil) {
        self.id = id; self.aliases = aliases; self.summary = summary; self.withdrawn = withdrawn
        self.upstream = upstream; self.sourceURL = sourceURL
        self.severity = severity; self.affected = affected; self.database_specific = databaseSpecific
        self.sourceRatings = sourceRatings
    }

    var ratings: [CVESeverityRating] {
        (sourceRatings ?? []) + (severity ?? []).compactMap(\.rating)
            + (affected ?? []).flatMap { ($0.severity ?? []).compactMap(\.rating) }
            + ([database_specific?.severity] + (affected ?? []).map { $0.database_specific?.severity })
                .compactMap { label in label.map { CVESeverityRating(score: nil, label: $0, method: "Publisher rating") } }
    }
    var fixedVersions: [String] {
        Set((affected ?? []).flatMap { $0.ranges ?? [] }
            .filter { ["SEMVER", "ECOSYSTEM"].contains($0.type) }
            .flatMap(\.events).compactMap { $0.count == 1 ? $0["fixed"] : nil }
            .filter { !$0.isEmpty && $0 != "0" }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    /// OSV records can cover multiple packages. Never show another package's rating or fixes.
    func scoped(to query: CVEPackageQuery) -> Self {
        Self(id: id, aliases: aliases, summary: summary, withdrawn: withdrawn, upstream: upstream,
             sourceURL: sourceURL, severity: severity,
             affected: affected?.filter {
                 guard let package = $0.package, package.ecosystem == query.ecosystem else { return false }
                 func canonical(_ name: String) -> String {
                     if query.ecosystem == "PyPI" {
                         return name.lowercased().replacingOccurrences(of: "[-_.]+", with: "-", options: .regularExpression)
                     }
                     return query.ecosystem == "NuGet" ? name.lowercased() : name
                 }
                 return canonical(package.name) == canonical(query.name)
             },
             databaseSpecific: database_specific, sourceRatings: sourceRatings)
    }

    var cveIDs: [String] {
        Set(([id] + (aliases ?? []) + (upstream ?? [])).filter { $0.hasPrefix("CVE-") }).sorted()
    }
    var url: URL { sourceURL ?? URL(string: "https://osv.dev/vulnerability/")!.appendingPathComponent(id) }
}

struct CVEPackageResult: Identifiable, Sendable {
    let package: DeveloperPackage
    let advisories: [CVEAdvisory]
    let failure: String?
    let supported: Bool
    var id: String { package.id }
    var status: String {
        if !supported { return "Not covered" }
        if failure != nil { return "Check incomplete" }
        return advisories.isEmpty ? "No known advisories returned" : "\(advisories.count) \(advisories.count == 1 ? "advisory" : "advisories")"
    }
}
