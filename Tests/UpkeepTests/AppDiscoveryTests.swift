import Testing
@testable import Upkeep

@Test func classifiesProductionAndTestFlightReceiptsSeparately() {
    let production = AppDiscovery.updateManagement(
        bundleIdentifier: "com.example.app",
        appPath: "/Applications/Example.app",
        hasReceipt: true,
        receiptType: "Production",
        hasEmbeddedProvisioningProfile: false,
        hasSetappFramework: false,
        microsoftRegisteredPaths: []
    )
    let testFlight = AppDiscovery.updateManagement(
        bundleIdentifier: "com.example.app",
        appPath: "/Applications/Example Beta.app",
        hasReceipt: true,
        receiptType: "Sandbox",
        hasEmbeddedProvisioningProfile: true,
        hasSetappFramework: false,
        microsoftRegisteredPaths: []
    )
    let productionWithEmbeddedProfile = AppDiscovery.updateManagement(
        bundleIdentifier: "com.example.app",
        appPath: "/Applications/Example.app",
        hasReceipt: true,
        receiptType: "Production",
        hasEmbeddedProvisioningProfile: true,
        hasSetappFramework: false,
        microsoftRegisteredPaths: []
    )

    #expect(production == .appStore)
    #expect(testFlight == .testFlight)
    #expect(productionWithEmbeddedProfile == .appStore)
}

@Test func classifiesSetappByBundleIdentifierOrFramework() {
    let identifierMatch = AppDiscovery.updateManagement(
        bundleIdentifier: "com.example.app-setapp",
        appPath: "/Applications/Example.app",
        hasReceipt: false,
        receiptType: nil,
        hasEmbeddedProvisioningProfile: false,
        hasSetappFramework: false,
        microsoftRegisteredPaths: []
    )
    let frameworkMatch = AppDiscovery.updateManagement(
        bundleIdentifier: "com.example.app",
        appPath: "/Applications/Example.app",
        hasReceipt: false,
        receiptType: nil,
        hasEmbeddedProvisioningProfile: false,
        hasSetappFramework: true,
        microsoftRegisteredPaths: []
    )

    #expect(identifierMatch == .setapp)
    #expect(frameworkMatch == .setapp)
}

@Test func microsoftAutoUpdateUsesRegistrationWithoutMisclassifyingVSCode() {
    let registered = AppDiscovery.updateManagement(
        bundleIdentifier: "com.microsoft.custom",
        appPath: "/Applications/Microsoft Custom.app",
        hasReceipt: false,
        receiptType: nil,
        hasEmbeddedProvisioningProfile: false,
        hasSetappFramework: false,
        microsoftRegisteredPaths: ["/Applications/Microsoft Custom.app"]
    )
    let visualStudioCode = AppDiscovery.updateManagement(
        bundleIdentifier: "com.microsoft.VSCode",
        appPath: "/Applications/Visual Studio Code.app",
        hasReceipt: false,
        receiptType: nil,
        hasEmbeddedProvisioningProfile: false,
        hasSetappFramework: false,
        microsoftRegisteredPaths: []
    )

    #expect(registered == .microsoftAutoUpdate)
    #expect(visualStudioCode == .direct)
}
