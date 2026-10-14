import Darwin
import Foundation
import Testing
@testable import Upkeep

@Test(.enabled(if: ProcessInfo.processInfo.environment["UPKEEP_PROCESS_STRESS"] == "1"))
func processAdmissionAcrossNetworkDestinations() async throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("DestinationAdmission.\(UUID())")
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }
    let release = root.appendingPathComponent("release")
    let tasks = (0..<6).map { index in
        Task {
            try await CommandRunner.run(URL(fileURLWithPath: "/bin/sh"),
                ["-c", "printf ready > \"$1\"; while [ ! -f \"$2\" ]; do sleep 0.02; done", "fixture",
                 root.appendingPathComponent("ready-\(index)").path, release.path], timeout: 15,
                admissionKey: index < 3 ? "network:fixture-a" : "network:fixture-b")
        }
    }
    defer { tasks.forEach { $0.cancel() } }
    func startedIndices() -> Set<Int> {
        Set((0..<6).filter { manager.fileExists(atPath: root.appendingPathComponent("ready-\($0)").path) })
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(12))
    while startedIndices().count < 4, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    try await Task.sleep(for: .milliseconds(150))
    let beforeRelease = startedIndices()
    try Data().write(to: release)
    for task in tasks { #expect(try await task.value.status == 0) }
    #expect(beforeRelease.filter { $0 < 3 }.count == 2)
    #expect(beforeRelease.filter { $0 >= 3 }.count == 2)
    #expect(startedIndices().count == 6)
}

// Run separately: deliberately saturating all slots would distort unrelated
// deadline tests running concurrently in the normal Swift Testing suite.
@Test(.enabled(if: ProcessInfo.processInfo.environment["UPKEEP_PROCESS_STRESS"] == "1"))
func globalProcessAdmissionAcrossDistinctExecutables() async throws {
    let samples = ProcessInfo.processInfo.environment["UPKEEP_PROCESS_BENCHMARK"] == "1" ? 8 : 1
    for sample in 0..<samples { try await largeProcessAdmissionFixture(sample: sample) }
}

private func largeProcessAdmissionFixture(sample: Int) async throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("GlobalProcessAdmission.\(UUID())")
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }
    let release = root.appendingPathComponent("release")
    var executables: [URL] = []
    for index in 0..<8 {
        let executable = root.appendingPathComponent("shell-\(index)")
        try manager.copyItem(at: URL(fileURLWithPath: "/bin/sh"), to: executable)
        let signature = try await CommandRunner.run(URL(fileURLWithPath: "/usr/bin/codesign"),
            ["--force", "--sign", "-", executable.path], timeout: 10)
        try #require(signature.status == 0)
        executables.append(executable)
    }
    let commandExecutables = executables
    let workload = 64
    let clock = ContinuousClock()
    let started = clock.now
    let tasks = (0..<workload).map { index in
        Task {
            try await CommandRunner.run(commandExecutables[index % 8],
                ["-c", "printf '%s\\n' \"$$\" > \"$1\"; while [ ! -f \"$2\" ]; do sleep 0.02; done", "fixture",
                 root.appendingPathComponent("ready-\(index)").path, release.path], timeout: 15)
        }
    }
    defer { tasks.forEach { $0.cancel() } }
    func startedCount() -> Int {
        ((try? manager.contentsOfDirectory(atPath: root.path)) ?? []).filter { $0.hasPrefix("ready-") }.count
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(12))
    while startedCount() < 8, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    try await Task.sleep(for: .milliseconds(150))
    let admittedBeforeRelease = startedCount()
    let live = (0..<workload).compactMap { index -> (Int, Int32)? in
        guard let pid = TerminalCommandFiles.processID(at: root.appendingPathComponent("ready-\(index)")),
              kill(pid, 0) == 0 else { return nil }
        return (index % 8, pid)
    }
    let maximumPerExecutable = Dictionary(grouping: live, by: { $0.0 }).values.map(\.count).max() ?? 0
    try Data().write(to: release)
    for task in tasks { #expect(try await task.value.status == 0) }
    #expect(admittedBeforeRelease == 8)
    #expect(live.count == 8)
    #expect(maximumPerExecutable <= 2)
    #expect(startedCount() == workload)
    let elapsed = started.duration(to: clock.now)
    var usage = rusage()
    let memoryAvailable = getrusage(RUSAGE_SELF, &usage) == 0
    let milliseconds = Double(elapsed.components.seconds) * 1_000
        + Double(elapsed.components.attoseconds) / 1e15
    print("PROCESS_LOAD_BENCHMARK sample=\(sample) commands=\(workload) executables=8 admitted_before_release=\(admittedBeforeRelease) live_owned_commands=\(live.count) max_per_executable=\(maximumPerExecutable) completed=\(startedCount()) elapsed_ms=\(milliseconds) process_peak_rss_bytes=\(memoryAvailable ? usage.ru_maxrss : -1) fixture_hold_ms=150")
}

