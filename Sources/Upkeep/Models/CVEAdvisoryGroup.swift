import Foundation

/// One issue may be published as both an OSV/CVE record and a GHSA record.
/// Merge connected aliases per installed item, retaining every source link.
struct CVEAdvisoryGroup: Identifiable, Sendable {
    let records: [CVEAdvisory]
    var identifiers: [String] {
        Set(records.flatMap { [$0.id] + ($0.aliases ?? []) + ($0.upstream ?? []) }).sorted()
    }
    var cveIDs: [String] { identifiers.filter { $0.hasPrefix("CVE-") } }
    var id: String { cveIDs.first ?? identifiers.first ?? "" }
    var severity: CVESeverityRating? { CVESeverityRating.highest(records.flatMap(\.ratings)) }
    var fixedVersions: [String] {
        Set(records.flatMap(\.fixedVersions)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    var summary: String? {
        records.compactMap(\.summary).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .max { $0.count < $1.count }
    }

    static func grouped(_ advisories: [CVEAdvisory]) -> [Self] {
        var groups: [Self] = []
        for advisory in advisories.sorted(by: { $0.id < $1.id }) {
            var records = [advisory]
            let keys = Set([advisory.id] + (advisory.aliases ?? []) + (advisory.upstream ?? []))
            let connected = groups.indices.filter { !keys.isDisjoint(with: groups[$0].identifiers) }
            for index in connected.reversed() { records.append(contentsOf: groups.remove(at: index).records) }
            let unique = Dictionary(grouping: records, by: \.id).compactMap { $0.value.first }
                .sorted { $0.id < $1.id }
            groups.append(Self(records: unique))
        }
        return groups.sorted {
            let left = $0.severity?.level.rank ?? 0, right = $1.severity?.level.rank ?? 0
            return left == right ? $0.id < $1.id : left > right
        }
    }
}

enum CVEResultFilter: String, CaseIterable, Identifiable {
    case findings = "Findings"
    case all = "All software"
    case incomplete = "Incomplete"
    case notCovered = "Not covered"
    var id: Self { self }

    func includes(_ item: CVEInventoryItem, result: CVEInventoryResult?) -> Bool {
        switch self {
        case .all: true
        case .findings: result?.advisories.isEmpty == false
        case .incomplete: item.target != nil && result?.failure != nil
        case .notCovered: item.target == nil
        }
    }
}
