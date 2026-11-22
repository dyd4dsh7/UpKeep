import Foundation

struct AppStoreClient: Sendable {
    /// iTunes lookup accepts a comma-separated `bundleId` list. Keep URLs short
    /// and the blast radius of a failed request small.
    static let lookupBatchSize = 50

    func update(for app: InstalledApp) async throws -> AvailableUpdate? {
        guard app.updateManagement == .appStore, let bundleID = app.bundleIdentifier else { return nil }
        do {
            let results = try await lookup(bundleIDs: [bundleID])
            return Self.update(for: app, lookupResult: results[Self.lookupKey(bundleID)])
        } catch { throw UpdateSourceError(error) }
    }

    /// Batched equivalent of `update(for:)`, keyed by `InstalledApp.id`. Apps
    /// that are not App Store managed map to `.success(nil)`; a failed lookup
    /// request fails every app in that batch.
    func updates(for apps: [InstalledApp]) async -> [String: Swift.Result<AvailableUpdate?, any Error>] {
        var outcomes: [String: Swift.Result<AvailableUpdate?, any Error>] = [:]
        var eligible: [(app: InstalledApp, bundleID: String)] = []
        for app in apps {
            if app.updateManagement == .appStore, let bundleID = app.bundleIdentifier {
                eligible.append((app, bundleID))
            } else {
                outcomes[app.id] = .success(nil)
            }
        }
        let chunks = stride(from: 0, to: eligible.count, by: Self.lookupBatchSize).map {
            Array(eligible[$0..<min($0 + Self.lookupBatchSize, eligible.count)])
        }
        await withTaskGroup(of: [(String, Swift.Result<AvailableUpdate?, any Error>)].self) { group in
            for chunk in chunks {
                group.addTask {
                    let bundleIDs = Array(Set(chunk.map(\.bundleID))).sorted()
                    do {
                        let results = try await lookup(bundleIDs: bundleIDs)
                        return chunk.map { entry in
                            (entry.app.id, .success(Self.update(for: entry.app, lookupResult: results[Self.lookupKey(entry.bundleID)])))
                        }
                    } catch {
                        let failure = UpdateSourceError(error)
                        return chunk.map { ($0.app.id, .failure(failure)) }
                    }
                }
            }
            for await chunkOutcomes in group {
                for (id, outcome) in chunkOutcomes { outcomes[id] = outcome }
            }
        }
        return outcomes
    }

    /// Single place that turns an iTunes lookup result (or its absence) into
    /// an update for one installed app. `nil` means the bundle ID was not in
    /// the lookup response.
    static func update(for app: InstalledApp, lookupResult result: LookupResult?) -> AvailableUpdate? {
        guard let result, VersionComparator.isNewer(result.version, than: app.installedVersion) else { return nil }
        return AvailableUpdate(
            app: app,
            availableVersion: result.version,
            source: .appStore,
            releaseNotes: result.releaseNotes,
            actionURL: result.trackViewUrl.flatMap(URL.init(string:)),
            homebrewToken: nil
        )
    }

    static func lookupKey(_ bundleID: String) -> String { bundleID.lowercased() }

    /// The iTunes lookup defaults to the US storefront; apps sold only in other
    /// regions are missing there.
    static var storefrontCountry: String? {
        Locale.current.region?.identifier.lowercased()
    }

    /// Looks up bundle IDs and returns results keyed by `lookupKey(bundleId)`.
    /// A bundle ID missing from the response is absent from the dictionary.
    func lookup(bundleIDs: [String]) async throws -> [String: LookupResult] {
        guard !bundleIDs.isEmpty else { return [:] }
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleIDs.joined(separator: ",")),
            URLQueryItem(name: "entity", value: "macSoftware")
        ] + (Self.storefrontCountry.map { [URLQueryItem(name: "country", value: $0)] } ?? [])
        guard let url = components?.url else { return [:] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Upkeep/1.0", forHTTPHeaderField: "User-Agent")
        let (data, http) = try await PublisherHTTPClient.data(for: request)
        guard 200..<300 ~= http.statusCode else { throw UpdateSourceError.httpStatus(http.statusCode) }
        return try Self.decodeLookup(data, requestedBundleIDs: bundleIDs)
    }

    static func decodeLookup(_ data: Data, requestedBundleIDs: [String]) throws -> [String: LookupResult] {
        let lookup: LookupResponse
        do { lookup = try JSONDecoder().decode(LookupResponse.self, from: data) }
        catch { throw UpdateSourceError.malformedData(error.localizedDescription) }
        // A single-ID lookup historically used the first result regardless of
        // the echoed bundle ID; keep that behaviour.
        if requestedBundleIDs.count == 1 {
            return lookup.results.first.map { [lookupKey(requestedBundleIDs[0]): $0] } ?? [:]
        }
        var results: [String: LookupResult] = [:]
        for result in lookup.results {
            guard let bundleID = result.bundleId else { continue }
            let key = lookupKey(bundleID)
            if results[key] == nil { results[key] = result }
        }
        return results
    }

    private struct LookupResponse: Decodable {
        let results: [LookupResult]
    }

    struct LookupResult: Decodable, Sendable {
        let bundleId: String?
        let version: String
        let releaseNotes: String?
        let trackViewUrl: String?
    }
}
