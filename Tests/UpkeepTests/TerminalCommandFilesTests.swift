import Foundation
import Testing
@testable import Upkeep

@Test(arguments: ["", "invalid", "0", "1"])
func terminalWorkspaceRetainsUnverifiedResults(receipt: String) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let status = root.appendingPathComponent("status")
    if !receipt.isEmpty { try Data(receipt.utf8).write(to: status) }
    let complete = receipt == "0" || receipt == "1"
    #expect(try TerminalCommandFiles.removeCompletedWorkspace(root, statusURL: status) == complete)
    #expect(FileManager.default.fileExists(atPath: root.path) == !complete)
    if !complete {
        // A command still running after monitor cancellation can publish later.
        try Data("0".utf8).write(to: status)
        #expect(try TerminalCommandFiles.removeCompletedWorkspace(root, statusURL: status))
    }
}

@Test(arguments: [0, 64, 65, 100_000])
func terminalOutputReadsOnlyTheConfiguredPrefix(length: Int) throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    try Data(repeating: 65, count: length).write(to: file)
    let output = try TerminalCommandFiles.readOutput(at: file, maximumBytes: 64)
    #expect(output.data == Data(repeating: 65, count: min(length, 64)))
    #expect(output.truncated == (length > 64))
    #expect(String(decoding: output.displayData, as: UTF8.self).contains("truncated") == (length > 64))
}

@Test func terminalStatusAndPIDRejectMalformedAndOversizedFiles() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    for text in ["", "garbage", "0\nextra", "2147483648", "0" + String(repeating: " ", count: 100)] {
        try Data(text.utf8).write(to: file)
        #expect(TerminalCommandFiles.status(at: file) == nil)
        #expect(TerminalCommandFiles.processID(at: file) == nil)
    }
    for text in ["-1", "256"] {
        try Data(text.utf8).write(to: file)
        #expect(TerminalCommandFiles.status(at: file) == nil)
    }
    try Data("0\n".utf8).write(to: file)
    #expect(TerminalCommandFiles.status(at: file) == 0)
    #expect(TerminalCommandFiles.processID(at: file) == nil)
    try Data("123\n".utf8).write(to: file)
    #expect(TerminalCommandFiles.processID(at: file) == 123)
}
