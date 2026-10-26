import Foundation

/// Uses the current inventory/update offer, never a version or command supplied by an advisory.
enum CVEUpdateAction {
    case application(AvailableUpdate)
    case homebrew(HomebrewPackage)
    case developer(DeveloperPackage)

    var title: String {
        switch self {
        case let .application(update): update.actionTitle
        case .homebrew: "Update"
        case let .developer(package): package.canUpdateAutomatically ? "Update" : "View Update"
        }
    }
    var version: String {
        switch self {
        case let .application(update): update.displayAvailableVersion
        case let .homebrew(package): package.currentVersion
        case let .developer(package): package.latestVersion
        }
    }
    var batchItem: BatchUpdateItem {
        switch self {
        case let .application(update): .application(update)
        case let .homebrew(package): .homebrew(package)
        case let .developer(package): .developer(package)
        }
    }
    var operation: OperationID {
        switch self {
        case let .application(update): .applicationUpdate(update.id)
        case let .homebrew(package): .homebrewPackage(package.id)
        case let .developer(package): .developerPackage(package.id)
        }
    }
}

@MainActor extension UpkeepStore {
    func cveUpdateAction(for item: CVEInventoryItem) -> CVEUpdateAction? {
        guard cveScanState.results.contains(where: {
            !$0.advisories.isEmpty && $0.item.hasSameCheckIdentity(as: item)
        }) else { return nil }
        if let app = apps.first(where: { item.hasSameCheckIdentity(as: CVEInventoryItem($0)) }),
           let update = visibleUpdate(for: app),
           item.hasSameCheckIdentity(as: CVEInventoryItem(update.app)) {
            return .application(update)
        }
        if let package = homebrewPackages.first(where: { item.hasSameCheckIdentity(as: CVEInventoryItem($0)) }),
           package.isOutdated, !isExcluded(package) {
            return .homebrew(package)
        }
        if let package = developerPackages.first(where: { item.hasSameCheckIdentity(as: CVEInventoryItem($0)) }),
           package.isOutdated, !isExcluded(package) {
            return .developer(package)
        }
        return nil
    }

    /// All findings, independent of the checker's current search/filter. One update per installation.
    var cveBatchUpdateItems: [BatchUpdateItem] {
        let actions = cveScanState.results.compactMap { cveUpdateAction(for: $0.item) }
            .filter { !isUpdatingCVESoftware($0) }
        let representedCasks = Set(actions.compactMap { action -> String? in
            if case let .application(update) = action { return update.homebrewToken }
            return nil
        })
        var seen: Set<String> = []
        return actions.compactMap { action -> BatchUpdateItem? in
            if case let .homebrew(package) = action, package.kind == .cask,
               representedCasks.contains(package.token) { return nil }
            let item = action.batchItem
            return seen.insert(item.id).inserted ? item : nil
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func performCVEBatchUpdates(_ reviewed: [BatchUpdateItem]) async -> BatchUpdateSummary {
        let current = Dictionary(uniqueKeysWithValues: cveBatchUpdateItems.map { ($0.id, $0) })
        var seen: Set<String> = []
        let unique = reviewed.filter { seen.insert($0.id).inserted }
        let valid = unique.filter { current[$0.id] == $0 }
        let changed = unique.filter { current[$0.id] != $0 }.map {
            BatchUpdateResult(item: $0, outcome: .failed,
                detail: "This update offer or installed version changed, was excluded, or is already in progress. Refresh and review it again.")
        }
        let summary = await performBatchUpdates(valid)
        refreshCVEsAutomatically()
        return BatchUpdateSummary(results: summary.results + changed)
    }

    func isUpdatingCVESoftware(_ action: CVEUpdateAction) -> Bool {
        if case let .application(update) = action { return isUpdating(update) }
        return isWorking(action.operation)
    }

    func updateCVESoftware(_ item: CVEInventoryItem) async {
        // Re-resolve on click so an old scan row cannot install against a changed inventory.
        guard let action = cveUpdateAction(for: item), !isUpdatingCVESoftware(action) else { return }
        switch action {
        case let .application(update): await performUpdate(update)
        case let .homebrew(package): await updatePackage(package)
        case let .developer(package): await updateDeveloperPackage(package)
        }
    }
}