@Test func processAdmissionStartsAtMostTwoCommandsForOneExecutable() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ProcessAdmission.\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let release = root.appendingPathComponent("release")
    defer { try? FileManager.default.removeItem(at: root) }
    let tasks = (0..<6).map { index in
        Task {
            try await CommandRunner.run(URL(fileURLWithPath: "/bin/sh"),
                ["-c", "printf ready > \"$1\"; while [ ! -f \"$2\" ]; do sleep 0.02; done", "fixture",
                 root.appendingPathComponent("ready-\(index)").path, release.path], timeout: 15)
        }
    }
    func startedCount() -> Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).filter { $0.hasPrefix("ready-") }.count
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(12))
    while startedCount() < 2, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    try await Task.sleep(for: .milliseconds(150))
    let admittedBeforeRelease = startedCount()
    try Data().write(to: release)
    for task in tasks { #expect(try await task.value.status == 0) }
    #expect(admittedBeforeRelease == 2)
    #expect(startedCount() == 6)
}

@Test func commandPurposeControlsDeadlinesForShellWrappedMutations() {
    let shell = nvmNodeUpdateArguments(nvmDirectory: "/fixture/.nvm", currentVersion: "18",
                                       targetVersion: "20", isDefault: true)
    #expect(CommandRunner.deadline(for: shell, purpose: .mutation) == 2_400)
    #expect(CommandRunner.deadline(for: ["upgrade"], purpose: .inventory) == 120)
    #expect(CommandRunner.deadline(for: ["cleanup", "--dry-run"]) == 120)
    #expect(CommandRunner.deadline(for: ["install", "example"]) == 2_400)
}

@Test func commandDeadlineTerminatesStalledProcess() async {
    let started = ContinuousClock.now
    await #expect(throws: CommandRunner.Failure.self) {
        try await CommandRunner.run(URL(fileURLWithPath: "/bin/sleep"), ["30"], timeout: 0.1)
    }
    #expect(started.duration(to: .now) < .seconds(3))
}

@Test func commandCancellationReachesChild() async {
    let task = Task { try await CommandRunner.run(URL(fileURLWithPath: "/bin/sleep"), ["30"], timeout: 30) }
    try? await Task.sleep(for: .milliseconds(100))
    let started = ContinuousClock.now
    task.cancel()
    await #expect(throws: (any Error).self) { try await task.value }
    #expect(started.duration(to: .now) < .seconds(3))
}

@Test func commandDrainsBothPipesAndPreservesExitStatus() async throws {
    let result = try await CommandRunner.run(URL(fileURLWithPath: "/bin/sh"),
        ["-c", "i=0; while [ $i -lt 5000 ]; do echo stdout; echo stderr >&2; i=$((i + 1)); done; exit 7"], timeout: 10)
    #expect(result.status == 7)
    #expect(result.stdout.count == 35_000)
    #expect(result.stderr.count == 35_000)
    #expect(result.output.count == 70_000)
}

@Test func commandOutputLimitStopsProducer() async {
    await #expect(throws: CommandRunner.Failure.self) {
        try await CommandRunner.run(URL(fileURLWithPath: "/usr/bin/yes"), [], timeout: 5, maximumOutputBytes: 1024)
    }
}

@Test func outputLimitRetainsThePrefixOfAnOversizedRead() async {
    let log = OperationCommandLog()
    await OperationCommandLogContext.$current.withValue(log) {
        await #expect(throws: CommandRunner.Failure.self) {
            try await CommandRunner.run(URL(fileURLWithPath: "/bin/sh"),
                ["-c", "printf 'useful-error-context-and-extra-output' >&2"],
                timeout: 5, maximumOutputBytes: 20)
        }
    }
    #expect(log.text.contains("useful-error-context"))
}

@Test func synchronousWorkerCancellationStopsCurrentAndFutureCommands() async throws {
    let cancellation = CommandRunner.Cancellation()
    let first = try CommandRunner.capture(URL(fileURLWithPath: "/usr/bin/true"), [], cancellation: cancellation)
    #expect(first.status == 0)
    let task = Task.detached {
        try CommandRunner.capture(URL(fileURLWithPath: "/bin/sleep"), ["30"], timeout: 30,
            cancellation: cancellation)
    }
    try await Task.sleep(for: .milliseconds(100))
    let started = ContinuousClock.now
    cancellation.cancel()
    await #expect(throws: CommandRunner.Failure.self) { try await task.value }
    #expect(started.duration(to: .now) < .seconds(3))
    #expect(throws: CommandRunner.Failure.self) {
        try CommandRunner.capture(URL(fileURLWithPath: "/usr/bin/true"), [], cancellation: cancellation)
    }
    #expect(throws: CommandRunner.Failure.self) { try cancellation.check() }
}

