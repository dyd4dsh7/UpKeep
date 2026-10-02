import Foundation
import Testing
@testable import Upkeep

@Test func scopedRetryPreservesOtherEnvironmentFailures() {
    for source in [ScanWarningSource.developerPackages, .localModels] {
        let shared = ScanWarning(source: source, itemNames: ["first", "second"], message: "Offline")
        let unknown = ScanWarning(source: source, message: "Unknown failure")
        let unrelated = ScanWarning(source: .homebrew, message: "Receipt failed")
        let result = reconcileSourceWarnings(existing: [shared, unknown, unrelated], fresh: [],
                                             source: source, checkedName: "first")
        #expect(result.count == 3)
        #expect(result[0].itemNames == ["second"])
        #expect(result[0].affectedItemCount == 1)
        #expect(result[1] == unknown)
        #expect(result[2] == unrelated)
    }
}

@Test func wholeSourceRetryKeepsFreshExplicitAttribution() {
    let fresh = ScanWarning(source: .developerPackages, itemNames: ["npm", "pipx"], message: "Offline")
    let result = reconcileSourceWarnings(
        existing: [ScanWarning(source: .developerPackages, message: "Old failure")],
        fresh: [fresh], source: .developerPackages, checkedName: nil)
    #expect(result == [fresh])
}

@Test func scopedRetryRetainsUnlistedAffectedEnvironments() {
    let warning = ScanWarning(source: .localModels, itemNames: ["Ollama"], affectedItemCount: 2, message: "Offline")
    let result = reconcileSourceWarnings(existing: [warning], fresh: [], source: .localModels, checkedName: "Ollama")
    #expect(result.count == 1)
    #expect(result[0].itemNames.isEmpty)
    #expect(result[0].affectedItemCount == 1)
}

@Test func repeatedSharedFailureHasOneWarningIdentity() {
    let result = reconcileSourceWarnings(
        existing: [ScanWarning(source: .localModels, itemNames: ["Ollama", "LM Studio"], message: "Offline")],
        fresh: [ScanWarning(source: .localModels, itemNames: ["Ollama"], message: "Offline")],
        source: .localModels, checkedName: "Ollama")
    #expect(result.count == 1)
    #expect(result[0].itemNames == ["LM Studio", "Ollama"])
    #expect(result[0].affectedItemCount == 2)
}

@Test func stableWarningOwnershipPreservesDuplicateNamedAppAfterScopedRemoval() throws {
    let warning = ScanWarning(source: .sparkle, itemNames: ["Same name"],
        itemNamesByID: ["app-a": "Same name", "app-b": "Same name"], message: "Offline")
    #expect(warning.affectedItemCount == 2)
    let remaining = try #require(warning.removingItems(ids: ["app-a"]))
    #expect(remaining.itemNamesByID == ["app-b": "Same name"])
    #expect(remaining.affectedItemCount == 1)
    #expect(remaining.itemNames == ["Same name"])
    #expect(remaining.removingItems(ids: ["app-b"]) == nil)
    let encoded = try JSONEncoder().encode(warning)
    var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    legacy.removeValue(forKey: "itemNamesByID")
    let decoded = try JSONDecoder().decode(ScanWarning.self, from: JSONSerialization.data(withJSONObject: legacy))
    #expect(decoded.itemNamesByID == nil)
    #expect(decoded.message == "Offline")
    #expect(decoded.affectedItemCount == 2)
}

@Test func identifiedAppRetryMergesSharedFailureWithoutLosingOtherAppOwnership() throws {
    let old = ScanWarning(source: .sparkle, itemNames: ["Same"],
        itemNamesByID: ["a": "Same", "b": "Same"], message: "Offline")
    let fresh = ScanWarning(source: .sparkle, itemNames: ["Same"],
        itemNamesByID: ["a": "Same"], message: "Offline")
    let result = reconcileSourceWarnings(existing: [old], fresh: [fresh], source: .sparkle,
                                         checkedName: "Same", checkedID: "a")
    #expect(result.count == 1)
    let warning = try #require(result.first)
    #expect(warning.itemNamesByID == ["a": "Same", "b": "Same"])
    #expect(warning.affectedItemCount == 2)
    let success = reconcileSourceWarnings(existing: result, fresh: [], source: .sparkle,
                                          checkedName: "Same", checkedID: "a")
    #expect(success.first?.itemNamesByID == ["b": "Same"])
    #expect(success.first?.affectedItemCount == 1)
}
