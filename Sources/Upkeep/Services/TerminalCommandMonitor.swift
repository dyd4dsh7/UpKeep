import Darwin
import Foundation

enum TerminalCommandCompletion {
    case completed, timedOut, cancelled, missingReceipt
}

func monitorOwnedTerminalCommand(
    statusURL: URL, processIDURL: URL, scriptURL: URL,
    launchTimeout: Duration = .seconds(30), executionTimeout: Duration = .seconds(2_400),
    terminationGrace: Duration = .milliseconds(500), pollInterval: Duration = .milliseconds(250),
    cancellation: CommandRunner.Cancellation? = nil, reportedProcessID: Int32? = nil
) async throws -> TerminalCommandCompletion {
    let clock = ContinuousClock()
    let started = clock.now
    let launchDeadline = started.advanced(by: launchTimeout)
    let executionDeadline = started.advanced(by: executionTimeout)
    var group: TerminalProcessGroup?
    var warnedDuringLaunch = false
    var publishedPID = reportedProcessID
    while group == nil {
        if publishedPID == nil { publishedPID = TerminalCommandFiles.processID(at: processIDURL) }
        if let pid = publishedPID,
           let identity = TerminalProcessIdentity.capture(processID: pid, scriptURL: scriptURL) {
            group = TerminalProcessGroup(identity: identity)
        }
        if group != nil { break }
        // A fast command may finish before its identity is captured. Its receipt
        // is insufficient until the recorded process group is actually empty.
        if let pid = publishedPID,
           TerminalProcessGroup.isEmpty(groupID: pid) == true {
            return TerminalCommandFiles.status(at: statusURL) != nil ? .completed : .missingReceipt
        }
        if clock.now >= launchDeadline {
            guard publishedPID != nil else {
                throw HomebrewClient.BrewError.failed("The dedicated Terminal command could not be identified. Review Terminal before retrying; its command files have been retained.")
            }
            if !warnedDuringLaunch {
                warnedDuringLaunch = true
                OperationCommandLogContext.current?.append("Terminal has reported a process but ownership is unverified. Waiting for its group to stop before releasing the install reservation.")
            }
        }
        try await Task.sleep(for: pollInterval)
    }
    guard var owned = group else { return .missingReceipt }
    var interruption: TerminalCommandCompletion?
    var escalationDeadline: ContinuousClock.Instant?
    var warned = false
    while true {
        switch owned.observe() {
        case .stopped:
            if let interruption { return interruption }
            return TerminalCommandFiles.status(at: statusURL) != nil ? .completed : .missingReceipt
        case .running, .unverified: break
        }
        let cancellationRequested: Bool
        do { try cancellation?.check(); cancellationRequested = false }
        catch { cancellationRequested = true }
        if interruption == nil && (cancellationRequested || clock.now >= executionDeadline) {
            interruption = cancellationRequested ? .cancelled : .timedOut
            escalationDeadline = clock.now.advanced(by: terminationGrace)
            _ = owned.signal(SIGTERM)
            OperationCommandLogContext.current?.append(cancellationRequested
                ? "Terminal command cancellation requested; stopping its verified process group and waiting for completion."
                : "Terminal command deadline exceeded; stopping its verified process group and waiting for completion.")
        }
        if interruption != nil, let deadline = escalationDeadline, clock.now >= deadline {
            if !owned.signal(SIGKILL), !warned {
                warned = true
                OperationCommandLogContext.current?.append("Terminal command termination could not be confirmed. The install reservation remains held; review Terminal for an administrator-owned or unidentified process.")
            }
        }
        // A receipt alone cannot release the reservation while descendants remain.
        try await Task.sleep(for: pollInterval)
    }
}
