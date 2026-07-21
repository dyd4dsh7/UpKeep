import Foundation

enum VersionComparator {
    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        compare(candidate, installed) == .orderedDescending
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = tokens(in: normalized(lhs))
        let right = tokens(in: normalized(rhs))
        let count = max(left.count, right.count)

        for index in 0..<count {
            let l = index < left.count ? left[index] : .number(0)
            let r = index < right.count ? right[index] : .number(0)
            let result = compare(l, r)
            if result != .orderedSame { return result }
        }
        return .orderedSame
    }

    private enum Token: Equatable {
        case number(Int)
        case text(String)
    }

    private static func normalized(_ value: String) -> String {
        var value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("v") { value.removeFirst() }
        return value
    }

    private static func tokens(in value: String) -> [Token] {
        let groups = value.split { !$0.isLetter && !$0.isNumber }
        return groups.flatMap { group -> [Token] in
            var output: [Token] = []
            var current = ""
            var numeric: Bool?

            for character in group {
                let isNumber = character.isNumber
                if let numeric, numeric != isNumber {
                    output.append(token(current, numeric: numeric))
                    current = ""
                }
                current.append(character)
                numeric = isNumber
            }
            if let numeric, !current.isEmpty {
                output.append(token(current, numeric: numeric))
            }
            return output
        }
    }

    private static func token(_ value: String, numeric: Bool) -> Token {
        numeric ? .number(Int(value) ?? 0) : .text(value)
    }

    private static func compare(_ lhs: Token, _ rhs: Token) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (.number(l), .number(r)):
            if l == r { return .orderedSame }
            return l > r ? .orderedDescending : .orderedAscending
        case let (.text(l), .text(r)):
            if l == r { return .orderedSame }
            return l.localizedStandardCompare(r)
        case (.number, .text):
            return .orderedDescending
        case (.text, .number):
            return .orderedAscending
        }
    }
}
