import Testing
@testable import Upkeep

@Test func targetedModelFallbackPreservesCheckedAndUnknownWarningScopes() async {
    let report = await WholeInventoryModels().scan(runtime: .ollama)
    #expect(report.warnings == ["shared", "unknown"])
    #expect(report.warningRuntimes["shared"] == [.ollama])
    #expect(report.warningRuntimes["studio"] == nil)
    #expect(report.failedRuntimes == [.ollama])
    #expect(report.failedModelIDs == ["ollama-model"])
    #expect(report.models.map(\.id) == ["ollama-model"])
}

private struct WholeInventoryModels: LocalModelManaging {
    func scan() async -> LocalModelClient.Report {
        let models = LocalModelRuntime.allCases.map { runtime in
            LocalLLMModel(id: runtime == .ollama ? "ollama-model" : "studio-model", name: "Fixture",
                variant: "Q4", runtime: runtime, installedRevision: "1", latestRevision: "2",
                sizeBytes: nil, modifiedAt: nil, homepage: nil, executablePath: nil,
                updateReference: "fixture", isOutdated: true)
        }
        return .init(models: models, warnings: ["studio", "shared", "unknown"],
            failedModelIDs: ["ollama-model", "studio-model"], failedRuntimes: [.ollama, .lmStudio],
            warningRuntimes: ["studio": [.lmStudio], "shared": [.ollama, .lmStudio]])
    }
    func update(_ model: LocalLLMModel) async throws {}
}
