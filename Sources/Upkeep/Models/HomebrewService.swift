import Foundation

/// A current-user service reported by `brew services list --json`.
/// Unknown status values remain visible rather than being inferred as stopped.
struct HomebrewService: Decodable, Sendable, Equatable {
    let name: String
    let status: String
    let user: String?
    let file: String?
    let exitCode: Int?

    var isStarted: Bool { status == "started" }

    enum CodingKeys: String, CodingKey {
        case name, status, user, file
        case exitCode = "exit_code"
    }
}
