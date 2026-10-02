import Foundation

struct ListProjectionKey<Filter: Equatable>: Equatable {
    let generation: UInt64
    var relatedGeneration: UInt64 = 0
    var exclusions: UInt64 = 0
    let query: String
    let filter: Filter
}

struct DeveloperListFilterKey: Equatable {
    let manager: DeveloperManagerFilter
    let showCurrent: Bool
}

/// Retains only the latest projection; query churn cannot grow cache storage.
struct ListProjectionCache<Value, Key: Equatable> {
    private var entry: (key: Key, expiresAt: Date?, values: [Value])?

    mutating func values(for key: Key, expiresAt: Date? = nil, now: Date = Date(),
                         build: () -> [Value]) -> [Value] {
        if let entry, entry.key == key, entry.expiresAt.map({ now < $0 }) ?? true {
            return entry.values
        }
        let values = build()
        entry = (key, expiresAt, values)
        return values
    }
}
