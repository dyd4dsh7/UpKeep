import Foundation

enum VersionComparator {
    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        compare(candidate, installed) == .orderedDescending
    }

    static func isPrerelease(_ version: String) -> Bool {
        prereleaseChannel(for: version) != nil || ParsedVersion(version)?.prerelease != nil
    }

    static func prereleaseChannel(for version: String) -> PrereleaseChannel? {
        let value = version.lowercased()
        if value.contains("release candidate") { return .releaseCandidate }
        if value.contains("nightly") { return .nightly }
        if value.contains("snapshot") { return .snapshot }
        if value.contains("alpha") { return .alpha }
        if value.contains("beta") { return .beta }
        if value.contains("preview") { return .preview }
        if let label = ParsedVersion(version)?.prerelease?.label {
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
        return hasHyphenatedQualifier(value) ? .prerelease : nil
    }

    private static func hasHyphenatedQualifier(_ value: String) -> Bool {
        guard let hyphen = value.firstIndex(of: "-") else { return false }
        let release = value[..<hyphen]
        let qualifier = value[value.index(after: hyphen)...]
        return release.contains(".") && release.last?.isNumber == true && qualifier.first?.isLetter == true
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        guard let left = ParsedVersion(lhs), let right = ParsedVersion(rhs) else {
            // An unversioned value such as "latest" must not create an update.
            return .orderedSame
        }

        let coreResult = compareNumericSequences(left.core, right.core)
        if coreResult != .orderedSame { return coreResult }

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
        let result = compare(lhs, rhs)
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

    private struct ParsedVersion {
        let core: [NumericIdentifier]
        let prerelease: Prerelease?

        init?(_ rawValue: String) {
            var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !value.isEmpty else { return nil }

            value = Self.removingVersionPrefix(from: value)
            value = String(value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0])

            let groups = value.split { !$0.isLetter && !$0.isNumber }.map(String.init)
            guard groups.contains(where: { $0.contains(where: \Character.isNumber) }) else { return nil }

            var core: [NumericIdentifier] = []
            var prerelease: Prerelease?

            for group in groups {
                if Self.isPackagingGroup(group) { break }
                if Self.ignoredLabels.contains(group) { continue }
                let identifiers = Self.identifiers(in: group)

                for identifier in identifiers {
                    switch identifier {
                    case let .number(number):
                        if prerelease == nil { core.append(number) }
                        else { prerelease?.identifiers.append(.number(number)) }
                    case let .text(label):
                        if Self.ignoredLabels.contains(label) { continue }
                        // Some package managers include the package name before the version.
                        guard !core.isEmpty || prerelease != nil else { continue }
                        if prerelease == nil {
                            prerelease = Prerelease(label: label)
                        } else {
                            prerelease?.identifiers.append(.text(label))
                        }
                    }
                }
            }

            guard !core.isEmpty else { return nil }
            self.core = core
            self.prerelease = prerelease
        }

        private static let ignoredLabels: Set<String> = [
            "app", "build", "final", "release", "stable"
        ]

        fileprivate static let packagingLabels: Set<String> = [
            "darwin", "mac", "macos", "osx", "universal", "universal2",
            "x64", "x86", "x86_64", "amd64", "arm", "arm64", "aarch64"
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
