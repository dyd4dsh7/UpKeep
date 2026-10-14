import Foundation

enum TerminalCommandFiles {
    /// An absent or invalid receipt does not prove the Terminal command stopped.
    /// Preserve its workspace so a still-running command can publish its result.
    static func removeCompletedWorkspace(_ directory: URL, statusURL: URL) throws -> Bool {
        guard status(at: statusURL) != nil else { return false }
        try FileManager.default.removeItem(at: directory)
        return true
    }

    struct Output {
        let data: Data
        let truncated: Bool

        var displayData: Data {
            truncated ? data + Data("\n[Command output truncated]\n".utf8) : data
        }
    }

    static func readOutput(at url: URL, maximumBytes: Int = 16 * 1_024 * 1_024) throws -> Output {
        let limit = min(max(1, maximumBytes), Int.max - 1)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= limit {
            guard let chunk = try handle.read(upToCount: min(32_768, limit + 1 - data.count)),
                  !chunk.isEmpty else { break }
            data.append(chunk)
        }
        return Output(data: Data(data.prefix(limit)), truncated: data.count > limit)
    }

    static func status(at url: URL) -> Int32? {
        guard let value = integer(at: url), (0...255).contains(value) else { return nil }
        return value
    }

    static func processID(at url: URL) -> Int32? {
        guard let value = integer(at: url), value > 0 else { return nil }
        return value
    }

    private static func integer(at url: URL) -> Int32? {
        guard let output = try? readOutput(at: url, maximumBytes: 64), !output.truncated,
              let text = String(data: output.data, encoding: .utf8) else { return nil }
        return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
