import Foundation

/// Shared pacing reserves a request slot before suspending, including across windows.
actor NVDRequestPacer {
    static let shared = NVDRequestPacer()
    private var nextSlot = ContinuousClock.now
    func wait() async throws {
        try Task.checkCancellation()
        let slot = max(nextSlot, .now)
        nextSlot = slot.advanced(by: .milliseconds(6_100))
        try await Task.sleep(until: slot, clock: .continuous)
    }
}

struct NVDCVEClient: Sendable {
    private let transport: CVEClient.Transport
    private let pace: @Sendable () async throws -> Void
    init(transport: @escaping CVEClient.Transport = CVEClient.networkTransport,
         pace: @escaping @Sendable () async throws -> Void = { try await NVDRequestPacer.shared.wait() }) {
        self.transport = transport; self.pace = pace
    }

    func check(_ product: CVEProduct) async throws -> [CVEAdvisory] {
        var start = 0
        var advisories: [String: CVEAdvisory] = [:]
        while true {
            try Task.checkCancellation()
            try await pace()
            var components = URLComponents(string: "https://services.nvd.nist.gov/rest/json/cves/2.0")!
            components.queryItems = [URLQueryItem(name: "cpeName", value: product.cpeName),
                URLQueryItem(name: "isVulnerable", value: nil), URLQueryItem(name: "noRejected", value: nil),
                URLQueryItem(name: "resultsPerPage", value: "2000"), URLQueryItem(name: "startIndex", value: String(start))]
            var request = URLRequest(url: components.url!)
            request.timeoutInterval = 45
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await transport(request)
            guard response.statusCode == 200 else { throw NVDCheckError.http(response.statusCode) }
            let page = try JSONDecoder().decode(Page.self, from: data)
            guard page.startIndex == start, page.totalResults >= 0, page.resultsPerPage >= 0,
                  page.vulnerabilities.count <= page.resultsPerPage,
                  start + page.vulnerabilities.count <= page.totalResults else { throw NVDCheckError.pagination }
            for entry in page.vulnerabilities where entry.cve.vulnStatus != "Rejected" {
                let cve = entry.cve
                advisories[cve.id] = CVEAdvisory(id: cve.id,
                    summary: cve.descriptions.first { $0.lang == "en" }?.value,
                    sourceURL: URL(string: "https://nvd.nist.gov/vuln/detail/")!.appendingPathComponent(cve.id), sourceRatings: cve.metrics?.ratings)
            }
            let next = start + page.vulnerabilities.count
            if next >= page.totalResults { break }
            guard next > start, next < 100_000 else { throw NVDCheckError.pagination }
            start = next
        }
        return advisories.values.sorted { $0.id < $1.id }
    }

    private struct Page: Decodable {
        let startIndex: Int; let totalResults: Int; let resultsPerPage: Int
        let vulnerabilities: [Entry]
        struct Entry: Decodable {
            let cve: CVE
            struct CVE: Decodable {
                let id: String; let vulnStatus: String?; let descriptions: [Description]
                let metrics: Metrics?
                struct Metrics: Decodable {
                    let cvssMetricV40: [Metric]?
                    let cvssMetricV31: [Metric]?
                    let cvssMetricV30: [Metric]?
                    let cvssMetricV2: [Metric]?
                    struct Metric: Decodable {
                        let cvssData: Data
                        let baseSeverity: String?
                        struct Data: Decodable {
                            let baseScore: Double?
                            let baseSeverity: String?
                        }
                    }
                    var ratings: [CVESeverityRating] {
                        // Prefer the newest published CVSS generation; keep all providers within it.
                        for (entries, method) in [(cvssMetricV40, "CVSS 4.0"), (cvssMetricV31, "CVSS 3.1"),
                                                  (cvssMetricV30, "CVSS 3.0"), (cvssMetricV2, "CVSS 2.0")] {
                            let ratings = (entries ?? []).map {
                                CVESeverityRating(score: $0.cvssData.baseScore,
                                                  label: $0.cvssData.baseSeverity ?? $0.baseSeverity, method: method)
                            }.filter { $0.level != .unknown }
                            if !ratings.isEmpty { return ratings }
                        }
                        return []
                    }
                }
                struct Description: Decodable { let lang: String; let value: String }
            }
        }
    }
    private enum NVDCheckError: LocalizedError {
        case http(Int), pagination
        var errorDescription: String? {
            switch self {
            case let .http(status): "NVD returned HTTP \(status). It may be unavailable or rate limited; retry later."
            case .pagination: "NVD results could not be fully retrieved."
            }
        }
    }
}
