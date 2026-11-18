import Foundation
import Observation

/// App-owned scan state survives navigation and keeps network work off the view lifecycle.
@MainActor @Observable
final class CVEScanState {
    var filter: CVEResultFilter = .all
    var searchText = ""
    var requestedItemID: String?
    private(set) var results: [CVEInventoryResult] = []
    private(set) var inventory: [CVEInventoryItem] = []
    private(set) var checkedAt: Date?
    private(set) var running = false
    private(set) var currentItemID: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    @discardableResult
    func start(inventory: [CVEInventoryItem], client: CVEInventoryClient) -> Bool {
        guard !running, !inventory.isEmpty else { return false }
        self.inventory = inventory
        results = []
        checkedAt = Date()
        running = true
        task = Task { await run(inventory: inventory, client: client) }
        return true
    }

    func cancel() { task?.cancel() }
    func waitForCompletion() async { await task?.value }

    private func run(inventory: [CVEInventoryItem], client: CVEInventoryClient) async {
        defer {
            currentItemID = nil; running = false; task = nil
            if filter == .all, results.contains(where: { !$0.advisories.isEmpty }) { filter = .findings }
        }
        for item in inventory {
            if Task.isCancelled { break }
            currentItemID = item.id
            do {
                let result = try await client.check(item)
                try Task.checkCancellation()
                results.append(result)
            } catch {
                if Task.isCancelled { break }
                results.append(CVEInventoryResult(item: item, advisories: [], failure: error.localizedDescription))
            }
        }
        for item in inventory.dropFirst(results.count) {
            results.append(CVEInventoryResult(item: item, advisories: [],
                failure: item.target == nil ? nil : "Check cancelled before completion."))
        }
    }
}
