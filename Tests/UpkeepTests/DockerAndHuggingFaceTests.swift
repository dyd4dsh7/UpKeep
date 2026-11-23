import Foundation
import Testing
@testable import Upkeep

@Test func dockerReferencesNameTheirRegistry() {
    let official = DockerImageReference.parse(repository: "postgres", tag: "17-alpine")
    #expect(official == DockerImageReference(registryHost: "registry-1.docker.io", repository: "library/postgres", tag: "17-alpine"))
    #expect(official?.pullReference == "postgres:17-alpine")

    let namespaced = DockerImageReference.parse(repository: "timescale/timescaledb", tag: "2.30.1-pg17")
    #expect(namespaced?.repository == "timescale/timescaledb")
    #expect(namespaced?.isDockerHub == true)

    let ghcr = DockerImageReference.parse(repository: "ghcr.io/owner/tool", tag: "v1")
    #expect(ghcr == DockerImageReference(registryHost: "ghcr.io", repository: "owner/tool", tag: "v1"))
    #expect(ghcr?.pullReference == "ghcr.io/owner/tool:v1")
    #expect(DockerImageReference.parse(repository: "docker.io/library/redis", tag: "7")?.pullReference == "redis:7")

    // Untagged images and local registries are never checked.
    #expect(DockerImageReference.parse(repository: "archlinux", tag: "<none>") == nil)
    #expect(DockerImageReference.parse(repository: "<none>", tag: "<none>") == nil)
    #expect(DockerImageReference.parse(repository: "localhost:5000/app", tag: "dev") == nil)
    #expect(DockerImageReference.parse(repository: "127.0.0.1:5000/app", tag: "dev") == nil)
}

@Test func dockerHubPagesLinkOfficialAndNamespacedImages() {
    #expect(DockerImageReference.pageURL(forPullReference: "postgres:17-alpine")?.absoluteString
        == "https://hub.docker.com/_/postgres")
    #expect(DockerImageReference.pageURL(forPullReference: "timescale/timescaledb:2.30.1-pg17")?.absoluteString
        == "https://hub.docker.com/r/timescale/timescaledb")
    #expect(DockerImageReference.pageURL(forPullReference: "ghcr.io/owner/tool:v1") == nil)
}

@Test func dockerImageListSkipsUntaggedAndDuplicateRows() {
    let output = Data("""
        {"Containers":"N/A","Digest":"sha256:526f86d93c6ea08fd3f1fe5605650cacc781b2c6013169a0ad8f42c7d3d84f32","ID":"sha256:526f","Repository":"postgres","Tag":"17-alpine"}
        {"Digest":"sha256:4e77cf2ea5f410e6f8be5abf93ccf17ce2436e87a138c167208356711a405dbd","Repository":"archlinux","Tag":"<none>"}
        {"Digest":"<none>","Repository":"legacy-build","Tag":"latest"}
        {"Digest":"sha256:526f86d93c6ea08fd3f1fe5605650cacc781b2c6013169a0ad8f42c7d3d84f32","Repository":"postgres","Tag":"17-alpine"}
        not json
        """.utf8)
    let rows = parseDockerImageList(output)
    #expect(rows.map(\.reference.pullReference) == ["postgres:17-alpine"])
    #expect(rows.first?.digest.hasPrefix("sha256:526f86d93c6e") == true)
}

