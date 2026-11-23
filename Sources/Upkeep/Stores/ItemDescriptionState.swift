import Foundation
import Observation

/// One-line "what is this" descriptions for apps, packages and models. Lists
/// ask for the items they show; results fill in as lookups finish and are kept
/// on disk so later launches show them straight away.
@MainActor
@Observable
final class ItemDescriptionState {
    private(set) var texts: [String: String] = [:]
    @ObservationIgnored private var cache: ItemDescriptionCache?
    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private let describer: any ItemDescribing
    @ObservationIgnored private let cacheURL: URL?
    @ObservationIgnored private let now: @Sendable () -> Date

    /// Results are applied in chunks so a long list fills in progressively.
    static let chunkSize = 24
    /// Entries unused for this long are dropped from the cache file.
    static let pruneAge: TimeInterval = 90 * 24 * 60 * 60

    init(describer: any ItemDescribing, cacheURL: URL?, now: @escaping @Sendable () -> Date = { Date() }) {
        self.describer = describer
        self.cacheURL = cacheURL
        self.now = now
    }

    func text(for key: String?) -> String? {
        guard let key else { return nil }
        loadCacheIfNeeded()
        return texts[key]
    }

    func load(_ requests: [ItemDescriptionRequest]) async {
        loadCacheIfNeeded()
        let date = now()
        var seen = Set<String>()
        let pending = requests.filter { request in
            let key = request.key
            return seen.insert(key).inserted && !inFlight.contains(key) && cache?.isFresh(key, now: date) != true
        }
        guard !pending.isEmpty else { return }
        let keys = Set(pending.map(\.key))
        inFlight.formUnion(keys)
        defer { inFlight.subtract(keys) }

        var changed = false
        for start in stride(from: 0, to: pending.count, by: Self.chunkSize) {
            guard !Task.isCancelled else { break }
            let chunk = Array(pending[start..<min(start + Self.chunkSize, pending.count)])
            let results = await describer.describe(chunk)
            guard !results.isEmpty else { continue }
            changed = true
            apply(results, checkedAt: now())
        }
        if changed { saveCache() }
    }

    private func apply(_ results: [String: ItemDescriptionLookup], checkedAt: Date) {
        var cache = cache ?? ItemDescriptionCache()
        var updated = texts
        for (key, lookup) in results {
            switch lookup {
            case let .found(text):
                cache.entries[key] = .init(text: text, checkedAt: checkedAt)
                updated[key] = text
            case .notFound:
                cache.entries[key] = .init(text: nil, checkedAt: checkedAt)
                updated[key] = nil
            }
        }
        self.cache = cache
        if updated != texts { texts = updated }
    }

    private func loadCacheIfNeeded() {
        guard cache == nil else { return }
        let loaded = ItemDescriptionCache.load(from: cacheURL)
        cache = loaded
        // Stale descriptions still show while they are checked again.
        let stored = loaded.entries.compactMapValues(\.text)
        if !stored.isEmpty { texts = stored }
    }

    private func saveCache() {
        guard var cache else { return }
        let cutoff = now().addingTimeInterval(-Self.pruneAge)
        cache.entries = cache.entries.filter { $0.value.checkedAt > cutoff }
        let url = cacheURL
        Task.detached(priority: .utility) { cache.save(to: url) }
    }
}

@MainActor
extension UpkeepStore {
    func itemDescription(for package: DeveloperPackage) -> String? {
        ItemDescriptions.builtIn(for: package)
            ?? descriptions.text(for: ItemDescriptions.request(for: package)?.key)
    }

    func itemDescription(for package: HomebrewPackage) -> String? {
        ItemDescriptions.clean(package.description, name: package.displayName)
    }

    func itemDescription(for app: InstalledApp) -> String? {
        if let cask = uninstallingCask(for: app), let text = itemDescription(for: cask) { return text }
        return ItemDescriptions.builtIn(for: app)
            ?? descriptions.text(for: ItemDescriptions.request(for: app)?.key)
    }

    func itemDescription(for model: LocalLLMModel) -> String? {
        if let text = ItemDescriptions.builtIn(for: model) { return text }
        guard let request = ItemDescriptions.request(for: model) else {
            return ItemDescriptions.modelFamilyDescription(for: model.name)
        }
        return descriptions.text(for: request.key)
    }

    func loadDescriptions(for packages: [DeveloperPackage]) async {
        await descriptions.load(packages.compactMap(ItemDescriptions.request(for:)))
    }

    func loadDescriptions(for apps: [InstalledApp]) async {
        await descriptions.load(apps.compactMap { app in
            uninstallingCask(for: app)?.description == nil ? ItemDescriptions.request(for: app) : nil
        })
    }

    func loadDescriptions(for models: [LocalLLMModel]) async {
        await descriptions.load(models.compactMap(ItemDescriptions.request(for:)))
    }
}
