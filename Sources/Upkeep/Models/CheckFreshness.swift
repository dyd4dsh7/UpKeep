import Foundation

struct CheckFreshness: Codable, Equatable, Sendable {
    var lastAttempt: Date
    var lastSuccess: Date?
    var failure: String?

    var isRetained: Bool { failure != nil && lastSuccess != nil }
}