@Test func stoppedDockerDaemonIsNotAFailure() {
    #expect(dockerDaemonIsUnavailable(Data(
        "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?".utf8)))
    // Docker 28+ wording when Docker Desktop is quit.
    #expect(dockerDaemonIsUnavailable(Data("""
        failed to connect to the docker API at unix:///Users/test/.docker/run/docker.sock; check if the path is correct \
        and if the daemon is running: dial unix /Users/test/.docker/run/docker.sock: connect: no such file or directory
        """.utf8)))
    #expect(!dockerDaemonIsUnavailable(Data("permission denied".utf8)))
}

@Test func dockerTokensAcceptEitherField() {
    #expect(DockerImageRegistry.token(from: Data(#"{"token":"abc"}"#.utf8)) == "abc")
    #expect(DockerImageRegistry.token(from: Data(#"{"access_token":"def"}"#.utf8)) == "def")
    #expect(DockerImageRegistry.token(from: Data("{}".utf8)) == nil)
}

@Test func dockerImagePackagesCompareDigestsNotVersions() throws {
    func image(_ current: String, _ latest: String) -> DeveloperPackage {
        DeveloperPackage(name: "postgres:17-alpine", currentVersion: current, latestVersion: latest,
            manager: .dockerImages, executablePath: "/usr/local/bin/docker", registryIdentifier: "postgres:17-alpine")
    }
    // Hex digests look like versions and prereleases to the version helpers.
    let outdated = image("526f86d93c6e", "0a1b2c3d4e5f")
    #expect(outdated.isOutdated)
    #expect(outdated.prereleaseChannel == nil)
    #expect(!outdated.prereleaseIsInstalled)
    #expect(!image("526f86d93c6e", "526f86d93c6e").isOutdated)
    #expect(selectableDeveloperPackageVersions(discovered: [], package: outdated, includePrereleases: false)
        == ["0a1b2c3d4e5f"])

    let plan = try DeveloperPackageInstallAdapters.plan(for: outdated, version: outdated.latestVersion)
    guard case let .command(executable, arguments, _) = plan else {
        Issue.record("Expected a docker pull command")
        return
    }
    #expect(executable.path == "/usr/local/bin/docker")
    #expect(arguments == ["pull", "postgres:17-alpine"])
    #expect(try DeveloperPackageUninstallAdapters.plan(for: outdated).arguments == ["image", "rm", "postgres:17-alpine"])
}

@Test func publisherHeadRequestsUseCurlHeadMode() throws {
    var request = URLRequest(url: try #require(URL(string: "https://registry-1.docker.io/v2/library/postgres/manifests/17")))
    request.httpMethod = "HEAD"
    let arguments = try PublisherCurlTransport.curlArguments(
        for: request, resolvedAddress: "8.8.8.8",
        headerURL: URL(fileURLWithPath: "/tmp/h"), bodyURL: URL(fileURLWithPath: "/tmp/b"),
        requestBodyURL: nil, requestHeadersURL: nil, maximumBytes: 1_024
    )
    #expect(arguments.contains("--head"))
    #expect(!arguments.contains("--request"))

    request.httpMethod = "DELETE"
    #expect(throws: (any Error).self) {
        try PublisherCurlTransport.curlArguments(
            for: request, resolvedAddress: "8.8.8.8",
            headerURL: URL(fileURLWithPath: "/tmp/h"), bodyURL: URL(fileURLWithPath: "/tmp/b"),
            requestBodyURL: nil, requestHeadersURL: nil, maximumBytes: 1_024
        )
    }
}

@Test func huggingFaceCacheListsModelsTrackingMain() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("Upkeep-HF-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: root) }
    let revision = "9ce89f2a58cb50cc57a38b3dab37b713f85447fa"

    func model(_ folder: String, ref: String?, files: [String]) throws {
        let base = root.appendingPathComponent(folder, isDirectory: true)
        let blobs = base.appendingPathComponent("blobs", isDirectory: true)
        try fileManager.createDirectory(at: blobs, withIntermediateDirectories: true)
        if let ref {
            try fileManager.createDirectory(at: base.appendingPathComponent("refs"), withIntermediateDirectories: true)
            try ref.write(to: base.appendingPathComponent("refs/main"), atomically: true, encoding: .utf8)
        }
        let snapshot = base.appendingPathComponent("snapshots/\(revision)", isDirectory: true)
        for (index, file) in files.enumerated() {
            let blob = blobs.appendingPathComponent("blob\(index)")
            try Data(repeating: 1, count: 10).write(to: blob)
            let link = snapshot.appendingPathComponent(file)
            try fileManager.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.createSymbolicLink(at: link, withDestinationURL: blob)
        }
    }
    try model("models--mlx-community--Qwen3.5-0.8B-OptiQ-4bit", ref: revision + "\n",
        files: ["config.json", "model.safetensors", "nested/tokenizer.json"])
    try model("models--org--pinned", ref: nil, files: ["config.json"])
    try model("datasets--org--data", ref: revision, files: ["data.csv"])

    let entries = huggingFaceCacheEntries(roots: [root])
    #expect(entries.map(\.repository) == ["mlx-community/Qwen3.5-0.8B-OptiQ-4bit"])
    #expect(entries.first?.revision == revision)
    #expect(entries.first?.sizeBytes == 30)
    #expect(huggingFaceCachedFiles(repository: "mlx-community/Qwen3.5-0.8B-OptiQ-4bit", roots: [root])
        == ["config.json", "model.safetensors", "nested/tokenizer.json"])
}

@Test func huggingFaceCacheHonoursItsEnvironmentVariables() throws {
    let fileManager = FileManager.default
    let home = fileManager.temporaryDirectory.appendingPathComponent("Upkeep-HFHome-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: home) }
    try fileManager.createDirectory(at: home.appendingPathComponent("hub"), withIntermediateDirectories: true)
    let roots = huggingFaceCacheRoots(environment: ["HF_HOME": home.path])
    #expect(roots.first?.standardizedFileURL.path == home.appendingPathComponent("hub").standardizedFileURL.path)
}
