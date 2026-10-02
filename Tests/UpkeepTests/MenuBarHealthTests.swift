import Testing
@testable import Upkeep

@Test(arguments: [UpdateCheckState.notChecked, .checking, .disabled, .failed, .partial])
func zeroCountDoesNotClaimSuccessfulChecks(state: UpdateCheckState) {
    let health = MenuBarHealth(count: 0, state: state, lastChecked: nil)
    #expect(health.symbol != "checkmark.circle.fill")
    #expect(health.summary == state.title)
}

@Test func menuHealthRetainsKnownCountWhenSourcesFail() {
    let health = MenuBarHealth(count: 3, state: .partial, lastChecked: nil)
    #expect(health.summary.contains("3 known updates"))
    #expect(health.symbol == "exclamationmark.triangle")
    #expect(MenuBarHealth(count: 0, state: .complete, lastChecked: nil).summary == "No updates found in enabled sources")
}
