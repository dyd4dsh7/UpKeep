import Foundation

struct MenuBarHealth: Equatable {
    let symbol: String
    let summary: String
    let lastChecked: Date?
    var tooltip: String {
        let checked = lastChecked.map { " · Last full check: \($0.formatted(date: .abbreviated, time: .shortened))" } ?? ""
        return "Upkeep — \(summary)\(checked)"
    }

    init(count: Int, state: UpdateCheckState, lastChecked: Date?) {
        self.lastChecked = lastChecked
        switch state {
        case .complete:
            symbol = count == 0 ? "checkmark.circle.fill" : "arrow.down.circle.fill"
            summary = count == 0 ? "No updates found in enabled sources" : "\(count) update\(count == 1 ? "" : "s") available"
        case .notChecked, .disabled, .checking, .partial, .failed:
            symbol = state.symbol
            summary = count == 0 ? state.title : "\(count) known updates · \(state.title.lowercased())"
        }
    }
}
