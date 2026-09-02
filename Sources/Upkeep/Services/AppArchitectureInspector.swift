import Darwin
import Foundation

enum AppArchitecture: String, Sendable {
    case intel = "Intel"
    case appleSilicon = "Apple Silicon"
    case universal = "Universal"
    case unknown = "Unknown"

    init(architectures: [String]) {
        let arm = architectures.contains("arm64")
        let intel = architectures.contains("x86_64") || architectures.contains("i386")
        if arm { self = intel ? .universal : .appleSilicon }
        else if intel, architectures.allSatisfy({ ["x86_64", "i386"].contains($0) }) { self = .intel }
        else { self = .unknown }
    }

    var supportsAppleSilicon: Bool { self == .appleSilicon || self == .universal }

    func needsMigration(onAppleSilicon: Bool) -> Bool { self == .intel && onAppleSilicon }
}

enum AppArchitectureInspector {
    // Query the hardware, not Upkeep's build architecture: Upkeep may itself run under Rosetta.
    static let isAppleSilicon: Bool = {
        var supported: Int32 = 0
        var size = MemoryLayout.size(ofValue: supported)
        return sysctlbyname("hw.optional.arm64", &supported, &size, nil, 0) == 0 && supported == 1
    }()

    static func architectures(at appURL: URL, info: [String: Any]) -> [String] {
        guard let executable = info["CFBundleExecutable"] as? String,
              !executable.isEmpty, !executable.contains("/"), executable != "..",
              let handle = try? FileHandle(forReadingFrom: appURL.appendingPathComponent("Contents/MacOS/\(executable)"))
        else { return [] }
        defer { try? handle.close() }
        // Only the Mach-O header is needed; do not load whole executables or launch a process per app.
        guard let data = try? handle.read(upToCount: 4096) else { return [] }
        return architectures(in: data)
    }

    static func architectures(in data: Data) -> [String] {
        let bytes = Array(data)
        func word(_ offset: Int, littleEndian: Bool = false) -> UInt32? {
            guard offset >= 0, offset + 4 <= bytes.count else { return nil }
            let indices = littleEndian ? Array((offset..<offset + 4).reversed()) : Array(offset..<offset + 4)
            return indices.reduce(UInt32(0)) { ($0 << 8) | UInt32(bytes[$1]) }
        }
        func name(_ cpu: UInt32) -> String {
            switch cpu {
            case 7: "i386"
            case 0x01000007: "x86_64"
            case 0x0100000c: "arm64"
            default: "cpu-\(cpu)"
            }
        }
        guard let magic = word(0) else { return [] }
        switch magic {
        case 0xfeedface, 0xfeedfacf, 0xcefaedfe, 0xcffaedfe:
            let is64 = magic == 0xfeedfacf || magic == 0xcffaedfe
            guard bytes.count >= (is64 ? 32 : 28),
                  let cpu = word(4, littleEndian: magic == 0xcefaedfe || magic == 0xcffaedfe)
            else { return [] }
            return [name(cpu)]
        case 0xcafebabe, 0xbebafeca, 0xcafebabf, 0xbfbafeca:
            let littleEndian = magic == 0xbebafeca || magic == 0xbfbafeca
            let stride = magic == 0xcafebabf || magic == 0xbfbafeca ? 32 : 20
            guard let count = word(4, littleEndian: littleEndian), count > 0, count <= 64,
                  bytes.count >= 8 + Int(count) * stride else { return [] }
            return (0..<Int(count)).compactMap { index in
                word(8 + index * stride, littleEndian: littleEndian).map(name)
            }
        default:
            return []
        }
    }
}
