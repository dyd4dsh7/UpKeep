import Foundation

/// One scan owns its feed and query cache. Nothing is persisted between scans.
actor CVEInventoryClient {
    private let developer: CVEClient
    private let nvd: NVDCVEClient
    private let transport: CVEClient.Transport
    private var homebrew: Result<HomebrewAdvisoryIndex, Error>?
    private var products: [CVEProduct: Result<[CVEAdvisory], Error>] = [:]

    init(developer: CVEClient = CVEClient(), nvd: NVDCVEClient = NVDCVEClient(),
         transport: @escaping CVEClient.Transport = CVEClient.networkTransport) {
        self.developer = developer; self.nvd = nvd; self.transport = transport
    }

    func check(_ item: CVEInventoryItem) async throws -> CVEInventoryResult {
        guard let target = item.target else { return .init(item: item, advisories: [], failure: nil) }
        do {
            try Task.checkCancellation()
            let advisories: [CVEAdvisory]
            switch target {
            case let .developer(package): advisories = try await developer.check(package).advisories
            case let .formula(name, version):
                if homebrew == nil {
                    do {
                        var request = URLRequest(url: URL(string: "https://formulae.brew.sh/api/advisories.json")!)
                        request.timeoutInterval = 90
                        request.cachePolicy = .reloadIgnoringLocalCacheData
                        let (data, response) = try await transport(request)
                        guard response.statusCode == 200 else { throw HomebrewAdvisoryError.http(response.statusCode) }
                        homebrew = .success(try JSONDecoder().decode(HomebrewAdvisoryIndex.self, from: data))
                    } catch {
                        try Task.checkCancellation()
                        homebrew = .failure(error)
                    }
                }
                guard let homebrew else { throw URLError(.badServerResponse) }
                advisories = try homebrew.get().check(name: name, version: version)
            case let .nvd(product):
                if let cached = products[product] { advisories = try cached.get() }
                else {
                    do {
                        advisories = try await nvd.check(product)
                        products[product] = .success(advisories)
                    } catch {
                        try Task.checkCancellation()
                        products[product] = .failure(error)
                        throw error
                    }
                }
            }
            try Task.checkCancellation()
            return .init(item: item, advisories: advisories, failure: nil)
        } catch {
            try Task.checkCancellation()
            return .init(item: item, advisories: [], failure: error.localizedDescription)
        }
    }
}
