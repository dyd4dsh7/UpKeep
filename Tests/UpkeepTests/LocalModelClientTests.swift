import CryptoKit
import Foundation
import Testing
@testable import Upkeep

@Test func readsOllamaModelsDirectlyFromManifestStore() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let manifestURL = root.appendingPathComponent(
        "manifests/registry.ollama.ai/library/gemma4/e2b",
        isDirectory: false
    )
    try FileManager.default.createDirectory(
        at: manifestURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let data = Data(#"{"schemaVersion":2,"layers":[{"size":7000000000},{"size":12000}]}"#.utf8)
    try data.write(to: manifestURL)

    let models = ollamaRowsFromDisk(modelRoots: [root])

    #expect(models.count == 1)
    #expect(models.first?.name == "gemma4:e2b")
    #expect(models.first?.sizeBytes == 7_000_012_000)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    #expect(models.first?.digest == "sha256:\(digest)")
}

@Test func preservesNamespacedOllamaRepositoryNames() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let manifestURL = root.appendingPathComponent(
        "manifests/registry.ollama.ai/acme/research/model/latest",
        isDirectory: false
    )
    try FileManager.default.createDirectory(
        at: manifestURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data(#"{"schemaVersion":2,"layers":[]}"#.utf8).write(to: manifestURL)

    let models = ollamaRowsFromDisk(modelRoots: [root])

    #expect(models.map(\.name) == ["acme/research/model:latest"])
}

@Test func buildsOllamaTokenURLFromRegistryChallenge() throws {
    let challenge = #"Bearer realm="https://auth.example.com/token",service="registry.example.com",scope="repository:library/gemma4:pull""#

    let url = try #require(ollamaTokenURL(from: challenge, repository: "library/gemma4"))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

    #expect(components.scheme == "https")
    #expect(components.host == "auth.example.com")
    #expect(query["service"] == "registry.example.com")
    #expect(query["scope"] == "repository:library/gemma4:pull")
}
