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

    init(advisories: [String: [Record]]) { self.advisories = advisories }

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

/// Finds the raw JSON of selected formulae in the Homebrew advisory feed
/// without building the whole document. The feed is about 79 MB; decoding it
/// in full temporarily used roughly 270 MB, while a Mac usually needs a few
/// formulae. Returns nil if the bytes are not the expected shape, so callers
/// can fall back to a full decode.
enum HomebrewAdvisoryFeedScanner {
    static func records(in data: Data, formulae names: Set<String>) -> [String: [HomebrewAdvisoryIndex.Record]]? {
        guard let slices = slices(in: data, formulae: names) else { return nil }
        var output: [String: [HomebrewAdvisoryIndex.Record]] = [:]
        for (name, slice) in slices {
            guard let records = try? JSONDecoder().decode([HomebrewAdvisoryIndex.Record].self, from: slice) else { return nil }
            output[name] = records
        }
        return output
    }

    static func slices(in data: Data, formulae names: Set<String>) -> [String: Data]? {
        data.withUnsafeBytes { raw -> [String: Data]? in
            guard let bytes = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            var scanner = Scanner(bytes: bytes, count: raw.count)
            var found: [String: Data] = [:]
            var sawAdvisories = false
            let ok = scanner.object { key, scanner in
                guard key == "advisories" else { return scanner.skipValue() }
                sawAdvisories = true
                return scanner.object { formula, scanner in
                    let start = scanner.position
                    guard scanner.skipValue() else { return false }
                    if names.contains(formula) {
                        found[formula] = Data(bytes: bytes + start, count: scanner.position - start)
                    }
                    return true
                }
            }
            guard ok, sawAdvisories else { return nil }
            scanner.skipWhitespace()
            return scanner.position == scanner.count ? found : nil
        }
    }

    private struct Scanner {
        let bytes: UnsafePointer<UInt8>
        let count: Int
        var position = 0

        init(bytes: UnsafePointer<UInt8>, count: Int) { self.bytes = bytes; self.count = count }

        mutating func skipWhitespace() {
            while position < count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[position]) { position += 1 }
        }

        /// Walks an object, calling `member` with each key positioned at its value.
        mutating func object(_ member: (String, inout Scanner) -> Bool) -> Bool {
            skipWhitespace()
            guard position < count, bytes[position] == UInt8(ascii: "{") else { return false }
            position += 1
            skipWhitespace()
            if position < count, bytes[position] == UInt8(ascii: "}") { position += 1; return true }
            while true {
                skipWhitespace()
                guard let key = string() else { return false }
                skipWhitespace()
                guard position < count, bytes[position] == UInt8(ascii: ":") else { return false }
                position += 1
                skipWhitespace()
                guard member(key, &self) else { return false }
                skipWhitespace()
                guard position < count else { return false }
                if bytes[position] == UInt8(ascii: ",") { position += 1; continue }
                if bytes[position] == UInt8(ascii: "}") { position += 1; return true }
                return false
            }
        }

        mutating func string() -> String? {
            guard position < count, bytes[position] == UInt8(ascii: "\"") else { return nil }
            let start = position
            position += 1
            var escaped = false
            while position < count {
                let byte = bytes[position]
                position += 1
                if byte == UInt8(ascii: "\\") { escaped = true; position += 1; continue }
                if byte == UInt8(ascii: "\"") {
                    let quoted = Data(bytes: bytes + start, count: position - start)
                    if !escaped { return String(decoding: quoted.dropFirst().dropLast(), as: UTF8.self) }
                    return try? JSONDecoder().decode(String.self, from: quoted)
                }
            }
            return nil
        }

        /// Skips one JSON value, tracking nesting and strings.
        mutating func skipValue() -> Bool {
            skipWhitespace()
            guard position < count else { return false }
            switch bytes[position] {
            case UInt8(ascii: "\""):
                return string() != nil
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                var depth = 0
                while position < count {
                    let byte = bytes[position]
                    if byte == UInt8(ascii: "\"") {
                        guard string() != nil else { return false }
                        continue
                    }
                    if byte == UInt8(ascii: "{") || byte == UInt8(ascii: "[") { depth += 1 }
                    if byte == UInt8(ascii: "}") || byte == UInt8(ascii: "]") {
                        depth -= 1
                        if depth == 0 { position += 1; return true }
                    }
                    position += 1
                }
                return false
            default:
                let start = position
                while position < count, ![UInt8(ascii: ","), UInt8(ascii: "}"), UInt8(ascii: "]"), 0x20, 0x09, 0x0A, 0x0D]
                        .contains(bytes[position]) { position += 1 }
                return position > start
            }
        }
    }
}
