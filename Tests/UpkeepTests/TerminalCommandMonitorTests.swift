import Foundation
import Testing
@testable import Upkeep

@MainActor
@Test func terminalReceiptDoesNotFinishMonitorWhileItsGroupIsRunning() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Upkeep-Terminal-Early-Receipt-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let script = root.appendingPathComponent("command.zsh")
    let pid = root.appendingPathComponent("pid")
    let status = root.appendingPathComponent("status")
    let release = root.appendingPathComponent("release")
    try """
    setopt NO_MONITOR
    print -r -- "$$" > '\(pid.path)'
    print -r -- "0" > '\(status.path)'
    while [[ ! -f '\(release.path)' ]]; do /bin/sleep 0.01; done
    """.write(to: script, atomically: true, encoding: .utf8)
    let launch = Task {
        try await CommandRunner.run(TerminalCommandLaunch.executable,
            TerminalCommandLaunch.arguments(script: script), timeout: 10)
    }
    var finished = false
    let monitor = Task {
        defer { finished = true }
        return try await monitorOwnedTerminalCommand(statusURL: status, processIDURL: pid,
            scriptURL: script, launchTimeout: .seconds(1), executionTimeout: .seconds(3),
            pollInterval: .milliseconds(5))
    }
    for _ in 0..<1_000 {
        if TerminalCommandFiles.status(at: status) == 0 { break }
        try? await Task.sleep(for: .milliseconds(1))
    }
    #expect(TerminalCommandFiles.status(at: status) == 0)
    try? await Task.sleep(for: .milliseconds(20))
    #expect(!finished)
    try Data().write(to: release)
    #expect(try await monitor.value == .completed)
    #expect(try await launch.value.status == 0)
    #expect(finished)
}

@Test(arguments: [false, true], [false, true])
func terminalInterruptionStopsTermIgnoringDescendantsBeforeReturning(leaderIgnoresTerm: Bool, cancel: Bool) async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Upkeep-Terminal-Deadline-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let script = root.appendingPathComponent("command.zsh")
    let child = root.appendingPathComponent("child.zsh")
    let pid = root.appendingPathComponent("pid")
    let ready = root.appendingPathComponent("ready")
    let release = root.appendingPathComponent("release")
    let status = root.appendingPathComponent("status")
    try """
    trap '' TERM
    print -r -- "ready" > '\(ready.path)'
    while [[ ! -f '\(release.path)' ]]; do /bin/sleep 0.01; done
    """.write(to: child, atomically: true, encoding: .utf8)
    try """
    setopt NO_MONITOR
    print -r -- "$$" > '\(pid.path)'
    trap 'print -r -- "1" > "\(status.path)"' EXIT
    \(leaderIgnoresTerm ? "trap '' TERM" : "trap 'exit 143' TERM")
    /bin/zsh '\(child.path)' &
    wait
    """.write(to: script, atomically: true, encoding: .utf8)
    let launch = Task {
        try await CommandRunner.run(TerminalCommandLaunch.executable,
            TerminalCommandLaunch.arguments(script: script), timeout: 10)
    }
    // Fallback only releases this harmless fixture if termination is broken.
    let fallback = Task {
        try? await Task.sleep(for: .seconds(2))
        if !Task.isCancelled { try? Data().write(to: release) }
    }
    defer { fallback.cancel() }
    for _ in 0..<1_000 {
        if FileManager.default.fileExists(atPath: ready.path) { break }
        try? await Task.sleep(for: .milliseconds(1))
    }
    #expect(FileManager.default.fileExists(atPath: ready.path))
    let processID = try #require(TerminalCommandFiles.processID(at: pid))
    let identity = try #require(TerminalProcessIdentity.capture(processID: processID, scriptURL: script))
    var group = try #require(TerminalProcessGroup(identity: identity))
    #expect(group.observe() == .running)
    let cancellation = CommandRunner.Cancellation()
    if cancel { cancellation.cancel() }
    let completion = try await monitorOwnedTerminalCommand(statusURL: status, processIDURL: pid, scriptURL: script,
            launchTimeout: .seconds(1), executionTimeout: cancel ? .seconds(3) : .milliseconds(40),
            terminationGrace: .milliseconds(20), pollInterval: .milliseconds(5), cancellation: cancellation)
    #expect(completion == (cancel ? .cancelled : .timedOut))
    #expect(group.observe() == .stopped)
    #expect(!identity.stillMatches())
    let result = try await launch.value
    #expect(result.status != 0)
    #expect(!FileManager.default.fileExists(atPath: release.path))
}
