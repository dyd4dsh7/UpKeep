import Foundation
import Testing
@testable import Upkeep

private struct LaunchFenceFixture {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Upkeep-Fence-Fixture-\(UUID().uuidString)")
        .appendingPathComponent("path with ' quote $literal")
    var script: URL { root.appendingPathComponent("command.zsh") }
    var pid: URL { root.appendingPathComponent("pid") }
    var status: URL { root.appendingPathComponent("status") }
    var marker: URL { root.appendingPathComponent("mutation") }
    var fence: TerminalLaunchFence {
        TerminalLaunchFence(url: root.appendingPathComponent("launch-cancelled"), processIDURL: pid)
    }
    func prepare() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    func cleanUp() { try? FileManager.default.removeItem(at: root) }
    func launch() async throws -> CommandRunner.Result {
        try await CommandRunner.run(TerminalCommandLaunch.executable,
            TerminalCommandLaunch.arguments(script: script), timeout: 10)
    }
    func quote(_ url: URL) -> String { "'" + url.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

@Test func failedLaunchFencePreventsALateScriptFromMutating() async throws {
    let f = LaunchFenceFixture()
    try f.prepare()
    defer { f.cleanUp() }
    try """
    setopt NO_MONITOR
    \(f.fence.scriptPreamble(statusURL: f.status))
    print -r -- "mutated" > \(f.quote(f.marker))
    """.write(to: f.script, atomically: true, encoding: .utf8)
    #expect(await settleFailedTerminalLaunch(fence: f.fence, statusURL: f.status,
        scriptURL: f.script, cancellation: CommandRunner.Cancellation()) == false)
    #expect(FileManager.default.fileExists(atPath: f.script.path))
    #expect(FileManager.default.fileExists(atPath: f.fence.url.path))
    let late = try await f.launch()
    #expect(late.status == 125)
    #expect(TerminalCommandFiles.status(at: f.status) == 125)
    #expect(!FileManager.default.fileExists(atPath: f.marker.path))
}

@Test func failedLaunchWithPublishedPIDWaitsForVerifiedShutdown() async throws {
    let f = LaunchFenceFixture()
    try f.prepare()
    defer { f.cleanUp() }
    let release = f.root.appendingPathComponent("release")
    try """
    setopt NO_MONITOR
    \(f.fence.scriptPreamble(statusURL: f.status))
    trap '' TERM
    print -r -- "started" > \(f.quote(f.marker))
    while [[ ! -f \(f.quote(release)) ]]; do /bin/sleep 0.01; done
    """.write(to: f.script, atomically: true, encoding: .utf8)
    let launch = Task { try await f.launch() }
    let fallback = Task {
        try? await Task.sleep(for: .seconds(3))
        if !Task.isCancelled { try? Data().write(to: release) }
    }
    defer { fallback.cancel() }
    for _ in 0..<1_000 {
        if FileManager.default.fileExists(atPath: f.marker.path) { break }
        try? await Task.sleep(for: .milliseconds(1))
    }
    #expect(FileManager.default.fileExists(atPath: f.marker.path))
    let pid = TerminalCommandFiles.processID(at: f.pid)
    #expect(pid != nil)
    let stopped = await settleFailedTerminalLaunch(fence: f.fence, statusURL: f.status,
        scriptURL: f.script, cancellation: CommandRunner.Cancellation(), pollInterval: .milliseconds(5))
    #expect(stopped)
    if let pid { #expect(TerminalProcessGroup.isEmpty(groupID: pid) == true) }
    #expect(try await launch.value.status != 0)
    #expect(!FileManager.default.fileExists(atPath: release.path))
}

@Test func launchFenceDoesNotTreatAnUnreadablePIDReceiptAsNoLaunch() throws {
    let f = LaunchFenceFixture()
    try f.prepare()
    defer { f.cleanUp() }
    try Data("invalid PID".utf8).write(to: f.pid)
    #expect(try f.fence.close() == .unverified)
}

@Test func PIDPublicationFailureAbortsBeforeAnyMutation() async throws {
    let f = LaunchFenceFixture()
    try f.prepare()
    defer { f.cleanUp() }
    let broken = TerminalLaunchFence(url: f.fence.url,
        processIDURL: f.root.appendingPathComponent("missing-parent/pid"))
    try """
    setopt NO_MONITOR
    \(broken.scriptPreamble(statusURL: f.status))
    print -r -- "mutated" > \(f.quote(f.marker))
    """.write(to: f.script, atomically: true, encoding: .utf8)
    #expect(try await f.launch().status == 125)
    #expect(!FileManager.default.fileExists(atPath: f.marker.path))
}
