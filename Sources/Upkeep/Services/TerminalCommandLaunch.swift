import Foundation

/// A dedicated pseudo-terminal preserves interactive authorization while keeping
/// the operation's shell separate from the user's interactive Terminal shell.
enum TerminalCommandLaunch {
    static let executable = URL(fileURLWithPath: "/usr/bin/script")

    static func arguments(script: URL) -> [String] {
        ["-q", "/dev/null", "/bin/zsh", script.path]
    }
}
