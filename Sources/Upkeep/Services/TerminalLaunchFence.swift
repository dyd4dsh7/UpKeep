import Darwin
import Foundation

/// Publish PID before checking this gate. Once closed, a launcher either has a
/// published PID to supervise or is guaranteed to refuse the mutation on start.
struct TerminalLaunchFence: Sendable {
    enum State: Equatable { case prevented, published(Int32), unverified }
    let url: URL
    let processIDURL: URL

    func close() throws -> State {
        try Data().write(to: url, options: .atomic)
        var info = stat()
        guard lstat(processIDURL.path, &info) == 0 else {
            return errno == ENOENT ? .prevented : .unverified
        }
        guard let pid = TerminalCommandFiles.processID(at: processIDURL) else { return .unverified }
        return .published(pid)
    }

    func scriptPreamble(statusURL: URL) -> String {
        func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let temporaryPID = processIDURL.appendingPathExtension("publishing")
        return """
        if ! print -r -- "$$" > \(quote(temporaryPID.path)); then exit 125; fi
        if ! /bin/mv -f \(quote(temporaryPID.path)) \(quote(processIDURL.path)); then exit 125; fi
        if [[ -e \(quote(url.path)) ]]; then
          print -r -- "125" > \(quote(statusURL.path))
          print "Upkeep cancelled this Terminal launch before its command started."
          exit 125
        fi
        """
    }
}

/// Failure to write/read the fence cannot authorize releasing a reservation.
func settleFailedTerminalLaunch(
    fence: TerminalLaunchFence, statusURL: URL, scriptURL: URL,
    cancellation: CommandRunner.Cancellation, pollInterval: Duration = .milliseconds(250)
) async -> Bool {
    cancellation.cancel()
    var warned = false
    while true {
        do {
            switch try fence.close() {
            case .prevented:
                OperationCommandLogContext.current?.append("Terminal launch cancelled before PID publication. Retained launch files prevent a late command from mutating the installation.")
                return false
            case let .published(pid):
                _ = try await monitorOwnedTerminalCommand(statusURL: statusURL,
                    processIDURL: fence.processIDURL, scriptURL: scriptURL,
                    pollInterval: pollInterval, cancellation: cancellation, reportedProcessID: pid)
                return true
            case .unverified: break
            }
        } catch { /* Retain the reservation and retry authoritative observation. */ }
        if !warned {
            warned = true
            OperationCommandLogContext.current?.append("Terminal launch outcome is uncertain. Waiting to close its launch gate or verify its process before releasing the install reservation.")
        }
        try? await Task.sleep(for: pollInterval)
    }
}
