import Darwin
import Foundation

enum PublisherHTTPClient {
    static let metadataLimit = 64 * 1_024 * 1_024
    static let archiveLimit: Int64 = 1_024 * 1_024 * 1_024

    static func data(for request: URLRequest, maximumBytes: Int = metadataLimit) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw HTTPError.invalidDestination }
        try PublisherURLPolicy.validate(url)
        let loader = BoundedDataLoader(maximumBytes: maximumBytes)
        return try await loader.load(request)
    }

    static func download(for request: URLRequest, maximumBytes: Int64 = archiveLimit) async throws -> (URL, HTTPURLResponse) {
        guard let url = request.url else { throw HTTPError.invalidDestination }
        try PublisherURLPolicy.validate(url)
        let loader = BoundedDownloadLoader(maximumBytes: maximumBytes)
        return try await loader.load(request)
    }

    enum HTTPError: LocalizedError {
        case invalidDestination
        case nonPublicDestination
        case responseTooLarge
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidDestination: "The publisher URL is not a valid HTTPS destination."
            case .nonPublicDestination: "The publisher URL resolves to a local or private network destination."
            case .responseTooLarge: "The publisher response exceeded Upkeep’s safety limit."
            case .invalidResponse: "The publisher returned an invalid response."
            }
        }
    }
}

enum PublisherURLPolicy {
    static func validate(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              let host = url.host, !host.isEmpty
        else { throw PublisherHTTPClient.HTTPError.invalidDestination }

        let normalized = host.lowercased()
        guard normalized != "localhost", !normalized.hasSuffix(".localhost"),
              !normalized.hasSuffix(".local")
        else { throw PublisherHTTPClient.HTTPError.nonPublicDestination }

        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let result else {
            throw PublisherHTTPClient.HTTPError.invalidDestination
        }
        defer { freeaddrinfo(result) }

        var current: UnsafeMutablePointer<addrinfo>? = result
        var foundAddress = false
        while let address = current {
            foundAddress = true
            guard isPublic(address.pointee.ai_addr) else {
                throw PublisherHTTPClient.HTTPError.nonPublicDestination
            }
            current = address.pointee.ai_next
        }
        guard foundAddress else { throw PublisherHTTPClient.HTTPError.invalidDestination }
    }

    private static func isPublic(_ address: UnsafeMutablePointer<sockaddr>?) -> Bool {
        guard let address else { return false }
        if address.pointee.sa_family == sa_family_t(AF_INET) {
            let value = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            let first = UInt8((value >> 24) & 0xff)
            let second = UInt8((value >> 16) & 0xff)
            return first != 0 && first != 10 && first != 127
                && !(first == 100 && (64...127).contains(second))
                && !(first == 169 && second == 254)
                && !(first == 172 && (16...31).contains(second))
                && !(first == 192 && second == 168)
                && !(first >= 224)
        }
        if address.pointee.sa_family == sa_family_t(AF_INET6) {
            let bytes = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                withUnsafeBytes(of: $0.pointee.sin6_addr) { Array($0) }
            }
            guard bytes.count == 16 else { return false }
            if bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes.last == 1 { return false }
            if bytes.allSatisfy({ $0 == 0 }) { return false }
            if bytes[0] & 0xfe == 0xfc { return false }
            if bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80 { return false }
            if bytes[0] == 0xff { return false }
            if bytes.prefix(10).allSatisfy({ $0 == 0 }) && bytes[10] == 0xff && bytes[11] == 0xff {
                let mapped = UInt32(bytes[12]) << 24 | UInt32(bytes[13]) << 16
                    | UInt32(bytes[14]) << 8 | UInt32(bytes[15])
                var ipv4 = sockaddr_in()
                ipv4.sin_family = sa_family_t(AF_INET)
                ipv4.sin_addr.s_addr = mapped.bigEndian
                return withUnsafeMutablePointer(to: &ipv4) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { isPublic($0) }
                }
            }
            return true
        }
        return false
    }
}

private final class BoundedDataLoader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maximumBytes: Int
    private var data = Data()
    private var response: HTTPURLResponse?
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    private var session: URLSession?

    init(maximumBytes: Int) { self.maximumBytes = maximumBytes }

    func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
            self.session = session
            session.dataTask(with: request).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url else {
            completionHandler(nil)
            task.cancel()
            finish(.failure(PublisherHTTPClient.HTTPError.invalidDestination))
            return
        }
        do { try PublisherURLPolicy.validate(url) }
        catch {
            completionHandler(nil)
            task.cancel()
            finish(.failure(error))
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(.failure(PublisherHTTPClient.HTTPError.invalidResponse))
            return
        }
        guard response.expectedContentLength <= 0 || response.expectedContentLength <= Int64(maximumBytes) else {
            completionHandler(.cancel)
            finish(.failure(PublisherHTTPClient.HTTPError.responseTooLarge))
            return
        }
        self.response = http
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard data.count <= maximumBytes - chunk.count else {
            dataTask.cancel()
            finish(.failure(PublisherHTTPClient.HTTPError.responseTooLarge))
            return
        }
        data.append(chunk)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            if (error as NSError).code != NSURLErrorCancelled { finish(.failure(error)) }
            return
        }
        guard let response else {
            finish(.failure(PublisherHTTPClient.HTTPError.invalidResponse))
            return
        }
        finish(.success((data, response)))
    }

    private func finish(_ result: Result<(Data, HTTPURLResponse), Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
        session?.finishTasksAndInvalidate()
        session = nil
    }
}

private final class BoundedDownloadLoader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let maximumBytes: Int64
    private var continuation: CheckedContinuation<(URL, HTTPURLResponse), Error>?
    private var session: URLSession?
    private var downloadedURL: URL?
    private var response: HTTPURLResponse?

    init(maximumBytes: Int64) { self.maximumBytes = maximumBytes }

    func load(_ request: URLRequest) async throws -> (URL, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: request).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url else {
            completionHandler(nil)
            task.cancel()
            finish(.failure(PublisherHTTPClient.HTTPError.invalidDestination))
            return
        }
        do { try PublisherURLPolicy.validate(url) }
        catch {
            completionHandler(nil)
            task.cancel()
            finish(.failure(error))
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > maximumBytes || totalBytesExpectedToWrite > maximumBytes {
            downloadTask.cancel()
            finish(.failure(PublisherHTTPClient.HTTPError.responseTooLarge))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let http = downloadTask.response as? HTTPURLResponse else {
            finish(.failure(PublisherHTTPClient.HTTPError.invalidResponse))
            return
        }
        let persistentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Upkeep-Publisher-\(UUID().uuidString).download")
        do {
            try FileManager.default.moveItem(at: location, to: persistentURL)
            downloadedURL = persistentURL
            response = http
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            if (error as NSError).code != NSURLErrorCancelled { finish(.failure(error)) }
            return
        }
        guard let downloadedURL, let response else {
            finish(.failure(PublisherHTTPClient.HTTPError.invalidResponse))
            return
        }
        finish(.success((downloadedURL, response)))
    }

    private func finish(_ result: Result<(URL, HTTPURLResponse), Error>) {
        guard let continuation else { return }
        self.continuation = nil
        if case .failure = result, let downloadedURL {
            try? FileManager.default.removeItem(at: downloadedURL)
        }
        continuation.resume(with: result)
        session?.finishTasksAndInvalidate()
        session = nil
    }
}
