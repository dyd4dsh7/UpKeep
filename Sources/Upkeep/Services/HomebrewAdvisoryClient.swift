import Foundation

/// Numeric Homebrew releases compare upstream version first, then the packaging revision.
/// Other version grammars remain uncovered rather than using a permissive comparison.
enum HomebrewAdvisoryVersion {
    static func isSupported(_ version: String) -> Bool {
        version.range(of: #"^[0-9]+(?:\.[0-9]+)*(?:_[0-9]+)?$"#, options: .regularExpression) != nil
    }
    static func compare(_ lhs: String, _ rhs: String) throws -> ComparisonResult {
        guard isSupported(lhs), isSupported(rhs) else { throw HomebrewAdvisoryError.version }
        let left = lhs.split(separator: "_"); let right = rhs.split(separator: "_")
        let upstream = VersionComparator.compare(String(left[0]), String(right[0]))
        if upstream != .orderedSame { return upstream }
        return VersionComparator.compare(left.count == 2 ? String(left[1]) : "0",
                                         right.count == 2 ? String(right[1]) : "0")
    }
}

enum HomebrewAdvisoryError: LocalizedError {
    case version, range, http(Int)
    var errorDescription: String? {
        switch self {
        case .version: "A Homebrew advisory uses an unsupported version format. Review its affected ranges manually."
        case .range: "A Homebrew advisory has an unsupported affected range."
        case let .http(status): "Homebrew advisory feed returned HTTP \(status). Retry later."
        }
    }
}

struct HomebrewAdvisoryIndex: Decodable, Sendable {
    let advisories: [String: [Record]]
    struct Record: Decodable, Sendable {
        let id: String
        let aliases: [String]?
        let upstream: [String]?
        let summary: String?
        let withdrawn: String?
        let severity: [CVEOSVSeverity]?
        let database_specific: CVEDatabaseMetadata?
        let affected: [Affected]
        struct Affected: Decodable, Sendable {
            struct Package: Decodable, Sendable { let name: String; let ecosystem: String }
            let package: Package
            let versions: [String]?
            let ranges: [Range]?
            let severity: [CVEOSVSeverity]?
            let database_specific: CVEDatabaseMetadata?
        }
        struct Range: Decodable, Sendable {
            let type: String
            let events: [[String: String]]
            func contains(_ version: String) throws -> Bool {
                guard type == "ECOSYSTEM", !events.isEmpty else { throw HomebrewAdvisoryError.range }
                var start: String?
                var matched = false
                for event in events {
                    guard event.count == 1, let entry = event.first else { throw HomebrewAdvisoryError.range }
                    if entry.key == "introduced" {
                        guard start == nil else { throw HomebrewAdvisoryError.range }
                        // Validate even boundaries beyond the installed version.
                        _ = try HomebrewAdvisoryVersion.compare(entry.value, version)
                        start = entry.value
                    } else {
                        guard let lower = start, ["fixed", "last_affected", "limit"].contains(entry.key) else {
                            throw HomebrewAdvisoryError.range
                        }
                        let lowerMatch = try HomebrewAdvisoryVersion.compare(version, lower) != .orderedAscending
                        let upper = try HomebrewAdvisoryVersion.compare(version, entry.value)
                        if lowerMatch && (entry.key == "last_affected" ? upper != .orderedDescending : upper == .orderedAscending) {
                            matched = true
                        }
                        start = nil
                    }
                }
                if let start, try HomebrewAdvisoryVersion.compare(version, start) != .orderedAscending {
                    matched = true
                }
                return matched
            }
        }
    }

    func check(name: String, version: String) throws -> [CVEAdvisory] {
        var matches: [String: CVEAdvisory] = [:]
        for record in advisories[name] ?? [] where record.withdrawn == nil {
            var affected = false
            for entry in record.affected where entry.package.ecosystem == "Homebrew" && entry.package.name == name {
                if entry.versions?.contains(version) == true { affected = true }
                for range in entry.ranges ?? [] {
                    if try range.contains(version) { affected = true }
                }
                if entry.versions == nil && (entry.ranges ?? []).isEmpty { throw HomebrewAdvisoryError.range }
            }
            if affected {
                matches[record.id] = CVEAdvisory(id: record.id, aliases: record.aliases, summary: record.summary,
                    upstream: record.upstream, sourceURL: URL(string: "https://github.com/Homebrew/advisory-database/blob/main/advisories/")!
                        .appendingPathComponent(record.id + ".json"), severity: record.severity,
                    affected: record.affected.filter { $0.package.ecosystem == "Homebrew" && $0.package.name == name }.map {
                        CVEAffectedPackage(package: .init(name: $0.package.name, ecosystem: $0.package.ecosystem),
                            severity: $0.severity, ranges: $0.ranges?.map { .init(type: $0.type, events: $0.events) },
                            database_specific: $0.database_specific)
                    }, databaseSpecific: record.database_specific)
            }
        }
        return matches.values.sorted { $0.id < $1.id }
    }
}
