import Foundation
import IOKit.ps
import Network

/// Automatic updates run without anyone watching, so they wait for a Mac that
/// is plugged in, not saving power, and on a network that isn't metered.
protocol UnattendedConditionsChecking: Sendable {
    /// Why unattended installs should wait right now, or nil when they can run.
    func reasonToWait() async -> String?
}

struct LiveUnattendedConditions: UnattendedConditionsChecking {
    func reasonToWait() async -> String? {
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return "Low Power Mode is on" }
        if Self.isOnBattery() { return "the Mac is on battery power" }
        guard let path = await Self.currentPath() else { return nil }
        return Self.reasonToWait(status: path.status, isExpensive: path.isExpensive, isConstrained: path.isConstrained)
    }

    static func reasonToWait(status: NWPath.Status, isExpensive: Bool, isConstrained: Bool) -> String? {
        if status != .satisfied { return "there is no network connection" }
        if isExpensive { return "the network is metered, such as a phone hotspot" }
        if isConstrained { return "Low Data Mode is on for this network" }
        return nil
    }

    /// True when the Mac is running from its battery. Desktop Macs have no
    /// battery and always report AC power.
    static func isOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPSBatteryPowerValue
    }

    /// The current network path, or nil if it isn't known within two seconds.
    static func currentPath() async -> NWPath? {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let gate = ResumeOnce()
            monitor.pathUpdateHandler = { path in
                guard gate.claim() else { return }
                monitor.cancel()
                continuation.resume(returning: path)
            }
            monitor.start(queue: DispatchQueue.global(qos: .utility))
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                guard gate.claim() else { return }
                monitor.cancel()
                continuation.resume(returning: nil)
            }
        }
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool { lock.withLock { defer { claimed = true }; return !claimed } }
}
