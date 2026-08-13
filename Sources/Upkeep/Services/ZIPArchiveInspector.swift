import Foundation

enum ZIPArchiveInspector {
    static let maximumEntryCount = 10_000
    static let maximumExpandedBytes: UInt64 = 4 * 1_024 * 1_024 * 1_024
    static let maximumEntryBytes: UInt64 = 2 * 1_024 * 1_024 * 1_024
    static let maximumCompressionRatio: UInt64 = 200
    private static let maximumDirectoryBytes = 32 * 1_024 * 1_024

    static func validate(_ url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        guard fileSize >= 22 else { throw ArchiveError.invalidDirectory }

        let tailSize = Int(min(fileSize, 65_557))
        try handle.seek(toOffset: fileSize - UInt64(tailSize))
        let tail = try handle.read(upToCount: tailSize) ?? Data()
        guard let eocd = lastSignature([0x50, 0x4b, 0x05, 0x06], in: tail),
              eocd + 22 <= tail.count else { throw ArchiveError.invalidDirectory }

        let entryCount = Int(tail.uint16LE(at: eocd + 10))
        let directorySize = UInt64(tail.uint32LE(at: eocd + 12))
        let directoryOffset = UInt64(tail.uint32LE(at: eocd + 16))
        guard entryCount != 0xffff, directorySize != UInt64(UInt32.max),
              directoryOffset != UInt64(UInt32.max),
              entryCount <= maximumEntryCount,
              directorySize <= UInt64(maximumDirectoryBytes),
              directoryOffset <= fileSize,
              directorySize <= fileSize - directoryOffset
        else { throw ArchiveError.safetyLimitExceeded }

        try handle.seek(toOffset: directoryOffset)
        let directory = try handle.read(upToCount: Int(directorySize)) ?? Data()
        guard directory.count == Int(directorySize) else { throw ArchiveError.invalidDirectory }

        var cursor = 0
        var expanded: UInt64 = 0
        for _ in 0..<entryCount {
            guard cursor + 46 <= directory.count,
                  directory[cursor..<cursor + 4].elementsEqual([0x50, 0x4b, 0x01, 0x02])
            else { throw ArchiveError.invalidDirectory }
            let flags = directory.uint16LE(at: cursor + 8)
            let compressed = UInt64(directory.uint32LE(at: cursor + 20))
            let uncompressed = UInt64(directory.uint32LE(at: cursor + 24))
            let nameLength = Int(directory.uint16LE(at: cursor + 28))
            let extraLength = Int(directory.uint16LE(at: cursor + 30))
            let commentLength = Int(directory.uint16LE(at: cursor + 32))
            let localOffset = UInt64(directory.uint32LE(at: cursor + 42))
            let recordLength = 46 + nameLength + extraLength + commentLength
            guard nameLength > 0, cursor + recordLength <= directory.count,
                  let name = String(data: directory[cursor + 46..<cursor + 46 + nameLength], encoding: .utf8),
                  safeRelativePath(name), flags & 0x1 == 0,
                  uncompressed <= maximumEntryBytes,
                  expanded <= maximumExpandedBytes - uncompressed,
                  compressionIsReasonable(compressed: compressed, uncompressed: uncompressed)
            else { throw ArchiveError.safetyLimitExceeded }
            try validateLocalEntry(
                handle: handle,
                fileSize: fileSize,
                directoryOffset: directoryOffset,
                offset: localOffset,
                expectedName: name,
                compressedBytes: compressed
            )
            expanded += uncompressed
            cursor += recordLength
        }
        guard cursor == directory.count else { throw ArchiveError.invalidDirectory }
    }

    private static func validateLocalEntry(
        handle: FileHandle,
        fileSize: UInt64,
        directoryOffset: UInt64,
        offset: UInt64,
        expectedName: String,
        compressedBytes: UInt64
    ) throws {
        guard offset <= fileSize, 30 <= fileSize - offset else { throw ArchiveError.invalidDirectory }
        try handle.seek(toOffset: offset)
        let header = try handle.read(upToCount: 30) ?? Data()
        guard header.count == 30,
              header[0..<4].elementsEqual([0x50, 0x4b, 0x03, 0x04])
        else { throw ArchiveError.invalidDirectory }
        let nameLength = Int(header.uint16LE(at: 26))
        let extraLength = UInt64(header.uint16LE(at: 28))
        guard nameLength > 0,
              UInt64(nameLength) <= fileSize - offset - 30 else { throw ArchiveError.invalidDirectory }
        let nameData = try handle.read(upToCount: nameLength) ?? Data()
        let payloadOffset = offset + 30 + UInt64(nameLength) + extraLength
        guard String(data: nameData, encoding: .utf8) == expectedName,
              payloadOffset <= directoryOffset,
              compressedBytes <= directoryOffset - payloadOffset
        else { throw ArchiveError.invalidDirectory }
    }

    private static func compressionIsReasonable(compressed: UInt64, uncompressed: UInt64) -> Bool {
        guard uncompressed > 0 else { return true }
        guard compressed > 0 else { return false }
        return uncompressed / compressed <= maximumCompressionRatio
    }

    private static func safeRelativePath(_ path: String) -> Bool {
        guard !path.hasPrefix("/"), !path.hasPrefix("\\"), !path.contains("\\"),
              !path.unicodeScalars.contains(where: { $0.value == 0 }) else { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }

    private static func lastSignature(_ signature: [UInt8], in data: Data) -> Int? {
        guard data.count >= signature.count else { return nil }
        for offset in stride(from: data.count - signature.count, through: 0, by: -1)
        where data[offset..<offset + signature.count].elementsEqual(signature) {
            return offset
        }
        return nil
    }

    enum ArchiveError: LocalizedError {
        case invalidDirectory
        case safetyLimitExceeded

        var errorDescription: String? {
            switch self {
            case .invalidDirectory: "The ZIP archive directory is malformed."
            case .safetyLimitExceeded: "The ZIP archive exceeds Upkeep’s extraction safety limits."
            }
        }
    }
}

private extension Data {
    func uint16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func uint32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset]) | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16 | UInt32(self[offset + 3]) << 24
    }
}
