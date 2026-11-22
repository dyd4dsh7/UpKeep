import Testing
@testable import Upkeep

@MainActor
@Test func managedDetailIsHiddenWhenItRepeatsTheDescription() {
    let explanation = AppUpdateManagement.testFlight.updateExplanation
    #expect(AppDetailView.additionalManagedDetail(explanation, primaryDescription: explanation) == nil)
    #expect(AppDetailView.additionalManagedDetail(nil, primaryDescription: explanation) == nil)
}

@MainActor
@Test func managedDetailIsShownWhenItAddsInformation() {
    let detail = "Steam is downloading this update."
    let description = AppUpdateManagement.steam.updateExplanation
    #expect(AppDetailView.additionalManagedDetail(detail, primaryDescription: description) == detail)
}
