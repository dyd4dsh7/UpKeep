import Foundation

struct AppStoreClient: Sendable {
    func update(for app: InstalledApp) async throws -> AvailableUpdate? {
        guard app.updateManagement == .appStore, let bundleID = app.bundleIdentifier else { return nil }
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleID),
            URLQueryItem(name: "entity", value: "macSoftware")
        ]
        guard let url = components?.url else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("Upkeep/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw UpdateSourceError.invalidResponse }
            guard 200..<300 ~= http.statusCode else { throw UpdateSourceError.httpStatus(http.statusCode) }
            let lookup: LookupResponse
            do { lookup = try JSONDecoder().decode(LookupResponse.self, from: data) }
            catch { throw UpdateSourceError.malformedData(error.localizedDescription) }
            guard let result = lookup.results.first,
                  VersionComparator.isNewer(result.version, than: app.installedVersion)
            else { return nil }

            return AvailableUpdate(
                app: app,
                availableVersion: result.version,
                source: .appStore,
                releaseNotes: result.releaseNotes,
                actionURL: result.trackViewUrl.flatMap(URL.init(string:)),
                homebrewToken: nil
            )
        } catch { throw UpdateSourceError(error) }
    }

    private struct LookupResponse: Decodable {
        let results: [Result]
    }

    private struct Result: Decodable {
        let version: String
        let releaseNotes: String?
        let trackViewUrl: String?
    }
}
