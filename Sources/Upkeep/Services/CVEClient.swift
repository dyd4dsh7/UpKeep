import Foundation

/// Queries registry identities only; never sends executable paths or installation contexts.
struct CVEClient: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let transport: Transport

    static let networkTransport: Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, response)
    }

    init(transport: @escaping Transport = Self.networkTransport) {
        self.transport = transport
    }

    func check(_ package: DeveloperPackage) async throws -> CVEPackageResult {
        guard let query = CVEPackageQuery(package) else {
            return CVEPackageResult(package: package, advisories: [], failure: nil, supported: false)
        }
        var advisories: [String: CVEAdvisory] = [:]
        var pageToken: String?
        var seenTokens: Set<String> = []
        repeat {
            try Task.checkCancellation()
            var request = URLRequest(url: URL(string: "https://api.osv.dev/v1/query")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONEncoder().encode(QueryRequest(
                package: .init(name: query.name, ecosystem: query.ecosystem),
                version: query.version, page_token: pageToken
            ))
            let (data, response) = try await transport(request)
            guard response.statusCode == 200 else { throw CVEError.http(response.statusCode) }
            let page = try JSONDecoder().decode(QueryResponse.self, from: data)
            for advisory in page.vulns ?? [] where advisory.withdrawn == nil {
                advisories[advisory.id] = advisory.scoped(to: query)
            }
            pageToken = page.next_page_token.flatMap { $0.isEmpty ? nil : $0 }
            if let pageToken {
                guard seenTokens.insert(pageToken).inserted, seenTokens.count <= 100 else {
                    throw CVEError.pagination
                }
            }
        } while pageToken != nil
        return CVEPackageResult(package: package, advisories: advisories.values.sorted { $0.id < $1.id },
                                failure: nil, supported: true)
    }

    private struct QueryRequest: Encodable {
        struct Package: Encodable { let name: String; let ecosystem: String }
        let package: Package
        let version: String
        let page_token: String?
    }
    private struct QueryResponse: Decodable {
        let vulns: [CVEAdvisory]?
        let next_page_token: String?
    }
    private enum CVEError: LocalizedError {
        case invalidResponse, http(Int), pagination
        var errorDescription: String? {
            switch self {
            case .invalidResponse: "OSV returned an invalid response."
            case let .http(status): "OSV returned HTTP \(status). Retry the check later."
            case .pagination: "OSV results could not be fully retrieved."
            }
        }
    }
}
