import Foundation

func reconcileSourceWarnings(
    existing: [ScanWarning], fresh: [ScanWarning], source: ScanWarningSource,
    checkedName: String?, checkedID: String? = nil
) -> [ScanWarning] {
    let retained = existing.compactMap { warning -> ScanWarning? in
        guard warning.source == source else { return warning }
        guard let checkedName else { return nil }
        if warning.itemNamesByID != nil {
            guard let checkedID else { return warning }
            return warning.removingItems(ids: [checkedID])
        }
        guard warning.itemNames.contains(checkedName) else { return warning }
        let remaining = warning.itemNames.filter { $0 != checkedName }
        let count = warning.affectedItemCount - 1
        guard count > 0 else { return nil }
        return ScanWarning(source: source, itemNames: remaining, affectedItemCount: count, message: warning.message)
    }
    let combined = retained + fresh.map { warning in
        guard warning.itemNames.isEmpty, let checkedName else { return warning }
        return ScanWarning(source: warning.source, itemNames: [checkedName],
                           affectedItemCount: warning.affectedItemCount,
                           itemNamesByID: checkedID.map { [$0: checkedName] }, message: warning.message)
    }
    return combined.reduce(into: [ScanWarning]()) { result, warning in
        guard let index = result.firstIndex(where: { $0.id == warning.id }) else {
            result.append(warning)
            return
        }
        let previous = result[index]
        if let previousItems = previous.itemNamesByID, let freshItems = warning.itemNamesByID {
            let items = previousItems.merging(freshItems) { _, latest in latest }
            result[index] = ScanWarning(source: warning.source, itemNames: Array(items.values),
                                        affectedItemCount: items.count, itemNamesByID: items, message: warning.message)
            return
        }
        let overlap = Set(previous.itemNames).intersection(warning.itemNames).count
        result[index] = ScanWarning(source: warning.source,
                                    itemNames: previous.itemNames + warning.itemNames,
                                    affectedItemCount: previous.affectedItemCount + warning.affectedItemCount - overlap,
                                    message: warning.message)
    }
}
