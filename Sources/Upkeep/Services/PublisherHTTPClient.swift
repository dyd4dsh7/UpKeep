import Darwin
import Foundation

enum PublisherHTTPClient {
    static let metadataLimit = 64 * 1_024 * 1_024
    static let archiveLimit: Int64 = 1_024 * 1_024 * 1_024

    static func data(for request: URLRequest, maximumBytes: Int = metadataLimit) async throws -> (Data, HTTPURLResponse) {
        let result = try await PublisherCurlTransport.load(
            request,
            maximumBytes: Int64(maximumBytes)
        )
        defer { try? FileManager.default.removeItem(at: result.bodyURL) }
        return (try Data(contentsOf: result.bodyURL), result.response)
    }

    static func download(for request: URLRequest, maximumBytes: Int64 = archiveLimit) async throws -> (URL, HTTPURLResponse) {
        let result = try await PublisherCurlTransport.load(request, maximumBytes: maximumBytes)
        return (result.bodyURL, result.response)
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
        _ = try validatedAddresses(for: url)
    }

    static func validatedAddresses(for url: URL) throws -> [String] {
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
        var addresses: [String] = []
        while let address = current {
            guard isPublic(address.pointee.ai_addr) else {
                throw PublisherHTTPClient.HTTPError.nonPublicDestination
            }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                address.pointee.ai_addr,
                address.pointee.ai_addrlen,
                &buffer,
                socklen_t(buffer.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 else {
                throw PublisherHTTPClient.HTTPError.invalidDestination
            }
            let terminator = buffer.firstIndex(of: 0) ?? buffer.endIndex
            let numericAddress = String(
                decoding: buffer[..<terminator].map { UInt8(bitPattern: $0) },
                as: UTF8.self
            )
            if !addresses.contains(numericAddress) { addresses.append(numericAddress) }
            current = address.pointee.ai_next
        }
        guard !addresses.isEmpty else { throw PublisherHTTPClient.HTTPError.invalidDestination }
        return addresses
    }

    static func validateRemoteAddress(_ address: String) throws {
        var ipv4 = in_addr()
        if inet_pton(AF_INET, address, &ipv4) == 1 {
            var socketAddress = sockaddr_in()
            socketAddress.sin_family = sa_family_t(AF_INET)
            socketAddress.sin_addr = ipv4
            let allowed = withUnsafeMutablePointer(to: &socketAddress) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { isPublic($0) }
            }
            guard allowed else { throw PublisherHTTPClient.HTTPError.nonPublicDestination }
            return
        }

        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, address, &ipv6) == 1 {
            var socketAddress = sockaddr_in6()
            socketAddress.sin6_family = sa_family_t(AF_INET6)
            socketAddress.sin6_addr = ipv6
            let allowed = withUnsafeMutablePointer(to: &socketAddress) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { isPublic($0) }
            }
            guard allowed else { throw PublisherHTTPClient.HTTPError.nonPublicDestination }
            return
        }

        throw PublisherHTTPClient.HTTPError.invalidDestination
    }

    private static func isPublic(_ address: UnsafeMutablePointer<sockaddr>?) -> Bool {
        guard let address else { return false }
        if address.pointee.sa_family == sa_family_t(AF_INET) {
            let value = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            let first = UInt8((value >> 24) & 0xff)
            let second = UInt8((value >> 16) & 0xff)
            let third = UInt8((value >> 8) & 0xff)
            return first != 0 && first != 10 && first != 127
                && !(first == 100 && (64...127).contains(second))
                && !(first == 169 && second == 254)
                && !(first == 172 && (16...31).contains(second))
                && !(first == 192 && second == 0 && (third == 0 || third == 2))
                && !(first == 192 && second == 88 && third == 99)
                && !(first == 192 && second == 168)
                && !(first == 198 && (18...19).contains(second))
                && !(first == 198 && second == 51 && third == 100)
                && !(first == 203 && second == 0 && third == 113)
                && !(first >= 224)
        }
        if address.pointee.sa_family == sa_family_t(AF_INET6) {
            let bytes = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                withUnsafeBytes(of: $0.pointee.sin6_addr) { Array($0) }
            }
            guard bytes.count == 16 else { return false }
            if bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes.last == 1 { return false }
            if bytes.allSatisfy({ $0 == 0 }) { return false }
            if bytes.prefix(12).allSatisfy({ $0 == 0 }) { return false }
            if bytes[0] == 0x01 && bytes[1] == 0x00
                && bytes[2..<8].allSatisfy({ $0 == 0 }) { return false }
            if bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x00 && bytes[3] == 0x02 {
                return false
            }
            if bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8 {
                return false
            }
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

enum PublisherCurlTransport {
    private static let maximumRedirects = 10

    struct Result: Sendable {
        let bodyURL: URL
        let response: HTTPURLResponse
    }

    static func load(_ request: URLRequest, maximumBytes: Int64) async throws -> Result {
        try await Task.detached(priority: .utility) {
            try loadSynchronously(request, maximumBytes: maximumBytes)
        }.value
    }

    private static func loadSynchronously(_ initialRequest: URLRequest, maximumBytes: Int64) throws -> Result {
        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("Upkeep-Publisher-Curl-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: workspace.path)
        defer { try? fileManager.removeItem(at: workspace) }

        var request = initialRequest
        for redirectCount in 0...maximumRedirects {
            guard let url = request.url else { throw PublisherHTTPClient.HTTPError.invalidDestination }
            let addresses = try PublisherURLPolicy.validatedAddresses(for: url)
            let hop = try execute(
                request,
                addresses: addresses,
                maximumBytes: maximumBytes,
                workspace: workspace
            )
            if let redirected = try redirectedRequest(from: request, response: hop.response) {
                guard redirectCount < maximumRedirects else {
                    throw URLError(.httpTooManyRedirects)
                }
                request = redirected
                continue
            }

            let persistentURL = fileManager.temporaryDirectory
                .appendingPathComponent("Upkeep-Publisher-\(UUID().uuidString).download")
            try fileManager.moveItem(at: hop.bodyURL, to: persistentURL)
            return Result(bodyURL: persistentURL, response: hop.response)
        }
        throw URLError(.httpTooManyRedirects)
    }

    private static func execute(
        _ request: URLRequest,
        addresses: [String],
        maximumBytes: Int64,
        workspace: URL
    ) throws -> Result {
        var lastError: Error = URLError(.cannotConnectToHost)
        let candidates = request.httpMethod == "POST" ? Array(addresses.prefix(1)) : addresses
        for address in candidates {
            do {
                return try execute(
                    request,
                    address: address,
                    maximumBytes: maximumBytes,
                    workspace: workspace
                )
            } catch let error as CurlTransportError {
                lastError = error.underlyingError
            }
        }
        throw lastError
    }

    private static func execute(
        _ request: URLRequest,
        address: String,
        maximumBytes: Int64,
        workspace: URL
    ) throws -> Result {
        guard let url = request.url else {
            throw PublisherHTTPClient.HTTPError.invalidDestination
        }
        let identifier = UUID().uuidString
        let headerURL = workspace.appendingPathComponent("\(identifier).headers")
        let bodyURL = workspace.appendingPathComponent("\(identifier).body")
        let requestBodyURL = workspace.appendingPathComponent("\(identifier).request")
        let requestHeadersURL = workspace.appendingPathComponent("\(identifier).request-headers")
        if let body = request.httpBody { try body.write(to: requestBodyURL) }
        let requestHeaders = try validatedHeaderLines(for: request)
        if !requestHeaders.isEmpty {
            try Data((requestHeaders.joined(separator: "\n") + "\n").utf8)
                .write(to: requestHeadersURL, options: .atomic)
        }

        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = try curlArguments(
            for: request,
            resolvedAddress: address,
            headerURL: headerURL,
            bodyURL: bodyURL,
            requestBodyURL: request.httpBody == nil ? nil : requestBodyURL,
            requestHeadersURL: requestHeaders.isEmpty ? nil : requestHeadersURL,
            maximumBytes: maximumBytes
        )
        process.standardOutput = output
        process.standardError = errors
        do { try process.run() }
        catch { throw CurlTransportError(underlyingError: error) }
        let standardOutput = output.fileHandleForReading.readDataToEndOfFile()
        let standardError = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CurlTransportError(underlyingError: curlError(
                status: process.terminationStatus,
                output: standardError
            ))
        }
        guard let statusText = String(data: standardOutput, encoding: .utf8),
              let statusCode = Int(statusText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: try responseHeaders(at: headerURL)
              )
        else { throw PublisherHTTPClient.HTTPError.invalidResponse }
        let attributes = try FileManager.default.attributesOfItem(atPath: bodyURL.path)
        guard let size = attributes[.size] as? NSNumber, size.int64Value <= maximumBytes else {
            throw PublisherHTTPClient.HTTPError.responseTooLarge
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: bodyURL.path)
        return Result(bodyURL: bodyURL, response: response)
    }

    static func curlArguments(
        for request: URLRequest,
        resolvedAddress: String,
        headerURL: URL,
        bodyURL: URL,
        requestBodyURL: URL?,
        requestHeadersURL: URL?,
        maximumBytes: Int64
    ) throws -> [String] {
        guard let url = request.url, let host = url.host else {
            throw PublisherHTTPClient.HTTPError.invalidDestination
        }
        let method = request.httpMethod ?? "GET"
        guard ["GET", "POST"].contains(method) else {
            throw PublisherHTTPClient.HTTPError.invalidDestination
        }
        let port = url.port ?? 443
        let pinnedAddress = resolvedAddress.contains(":") ? "[\(resolvedAddress)]" : resolvedAddress
        var arguments = [
            "--silent", "--show-error",
            "--proto", "=https",
            "--proto-redir", "=https",
            "--noproxy", "*",
            "--request", method,
            "--max-time", String(max(1, request.timeoutInterval)),
            "--max-filesize", String(maximumBytes),
            "--dump-header", headerURL.path,
            "--output", bodyURL.path,
            "--write-out", "%{http_code}",
        ]
        if host != resolvedAddress {
            arguments.append(contentsOf: ["--resolve", "\(host):\(port):\(pinnedAddress)"])
        }
        if let requestHeadersURL {
            arguments.append(contentsOf: ["--header", "@\(requestHeadersURL.path)"])
        }
        if let requestBodyURL {
            arguments.append(contentsOf: ["--data-binary", "@\(requestBodyURL.path)"])
        }
        arguments.append(url.absoluteString)
        return arguments
    }

    static func validatedHeaderLines(for request: URLRequest) throws -> [String] {
        try (request.allHTTPHeaderFields ?? [:]).sorted(by: { $0.key < $1.key }).map { name, value in
            guard !name.contains(where: \Character.isNewline),
                  !value.contains(where: \Character.isNewline)
            else { throw PublisherHTTPClient.HTTPError.invalidDestination }
            return "\(name): \(value)"
        }
    }

    private static func redirectedRequest(
        from request: URLRequest,
        response: HTTPURLResponse
    ) throws -> URLRequest? {
        guard [301, 302, 303, 307, 308].contains(response.statusCode),
              let location = response.value(forHTTPHeaderField: "Location"),
              let baseURL = request.url,
              let destination = URL(string: location, relativeTo: baseURL)?.absoluteURL
        else { return nil }
        try PublisherURLPolicy.validate(destination)
        var redirected = request
        redirected.url = destination
        if response.statusCode == 303
            || ([301, 302].contains(response.statusCode) && request.httpMethod == "POST") {
            redirected.httpMethod = "GET"
            redirected.httpBody = nil
            redirected.setValue(nil, forHTTPHeaderField: "Content-Type")
            redirected.setValue(nil, forHTTPHeaderField: "Content-Length")
        }
        if !sameOrigin(baseURL, destination) {
            redirected.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        return redirected
    }

    static func sameOrigin(_ left: URL, _ right: URL) -> Bool {
        left.scheme?.lowercased() == right.scheme?.lowercased()
            && left.host?.lowercased() == right.host?.lowercased()
            && (left.port ?? 443) == (right.port ?? 443)
    }

    static func responseHeaders(at url: URL) throws -> [String: String] {
        let text = try String(contentsOf: url, encoding: .isoLatin1)
            .replacingOccurrences(of: "\r\n", with: "\n")
        guard let block = text.components(separatedBy: "\n\n")
            .last(where: { $0.hasPrefix("HTTP/") })
        else { throw PublisherHTTPClient.HTTPError.invalidResponse }
        var headers: [String: String] = [:]
        for line in block.split(separator: "\n").dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            headers[name] = headers[name].map { "\($0), \(value)" } ?? value
        }
        return headers
    }

    private static func curlError(status: Int32, output: Data) -> Error {
        switch status {
        case 6: URLError(.cannotFindHost)
        case 7: URLError(.cannotConnectToHost)
        case 28: URLError(.timedOut)
        case 35, 51, 58, 60: URLError(.secureConnectionFailed)
        case 63: PublisherHTTPClient.HTTPError.responseTooLarge
        default:
            UpdateSourceError.malformedData(
                String(data: output, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? "The publisher request failed."
            )
        }
    }

    private struct CurlTransportError: Error {
        let underlyingError: Error
    }
}
