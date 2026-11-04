import Darwin
import Foundation

enum CommandRunner {
    /// Finder and login-item launches need not inherit a shell's HOME variable.
    static func commandEnvironment(_ base: [String: String]) -> [String: String] {
        var environment = base
        if environment["HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        }
        return environment
    }

    private static let processGate = SourceRequestGate(globalLimit: 8, perHostLimit: 2, caseInsensitiveKeys: false)
    enum Purpose {
        case automatic, inventory, mutation
    }
    /// Shares cancellation across sequential synchronous commands inside a worker.
    final class Cancellation: Sendable {
        fileprivate let control = Control()
        func cancel() { control.cancel() }
        func check() throws {
            if let failure = control.failure { throw failure }
        }
    }
    struct Result: Sendable {
        let stdout: Data
        let stderr: Data
        let output: Data
        let status: Int32
    }

    enum Failure: LocalizedError {
        case timedOut, cancelled, outputLimit
        var errorDescription: String? {
            switch self {
            case .timedOut: "The command exceeded its time limit. Refresh the installed item to verify its state."
            case .cancelled: "The command was cancelled. Refresh the installed item to verify its state."
            case .outputLimit: "The command exceeded the output limit. Refresh the installed item to verify its state."
            }
        }
    }

    /// Inventory has a short deadline; mutations can legitimately download large
    /// packages. Cancellation always reaches the actual child process.
    static func deadline(for arguments: [String], purpose: Purpose = .automatic) -> TimeInterval {
        switch purpose {
        case .inventory: return 120
        case .mutation: return 2_400
        case .automatic: break
        }
        let mutations: Set<String> = ["install", "uninstall", "upgrade", "update", "add", "remove", "pull", "get", "prune", "cleanup", "verify"]
        return arguments.contains(where: mutations.contains) && !arguments.contains("--dry-run") ? 2_400 : 120
    }

    static func run(
        _ executable: URL, _ arguments: [String], environment: [String: String]? = nil,
        directory: URL? = nil, timeout: TimeInterval = 120, maximumOutputBytes: Int = 16 * 1_024 * 1_024,
        admissionKey: String? = nil, admissionTimeout: TimeInterval = 120
    ) async throws -> Result {
        do {
            return try await processGate.withPermit(host: admissionKey ?? executableAdmissionKey(executable),
                                                   queueTimeout: .seconds(admissionTimeout)) {
                try await runAdmitted(executable, arguments, environment: environment, directory: directory,
                                      timeout: timeout, maximumOutputBytes: maximumOutputBytes)
            }
        } catch is CancellationError { throw Failure.cancelled }
        catch SourceRequestGate.AdmissionFailure.timedOut { throw Failure.timedOut }
    }

    static func executableAdmissionKey(_ executable: URL) -> String {
        let resolved = executable.resolvingSymlinksInPath().standardizedFileURL
        if let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path),
           let device = attributes[.systemNumber] as? NSNumber,
           let inode = attributes[.systemFileNumber] as? NSNumber {
            return "executable:\(device):\(inode)"
        }
        return "executable-path:" + resolved.path
    }

    private static func runAdmitted(
        _ executable: URL, _ arguments: [String], environment: [String: String]?,
        directory: URL?, timeout: TimeInterval, maximumOutputBytes: Int
    ) async throws -> Result {
        let control = Control()
        let log = OperationCommandLogContext.current
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        continuation.resume(returning: try capture(executable, arguments, environment: environment,
                            directory: directory, timeout: timeout, maximumOutputBytes: maximumOutputBytes, control: control, log: log))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { control.cancel() }
    }

    static func capture(
        _ executable: URL, _ arguments: [String], environment: [String: String]? = nil,
        directory: URL? = nil, timeout: TimeInterval = 120, maximumOutputBytes: Int = 16 * 1_024 * 1_024,
        cancellation: Cancellation? = nil
    ) throws -> Result {
        try capture(executable, arguments, environment: environment, directory: directory,
                    timeout: timeout, maximumOutputBytes: maximumOutputBytes, control: cancellation?.control ?? Control(),
                    log: OperationCommandLogContext.current)
    }

    private static func capture(
        _ executable: URL, _ arguments: [String], environment: [String: String]?, directory: URL?,
        timeout: TimeInterval, maximumOutputBytes: Int, control: Control, log: OperationCommandLog?
    ) throws -> Result {
        log?.append("Command: " + executable.lastPathComponent + " " + arguments.joined(separator: " "))
        do {
            let result = try captureProcess(executable, arguments, environment: environment, directory: directory,
                timeout: timeout, maximumOutputBytes: maximumOutputBytes, control: control, log: log)
            return result
        } catch {
            log?.append("Command failed: \(error.localizedDescription)")
            throw error
        }
    }

