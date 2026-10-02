import Darwin
import Foundation
import Testing
@testable import Upkeep

@Test func terminalProcessIdentityRejectsUnownedOrMissingProcesses() {
    let script = URL(fileURLWithPath: "/nonexistent/Upkeep-command.zsh")
    #expect(TerminalProcessIdentity.capture(processID: getpid(), scriptURL: script) == nil)
    #expect(TerminalProcessIdentity.capture(processID: 0, scriptURL: script) == nil)
    #expect(TerminalProcessIdentity.capture(processID: -1, scriptURL: script) == nil)
    #expect(TerminalProcessIdentity.capture(processID: Int32.max, scriptURL: script) == nil)
}

@Test func terminalProcessIdentityMatchesOnlyItsLiveScriptAndBirthTime() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Upkeep-Process-Identity-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let script = root.appendingPathComponent("command.zsh")
    let pidFile = root.appendingPathComponent("pid")
    let releaseFile = root.appendingPathComponent("release")
    // All paths are generated UUID directories; no user-supplied shell source.
    try """
    setopt NO_MONITOR
    print -r -- "$$" > '\(pidFile.path)'
    while [[ ! -f '\(releaseFile.path)' ]]; do /bin/sleep 0.01; done
    """.write(to: script, atomically: true, encoding: .utf8)
    let launch = Task {
        try await CommandRunner.run(TerminalCommandLaunch.executable,
            TerminalCommandLaunch.arguments(script: script), timeout: 10)
    }
    var identity: TerminalProcessIdentity?
    for _ in 0..<1_000 {
        if let pid = TerminalCommandFiles.processID(at: pidFile) {
            identity = TerminalProcessIdentity.capture(processID: pid, scriptURL: script)
            if identity != nil { break }
        }
        try? await Task.sleep(for: .milliseconds(1))
    }
    // Always release the fixture before a failed requirement can throw.
    let observed = identity
    if let observed {
        #expect(observed.stillMatches())
        #expect(TerminalProcessIdentity.capture(processID: observed.processID,
            scriptURL: root.appendingPathComponent("different.zsh")) == nil)
        let wrongBirth = TerminalProcessIdentity(processID: observed.processID,
            startSeconds: observed.startSeconds + 1, startMicroseconds: observed.startMicroseconds,
            scriptURL: observed.scriptURL)
        #expect(!wrongBirth.stillMatches())
    }
    try Data().write(to: releaseFile)
    let result = try await launch.value
    #expect(result.status == 0)
    let captured = try #require(observed)
    #expect(!captured.stillMatches())
}

@Test func terminalCommandLaunchOwnsItsShellGroupAndPreservesControllingTTY() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Upkeep-PTY-Fixture-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    // Spaces and shell metacharacters remain an argv path, not shell source.
    let script = root.appendingPathComponent("fixture with spaces $literal.zsh")
    try """
    setopt NO_MONITOR
    print -r -- "UPKEEP_FIXTURE_PID=$$"
    print -r -- "UPKEEP_FIXTURE_GROUP=$(/bin/ps -o pgid= -p $$ | /usr/bin/tr -d ' ')"
    if test -t 0 && test -t 1 && test -r /dev/tty; then
      print -r -- "UPKEEP_FIXTURE_TTY=ready"
    fi
    /bin/zsh -c 'print -r -- "UPKEEP_DESCENDANT_GROUP=$(/bin/ps -o pgid= -p $$ | /usr/bin/tr -d " ")"'
    exit 7
    """.write(to: script, atomically: true, encoding: .utf8)
    let result = try await CommandRunner.run(TerminalCommandLaunch.executable,
        TerminalCommandLaunch.arguments(script: script), timeout: 10)
    // macOS script propagates its child's exit status.
    #expect(result.status == 7)
    let output = String(decoding: result.output, as: UTF8.self)
    func value(_ key: String) -> String? {
        // script may echo its stdin EOF marker before the first output line.
        guard let line = output.components(separatedBy: .newlines).first(where: { $0.contains(key + "=") }),
              let marker = line.range(of: key + "=") else { return nil }
        return String(line[marker.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let pid = try #require(value("UPKEEP_FIXTURE_PID").flatMap(Int32.init))
    let group = try #require(value("UPKEEP_FIXTURE_GROUP").flatMap(Int32.init))
    #expect(pid == group)
    #expect(group != getpgrp())
    #expect(value("UPKEEP_FIXTURE_TTY") == "ready")
    #expect(value("UPKEEP_DESCENDANT_GROUP").flatMap(Int32.init) == group)
}
