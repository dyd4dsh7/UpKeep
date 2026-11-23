import Foundation
import Testing
@testable import Upkeep

private func package(_ name: String, _ manager: DeveloperPackageManager, registry: String? = nil, context: String? = nil) -> DeveloperPackage {
    DeveloperPackage(name: name, currentVersion: "1.0", latestVersion: "1.0", manager: manager,
                     executablePath: "/fixture/bin/tool", registryIdentifier: registry, installationContext: context)
}

private func model(_ name: String, _ runtime: LocalModelRuntime) -> LocalLLMModel {
    LocalLLMModel(id: "\(runtime.rawValue):\(name)", name: name, variant: nil, runtime: runtime,
                  installedRevision: "a", latestRevision: "a", sizeBytes: nil, modifiedAt: nil,
                  homepage: nil, executablePath: nil, updateReference: name, isOutdated: false)
}

private func app(_ name: String, bundleID: String?, url: URL? = nil, appStore: Bool = false) -> InstalledApp {
    InstalledApp(name: name, bundleIdentifier: bundleID, installedVersion: "1.0", buildVersion: nil,
                 url: url ?? URL(fileURLWithPath: "/fixture/\(name).app"), sparkleFeedURL: nil,
                 githubRepository: nil, hasAppStoreReceipt: appStore)
}

private func response(_ json: String) -> ItemDescriptionClient.FetchOutcome { .data(Data(json.utf8)) }

// MARK: - Text cleanup

@Test func descriptionCleanupJoinsWrappedLinesAndKeepsTheFirstParagraph() {
    let crate = "ripgrep is a line-oriented search tool that recursively searches the current\ndirectory for a regex pattern."
    #expect(ItemDescriptions.clean(crate) == "ripgrep is a line-oriented search tool that recursively searches the current directory for a regex pattern.")
    #expect(ItemDescriptions.clean("First paragraph.\n\nSecond paragraph.") == "First paragraph.")
    #expect(ItemDescriptions.clean("  <b>Bold</b>   tool  ") == "Bold tool")
    #expect(ItemDescriptions.clean("   ") == nil)
    #expect(ItemDescriptions.clean("Upkeep", name: "upkeep") == nil)
}

@Test func longDescriptionsAreCutToTheirFirstSentenceOrAWordBoundary() throws {
    let long = "Xcode offers the tools you need to develop, test, and distribute apps for Apple platforms. "
        + String(repeating: "More marketing text follows here. ", count: 10)
    #expect(ItemDescriptions.clean(long) == "Xcode offers the tools you need to develop, test, and distribute apps for Apple platforms")

    let runOn = String(repeating: "word ", count: 60)
    let cut = try #require(ItemDescriptions.clean(runOn))
    #expect(cut.count <= ItemDescriptions.maximumLength)
    #expect(cut.hasSuffix("word…"))
}

// MARK: - Choosing a source

@Test func runtimesAndToolsUseBuiltInDescriptionsWithoutALookup() {
    let node = package("Node.js", .node, context: "NVM Node 22.23.4")
    #expect(ItemDescriptions.builtIn(for: node) != nil)
    #expect(ItemDescriptions.request(for: node) == nil)

    let runtime = package("CPython Python 3.10", .uv, context: "uv-managed runtime")
    #expect(ItemDescriptions.builtIn(for: runtime) == "Python interpreter installed by uv")
    #expect(ItemDescriptions.request(for: runtime) == nil)

    #expect(ItemDescriptions.builtIn(for: package("java", .sdkman)) != nil)
    #expect(ItemDescriptions.builtIn(for: package("python@3.12", .mise)) == "Python programming language")
    #expect(ItemDescriptions.builtIn(for: package("unknown-tool", .mise)) == nil)
    #expect(ItemDescriptions.request(for: package("unknown-tool", .mise)) == nil)
}

@Test func registryPackagesBecomeLookupsKeyedByManagerAndName() {
    let codex = package("@openai/codex", .npm)
    #expect(ItemDescriptions.request(for: codex) == .developerPackage(manager: .npm, identifier: "@openai/codex"))
    #expect(ItemDescriptions.request(for: package("Some Display Name", .npm)) == nil)
    #expect(ItemDescriptions.request(for: package("Json", .rubyGems))?.key == "dev:RubyGems:json")
    #expect(ItemDescriptions.request(for: package("gh-dash", .githubCLI, registry: "dlvhdr/gh-dash")) != nil)
    #expect(ItemDescriptions.request(for: package("tool", .go, registry: "golang.org/x/tools/gopls")) == nil)
    #expect(ItemDescriptions.request(for: package("tool", .nix)) == nil)
}

