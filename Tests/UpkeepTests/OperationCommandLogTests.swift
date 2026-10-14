import Foundation
import Testing
@testable import Upkeep

@Test func concurrentCommandsKeepSeparateOperationLogs() async throws {
    let first = OperationCommandLog(), second = OperationCommandLog()
    async let a = OperationCommandLogContext.$current.withValue(first) {
        try await CommandRunner.run(URL(fileURLWithPath: "/bin/echo"), ["first-output"])
    }
    async let b = OperationCommandLogContext.$current.withValue(second) {
        try await CommandRunner.run(URL(fileURLWithPath: "/bin/echo"), ["second-output"])
    }
    _ = try await (a, b)
    #expect(first.text.contains("first-output"))
    #expect(!first.text.contains("second-output"))
    #expect(second.text.contains("second-output"))
    #expect(!second.text.contains("first-output"))
}

@Test func operationLogsRedactAndBoundRetainedOutput() {
    let log = OperationCommandLog()
    log.append("password=private-value")
    log.append("tool --password paired-private-value")
    for _ in 0..<100 { log.append(String(repeating: "x", count: 2_000)) }
    #expect(!log.text.contains("private-value"))
    #expect(log.text.contains("[Log output truncated]"))
    #expect(log.text.count <= 32_768)
}

@Test func timedOutCommandRetainsOutputAndFailureInOperationLog() async {
    let log = OperationCommandLog()
    do {
        _ = try await OperationCommandLogContext.$current.withValue(log) {
            try await CommandRunner.run(URL(fileURLWithPath: "/bin/sh"),
                ["-c", "printf 'before-timeout\\n'; exec /bin/sleep 5"], timeout: 0.2)
        }
        Issue.record("Command unexpectedly completed")
    } catch {
        #expect(log.text.contains("before-timeout\n"))
        #expect(log.text.contains("Exit status:"))
        #expect(log.text.contains("Command failed:"))
    }
}

@Test func terminalLogCapturesFixtureOutputAndMissingStatusHonestly() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let output = directory.appendingPathComponent("output"), status = directory.appendingPathComponent("status")
    try "terminal-fixture-output password=private-value".write(to: output, atomically: true, encoding: .utf8)
    let log = OperationCommandLog()
    log.appendTerminalOutput(outputURL: output, statusURL: status)
    #expect(log.text.contains("not reported"))
    #expect(log.text.contains("terminal-fixture-output"))
    #expect(!log.text.contains("private-value"))
    try "42".write(to: status, atomically: true, encoding: .utf8)
    log.appendTerminalOutput(outputURL: output, statusURL: status)
    #expect(log.text.contains("Terminal exit status: 42"))
}
