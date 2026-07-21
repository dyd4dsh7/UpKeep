import Foundation

struct AppStoreClient: Sendable {
    func update(for app: InstalledApp) async -> AvailableUpdate? {
        guard app.hasAppStoreReceipt, let bundleID = app.bundleIdentifier else { return nil }
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleID),
            URLQueryItem(name: "entity", value: "macSoftware")
        ]
        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return nil }
            let lookup = try JSONDecoder().decode(LookupResponse.self, from: data)
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
        } catch {
            return nil
        }
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
