import Foundation

/// A source rating, not a prediction of exploitability on this Mac.
struct CVESeverityRating: Decodable, Sendable {
    enum Level: String, Decodable, Sendable {
        case critical = "Critical", high = "High", medium = "Medium", low = "Low", none = "None", unknown = "Unrated"
        var rank: Int {
            switch self { case .critical: 5; case .high: 4; case .medium: 3; case .low: 2; case .none: 1; case .unknown: 0 }
        }
        init(label: String?) {
            switch label?.uppercased() {
            case "CRITICAL": self = .critical
            case "HIGH": self = .high
            case "MEDIUM", "MODERATE": self = .medium
            case "LOW": self = .low
            case "NONE": self = .none
            default: self = .unknown
            }
        }
    }
    let level: Level
    let score: Double?
    let method: String

    init(score: Double?, label: String? = nil, method: String) {
        let score = score.flatMap { $0.isFinite && (0...10).contains($0) ? $0 : nil }
        self.score = score
        self.method = method
        if let score {
            // CVSS v2 uses Low/Medium/High, with no Critical category.
            if method == "CVSS 2.0" {
                level = score >= 7 ? .high : score >= 4 ? .medium : .low
            } else {
                level = score >= 9 ? .critical : score >= 7 ? .high : score >= 4 ? .medium : score > 0 ? .low : .none
            }
        } else { level = Level(label: label) }
    }
    var title: String {
        guard let score else { return level.rawValue }
        return "\(level.rawValue) · \(score.formatted(.number.precision(.fractionLength(1))))"
    }
    static func highest(_ ratings: [Self]) -> Self? {
        ratings.filter { $0.level != .unknown }.max {
            if $0.level.rank != $1.level.rank { return $0.level.rank < $1.level.rank }
            return ($0.score ?? -1) < ($1.score ?? -1)
        }
    }
}

struct CVEOSVSeverity: Decodable, Sendable {
    let type: String
    let score: String
    var rating: CVESeverityRating? {
        guard type == "CVSS_V3", let value = CVSS3BaseScore.calculate(score) else { return nil }
        return .init(score: value, method: score.hasPrefix("CVSS:3.1/") ? "CVSS 3.1" : "CVSS 3.0")
    }
}

struct CVEDatabaseMetadata: Decodable, Sendable {
    let severity: String?
    init(severity: String?) { self.severity = severity }
    private enum CodingKeys: String, CodingKey { case severity }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // database_specific is source-defined. A different severity shape is not a scan failure.
        severity = try? container.decode(String.self, forKey: .severity)
    }
}

struct CVEAffectedPackage: Decodable, Sendable {
    struct Package: Decodable, Sendable { let name: String; let ecosystem: String }
    struct Range: Decodable, Sendable {
        let type: String
        let events: [[String: String]]
    }
    let package: Package?
    let severity: [CVEOSVSeverity]?
    let ranges: [Range]?
    let database_specific: CVEDatabaseMetadata?
}

/// FIRST CVSS 3.x Base score. Temporal/environmental metrics do not alter this base rating.
/// Unknown versions and malformed or duplicate base metrics deliberately remain unrated.
enum CVSS3BaseScore {
    static func calculate(_ vector: String) -> Double? {
        let parts = vector.split(separator: "/", omittingEmptySubsequences: false)
        guard let prefix = parts.first, ["CVSS:3.0", "CVSS:3.1"].contains(prefix) else { return nil }
        var metrics: [String: String] = [:]
        for part in parts.dropFirst() {
            let pair = part.split(separator: ":", omittingEmptySubsequences: false)
            guard pair.count == 2, metrics[String(pair[0])] == nil else { return nil }
            metrics[String(pair[0])] = String(pair[1])
        }
        func weight(_ key: String, _ values: [String: Double]) -> Double? {
            metrics[key].flatMap { values[$0] }
        }
        guard let scope = metrics["S"], ["U", "C"].contains(scope),
              let av = weight("AV", ["N": 0.85, "A": 0.62, "L": 0.55, "P": 0.2]),
              let ac = weight("AC", ["L": 0.77, "H": 0.44]),
              let pr = weight("PR", ["N": 0.85, "L": scope == "C" ? 0.68 : 0.62, "H": scope == "C" ? 0.5 : 0.27]),
              let ui = weight("UI", ["N": 0.85, "R": 0.62]),
              let c = weight("C", ["N": 0, "L": 0.22, "H": 0.56]),
              let i = weight("I", ["N": 0, "L": 0.22, "H": 0.56]),
              let a = weight("A", ["N": 0, "L": 0.22, "H": 0.56]) else { return nil }
        let iss = 1 - (1 - c) * (1 - i) * (1 - a)
        let impact = scope == "U" ? 6.42 * iss : 7.52 * (iss - 0.029) - 3.25 * pow(iss - 0.02, 15)
        if impact <= 0 { return 0 }
        let exploitability = 8.22 * av * ac * pr * ui
        let base = min((impact + exploitability) * (scope == "C" ? 1.08 : 1), 10)
        // FIRST Roundup: avoid binary floating-point error around exact tenths.
        let scaled = (base * 100_000).rounded()
        return scaled.truncatingRemainder(dividingBy: 10_000) == 0
            ? scaled / 100_000 : (floor(scaled / 10_000) + 1) / 10
    }
}
