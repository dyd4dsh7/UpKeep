import Foundation

enum VersionComparator {
    private final class ParsedVersionBox: NSObject {
        let value: ParsedVersion?

        init(_ value: ParsedVersion?) {
            self.value = value
        }
    }

    // NSCache synchronizes access internally. This wrapper retains that guarantee
    // while exposing only immutable parsed values to concurrent scan tasks.
    private final class ParsedVersionCache: @unchecked Sendable {
        private let storage: NSCache<NSString, ParsedVersionBox>

        init() {
            storage = NSCache<NSString, ParsedVersionBox>()
            storage.countLimit = 512
        }

        func value(for rawValue: String) -> ParsedVersion? {
            let key = rawValue as NSString
            if let cached = storage.object(forKey: key) { return cached.value }
            let parsed = ParsedVersion(rawValue)
            storage.setObject(ParsedVersionBox(parsed), forKey: key)
            return parsed
        }
    }

    private static let parsedVersionCache = ParsedVersionCache()

    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        compare(candidate, installed) == .orderedDescending
    }

    static func isPrerelease(_ version: String) -> Bool {
        prereleaseChannel(for: version) != nil
    }

    /// Homebrew's stable versions use trailing letters for post-releases
    /// ("tmux 3.5a", "jpeg 9b"), so a single letter after the last number,
    /// optionally followed by a revision ("_1"), never marks a prerelease there.
    static func isHomebrewPrerelease(_ version: String) -> Bool {
        let release = String(version.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)[0])
        let base = release.replacingOccurrences(of: #"(?<=\d)[A-Za-z](?=(_\d+)?$)"#, with: "",
                                                options: .regularExpression)
        return isPrerelease(base)
    }

    static func prereleaseChannel(for version: String) -> PrereleaseChannel? {
        // Homebrew casks append build metadata after a comma (often a hash).
        // Only the release part describes stability.
        let release = version.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let value = release.lowercased()
        if value.contains("release candidate") { return .releaseCandidate }
        if value.contains("nightly") { return .nightly }
        if value.contains("snapshot") { return .snapshot }
        if value.contains("alpha") { return .alpha }
        if value.contains("beta") { return .beta }
        if value.contains("preview") { return .preview }
        if let label = parsedVersion(String(release))?.prerelease?.label {
            switch label {
            case "dev": return .development
            case "nightly": return .nightly
            case "snapshot": return .snapshot
            case "a", "alpha": return .alpha
            case "b", "beta": return .beta
            case "pre", "preview": return .preview
            case "rc": return .releaseCandidate
            default: return .prerelease
            }
        }
        if isPlatformQualified(value) { return nil }
        return hasHyphenatedQualifier(value) ? .prerelease : nil
    }

    private static func hasHyphenatedQualifier(_ value: String) -> Bool {
        guard let hyphen = value.firstIndex(of: "-") else { return false }
        let release = value[..<hyphen]
        let qualifier = value[value.index(after: hyphen)...]
        guard release.contains("."), release.last?.isNumber == true, qualifier.first?.isLetter == true else {
            return false
        }
        // "-stable", "-final" and "-release" describe a stable build.
        let label = String(qualifier.prefix(while: \.isLetter))
        return !ParsedVersion.ignoredLabels.contains(label)
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        compareParsed(parsedVersion(lhs), parsedVersion(rhs))
    }

    private static func compareParsed(_ lhs: ParsedVersion?, _ rhs: ParsedVersion?) -> ComparisonResult {
        guard let left = lhs, let right = rhs else {
            // An unversioned value such as "latest" must not create an update.
            return .orderedSame
        }

        let coreResult = compareNumericSequences(left.core, right.core)
        if coreResult != .orderedSame { return coreResult }
        let postResult = compareNumericSequences(left.postRelease, right.postRelease)
        if postResult != .orderedSame { return postResult }

        switch (left.prerelease, right.prerelease) {
        case (nil, nil):
            return .orderedSame
        case (nil, .some):
            return .orderedDescending
        case (.some, nil):
            return .orderedAscending
        case let (.some(leftPrerelease), .some(rightPrerelease)):
            if leftPrerelease.rank != rightPrerelease.rank {
                return leftPrerelease.rank > rightPrerelease.rank ? .orderedDescending : .orderedAscending
            }
            if leftPrerelease.label != rightPrerelease.label,
               leftPrerelease.rank == Prerelease.unknownRank {
                return leftPrerelease.label.localizedStandardCompare(rightPrerelease.label)
            }
            return comparePrereleaseIdentifiers(leftPrerelease.identifiers, rightPrerelease.identifiers)
        }
    }

    static func newestFirst(_ lhs: String, _ rhs: String) -> Bool {
        newestFirst(lhs, rhs, comparison: compare(lhs, rhs))
    }

    /// A registry can contain thousands of releases, exceeding the shared cache.
    /// Retain each parsed value for this sort so comparator calls never reparse it.
    static func sortedNewestFirst<S: Sequence>(_ versions: S) -> [String] where S.Element == String {
        let prepared = versions.map { (raw: $0, parsed: parsedVersion($0)) }
        return prepared.sorted {
            newestFirst($0.raw, $1.raw, comparison: compareParsed($0.parsed, $1.parsed))
        }.map(\.raw)
    }

    private static func newestFirst(_ lhs: String, _ rhs: String, comparison result: ComparisonResult) -> Bool {
        if result != .orderedSame { return result == .orderedDescending }
        let leftIsPlatformBuild = isPlatformQualified(lhs)
        let rightIsPlatformBuild = isPlatformQualified(rhs)
        if leftIsPlatformBuild != rightIsPlatformBuild { return !leftIsPlatformBuild }
        return lhs.localizedStandardCompare(rhs) == .orderedDescending
    }

    private static func isPlatformQualified(_ version: String) -> Bool {
        let value = version.lowercased()
        return ParsedVersion.packagingLabels.contains { label in
            value.contains("-\(label)") || value.contains(".\(label)")
        }
    }

    private static func parsedVersion(_ value: String) -> ParsedVersion? {
        parsedVersionCache.value(for: value)
    }

    private struct ParsedVersion {
        let core: [NumericIdentifier]
        /// Post-release suffixes such as "3.5a", "9e" or "9.9p1" sort after their base release.
        let postRelease: [NumericIdentifier]
        let prerelease: Prerelease?

        private struct Token {
            let identifier: Identifier
            let attachedToNumber: Bool
            let group: Int
        }

        init?(_ rawValue: String) {
            var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !value.isEmpty else { return nil }

            value = Self.removingVersionPrefix(from: value)
            value = String(value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0])
            // Homebrew cask metadata after a comma may be a commit hash; it is
            // not a version qualifier. Numeric build metadata still orders.
            let commaParts = value.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            if commaParts.count == 2, commaParts[1].contains(where: \.isLetter) {
                value = String(commaParts[0])
            }

            let groups = value.split { !$0.isLetter && !$0.isNumber }.map(String.init)
            guard groups.contains(where: { $0.contains(where: \Character.isNumber) }) else { return nil }

            var tokens: [Token] = []
            for (groupIndex, group) in groups.enumerated() {
                if Self.isPackagingGroup(group) { break }
                if Self.ignoredLabels.contains(group) { continue }
                var previousWasNumber = false
                for identifier in Self.identifiers(in: group) {
                    if case let .text(label) = identifier, Self.ignoredLabels.contains(label) {
                        previousWasNumber = false
                        continue
                    }
                    tokens.append(Token(identifier: identifier, attachedToNumber: previousWasNumber, group: groupIndex))
                    if case .number = identifier { previousWasNumber = true } else { previousWasNumber = false }
                }
            }

            var core: [NumericIdentifier] = []
            var postRelease: [NumericIdentifier] = []
            var prerelease: Prerelease?

            var index = 0
            tokenLoop: while index < tokens.count {
                let token = tokens[index]
                switch token.identifier {
                case let .number(number):
                    if prerelease == nil { core.append(number) }
                    else { prerelease?.identifiers.append(.number(number)) }
                case let .text(label):
                    // Some package managers include the package name before the version.
                    guard !core.isEmpty || prerelease != nil else { break }
                    if prerelease == nil, token.attachedToNumber,
                       let post = Self.postReleaseValue(label: label, group: token.group,
                                                        remaining: tokens[(index + 1)...]) {
                        postRelease = post
                        break tokenLoop
                    }
                    if prerelease == nil {
                        prerelease = Prerelease(label: label)
                    } else {
                        prerelease?.identifiers.append(.text(label))
                    }
                }
                index += 1
            }

            guard !core.isEmpty else { return nil }
            self.core = core
            self.postRelease = postRelease
            self.prerelease = prerelease
        }

        /// A single trailing letter ("1.1.1w", "9e") or "p" plus a number
        /// ("9.9p1") is a post-release. A bare "a" or "b" ("2.0b") stays an
        /// alpha or beta, as most app publishers mean it; Homebrew's stable
        /// formula versions use `isHomebrewPrerelease`. Numbers in later
        /// groups, such as a Homebrew revision ("1.1.1w_1"), extend it.
        private static func postReleaseValue(label: String, group: Int,
                                             remaining: ArraySlice<Token>) -> [NumericIdentifier]? {
            var rest = remaining
            var value: [NumericIdentifier]
            if label.count == 1, label != "a", label != "b",
               let ascii = label.unicodeScalars.first?.value, (97...122).contains(ascii),
               rest.first.map({ $0.group != group }) ?? true {
                value = [NumericIdentifier(String(ascii - 96))]
            } else if label == "p", let next = rest.first, next.group == group,
                      case let .number(number) = next.identifier {
                value = [number]
                rest = rest.dropFirst()
            } else {
                return nil
            }
            for token in rest {
                guard token.group != group, case let .number(number) = token.identifier else { return nil }
                value.append(number)
            }
            return value
        }

        fileprivate static let ignoredLabels: Set<String> = [
            "app", "build", "final", "release", "stable"
        ]

        fileprivate static let packagingLabels: Set<String> = [
            "darwin", "mac", "macos", "osx", "universal", "universal2",
            "linux", "windows", "win", "x64", "x86", "x86_64", "amd64",
            "arm", "arm64", "aarch64"
        ]

        private static func isPackagingGroup(_ group: String) -> Bool {
            if packagingLabels.contains(group) { return true }
            return packagingLabels.contains { label in
                group.hasPrefix(label) && !group.dropFirst(label.count).isEmpty &&
                    group.dropFirst(label.count).allSatisfy(\.isNumber)
            }
        }

        private static func removingVersionPrefix(from value: String) -> String {
            var output = value
            for prefix in ["version", "release"] where output.hasPrefix(prefix) {
                output.removeFirst(prefix.count)
                output = output.trimmingCharacters(in: CharacterSet(charactersIn: " .:_-"))
                break
            }
            if output.first == "v", output.dropFirst().first?.isNumber == true {
                output.removeFirst()
            }
            return output
        }

        private static func identifiers(in group: String) -> [Identifier] {
            var result: [Identifier] = []
            var current = ""
            var isNumeric: Bool?

            func appendCurrent() {
                guard let numeric = isNumeric, !current.isEmpty else { return }
                result.append(numeric ? .number(NumericIdentifier(current)) : .text(current))
            }

            for character in group {
                let numeric = character.isNumber
                if let isNumeric, isNumeric != numeric {
                    appendCurrent()
                    current = ""
                }
                current.append(character)
                isNumeric = numeric
            }
            appendCurrent()
            return result
        }
    }

    private struct Prerelease {
        static let unknownRank = 25

        let label: String
        let rank: Int
        var identifiers: [Identifier] = []

        init(label: String) {
            self.label = label
            switch label {
            case "dev", "nightly", "snapshot": rank = 0
            case "a", "alpha": rank = 10
            case "b", "beta": rank = 20
            case "pre", "preview": rank = 30
            case "rc": rank = 40
            default: rank = Self.unknownRank
            }
        }
    }

    private enum Identifier {
        case number(NumericIdentifier)
        case text(String)
    }

    /// Numeric strings are compared without converting to Int, avoiding overflow for long build numbers.
    private struct NumericIdentifier: Equatable, Comparable {
        let digits: String

        init(_ value: String) {
            let trimmed = value.drop(while: { $0 == "0" })
            digits = trimmed.isEmpty ? "0" : String(trimmed)
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.digits.count != rhs.digits.count { return lhs.digits.count < rhs.digits.count }
            return lhs.digits < rhs.digits
        }
    }

    private static func compareNumericSequences(
        _ lhs: [NumericIdentifier],
        _ rhs: [NumericIdentifier]
    ) -> ComparisonResult {
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : NumericIdentifier("0")
            let right = index < rhs.count ? rhs[index] : NumericIdentifier("0")
            if left != right { return left > right ? .orderedDescending : .orderedAscending }
        }
        return .orderedSame
    }

    private static func comparePrereleaseIdentifiers(
        _ lhs: [Identifier],
        _ rhs: [Identifier]
    ) -> ComparisonResult {
        for index in 0..<min(lhs.count, rhs.count) {
            let result: ComparisonResult
            switch (lhs[index], rhs[index]) {
            case let (.number(left), .number(right)):
                result = left == right ? .orderedSame : (left > right ? .orderedDescending : .orderedAscending)
            case let (.text(left), .text(right)):
                result = left == right ? .orderedSame : left.localizedStandardCompare(right)
            case (.number, .text):
                result = .orderedAscending
            case (.text, .number):
                result = .orderedDescending
            }
            if result != .orderedSame { return result }
        }
        if lhs.count == rhs.count { return .orderedSame }
        return lhs.count > rhs.count ? .orderedDescending : .orderedAscending
    }
}