@Test func githubRepositoriesComeFromModuleAndExtensionPaths() {
    #expect(ItemDescriptions.githubRepository(from: "github.com/cli/cli/v2/cmd/gh") == "cli/cli")
    #expect(ItemDescriptions.githubRepository(from: "dlvhdr/gh-dash") == "dlvhdr/gh-dash")
    #expect(ItemDescriptions.githubRepository(from: "golang.org/x/tools/gopls") == nil)
    #expect(ItemDescriptions.githubRepository(from: "single") == nil)
}

@Test func dockerImagesMapToDockerHubRepositories() {
    #expect(ItemDescriptionClient.dockerHubRepository("postgres:17-alpine") == "library/postgres")
    #expect(ItemDescriptionClient.dockerHubRepository("timescale/timescaledb:2.30.1-pg17") == "timescale/timescaledb")
    #expect(ItemDescriptionClient.dockerHubRepository("docker.io/library/mysql:8.4") == "library/mysql")
    #expect(ItemDescriptionClient.dockerHubRepository("ghcr.io/owner/image:latest") == nil)
    #expect(ItemDescriptionClient.dockerHubRepository("localhost:5000/image") == nil)
}

@Test func appleAppsUseBuiltInDescriptions() {
    let safari = app("Safari", bundleID: "com.apple.Safari")
    #expect(ItemDescriptions.builtIn(for: safari) == "Apple’s web browser")
    #expect(ItemDescriptions.request(for: safari) == nil)
    #expect(ItemDescriptions.request(for: app("Editor", bundleID: "com.example.editor"))?.key == "app:com.example.editor")
}

@Test func modelDescriptionsNameTheirTaskAndOrigin() {
    #expect(ItemDescriptions.modelTaskDescription(pipelineTag: "text-generation", baseModel: "Qwen/Qwen3-8B",
                                                  author: "lmstudio-community", repository: "lmstudio-community/Qwen3-8B-GGUF")
            == "Text generation model based on Qwen/Qwen3-8B")
    #expect(ItemDescriptions.modelTaskDescription(pipelineTag: "sentence-similarity", baseModel: nil,
                                                  author: "BAAI", repository: "BAAI/bge-small")
            == "Embedding model for search and retrieval from BAAI")
    #expect(ItemDescriptions.modelFamilyDescription(for: "qwen3.5:9b") == "Alibaba’s Qwen language model")
    #expect(ItemDescriptions.modelFamilyDescription(for: "qwen2.5vl:7b") == "Alibaba’s Qwen model that understands images")
    #expect(ItemDescriptions.modelFamilyDescription(for: "qwen2.5-coder:7b") == "Alibaba’s Qwen model for writing code")
    #expect(ItemDescriptions.modelFamilyDescription(for: "nomic-embed-text:latest") == "Embedding model for search and retrieval")
    #expect(ItemDescriptions.modelFamilyDescription(for: "devstral:24b") == "Mistral AI’s Devstral coding language model")
    #expect(ItemDescriptions.modelFamilyDescription(for: "my-private-model") == nil)

    #expect(ItemDescriptions.builtIn(for: model("llama3.2:3b", .ollama)) == "Meta’s Llama language model")
    #expect(ItemDescriptions.request(for: model("lmstudio-community/Qwen3-8B-GGUF", .lmStudio))
            == .model(runtime: .lmStudio, repository: "lmstudio-community/Qwen3-8B-GGUF"))
}

@Test func appCategoriesReadAsPlainLabels() {
    #expect(ItemDescriptions.categoryDescription("public.app-category.developer-tools") == "Developer tool")
    #expect(ItemDescriptions.categoryDescription("public.app-category.business") == "Business app")
    #expect(ItemDescriptions.categoryDescription("public.app-category.puzzle-games") == "Game")
    #expect(ItemDescriptions.categoryDescription("Utilities") == nil)
}

// MARK: - Lookups

