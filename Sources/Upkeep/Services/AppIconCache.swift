import AppKit
import Foundation

struct AppIconIdentity: Hashable {
    let path: String
    let modifiedAt: Date?

    init(url: URL) {
        path = url.standardizedFileURL.path
        // URL resource values can retain a previously read modification date.
        modifiedAt = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}

@MainActor
final class AppIconCache {
    static let shared = AppIconCache()
    private let cache = NSCache<NSString, NSImage>()
    private let loader: (String) -> NSImage

    init(limit: Int = 256, loader: @escaping (String) -> NSImage = { NSWorkspace.shared.icon(forFile: $0) }) {
        cache.countLimit = max(1, limit)
        self.loader = loader
    }

    func image(for identity: AppIconIdentity) -> NSImage {
        let key = "\(identity.path)|\(identity.modifiedAt?.timeIntervalSince1970.description ?? "missing")" as NSString
        if let image = cache.object(forKey: key) { return image }
        let image = loader(identity.path)
        cache.setObject(image, forKey: key)
        return image
    }
}

/// Memoizes `AppIconIdentity(url:)` (a file stat) so list rows do not stat
/// their bundle on every body evaluation. A path is re-stat'ed after
/// `maximumAge`, so a replaced bundle still gets its new icon.
@MainActor
final class AppIconIdentityCache {
    static let shared = AppIconIdentityCache()
    private var entries: [String: (identity: AppIconIdentity, checkedAt: ContinuousClock.Instant)] = [:]
    private let maximumAge: Duration
    private let limit: Int
    private let resolve: (URL) -> AppIconIdentity

    init(maximumAge: Duration = .seconds(5), limit: Int = 2_048,
         resolve: @escaping (URL) -> AppIconIdentity = AppIconIdentity.init(url:)) {
        self.maximumAge = maximumAge
        self.limit = max(1, limit)
        self.resolve = resolve
    }

    func identity(for url: URL, now: ContinuousClock.Instant = .now) -> AppIconIdentity {
        let key = url.path
        if let entry = entries[key], entry.checkedAt.duration(to: now) < maximumAge { return entry.identity }
        let identity = resolve(url)
        if entries.count >= limit { entries.removeAll(keepingCapacity: true) }
        entries[key] = (identity, now)
        return identity
    }
}
