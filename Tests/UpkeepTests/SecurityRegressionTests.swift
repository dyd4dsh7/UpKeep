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

@Test func publisherConnectionPolicyRejectsPrivateRemoteAddresses() throws {
    for address in [
        "127.0.0.1", "10.20.30.40", "169.254.169.254", "192.0.2.1",
        "198.18.0.1", "203.0.113.1", "::1", "::127.0.0.1", "100::1",
        "2001:2::1", "2001:db8::1", "fc00::1",
    ] {
        var rejected = false
        do { try PublisherURLPolicy.validateRemoteAddress(address) }
        catch { rejected = true }
        #expect(rejected)
    }

    try PublisherURLPolicy.validateRemoteAddress("8.8.8.8")
    try PublisherURLPolicy.validateRemoteAddress("2606:4700:4700::1111")
}

@Test func publisherCurlPinsTheValidatedAddressAndBypassesProxies() throws {
    var request = URLRequest(url: try #require(URL(string: "https://updates.example.com/feed")))
    request.timeoutInterval = 15
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let headers = URL(fileURLWithPath: "/tmp/request-headers")
    let arguments = try PublisherCurlTransport.curlArguments(
        for: request,
        resolvedAddress: "8.8.8.8",
        headerURL: URL(fileURLWithPath: "/tmp/response-headers"),
        bodyURL: URL(fileURLWithPath: "/tmp/response-body"),
        requestBodyURL: nil,
        requestHeadersURL: headers,
        maximumBytes: 1_024
    )

    #expect(arguments.contains("--noproxy"))
    #expect(arguments.contains("*"))
    #expect(arguments.contains("updates.example.com:443:8.8.8.8"))
    #expect(arguments.contains("@\(headers.path)"))
    #expect(!arguments.contains(where: { $0.contains("application/json") }))
    #expect(try PublisherCurlTransport.validatedHeaderLines(for: request) == ["Accept: application/json"])
}

@Test func publisherCurlUsesTheFinalResponseHeaderBlock() throws {
    let headerURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("Upkeep-Curl-Headers-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: headerURL) }
    try Data("""
    HTTP/1.1 100 Continue\r
    \r
    HTTP/2 302\r
    Location: /next\r
    Content-Type: application/json\r
    \r
    """.utf8).write(to: headerURL)

    let headers = try PublisherCurlTransport.responseHeaders(at: headerURL)
    #expect(headers["Location"] == "/next")
    #expect(headers["Content-Type"] == "application/json")
}

@Test func publisherRedirectOriginsIncludeTheEffectivePort() throws {
    let source = try #require(URL(string: "https://registry.example.com/token"))
    let sameOrigin = try #require(URL(string: "https://registry.example.com/v2/token"))
    let differentHost = try #require(URL(string: "https://cdn.example.net/token"))
    let differentPort = try #require(URL(string: "https://registry.example.com:8443/token"))

    #expect(PublisherCurlTransport.sameOrigin(source, sameOrigin))
    #expect(!PublisherCurlTransport.sameOrigin(source, differentHost))
    #expect(!PublisherCurlTransport.sameOrigin(source, differentPort))
}

@Test func terminalAuthorizationCommandIsPassedAsDataNotAppleScriptSource() {
    let malicious = "echo safe; touch '/tmp/quote'\n\" end tell\nrun script \"attacker\""
    let arguments = terminalAppleScriptArguments(command: malicious)

    #expect(arguments.last == malicious)
    #expect(arguments.dropLast().allSatisfy { !$0.contains(malicious) })
    #expect(arguments.contains("do script (item 1 of argv)"))
}

@Test func terminalAuthorizationWaitTimesOutWhenNoStatusArrives() async {
    let missingStatus = FileManager.default.temporaryDirectory
        .appendingPathComponent("Upkeep-Missing-Terminal-Status-\(UUID().uuidString)")
    let missingProcessID = missingStatus.appendingPathExtension("pid")
    var timedOut = false
    do {
        try await waitForTerminalStatus(
            at: missingStatus,
            processIDURL: missingProcessID,
            launchTimeout: .zero,
            pollInterval: .zero
        )
    }
    catch { timedOut = true }
    #expect(timedOut)
}

@Test func terminalAuthorizationWaitReturnsWhenStatusExists() async throws {
    let status = FileManager.default.temporaryDirectory
        .appendingPathComponent("Upkeep-Terminal-Status-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: status) }
    try Data("0".utf8).write(to: status)
    try await waitForTerminalStatus(
        at: status,
        processIDURL: status.appendingPathExtension("pid"),
        launchTimeout: .zero,
        pollInterval: .zero
    )
}

@Test func terminalAuthorizationWaitDetectsAStoppedCommand() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Upkeep-Stopped-Terminal-\(UUID().uuidString)")
    let status = root.appendingPathExtension("status")
    let processID = root.appendingPathExtension("pid")
    defer { try? FileManager.default.removeItem(at: processID) }
    try Data("123".utf8).write(to: processID)
    var stopped = false
    do {
        try await waitForTerminalStatus(
            at: status,
            processIDURL: processID,
            launchTimeout: .seconds(1),
            pollInterval: .zero,
            processIsRunning: { _ in false }
        )
    } catch { stopped = true }
    #expect(stopped)
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
