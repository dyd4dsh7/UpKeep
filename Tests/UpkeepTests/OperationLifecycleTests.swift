import Foundation
import Testing
@testable import Upkeep

@MainActor
@Test func operationLifecyclePreservesObservedOutcomeAndBoundsCombinedCommandLogs() {
    let state = UpkeepUpdateExecutionState()
    let operation = OperationID.localModel("fixture")
    let started = Date(timeIntervalSince1970: 100)
    let finished = started.addingTimeInterval(5)
    state.begin(operation, targets: [.modelRuntime(.ollama)], phase: .downloading, label: "Fixture", at: started)
    state.setPhase(.refreshing, for: operation)
    #expect(state.activities[operation]?.phase == .refreshing)
    state.appendRedactedCommandLog(String(repeating: "a", count: 20_000), for: operation)
    state.appendRedactedCommandLog(String(repeating: "b", count: 20_000), for: operation)
    state.appendRedactedCommandLog("discarded", for: operation)
    let verification = OperationVerificationDetail(requested: "3", observed: "2", targetReached: false)
    state.recordVerification(.verified, for: operation, commandError: "Interrupted", verification: verification)
    state.finish(operation, at: finished)
    #expect(state.activities.isEmpty)
    let result = state.completedOperations.first!
    #expect(result.startedAt == started)
    #expect(result.finishedAt == finished)
    #expect(result.result == .verified)
    #expect(result.commandError == "Interrupted")
    #expect(result.verification?.observed == "2")
    #expect(result.verification?.targetReached == false)
    #expect(result.commandLog.count <= 32_768)
    #expect(result.commandLog.hasPrefix(String(repeating: "a", count: 20_000)))
    #expect(result.commandLog.hasSuffix("\n[Log output truncated]\n"))
    #expect(!result.commandLog.contains("discarded"))
    state.finish(operation)
    #expect(state.completedOperations.count == 1)
}

@MainActor
@Test func operationLifecycleRetainsNewestHundredAndNeverAssumesUnverifiedSuccess() {
    let state = UpkeepUpdateExecutionState()
    for index in 0..<105 {
        let operation = OperationID.localModel(String(index))
        state.begin(operation, targets: [], phase: .updating, label: String(index))
        state.finish(operation)
    }
    #expect(state.completedOperations.count == 100)
    #expect(state.completedOperations.first?.label == "104")
    #expect(state.completedOperations.last?.label == "5")
    #expect(state.completedOperations.allSatisfy { $0.result == .unverified })
}
