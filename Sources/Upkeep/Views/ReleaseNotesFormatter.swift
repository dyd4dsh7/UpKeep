import Foundation

/// Formats publisher release notes, which are often Markdown (GitHub releases, Sparkle
/// descriptions), for a SwiftUI `Text`. `Text` ignores Markdown block syntax, so headings
/// become bold lines and list items become bullets instead of showing raw `#` and `-`.
enum ReleaseNotesFormatter {
    static func attributedString(from notes: String) -> AttributedString {
        var lines: [AttributedString] = []
        var previousWasBlank = true
        var fence: String?
        // Split on Characters so a CRLF (as GitHub sends) is one line break, not two.
        for rawSubstring in notes.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let rawLine = String(rawSubstring)
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                if line.hasPrefix(open) {
                    fence = nil
                } else {
                    lines.append(code(rawLine))
                    previousWasBlank = false
                }
                continue
            }
            if let marker = line.prefixMatch(of: /`{3,}|~{3,}/) {
                fence = String(marker.output)
                continue
            }
            if line.isEmpty || isHorizontalRule(line) {
                if !previousWasBlank { lines.append(AttributedString()) }
                previousWasBlank = true
                continue
            }
            previousWasBlank = false
            if let heading = headingText(line) {
                lines.append(bold(inline(heading)))
            } else if let item = listItemText(line) {
                let indent = String(repeating: "    ", count: indentLevel(rawLine))
                lines.append(AttributedString("\(indent)• ") + inline(item))
            } else {
                lines.append(inline(line))
            }
        }
        while lines.last?.characters.isEmpty == true { lines.removeLast() }

        var result = AttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 { result += AttributedString("\n") }
            result += line
        }
        return result
    }

    private static func headingText(_ line: String) -> String? {
        guard let match = line.wholeMatch(of: /#{1,6}[ \t]+(.+?)(?:[ \t]+#+)?/) else { return nil }
        return String(match.1)
    }

    private static func listItemText(_ line: String) -> String? {
        guard let match = line.wholeMatch(of: /[-*+][ \t]+(.+)/) else { return nil }
        return String(match.1)
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        line.wholeMatch(of: /([-*_])[ \t]*(?:\1[ \t]*){2,}/) != nil
    }

    private static func indentLevel(_ rawLine: String) -> Int {
        let leading = rawLine.prefix { $0 == " " || $0 == "\t" }
        let width = leading.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        return min(width / 2, 3)
    }

    /// Parses inline Markdown (emphasis, code, links). Links that are not web links are
    /// left as plain text so feed content cannot open arbitrary URL schemes.
    private static func inline(_ text: String) -> AttributedString {
        guard var parsed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else { return AttributedString(text) }
        for run in parsed.runs {
            guard let link = run.link else { continue }
            let scheme = link.scheme?.lowercased()
            if scheme != "https" && scheme != "http" {
                parsed[run.range].link = nil
            }
        }
        return parsed
    }

    /// Fenced code is shown as written, in the code font, without Markdown parsing.
    private static func code(_ line: String) -> AttributedString {
        var text = AttributedString(line)
        text.inlinePresentationIntent = .code
        return text
    }

    private static func bold(_ text: AttributedString) -> AttributedString {
        var text = text
        for run in text.runs {
            let intent = run.inlinePresentationIntent ?? []
            text[run.range].inlinePresentationIntent = intent.union(.stronglyEmphasized)
        }
        return text
    }
}
