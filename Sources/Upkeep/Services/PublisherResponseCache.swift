import Foundation

actor PublisherResponseCache {
    static let shared = PublisherResponseCache()

    private var inFlight: [String: Task<Data, Error>] = [:]

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

        let stale = cachedData(for: key, maximumAge: .infinity)
        let task = Task<Data, Error> {
            do {
                let data = try await fetch()
                self.store(data, for: key)
                return data
            } catch {
                if let stale { return stale }
                throw error
            }
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }

    private func cachedData(for key: String, maximumAge: TimeInterval) -> Data? {
        guard let url = cacheURL(for: key),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modifiedAt = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modifiedAt) <= maximumAge
        else { return nil }
        return try? Data(contentsOf: url)
    }

    private func store(_ data: Data, for key: String) {
        guard let url = cacheURL(for: key) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            // Cached publisher data is an optimization and stale-data fallback.
        }
    }

    private func cacheURL(for key: String) -> URL? {
        let safeKey = key.map { character in
            character.isLetter || character.isNumber || "-._".contains(character)
                ? character
                : "_"
        }
        let filename = String(safeKey.prefix(180)) + ".json"
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Upkeep/PublisherResponses", isDirectory: true)
            .appendingPathComponent(filename)
    }
}