    private static func captureProcess(
        _ executable: URL, _ arguments: [String], environment: [String: String]?, directory: URL?,
        timeout: TimeInterval, maximumOutputBytes: Int, control: Control, log: OperationCommandLog?
    ) throws -> Result {
        let process = Process(), stdout = Pipe(), stderr = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = commandEnvironment(environment ?? ProcessInfo.processInfo.environment)
        process.currentDirectoryURL = directory
        process.standardOutput = stdout
        process.standardError = stderr
        try control.start(process)
        defer { control.finish() }
        let output = Output(limit: max(1, maximumOutputBytes))
        defer {
            let result = output.result(status: process.terminationStatus)
            log?.append("Exit status: \(result.status)")
            log?.append(String(decoding: result.output.prefix(8_192), as: UTF8.self))
            if result.output.count > 8_192 { log?.append("[Command output truncated]") }
        }
        let readers = DispatchGroup()
        for (handle, isError) in [(stdout.fileHandleForReading, false), (stderr.fileHandleForReading, true)] {
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                defer { readers.leave(); try? handle.close() }
                while let chunk = try? handle.read(upToCount: 32_768), !chunk.isEmpty {
                    if !output.append(chunk, isError: isError) {
                        control.stop(.outputLimit)
                        break
                    }
                }
            }
        }
        let started = ContinuousClock.now
        while process.isRunning {
            if started.duration(to: .now) >= .seconds(max(0.01, timeout)) { control.stop(.timedOut) }
            control.enforceTermination()
            Thread.sleep(forTimeInterval: 0.01)
        }
        process.waitUntilExit()
        control.finishTermination()
        // A descendant may retain a pipe after its parent exits. Do not wait
        // indefinitely for its EOF; readability handlers are not on the main actor.
        guard readers.wait(timeout: .now() + 2) == .success else {
            control.stop(.timedOut)
            control.finishTermination()
            try? stdout.fileHandleForReading.close()
            try? stderr.fileHandleForReading.close()
            throw Failure.timedOut
        }
        // Cancellation can arrive while waiting for descendants to close pipes.
        control.finishTermination()
        if let failure = control.failure { throw failure }
        return output.result(status: process.terminationStatus)
    }

    fileprivate final class Control: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var processGroup: pid_t?
        private var reason: Failure?
        private var stoppedAt: ContinuousClock.Instant?
        var failure: Failure? { lock.withLock { reason } }

        func start(_ process: Process) throws {
            try lock.withLock {
                if let reason { throw reason }
                self.process = process
                try process.run()
                // Foundation normally creates a new group. Never signal a group
                // unless its leader is this exact child, keeping Upkeep's own
                // group and unrelated commands outside the cancellation scope.
                let pid = process.processIdentifier
                let group = getpgid(pid)
                // A very short-lived leader may already have exited. Its
                // surviving group is still addressable by the leader's PID.
                let ownsGroup = group == pid || (group == -1 && kill(-pid, 0) == 0)
                processGroup = ownsGroup && pid != getpgrp() ? pid : nil
            }
        }
        func cancel() { stop(.cancelled) }
        func stop(_ reason: Failure) {
            lock.withLock {
                guard self.reason == nil else { return }
                self.reason = reason
                stoppedAt = .now
                signal(SIGTERM)
            }
        }
        func enforceTermination() {
            lock.withLock {
                if let stoppedAt, stoppedAt.duration(to: .now) >= .milliseconds(500) {
                    signal(SIGKILL)
                }
            }
        }
        func finishTermination() {
            guard let stopped = lock.withLock({ stoppedAt }) else { return }
            // The leader can exit before its descendants. Retain the grace
            // period and enforce the group kill even after waitUntilExit.
            let remaining = Duration.milliseconds(500) - stopped.duration(to: .now)
            if remaining > .zero {
                let parts = remaining.components
                Thread.sleep(forTimeInterval: Double(parts.seconds) + Double(parts.attoseconds) / 1e18)
            }
            enforceTermination()
        }
        func finish() {
            lock.withLock {
                process = nil
                processGroup = nil
                stoppedAt = nil
            }
        }
        private func signal(_ value: Int32) {
            if let processGroup { kill(-processGroup, value) }
            else if let process, process.isRunning { kill(process.processIdentifier, value) }
        }
    }

    private final class Output: @unchecked Sendable {
        private let lock = NSLock()
        private let limit: Int
        private var stdout = Data(), stderr = Data(), combined = Data()
        init(limit: Int) { self.limit = limit }
        func append(_ chunk: Data, isError: Bool) -> Bool {
            lock.withLock {
                let remaining = limit - combined.count
                let accepted = chunk.prefix(remaining)
                if isError { stderr.append(accepted) } else { stdout.append(accepted) }
                combined.append(accepted)
                return chunk.count <= remaining
            }
        }
        func result(status: Int32) -> Result {
            lock.withLock { Result(stdout: stdout, stderr: stderr, output: combined, status: status) }
        }
    }
}
