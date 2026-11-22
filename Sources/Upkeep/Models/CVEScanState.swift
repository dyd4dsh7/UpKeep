import Foundation
import Observation

/// App-owned scan state survives navigation and keeps network work off the view lifecycle.
@MainActor @Observable
final class CVEScanState {
    /// A successful result stays current for a day.
    nonisolated static let freshnessInterval: TimeInterval = 86_400
    /// OSV registry checks are independent requests; NVD and the Homebrew
    /// advisory index each run in their own sequential lane (NVD is paced, and
    /// the Homebrew index is downloaded once per client).
    nonisolated static let generalConcurrency = 4

    var filter: CVEResultFilter = .all
    var searchText = ""
    var requestedItemID: String?
    /// Results produced (or reused) by the current or most recent check. While
    /// a check runs this grows in completion order; when it finishes it follows
    /// `inventory` order.
    private(set) var results: [CVEInventoryResult] = []
    /// Latest known result per inventory ID. Previous results stay here until
    /// a new check replaces them, so list badges do not flicker during a check.
    private(set) var resultsByID: [String: CVEInventoryResult] = [:]
    private(set) var inventory: [CVEInventoryItem] = []
    private(set) var checkedAt: Date?
    private(set) var running = false
    private(set) var currentItemID: String?
    private(set) var checkingItemIDs: Set<String> = []
    /// Start date of the check that produced each entry in `resultsByID`.
    private var resultDates: [String: Date] = [:]
    private var inventoryByID: [String: CVEInventoryItem] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?

    /// `reuseFreshResults` keeps successful, same-identity results younger than
    /// `freshnessInterval` and only checks new, changed, failed or stale items.
    @discardableResult
    func start(inventory: [CVEInventoryItem], client: CVEInventoryClient,
               reuseFreshResults: Bool = false, now: Date = Date()) -> Bool {
        guard !running, !inventory.isEmpty else { return false }
        var reused: [CVEInventoryResult] = []
        var pending: [CVEInventoryItem] = []
        var seen = Set<String>()
        for item in inventory {
            if reuseFreshResults, seen.insert(item.id).inserted, let result = reusableResult(for: item, now: now) {
                reused.append(result)
            } else {
                pending.append(item)
            }
        }
        self.inventory = inventory
        inventoryByID = Dictionary(inventory.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        results = reused
        for result in reused { resultsByID[result.id] = result }
        checkedAt = now
        running = true
        task = Task { await run(inventory: inventory, pending: pending, client: client, startedAt: now) }
        return true
    }

    func cancel() { task?.cancel() }
    func waitForCompletion() async { await task?.value }

    func result(for id: String) -> CVEInventoryResult? { resultsByID[id] }

    /// True when `inventory` matches the last check and every result is a
    /// successful check younger than `freshnessInterval`.
    func isCurrent(for inventory: [CVEInventoryItem], now: Date = Date()) -> Bool {
        guard !running, checkedAt != nil, inventory == self.inventory,
              results.count == inventory.count, !results.contains(where: { $0.failure != nil }) else { return false }
        return results.allSatisfy { result in
            resultDates[result.id].map { now.timeIntervalSince($0) < Self.freshnessInterval } ?? false
        }
    }

    func isInCurrentInventory(_ item: CVEInventoryItem) -> Bool {
        inventoryByID[item.id]?.hasSameCheckIdentity(as: item) == true
    }

    func isFreshResult(_ result: CVEInventoryResult, now: Date) -> Bool {
        guard let date = resultDates[result.id] ?? checkedAt else { return false }
        return now.timeIntervalSince(date) < Self.freshnessInterval
    }

    private func reusableResult(for item: CVEInventoryItem, now: Date) -> CVEInventoryResult? {
        guard let previous = resultsByID[item.id], previous.failure == nil,
              previous.item.hasSameCheckIdentity(as: item), isFreshResult(previous, now: now) else { return nil }
        return CVEInventoryResult(item: item, advisories: previous.advisories, failure: nil)
    }

    private enum Lane: CaseIterable {
        case nvd, formula, general
        init(_ item: CVEInventoryItem) {
            switch item.target {
            case .nvd?: self = .nvd
            case .formula?: self = .formula
            default: self = .general
            }
        }
        var limit: Int {
            switch self {
            case .nvd, .formula: 1
            case .general: CVEScanState.generalConcurrency
            }
        }
    }

    private func run(inventory: [CVEInventoryItem], pending: [CVEInventoryItem],
                     client: CVEInventoryClient, startedAt: Date) async {
        defer {
            currentItemID = nil; checkingItemIDs = []; running = false; task = nil
            if filter == .all, results.contains(where: { !$0.advisories.isEmpty }) { filter = .findings }
        }
        var queues: [Lane: ArraySlice<CVEInventoryItem>] = [:]
        for lane in Lane.allCases { queues[lane] = ArraySlice(pending.filter { Lane($0) == lane }) }
        var active: [Lane: Int] = [:]
        await withTaskGroup(of: (Lane, CVEInventoryResult?).self) { group in
            while true {
                if !Task.isCancelled {
                    for lane in Lane.allCases {
                        while active[lane, default: 0] < lane.limit, let item = queues[lane]?.popFirst() {
                            active[lane, default: 0] += 1
                            checkingItemIDs.insert(item.id)
                            currentItemID = item.id
                            group.addTask {
                                do {
                                    let result = try await client.check(item)
                                    try Task.checkCancellation()
                                    return (lane, result)
                                } catch {
                                    if Task.isCancelled { return (lane, nil) }
                                    return (lane, CVEInventoryResult(item: item, advisories: [], failure: error.localizedDescription))
                                }
                            }
                        }
                    }
                }
                guard let (lane, result) = await group.next() else { break }
                active[lane, default: 1] -= 1
                guard let result else { continue }
                checkingItemIDs.remove(result.id)
                if currentItemID == result.id { currentItemID = checkingItemIDs.first }
                results.append(result)
                resultsByID[result.id] = result
                resultDates[result.id] = startedAt
            }
        }
        // Items not reached (cancellation) are recorded explicitly.
        let finished = Set(results.map(\.id))
        for item in inventory where !finished.contains(item.id) {
            let result = CVEInventoryResult(item: item, advisories: [],
                failure: item.target == nil ? nil : "Check cancelled before completion.")
            results.append(result)
            resultsByID[result.id] = result
            resultDates[result.id] = startedAt
        }
        // Present results in inventory order and drop entries for removed items.
        var byID: [String: CVEInventoryResult] = [:]
        for result in results where byID[result.id] == nil { byID[result.id] = result }
        var ordered: [CVEInventoryResult] = []
        var emitted = Set<String>()
        for item in inventory {
            guard let result = byID[item.id] else { continue }
            if emitted.insert(item.id).inserted { ordered.append(result) }
            else { ordered.append(CVEInventoryResult(item: item, advisories: result.advisories, failure: result.failure)) }
        }
        results = ordered
        resultsByID = byID
        resultDates = resultDates.filter { byID[$0.key] != nil }
    }
}
