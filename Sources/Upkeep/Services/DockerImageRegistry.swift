import Foundation

/// A local image tag and the registry it names.
struct DockerImageReference: Equatable, Sendable {
    let registryHost: String
    let repository: String
    let tag: String

    static let dockerHubHost = "registry-1.docker.io"

    var isDockerHub: Bool { registryHost == Self.dockerHubHost }
    /// `docker pull` accepts this form.
    var pullReference: String { "\(displayName):\(tag)" }
    var displayName: String {
        guard isDockerHub else { return "\(registryHost)/\(repository)" }
        return repository.hasPrefix("library/") ? String(repository.dropFirst("library/".count)) : repository
    }

    /// Docker Hub's page for a pull reference such as `postgres:17-alpine`.
    /// Other registries have no common page layout.
    static func pageURL(forPullReference value: String) -> URL? {
        // The tag follows the last colon after the last slash ("host:5000/app:1").
        guard let colon = value.lastIndex(of: ":"),
              value.lastIndex(of: "/").map({ colon > $0 }) ?? true,
              let reference = parse(repository: String(value[..<colon]),
            tag: String(value[value.index(after: colon)...])), reference.isDockerHub else { return nil }
        let name = reference.displayName
        return URL(string: name.contains("/") ? "https://hub.docker.com/r/\(name)" : "https://hub.docker.com/_/\(name)")
    }

    /// Parses `docker image ls` columns. Returns nil for untagged images and
    /// local registries, which Upkeep never contacts.
    static func parse(repository name: String, tag: String) -> DockerImageReference? {
        guard !name.isEmpty, name != "<none>", !tag.isEmpty, tag != "<none>" else { return nil }
        var components = name.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.contains(where: \.isEmpty) else { return nil }
        var host = dockerHubHost
        if components.count > 1, let first = components.first,
           first.contains(".") || first.contains(":") || first == "localhost" {
            components.removeFirst()
            let lowered = first.lowercased()
            guard lowered != "localhost", !lowered.hasPrefix("localhost:"), !lowered.hasPrefix("127.") else { return nil }
            host = ["docker.io", "index.docker.io", "registry-1.docker.io"].contains(lowered) ? dockerHubHost : lowered
        }
        if host == dockerHubHost, components.count == 1 { components.insert("library", at: 0) }
        return DockerImageReference(registryHost: host, repository: components.joined(separator: "/"), tag: tag)
    }
}

enum DockerRegistryState: Equatable, Sendable {
    /// The registry does not know the local digest: a local build, a private
    /// image, or one whose upstream manifest is gone. Upkeep leaves it out.
    case notFromRegistry
    case checked(latestDigest: String)
}

/// Reads manifest digests with HEAD requests and anonymous pull tokens. Docker
/// Hub does not count HEAD requests toward its pull limit.
struct DockerImageRegistry: Sendable {
    static let manifestTypes = [
        "application/vnd.oci.image.index.v1+json",
        "application/vnd.docker.distribution.manifest.list.v2+json",
        "application/vnd.docker.distribution.manifest.v2+json",
        "application/vnd.oci.image.manifest.v1+json"
    ].joined(separator: ", ")

    func state(of reference: DockerImageReference, localDigest: String) async throws -> DockerRegistryState {
        var token: String?
        let local = try await manifestDigest(reference, manifest: localDigest, token: &token)
        guard local != nil else { return .notFromRegistry }
        // A removed tag has no newer release; keep showing the pulled digest.
        let latest = try await manifestDigest(reference, manifest: reference.tag, token: &token)
        return .checked(latestDigest: latest ?? localDigest)
    }

    /// Nil when the registry answers 401, 403 or 404 for this manifest.
    private func manifestDigest(
        _ reference: DockerImageReference,
        manifest: String,
        token: inout String?
    ) async throws -> String? {
        guard let url = URL(string: "https://\(reference.registryHost)/v2/\(reference.repository)/manifests/\(manifest)") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 20
        request.setValue(Self.manifestTypes, forHTTPHeaderField: "Accept")
        request.setValue("Upkeep/1.0", forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        var (_, response) = try await PublisherHTTPClient.data(for: request, maximumBytes: 64 * 1_024)
        if response.statusCode == 401, token == nil,
           let challenge = response.value(forHTTPHeaderField: "WWW-Authenticate"),
           let tokenURL = ollamaTokenURL(from: challenge, repository: reference.repository) {
            let (tokenData, tokenResponse) = try await PublisherHTTPClient.data(for: URLRequest(url: tokenURL))
            guard tokenResponse.statusCode == 200,
                  let issued = Self.token(from: tokenData) else { return nil }
            token = issued
            request.setValue("Bearer \(issued)", forHTTPHeaderField: "Authorization")
            (_, response) = try await PublisherHTTPClient.data(for: request, maximumBytes: 64 * 1_024)
        }
        if [401, 403, 404].contains(response.statusCode) { return nil }
        guard 200..<300 ~= response.statusCode else { throw UpdateSourceError.httpStatus(response.statusCode) }
        guard let digest = response.value(forHTTPHeaderField: "Docker-Content-Digest"), digest.hasPrefix("sha256:") else {
            throw UpdateSourceError.malformedData("\(reference.registryHost) did not return a manifest digest.")
        }
        return digest
    }

    static func token(from data: Data) -> String? {
        struct Response: Decodable { let token: String?; let accessToken: String?
            enum CodingKeys: String, CodingKey { case token; case accessToken = "access_token" } }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        return response.token ?? response.accessToken
    }

    // MARK: - Official images

    /// Unqualified names such as `postgres` look exactly like local builds
    /// (`my-app`). Only names on Docker's official image list are sent to
    /// Docker Hub, so local project names never leave the Mac. The list comes
    /// from docker-library/official-images, one file per image; Docker Hub's
    /// own API stops anonymous paging after 100 of its 180-odd entries.
    func officialImageNames() async throws -> Set<String> {
        let data = try await PublisherResponseCache.shared.data(
            for: "docker-official-images",
            maximumAge: 24 * 60 * 60
        ) {
            let url = URL(string: "https://api.github.com/repos/docker-library/official-images/contents/library")!
            let entries = try JSONDecoder().decode(
                [OfficialImageEntry].self,
                from: try await PublisherHTTPClient.data(from: url, accepting: "application/vnd.github+json")
            )
            let names = entries.filter { $0.type == "file" }.map(\.name)
            guard !names.isEmpty else { throw UpdateSourceError.malformedData("The official image list is empty.") }
            return try JSONEncoder().encode(names)
        }
        return Set(try JSONDecoder().decode([String].self, from: data))
    }

    private struct OfficialImageEntry: Decodable {
        let name: String
        let type: String
    }
}
