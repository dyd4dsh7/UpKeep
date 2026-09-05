import CryptoKit
import Foundation

actor PublisherResponseCache {
    static let shared = PublisherResponseCache()

    private var inFlight: [String: Task<Data, Error>] = [:]
    private let directory: URL?

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Upkeep/PublisherResponses", isDirectory: true)
    }

    func data(
        for key: String,
        maximumAge: TimeInterval,
        fetch: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        if let cached = cachedData(for: key, maximumAge: maximumAge) {
            return cached
        }
        if let task = inFlight[key] {
            return try await task.value
        }

        let task = Task<Data, Error> {
            let data = try await fetch()
            self.store(data, for: key)
            return data
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }

    private func cachedData(for key: String, maximumAge: TimeInterval) -> Data? {
        guard let url = cacheURL(for: key),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modifiedAt = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? NSNumber,
              size.intValue <= PublisherHTTPClient.metadataLimit,
              Date().timeIntervalSince(modifiedAt) <= maximumAge
        else { return nil }
        return try? Data(contentsOf: url)
    }

    private func store(_ data: Data, for key: String) {
        guard data.count <= PublisherHTTPClient.metadataLimit,
              let url = cacheURL(for: key) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            // Cache writes are an optimization; request failures still reach the scanner.
        }
    }

    private func cacheURL(for key: String) -> URL? {
        let filename = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }.joined() + ".json"
        return directory?.appendingPathComponent(filename)
    }
}
