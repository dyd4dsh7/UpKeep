import Darwin
import Foundation

/// Tracks kernel birth identities so an exited leader's PID is never enough to
/// authorize a signal to a potentially different process group.
struct TerminalProcessGroup {
    enum Observation { case stopped, running, unverified }
    private struct Member: Hashable {
        let pid: Int32
        let group: Int32
        let seconds: Int
        let microseconds: Int32
        init(_ info: kinfo_proc) {
            pid = info.kp_proc.p_pid
            group = info.kp_eproc.e_pgid
            seconds = info.kp_proc.p_un.__p_starttime.tv_sec
            microseconds = info.kp_proc.p_un.__p_starttime.tv_usec
        }
    }
    private let groupID: Int32
    private var anchors: Set<Member>

    static func isEmpty(groupID: Int32) -> Bool? {
        members(groupID: groupID).map(\.isEmpty)
    }

    init?(identity: TerminalProcessIdentity) {
        guard identity.stillMatches(), let members = Self.members(groupID: identity.processID),
              members.contains(where: { $0.pid == identity.processID
                  && $0.seconds == identity.startSeconds && $0.microseconds == identity.startMicroseconds }) else { return nil }
        groupID = identity.processID
        anchors = members
    }

    mutating func observe() -> Observation {
        guard let members = Self.members(groupID: groupID) else { return .unverified }
        if members.isEmpty { return .stopped }
        guard !members.isDisjoint(with: anchors) else { return .unverified }
        anchors = members
        return .running
    }

    mutating func signal(_ signal: Int32) -> Bool {
        guard observe() == .running else { return false }
        // Revalidate one live member immediately before signalling the group.
        // Its birth and membership establish continuity even after leader exit.
        guard anchors.contains(where: { member in
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.size
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, member.pid]
            let result = mib.withUnsafeMutableBufferPointer {
                sysctl($0.baseAddress, UInt32($0.count), &info, &size, nil, 0)
            }
            return result == 0 && size == MemoryLayout<kinfo_proc>.size && Member(info) == member
        }) else { return false }
        return kill(-groupID, signal) == 0
    }

    private static func members(groupID: Int32) -> Set<Member>? {
        guard groupID > 0, groupID != getpgrp() else { return nil }
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PGRP, groupID]
        let stride = MemoryLayout<kinfo_proc>.stride
        for _ in 0..<3 {
            var size = 0
            let sized = mib.withUnsafeMutableBufferPointer {
                sysctl($0.baseAddress, UInt32($0.count), nil, &size, nil, 0)
            }
            guard sized == 0, size >= 0, size <= stride * 4_096 else { return nil }
            if size == 0 { return [] }
            var records = [kinfo_proc](repeating: kinfo_proc(), count: min(4_096, size / stride + 16))
            size = records.count * stride
            let result = records.withUnsafeMutableBytes { bytes in
                mib.withUnsafeMutableBufferPointer {
                    sysctl($0.baseAddress, UInt32($0.count), bytes.baseAddress, &size, nil, 0)
                }
            }
            if result != 0 && errno == ENOMEM { continue }
            guard result == 0, size >= 0, size <= records.count * stride, size % stride == 0 else { return nil }
            let values = records.prefix(size / stride).map(Member.init)
            guard values.allSatisfy({ $0.group == groupID }) else { return nil }
            return Set(values)
        }
        return nil
    }
}
