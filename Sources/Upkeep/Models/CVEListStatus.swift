import Foundation

enum CVEListStatus: Equatable {
    case notCovered, pending, checking, needsCheck, incomplete, noAdvisories
    case advisories(Int, potential: Bool)

    var title: String {
        switch self {
        case .notCovered: return "CVE not covered"
        case .pending: return "CVE pending"
        case .checking: return "Checking CVEs"
        case .needsCheck: return "CVE check needed"
        case .incomplete: return "CVE check failed"
        case .noAdvisories: return "No known advisories"
        case let .advisories(count, potential):
            if potential { return "\(count) potential CVE\(count == 1 ? "" : "s")" }
            return "\(count) advisor\(count == 1 ? "y" : "ies")"
        }
    }
    var showsListBadge: Bool {
        if case let .advisories(count, _) = self { return count > 0 }
        return false
    }
    var requiresAttention: Bool {
        switch self {
        case .advisories, .incomplete: true
        default: false
        }
    }
}

extension CVEInventoryItem {
    /// Latest update metadata can change without changing the installed vulnerability query.
    func hasSameCheckIdentity(as other: Self) -> Bool {
        guard id == other.id, version == other.version else { return false }
        switch (target, other.target) {
        case let (.developer(left), .developer(right)): return CVEPackageQuery(left) == CVEPackageQuery(right)
        case let (.formula(leftName, leftVersion), .formula(rightName, rightVersion)):
            return leftName == rightName && leftVersion == rightVersion
        case let (.nvd(left), .nvd(right)): return left == right
        case (nil, nil): return true
        default: return false
        }
    }
}

extension CVEScanState {
    func listStatus(for item: CVEInventoryItem, now: Date = Date()) -> CVEListStatus {
        guard item.target != nil else { return .notCovered }
        if let result = results.first(where: { $0.id == item.id }) {
            guard result.item.hasSameCheckIdentity(as: item), let checkedAt,
                  now.timeIntervalSince(checkedAt) < 86_400 else { return .needsCheck }
            if result.failure != nil { return .incomplete }
            if result.advisories.isEmpty { return .noAdvisories }
            let potential: Bool
            if case .nvd? = item.target { potential = true } else { potential = false }
            return .advisories(result.advisoryGroups.count, potential: potential)
        }
        if running && inventory.contains(where: { $0.hasSameCheckIdentity(as: item) }) {
            return currentItemID == item.id ? .checking : .pending
        }
        return checkedAt == nil ? .pending : .needsCheck
    }
}
