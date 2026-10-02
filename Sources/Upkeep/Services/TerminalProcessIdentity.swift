import Darwin
import Foundation

/// Identifies the dedicated zsh script without treating a PID receipt alone as
/// authority to signal a process. Command arguments are inspected, never logged.
struct TerminalProcessIdentity: Equatable, Sendable {
    let processID: Int32
    let startSeconds: Int
    let startMicroseconds: Int32
    let scriptURL: URL

    static func capture(processID: Int32, scriptURL: URL) -> Self? {
        guard processID > 0, processID != getpid(), processID != getpgrp() else { return nil }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, processID]
        let result = mib.withUnsafeMutableBufferPointer {
            sysctl($0.baseAddress, UInt32($0.count), &info, &size, nil, 0)
        }
        guard result == 0, size == MemoryLayout<kinfo_proc>.size,
              info.kp_proc.p_pid == processID, info.kp_eproc.e_pgid == processID,
              info.kp_eproc.e_ucred.cr_uid == geteuid(),
              commandMatches(processID: processID, scriptURL: scriptURL) else { return nil }
        let started = info.kp_proc.p_un.__p_starttime
        return Self(processID: processID, startSeconds: started.tv_sec,
                    startMicroseconds: started.tv_usec, scriptURL: scriptURL)
    }

    func stillMatches() -> Bool {
        Self.capture(processID: processID, scriptURL: scriptURL) == self
    }

    private static func commandMatches(processID: Int32, scriptURL: URL) -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, processID]
        var size = 0
        let sized = mib.withUnsafeMutableBufferPointer {
            sysctl($0.baseAddress, UInt32($0.count), nil, &size, nil, 0)
        }
        guard sized == 0, size >= MemoryLayout<Int32>.size, size <= 1_024 * 1_024 else { return false }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { bytes in
            mib.withUnsafeMutableBufferPointer {
                sysctl($0.baseAddress, UInt32($0.count), bytes.baseAddress, &size, nil, 0)
            }
        }
        guard read == 0, size >= MemoryLayout<Int32>.size, size <= data.count else { return false }
        data = data.prefix(size)
        let argc = data.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc == 2 else { return false }
        var offset = MemoryLayout<Int32>.size
        func nextString() -> String? {
            guard offset < data.count, let end = data[offset...].firstIndex(of: 0) else { return nil }
            let value = String(data: data[offset..<end], encoding: .utf8)
            offset = end + 1
            return value
        }
        guard nextString() == "/bin/zsh" else { return false }
        while offset < data.count, data[offset] == 0 { offset += 1 }
        return nextString() == "/bin/zsh" && nextString() == scriptURL.path
    }
}
