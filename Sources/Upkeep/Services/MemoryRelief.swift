import Darwin
import Foundation

/// A full scan or CVE check briefly allocates a lot of short-lived data
/// (command output, JSON, publisher responses). The allocator keeps the freed
/// pages, so the app's memory footprint stays near the scan's peak. After that
/// work settles, ask malloc to return free pages to the system.
enum MemoryRelief {
    private static let queue = DispatchQueue(label: "nz.haydenthorn.Upkeep.memory-relief", qos: .utility)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var pending: DispatchWorkItem?

    /// Coalesces requests and runs once, `delay` seconds after the last one.
    static func scheduleRelease(after delay: TimeInterval = 3) {
        let work = DispatchWorkItem { _ = malloc_zone_pressure_relief(nil, 0) }
        lock.withLock {
            pending?.cancel()
            pending = work
        }
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
