import Foundation

func formattedDiagnosticDuration(since date: Date, now: Date = Date()) -> String {
    String(format: "%.0f ms", now.timeIntervalSince(date) * 1_000)
}

enum DiagnosticLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case info = "Info"
    case warning = "Warning"
    case error = "Error"

    var id: Self { self }
}

enum DiagnosticCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case scan = "Scan"
    case source = "Update Source"
    case comparison = "Version Comparison"
    case command = "Command"
    case update = "Update"
    case application = "Application"

    var id: Self { self }
    var shortTitle: String {
        switch self {
        case .scan: "Scan"
        case .source: "Source"
        case .comparison: "Comparison"
        case .command: "Command"
        case .update: "Update"
        case .application: "Application"
        }
    }

    var systemImage: String {
        switch self {
        case .scan: "waveform.path.ecg"
        case .source: "dot.radiowaves.left.and.right"
        case .comparison: "arrow.left.arrow.right"
        case .command: "terminal"
        case .update: "arrow.down.circle"
        case .application: "macwindow"
        }
    }
}

enum DiagnosticLevelFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case info
    case warning
    case error

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var level: DiagnosticLevel? {
        switch self {
        case .all: nil
        case .info: .info
        case .warning: .warning
        case .error: .error
        }
    }
}

struct DiagnosticEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let date: Date
    let level: DiagnosticLevel
    let category: DiagnosticCategory
    let message: String
    let metadata: [String: String]

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        level: DiagnosticLevel,
        category: DiagnosticCategory,
        message: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.date = date
        self.level = level
        self.category = category
        self.message = DiagnosticRedactor.redact(message)
        self.metadata = metadata.reduce(into: [:]) { result, pair in
            result[DiagnosticRedactor.redact(pair.key)] = DiagnosticRedactor.redact(pair.value)
        }
    }
}

enum DiagnosticRedactor {
    // NSRegularExpression instances are immutable and safe to reuse across the
    // concurrent scanner tasks that create buffered diagnostic entries.
    private final class CompiledRules: @unchecked Sendable {
        let values: [(expression: NSRegularExpression, replacement: String)]

        init() {
            values = [
                (#"(?i)(https?://)[^/\s:@]+:[^@\s/]+@"#, "$1<redacted>@"),
                (#"(?i)(authorization\s*[:=]\s*(?:bearer|basic)\s+)[^\s,;]+"#, "$1<redacted>"),
                (#"(?i)((?:api[_-]?key|access[_-]?token|auth[_-]?token|password|secret)\s*[:=]\s*)[^\s,;]+"#, "$1<redacted>"),
                (#"(?i)(https?://[^\s?#]+)\?[^\s#]+"#, "$1?<redacted>"),
                (#"(?i)([?&](?:token|key|signature|sig|password|secret|auth)=)[^&#\s]+"#, "$1<redacted>"),
                (#"\b(?:ghp|github_pat|sk|xox[baprs])[-_][A-Za-z0-9_-]{12,}\b"#, "<redacted-token>")
            ].map { pattern, replacement in
                (try! NSRegularExpression(pattern: pattern), replacement)
            }
        }
    }

    private static let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    private static let rules = CompiledRules()

    static func redact(_ input: String) -> String {
        var value = input
        if !homePath.isEmpty { value = value.replacingOccurrences(of: homePath, with: "~") }

        // Every rule below requires an ASCII colon, equals sign, hyphen, or
        // underscore. Plain status text cannot match any rule. Keep home-path
        // redaction and the length limit on this path as well.
        guard value.utf8.contains(where: { $0 == 58 || $0 == 61 || $0 == 45 || $0 == 95 }) else {
            return String(value.prefix(2_000))
        }

        for rule in rules.values {
            value = rule.expression.stringByReplacingMatches(
                in: value,
                range: NSRange(value.startIndex..<value.endIndex, in: value),
                withTemplate: rule.replacement
            )
        }
        return String(value.prefix(2_000))
    }
}

// SAFETY: Every access to cachedEntries and persistence is serialized by lock;
// fileURL is immutable after initialization.
final class DiagnosticsStore: @unchecked Sendable {
    // Only the packaged app owns the user's persistent diagnostics. SwiftPM
    // tests and standalone review harnesses must not write fixture failures to it.
    static let shared = DiagnosticsStore(
        persistent: Bundle.main.bundleIdentifier == InstalledApp.upkeepBundleIdentifier
    )
    private static let maximumEntries = 2_000

    private let lock = NSLock()
    private let fileURL: URL?
    private var cachedEntries: [DiagnosticEntry]

    init(fileURL: URL? = nil, persistent: Bool = true) {
        let resolvedURL = persistent ? (fileURL ?? Self.defaultFileURL()) : nil
        self.fileURL = resolvedURL
        self.cachedEntries = resolvedURL.map(Self.load(from:)) ?? []
    }

    func record(
        _ level: DiagnosticLevel,
        category: DiagnosticCategory,
        _ message: String,
        metadata: [String: String] = [:]
    ) {
        append(DiagnosticEntry(level: level, category: category, message: message, metadata: metadata), persist: true)
    }

    func recordBuffered(
        _ level: DiagnosticLevel,
        category: DiagnosticCategory,
        _ message: String,
        metadata: [String: String] = [:]
    ) {
        append(DiagnosticEntry(level: level, category: category, message: message, metadata: metadata), persist: false)
    }

    func entries() -> [DiagnosticEntry] {
        lock.lock()
        defer { lock.unlock() }
        return cachedEntries.sorted { $0.date > $1.date }
    }

    func clear() {
        lock.lock()
        cachedEntries.removeAll()
        persistLocked()
        lock.unlock()
    }

    func exportText() -> String {
        let entries = entries().reversed()
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        var lines = [
            "Upkeep Diagnostics",
            "App: \(appVersion) (\(build))",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Generated: \(Date().formatted(.iso8601))",
            "Entries: \(entries.count)",
            ""
        ]
        let formatter = ISO8601DateFormatter()
        for entry in entries {
            lines.append("[\(formatter.string(from: entry.date))] [\(entry.level.rawValue)] [\(entry.category.rawValue)] \(entry.message)")
            for pair in entry.metadata.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(pair.key): \(pair.value)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func persistLocked() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(cachedEntries).write(to: fileURL, options: .atomic)
        } catch {
            // Diagnostics must never interrupt update checks or update operations.
        }
    }

    private func append(_ entry: DiagnosticEntry, persist: Bool) {
        lock.lock()
        cachedEntries.append(entry)
        if cachedEntries.count > Self.maximumEntries {
            cachedEntries.removeFirst(cachedEntries.count - Self.maximumEntries)
        }
        if persist { persistLocked() }
        lock.unlock()
    }

    private static func load(from url: URL) -> [DiagnosticEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = (try? decoder.decode([DiagnosticEntry].self, from: data)) ?? []
        return decoded.suffix(maximumEntries).map {
            DiagnosticEntry(
                id: $0.id,
                date: $0.date,
                level: $0.level,
                category: $0.category,
                message: $0.message,
                metadata: $0.metadata
            )
        }
    }

    private static func defaultFileURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("Upkeep/Diagnostics/diagnostics.json")
    }
}
