import Foundation
import Testing
@testable import Upkeep

@Test func publisherCacheKeysDoNotCollideAfterSanitizationOrTruncation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = PublisherResponseCache(directory: root)
    let prefix = String(repeating: "a", count: 190)
    let keys = ["github-owner/repo", "github-owner_repo", prefix + "one", prefix + "two"]
    for key in keys {
        let data = try await cache.data(for: key, maximumAge: 3600) { Data(key.utf8) }
        #expect(data == Data(key.utf8))
    }
    let reloaded = PublisherResponseCache(directory: root)
    for key in keys {
        let data = try await reloaded.data(for: key, maximumAge: 3600) { throw CacheTestError.offline }
        #expect(data == Data(key.utf8))
    }
}

@Test func expiredPublisherCacheDoesNotHideFetchFailures() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = PublisherResponseCache(directory: root)
    _ = try await cache.data(for: "releases", maximumAge: 3600) { Data("old".utf8) }
    await #expect(throws: CacheTestError.self) {
        _ = try await cache.data(for: "releases", maximumAge: -1) { throw CacheTestError.offline }
    }
}

private enum CacheTestError: Error { case offline }
