import Foundation
import Testing
@testable import Upkeep

@Test(arguments: [Int32(0), 7], [false, true])
func terminalPipelineRetainsProducerFailureAndDetectsRelayFailure(producerStatus: Int32, relayFails: Bool) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    if !relayFails { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    let script = """
    typeset -i upkeep_status=1
    producer=$1; shift
    (exit "$producer") | "$@"
    \(TerminalOutputRelay.pipelineStatus)
    exit "$upkeep_status"
    """
    let result = try await CommandRunner.run(URL(fileURLWithPath: "/bin/zsh"),
        ["-c", script, "fixture", String(producerStatus), TerminalOutputRelay.executable.path]
            + TerminalOutputRelay.arguments(output: root.appendingPathComponent("output"), append: false, maximumBytes: 64), timeout: 5)
    if producerStatus != 0 { #expect(result.status == producerStatus) }
    else { #expect((result.status != 0) == relayFails) }
}

@Test(arguments: [0, 64, 65, 100_000])
func terminalRelayBoundsDiskWhilePreservingConsoleOutput(length: Int) async throws {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent("Relay ' \(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: output) }
    let text = String(repeating: "a", count: length)
    let result = try await runRelay(text: text, output: output, append: false)
    #expect(result.status == 0)
    #expect(result.stdout == Data(text.utf8))
    let retained = try Data(contentsOf: output)
    #expect(retained.count == min(length, 64))
    #expect(String(decoding: retained, as: UTF8.self).contains("[Command output truncated]") == (length > 64))
}

@Test func terminalRelayAppendSharesTheSameDiskBudget() async throws {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: output) }
    _ = try await runRelay(text: "repair-output\n", output: output, append: false)
    _ = try await runRelay(text: "update-output\n", output: output, append: true)
    #expect(try String(contentsOf: output, encoding: .utf8) == "repair-output\nupdate-output\n")
    let text = String(repeating: "b", count: 1_000)
    let result = try await runRelay(text: text, output: output, append: true)
    #expect(result.status == 0)
    #expect(result.stdout == Data(text.utf8))
    let retained = try Data(contentsOf: output)
    #expect(retained.count == 64)
    #expect(String(decoding: retained, as: UTF8.self).hasPrefix("repair-output\nupdate-output\n"))
    #expect(String(decoding: retained, as: UTF8.self).hasSuffix("[Command output truncated]\n"))
}

private func runRelay(text: String, output: URL, append: Bool) async throws -> CommandRunner.Result {
    try await CommandRunner.run(URL(fileURLWithPath: "/bin/sh"),
        ["-c", "text=$1; shift; printf '%s' \"$text\" | \"$@\"", "fixture", text, TerminalOutputRelay.executable.path]
            + TerminalOutputRelay.arguments(output: output, append: append, maximumBytes: 64), timeout: 5)
}
