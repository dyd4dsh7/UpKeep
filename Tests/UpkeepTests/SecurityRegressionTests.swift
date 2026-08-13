import Foundation
import Testing
@testable import Upkeep

@Test func publisherURLPolicyRejectsNonHTTPSAndPrivateDestinations() throws {
    for value in [
        "http://updates.example.com/feed.xml",
        "https://127.0.0.1/feed.xml",
        "https://10.20.30.40/feed.xml",
        "https://169.254.169.254/latest/meta-data"
    ] {
        var rejected = false
        do { try PublisherURLPolicy.validate(try #require(URL(string: value))) }
        catch { rejected = true }
        #expect(rejected)
    }
}

@Test func terminalAuthorizationCommandIsPassedAsDataNotAppleScriptSource() {
    let malicious = "echo safe; touch '/tmp/quote'\n\" end tell\nrun script \"attacker\""
    let arguments = terminalAppleScriptArguments(command: malicious)

    #expect(arguments.last == malicious)
    #expect(arguments.dropLast().allSatisfy { !$0.contains(malicious) })
    #expect(arguments.contains("do script (item 1 of argv)"))
}

@Test func directReplacementValidatesTheStagedCopyImmediatelyBeforeReplacement() throws {
    let source = URL(fileURLWithPath: "/tmp/Downloaded.app")
    let staged = URL(fileURLWithPath: "/Applications/.Upkeep-Example.app")
    let installed = URL(fileURLWithPath: "/Applications/Example.app")
    var events: [String] = []

    try StagedReplacementTransaction.perform(
        replacement: source,
        staged: staged,
        installed: installed,
        copy: {
            #expect($0 == source && $1 == staged)
            events.append("copy")
        },
        validate: {
            #expect($0 == staged)
            events.append("validate")
        },
        replace: {
            #expect($0 == installed && $1 == staged)
            events.append("replace")
        }
    )

    #expect(events == ["copy", "validate", "replace"])
}

@Test func zipSafetyInspectionAcceptsSmallArchivesAndRejectsBombsAndTraversal() throws {
    let small = try temporaryZIP(name: "Example.app/Contents/Info.plist", compressed: 40, expanded: 80)
    let bomb = try temporaryZIP(name: "Example.app/payload", compressed: 1, expanded: 10_000)
    let traversal = try temporaryZIP(name: "../Applications/Other.app", compressed: 10, expanded: 10)
    defer {
        try? FileManager.default.removeItem(at: small)
        try? FileManager.default.removeItem(at: bomb)
        try? FileManager.default.removeItem(at: traversal)
    }

    try ZIPArchiveInspector.validate(small)
    for archive in [bomb, traversal] {
        var rejected = false
        do { try ZIPArchiveInspector.validate(archive) }
        catch { rejected = true }
        #expect(rejected)
    }
}

private func temporaryZIP(name: String, compressed: UInt32, expanded: UInt32) throws -> URL {
    let nameData = Data(name.utf8)
    var local = Data()
    local.appendLE(UInt32(0x04034b50))
    local.appendLE(UInt16(20))
    local.appendLE(UInt16(0))
    local.appendLE(UInt16(8))
    local.appendLE(UInt16(0))
    local.appendLE(UInt16(0))
    local.appendLE(UInt32(0))
    local.appendLE(compressed)
    local.appendLE(expanded)
    local.appendLE(UInt16(nameData.count))
    local.appendLE(UInt16(0))
    local.append(nameData)
    local.append(Data(repeating: 0, count: Int(compressed)))

    var central = Data()
    central.appendLE(UInt32(0x02014b50))
    central.appendLE(UInt16(20))
    central.appendLE(UInt16(20))
    central.appendLE(UInt16(0))
    central.appendLE(UInt16(8))
    central.appendLE(UInt16(0))
    central.appendLE(UInt16(0))
    central.appendLE(UInt32(0))
    central.appendLE(compressed)
    central.appendLE(expanded)
    central.appendLE(UInt16(nameData.count))
    central.appendLE(UInt16(0))
    central.appendLE(UInt16(0))
    central.appendLE(UInt16(0))
    central.appendLE(UInt16(0))
    central.appendLE(UInt32(0))
    central.appendLE(UInt32(0))
    central.append(nameData)

    var archive = local
    archive.append(central)
    archive.appendLE(UInt32(0x06054b50))
    archive.appendLE(UInt16(0))
    archive.appendLE(UInt16(0))
    archive.appendLE(UInt16(1))
    archive.appendLE(UInt16(1))
    archive.appendLE(UInt32(central.count))
    archive.appendLE(UInt32(local.count))
    archive.appendLE(UInt16(0))

    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("Upkeep-ZIP-Test-\(UUID().uuidString).zip")
    try archive.write(to: url, options: .atomic)
    return url
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
