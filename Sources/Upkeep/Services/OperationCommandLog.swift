import Foundation

enum OperationCommandLogContext {
    @TaskLocal static var current: OperationCommandLog?
}

final class OperationCommandLog: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""
    private let limit = 32_768
    private var truncated = false

    func append(_ message: String) {
        let flags = message.replacingOccurrences(
            of: #"(?i)(--(?:password|secret|token|api-key|access-token|authorization|signature)(?:=|\s+))\S+"#,
            with: "$1<redacted>", options: .regularExpression)
        let safe = DiagnosticRedactor.redact(flags)
        lock.lock()
        defer { lock.unlock() }
        let remaining = max(0, limit - 32 - value.count)
        if flags.count > 2_000 || safe.count + 1 > remaining { truncated = true }
        value += String((safe + "\n").prefix(remaining))
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return value + (truncated ? "\n[Log output truncated]\n" : "")
    }

    func appendTerminalOutput(outputURL: URL, statusURL: URL) {
        let status = TerminalCommandFiles.status(at: statusURL).map(String.init)
        append("Terminal exit status: \(status ?? "not reported")")
        guard let output = try? TerminalCommandFiles.readOutput(at: outputURL, maximumBytes: 8_192) else {
            append("Terminal output unavailable")
            return
        }
        append(String(decoding: output.displayData, as: UTF8.self))
    }
}
