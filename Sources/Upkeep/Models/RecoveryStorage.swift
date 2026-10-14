import Foundation

struct RecoveryStorage: Sendable {
    let directory: URL
    let byteLimit: Int64
    let backups: [Backup]
    var metadataUnavailable = false

    struct Backup: Identifiable, Sendable {
        let path: String
        let bytes: Int64?
        let protected: Bool
        var id: String { path }
    }

    var measuredBytes: Int64 { Self.boundedSum(backups.compactMap(\.bytes)) }
    var unknownSizes: Bool { backups.contains { $0.bytes == nil || $0.bytes! < 0 } || Self.exactSum(backups.compactMap(\.bytes)) == nil }
    var protectedBytes: Int64 { Self.boundedSum(backups.filter(\.protected).compactMap(\.bytes)) }
    static func exactSum(_ sizes: [Int64]) -> Int64? {
        var total: Int64 = 0
        for size in sizes {
            guard size >= 0 else { return nil }
            let addition = total.addingReportingOverflow(size)
            guard !addition.overflow else { return nil }
            total = addition.partialValue
        }
        return total
    }

    static func boundedSum(_ sizes: [Int64]) -> Int64 {
        exactSum(sizes) ?? Int64.max
    }
}
