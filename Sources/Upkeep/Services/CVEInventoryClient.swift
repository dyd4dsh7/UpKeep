import Foundation

/// One scan owns its feed and query cache. Nothing is persisted between scans.
actor CVEInventoryClient {
    private let developer: CVEClient
    private let nvd: NVDCVEClient
    private let transport: CVEClient.Transport
    /// Loads the large Homebrew advisory feed; the live client downloads it to
    /// a file and memory-maps it instead of holding 79 MB in memory.
    private let feedTransport: CVEClient.Transport
    private var homebrew: Result<HomebrewAdvisoryIndex, Error>?
    private var formulaNames: Set<String>?
    /// The formulae a partial feed decode covers; nil after a full decode.
    private var decodedFormulae: Set<String>?
    private var products: [CVEProduct: Result<[CVEAdvisory], Error>] = [:]

    init(developer: CVEClient = CVEClient(), nvd: NVDCVEClient = NVDCVEClient(),
         transport: CVEClient.Transport? = nil) {
        self.developer = developer; self.nvd = nvd
        self.transport = transport ?? CVEClient.networkTransport
        self.feedTransport = transport ?? CVEClient.mappedDownloadTransport
    }

    /// Names every formula this client will check, so the Homebrew advisory
    /// feed decodes only those entries instead of the whole feed.
    func prepare(formulaNames names: Set<String>) {
        guard homebrew == nil else { return }
        formulaNames = names
    }

    func check(_ item: CVEInventoryItem) async throws -> CVEInventoryResult {
        guard let target = item.target else { return .init(item: item, advisories: [], failure: nil) }
        do {
            try Task.checkCancellation()
            let advisories: [CVEAdvisory]
            switch target {
            case let .developer(package): advisories = try await developer.check(package).advisories
            case let .formula(name, version):
                // A partial feed only covers the prepared formulae; anything
                // else reloads and decodes the full feed rather than missing data.
                if let decoded = decodedFormulae, !decoded.contains(name) {
                    homebrew = nil
                    formulaNames = nil
                }
                if homebrew == nil {
                    do {
                        var request = URLRequest(url: URL(string: "https://formulae.brew.sh/api/advisories.json")!)
                        request.timeoutInterval = 90
                        request.cachePolicy = .reloadIgnoringLocalCacheData
                        let (data, response) = try await feedTransport(request)
                        guard response.statusCode == 200 else { throw HomebrewAdvisoryError.http(response.statusCode) }
                        // Read only the prepared formulae; anything else, or an
                        // unexpected feed shape, falls back to the full decode.
                        if let names = formulaNames, names.contains(name),
                           let records = HomebrewAdvisoryFeedScanner.records(in: data, formulae: names) {
                            decodedFormulae = names
                            homebrew = .success(HomebrewAdvisoryIndex(advisories: records))
                        } else {
                            decodedFormulae = nil
                            homebrew = .success(try JSONDecoder().decode(HomebrewAdvisoryIndex.self, from: data))
                        }
                        // The rest of a CVE check can take minutes (NVD is paced);
                        // return the feed's temporary memory now, not at the end.
                        MemoryRelief.scheduleRelease(after: 1)
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