@Test func registryLookupsSeparateMissingPackagesFromFailedRequests() async {
    let client = ItemDescriptionClient(caskCatalog: { [] }, appStoreLookup: { _ in [:] }, fetch: { request in
        switch request.url?.absoluteString {
        case "https://registry.npmjs.org/@openai/codex/latest":
            return response(#"{"description":"Codex CLI is a coding agent from OpenAI that runs locally on your computer."}"#)
        case "https://rubygems.org/api/v1/gems/missing.json": return .notFound
        case "https://pypi.org/pypi/flaky/json": return .failed
        case "https://hub.docker.com/v2/repositories/library/postgres/":
            return response(#"{"description":"The PostgreSQL object-relational database system provides reliability and data integrity."}"#)
        case "https://huggingface.co/api/models/lmstudio-community/Qwen3-8B-GGUF":
            return response(#"{"pipeline_tag":"text-generation","author":"lmstudio-community","cardData":{"base_model":["Qwen/Qwen3-8B"]}}"#)
        default:
            return response(#"{"description":""}"#)
        }
    })
    let requests: [ItemDescriptionRequest] = [
        .developerPackage(manager: .npm, identifier: "@openai/codex"),
        .developerPackage(manager: .rubyGems, identifier: "missing"),
        .developerPackage(manager: .python, identifier: "flaky"),
        .developerPackage(manager: .dockerImages, identifier: "postgres:17-alpine"),
        .developerPackage(manager: .cargo, identifier: "empty"),
        .model(runtime: .lmStudio, repository: "lmstudio-community/Qwen3-8B-GGUF")
    ]
    let results = await client.describe(requests)
    #expect(results["dev:npm:@openai/codex"] == .found("Codex CLI is a coding agent from OpenAI that runs locally on your computer."))
    #expect(results["dev:RubyGems:missing"] == .notFound)
    #expect(results["dev:Python:flaky"] == nil)
    #expect(results["dev:Docker Images:postgres:17-alpine"] == .found("The PostgreSQL object-relational database system provides reliability and data integrity."))
    #expect(results["dev:Cargo:empty"] == .notFound)
    #expect(results["model:LM Studio:lmstudio-community/qwen3-8b-gguf"] == .found("Text generation model based on Qwen/Qwen3-8B"))
}

@Test func appLookupsPreferTheAppStoreThenHomebrewThenTheAppCategory() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("UpkeepDescriptions-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let categorized = folder.appendingPathComponent("Categorized.app")
    try FileManager.default.createDirectory(at: categorized.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    let plist: [String: Any] = ["CFBundleIdentifier": "com.example.categorized",
                                "LSApplicationCategoryType": "public.app-category.developer-tools"]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: categorized.appendingPathComponent("Contents/Info.plist"))

    let catalog = [CatalogCask(token: "visual-studio-code", name: ["Microsoft Visual Studio Code"], version: "1",
                               artifactAppNames: ["Visual Studio Code.app"], desc: "Open-source code editor")]
    let listing = try JSONDecoder().decode(AppStoreClient.LookupResult.self, from: Data(#"""
        {"bundleId":"com.example.store","version":"2","description":"Plan your day with ease.\n\nMore details."}
        """#.utf8))
    let client = ItemDescriptionClient(caskCatalog: { catalog }, appStoreLookup: { ids in
        ids.contains("com.example.store") ? ["com.example.store": listing] : [:]
    }, fetch: { _ in .failed })

    let store = AppDescriptionInput(bundleIdentifier: "com.example.store", name: "Planner",
                                    url: folder.appendingPathComponent("Planner.app"), isAppStore: true)
    let code = AppDescriptionInput(bundleIdentifier: "com.microsoft.VSCode", name: "Visual Studio Code",
                                   url: folder.appendingPathComponent("Visual Studio Code.app"), isAppStore: false)
    let category = AppDescriptionInput(bundleIdentifier: "com.example.categorized", name: "Categorized",
                                       url: categorized, isAppStore: false)
    let unknown = AppDescriptionInput(bundleIdentifier: "com.example.unknown", name: "Unknown",
                                      url: folder.appendingPathComponent("Unknown.app"), isAppStore: false)
    let results = await client.describe([.app(store), .app(code), .app(category), .app(unknown)])
    #expect(results[store.key] == .found("Plan your day with ease."))
    #expect(results[code.key] == .found("Open-source code editor"))
    #expect(results[category.key] == .found("Developer tool"))
    #expect(results[unknown.key] == .notFound)
}

@Test func appLookupsRetryLaterWhenTheCaskCatalogIsUnavailable() async {
    struct Offline: Error {}
    let client = ItemDescriptionClient(caskCatalog: { throw Offline() }, appStoreLookup: { _ in [:] }, fetch: { _ in .failed })
    let input = AppDescriptionInput(bundleIdentifier: "com.example.unknown", name: "Unknown",
                                    url: URL(fileURLWithPath: "/fixture/Unknown.app"), isAppStore: false)
    #expect(await client.describe([.app(input)]).isEmpty)
}

@Test func slimCaskCatalogKeepsDescriptions() throws {
    let catalog = [CatalogCask(token: "firefox", name: ["Mozilla Firefox"], version: "1", desc: "Web browser")]
    let restored = try #require(SlimCaskCatalog.decode(JSONEncoder().encode(SlimCaskCatalog(catalog))))
    #expect(restored.first?.desc == "Web browser")
}

// MARK: - State and cache

private actor RecordingDescriber: ItemDescribing {
    var calls: [[String]] = []
    var answers: [String: ItemDescriptionLookup]
    init(_ answers: [String: ItemDescriptionLookup]) { self.answers = answers }
    func setAnswers(_ value: [String: ItemDescriptionLookup]) { answers = value }
    func describe(_ requests: [ItemDescriptionRequest]) async -> [String: ItemDescriptionLookup] {
        calls.append(requests.map(\.key).sorted())
        return answers.filter { key, _ in requests.contains { $0.key == key } }
    }
}

@MainActor
@Test func descriptionStateCachesResultsAndRetriesOnlyFailedLookups() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("UpkeepDescriptionCache-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let cacheURL = folder.appendingPathComponent("descriptions.json")
    let found = ItemDescriptionRequest.developerPackage(manager: .npm, identifier: "left-pad")
    let missing = ItemDescriptionRequest.developerPackage(manager: .npm, identifier: "missing")
    let failing = ItemDescriptionRequest.developerPackage(manager: .npm, identifier: "offline")
    let describer = RecordingDescriber([found.key: .found("String padding"), missing.key: .notFound])
    let state = ItemDescriptionState(describer: describer, cacheURL: cacheURL)

    await state.load([found, missing, failing, found])
    #expect(state.text(for: found.key) == "String padding")
    #expect(state.text(for: missing.key) == nil)
    #expect(await describer.calls == [[found.key, missing.key, failing.key].sorted()])

    // Found and missing items are not requested again; the failed one is.
    await state.load([found, missing, failing])
    #expect(await describer.calls.last == [failing.key])

    // A new launch shows the saved description without a lookup.
    for _ in 0..<50 where !FileManager.default.fileExists(atPath: cacheURL.path) {
        try await Task.sleep(for: .milliseconds(20))
    }
    let relaunched = ItemDescriptionState(describer: RecordingDescriber([:]), cacheURL: cacheURL)
    #expect(relaunched.text(for: found.key) == "String padding")
}

@MainActor
@Test func staleDescriptionsStayVisibleWhileTheyAreCheckedAgain() async {
    let request = ItemDescriptionRequest.developerPackage(manager: .npm, identifier: "left-pad")
    let describer = RecordingDescriber([request.key: .found("Old text")])
    nonisolated(unsafe) var now = Date(timeIntervalSince1970: 1_000_000)
    let state = ItemDescriptionState(describer: describer, cacheURL: nil, now: { now })
    await state.load([request])
    await describer.setAnswers([:])
    now = now.addingTimeInterval(ItemDescriptionCache.foundLifetime + 1)
    await state.load([request])
    #expect(await describer.calls.count == 2)
    #expect(state.text(for: request.key) == "Old text")
}

@MainActor
@Test func developerRowsLeadWithTheDescriptionAndKeepWhatTellsRepeatsApart() {
    let codex = package("@openai/codex", .npm)
    #expect(DeveloperPackageRow.rowDetail(for: codex, description: "Coding agent", isRepeatedName: false) == "Coding agent · npm")
    #expect(DeveloperPackageRow.rowDetail(for: codex, description: "Coding agent", isRepeatedName: true) == "Coding agent · /fixture/bin")
    #expect(DeveloperPackageRow.rowDetail(for: codex, description: nil, isRepeatedName: false) == "npm · /fixture/bin")
    let node = package("Node.js", .node, context: "NVM Node 22.23.4")
    #expect(DeveloperPackageRow.rowDetail(for: node, description: "JavaScript runtime", isRepeatedName: true) == "Node.js · NVM Node 22.23.4")
}