@Test(arguments: [false, true])
func interruptedCommandTerminatesDescendants(cancel: Bool) async throws {
    let marker = FileManager.default.temporaryDirectory.appendingPathComponent("UpkeepDescendant.\(UUID().uuidString)")
    let ready = marker.appendingPathExtension("ready")
    defer {
        try? FileManager.default.removeItem(at: marker)
        try? FileManager.default.removeItem(at: ready)
    }
    let task = Task {
        try await CommandRunner.run(URL(fileURLWithPath: "/bin/sh"),
            ["-c", "trap '' TERM; printf ready > \"$2\"; (trap '' TERM; sleep 1.5; printf leaked > \"$1\") & wait", "fixture", marker.path, ready.path],
            timeout: cancel ? 30 : 0.1)
    }
    if cancel {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !FileManager.default.fileExists(atPath: ready.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(FileManager.default.fileExists(atPath: ready.path))
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
    }
    await #expect(throws: CommandRunner.Failure.self) { try await task.value }
    try await Task.sleep(for: .seconds(1.5))
    #expect(!FileManager.default.fileExists(atPath: marker.path))
}

@Test func exitedParentDoesNotLeavePipeHoldingDescendantRunning() async throws {
    let marker = FileManager.default.temporaryDirectory.appendingPathComponent("UpkeepOrphan.\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: marker) }
    await #expect(throws: CommandRunner.Failure.self) {
        try await CommandRunner.run(URL(fileURLWithPath: "/bin/sh"),
            ["-c", "(trap '' TERM; sleep 3.5; printf leaked > \"$1\") & exit 0", "fixture", marker.path], timeout: 10)
    }
    try await Task.sleep(for: .seconds(1.5))
    #expect(!FileManager.default.fileExists(atPath: marker.path))
}

@Test func executableAdmissionUsesFileIdentityAcrossLinks() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ExecutableIdentity-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let original = root.appendingPathComponent("original")
    let hardLink = root.appendingPathComponent("hard-link")
    let symbolicLink = root.appendingPathComponent("symbolic-link")
    let copy = root.appendingPathComponent("copy")
    try Data("fixture".utf8).write(to: original)
    try FileManager.default.linkItem(at: original, to: hardLink)
    try FileManager.default.createSymbolicLink(at: symbolicLink, withDestinationURL: original)
    try FileManager.default.copyItem(at: original, to: copy)
    let key = CommandRunner.executableAdmissionKey(original)
    #expect(key.hasPrefix("executable:"))
    #expect(CommandRunner.executableAdmissionKey(hardLink) == key)
    #expect(CommandRunner.executableAdmissionKey(symbolicLink) == key)
    #expect(CommandRunner.executableAdmissionKey(copy) != key)
    #expect(CommandRunner.executableAdmissionKey(root.appendingPathComponent("Missing"))
        != CommandRunner.executableAdmissionKey(root.appendingPathComponent("missing")))
}

@Test func commandQueueExpiryNeverLaunchesAndAllowsRetry() async throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("QueueExpiry-\(UUID())")
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }
    let release = root.appendingPathComponent("release")
    let key = "fixture-queue-\(UUID())"
    let held = (0..<2).map { index in
        Task {
            try await CommandRunner.run(URL(fileURLWithPath: "/bin/sh"),
                ["-c", "touch \"$1\"; while [ ! -f \"$2\" ]; do sleep 0.02; done", "fixture",
                 root.appendingPathComponent("ready-\(index)").path, release.path], timeout: 15, admissionKey: key)
        }
    }
    defer { held.forEach { $0.cancel() } }
    let deadline = ContinuousClock.now.advanced(by: .seconds(12))
    while !(0..<2).allSatisfy({ manager.fileExists(atPath: root.appendingPathComponent("ready-\($0)").path) }),
          ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    try #require((0..<2).allSatisfy { manager.fileExists(atPath: root.appendingPathComponent("ready-\($0)").path) })
    let marker = root.appendingPathComponent("must-not-launch")
    do {
        _ = try await CommandRunner.run(URL(fileURLWithPath: "/bin/sh"),
            ["-c", "touch \"$1\"", "fixture", marker.path], admissionKey: key, admissionTimeout: 0.03)
        Issue.record("Expected command admission timeout")
    } catch CommandRunner.Failure.timedOut {}
    #expect(!manager.fileExists(atPath: marker.path))
    try Data().write(to: release)
    for task in held { #expect(try await task.value.status == 0) }
    let retry = try await CommandRunner.run(URL(fileURLWithPath: "/bin/sh"),
        ["-c", "touch \"$1\"", "fixture", marker.path], admissionKey: key, admissionTimeout: 1)
    #expect(retry.status == 0)
    #expect(manager.fileExists(atPath: marker.path))
}
