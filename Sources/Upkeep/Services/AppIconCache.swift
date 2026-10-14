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
