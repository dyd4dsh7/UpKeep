import Foundation
import Testing
@testable import Upkeep

private actor VerificationDiscovery: ApplicationDiscovering {
    var observed: InstalledApp?
    private var blocked: CheckedContinuation<InstalledApp?, Never>?
    private(set) var calls = 0
    init(_ observed: InstalledApp?) { self.observed = observed }
    func discover() async -> [InstalledApp] { [] }
    func discover(at url: URL) async -> InstalledApp? {
        calls += 1
        if calls == 1 { return await withCheckedContinuation { blocked = $0 } }
        return observed
    }
    func releaseFirst(_ app: InstalledApp?) { blocked?.resume(returning: app); blocked = nil }
}

private struct FixedVerificationDiscovery: ApplicationDiscovering {
    let app: InstalledApp?
    func discover() async -> [InstalledApp] { [] }
    func discover(at url: URL) async -> InstalledApp? { app }
}

private func verificationApp(_ version: String) -> InstalledApp {
    InstalledApp(name: "Fixture", bundleIdentifier: "test.external-owner", installedVersion: version,
        buildVersion: nil, url: URL(fileURLWithPath: "/not-executed/Fixture.app"),
        sparkleFeedURL: nil, githubRepository: nil, hasAppStoreReceipt: false)
}
private func verificationUpdate() -> AvailableUpdate {
    AvailableUpdate(app: verificationApp("1"), availableVersion: "3", source: .appStore,
        releaseNotes: nil, actionURL: nil, homebrewToken: nil)
}

private enum VerificationFixtureError: Error { case timedOut }
@MainActor
private func waitForVerification(_ condition: @MainActor () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !(await condition()) {
        guard ContinuousClock.now < deadline else { throw VerificationFixtureError.timedOut }
        try await Task.sleep(for: .milliseconds(1))
    }
}

@MainActor
@Test func supersededExternalDiscoveryCannotPublishOrClearReplacement() async throws {
    let discovery = VerificationDiscovery(verificationApp("3"))
    let verifier = ExternalUpdateVerifier(discovery: discovery, interval: .zero, attempts: 1)
    var oldResults = 0
    var newResults = 0
    verifier.start(verificationUpdate()) { _ in oldResults += 1 }
    try await waitForVerification { await discovery.calls == 1 }
    verifier.start(verificationUpdate()) { result in
        if case let .installed(app) = result { #expect(app.installedVersion == "3") }
        else { Issue.record("Replacement did not verify the installed target") }
        newResults += 1
    }
    try await waitForVerification { newResults == 1 }
    await discovery.releaseFirst(verificationApp("3"))
    for _ in 0..<20 { await Task.yield() }
    #expect(oldResults == 0)
    #expect(newResults == 1)
}

@MainActor
@Test func externalVerificationReportsLastObservedVersionAndUnavailableBundle() async throws {
    for observed in [verificationApp("2"), nil] {
        let verifier = ExternalUpdateVerifier(discovery: FixedVerificationDiscovery(app: observed),
            interval: .zero, attempts: 2)
        var finished = false
        verifier.start(verificationUpdate()) { result in
            if case let .attention(lastObserved) = result {
                #expect(lastObserved?.installedVersion == observed?.installedVersion)
            } else { Issue.record("Uninstalled target was reported as installed") }
            finished = true
        }
        try await waitForVerification { finished }
    }
}
