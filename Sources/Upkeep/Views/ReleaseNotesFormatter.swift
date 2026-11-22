import Foundation

/// Formats publisher release notes, which are often Markdown (GitHub releases, Sparkle
/// descriptions), for a SwiftUI `Text`. `Text` ignores Markdown block syntax, so headings
/// become bold lines, list items and table rows become bullets, and quotes get a bar,
/// instead of showing raw `#`, `-`, `|`, and `>`.
enum ReleaseNotesFormatter {
    static func attributedString(from notes: String) -> AttributedString {
        // Split on Characters so a CRLF (as GitHub sends) is one line break, not two.
        let rawLines = notes
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)
        var lines: [AttributedString] = []
        var previousWasBlank = true
        var fence: String?
        var index = 0
        while index < rawLines.count {
            let rawLine = rawLines[index]
            index += 1
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
            if index < rawLines.count, isTableDelimiter(rawLines[index]), let header = tableCells(line) {
                index += 1
                var rows: [[String]] = []
                while index < rawLines.count,
                      let cells = tableCells(rawLines[index].trimmingCharacters(in: .whitespaces)) {
                    rows.append(cells)
                    index += 1
                }
                lines += tableLines(header: header, rows: rows)
            } else if let quote = quoteContent(line) {
                lines.append(quoteLine(depth: quote.depth, text: quote.text))
            } else {
                lines.append(blockLine(line, rawLine: rawLine))
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

    /// A heading, list item, or paragraph line.
    private static func blockLine(_ line: String, rawLine: String) -> AttributedString {
        if let heading = headingText(line) {
            return bold(inline(heading))
        }
        if let item = listItemText(line) {
            let indent = String(repeating: "    ", count: indentLevel(rawLine))
            return AttributedString("\(indent)• ") + inline(item)
        }
        return inline(line)
    }

    // MARK: Quote blocks

    /// Strips `>` markers, returning the nesting depth and the quoted text.
    private static func quoteContent(_ line: String) -> (depth: Int, text: String)? {
        guard line.hasPrefix(">") else { return nil }
        var rest = Substring(line)
        var depth = 0
        while rest.first == ">" {
            depth += 1
            rest = rest.dropFirst()
            if rest.first == " " { rest = rest.dropFirst() }
            if rest.drop(while: { $0 == " " }).first == ">" { rest = rest.drop { $0 == " " } }
        }
        return (depth, String(rest))
    }

    /// Quoted lines keep a bar per nesting level. GitHub alert markers such as
    /// `[!WARNING]` become a bold title.
    private static func quoteLine(depth: Int, text: String) -> AttributedString {
        let bar = String(repeating: "▎ ", count: depth)
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return AttributedString(String(bar.dropLast()))
        }
        if let alert = trimmed.wholeMatch(of: /\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]/.ignoresCase()) {
            return AttributedString(bar) + bold(AttributedString(alert.output.1.lowercased().capitalized))
        }
        return AttributedString(bar) + blockLine(trimmed, rawLine: text)
    }

    // MARK: Tables

    /// A GitHub table's delimiter row, such as `|---|:--:|`.
    private static func isTableDelimiter(_ rawLine: String) -> Bool {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        return line.contains("|")
            && line.wholeMatch(of: /\|?[ \t]*:?-+:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)*\|?/) != nil
    }

    /// Splits a table row on unescaped pipes outside code spans. Returns nil for a line
    /// that is not a table row.
    private static func tableCells(_ line: String) -> [String]? {
        guard line.contains("|") else { return nil }
        var cells: [String] = []
        var cell = ""
        var isEscaped = false
        var inCode = false
        for character in line {
            if isEscaped {
                cell.append(character)
                isEscaped = false
            } else if character == "\\" {
                cell.append(character)
                isEscaped = true
            } else if character == "`" {
                cell.append(character)
                inCode.toggle()
            } else if character == "|" && !inCode {
                cells.append(cell)
                cell = ""
            } else {
                cell.append(character)
            }
        }
        cells.append(cell)
        if line.hasPrefix("|") { cells.removeFirst() }
        if line.hasSuffix("|") && !line.hasSuffix("\\|") && !cells.isEmpty { cells.removeLast() }
        // Cells built from badge images or links often leave runs of spaces behind.
        return cells.map { $0.replacing(/[ \t]{2,}/, with: " ").trimmingCharacters(in: .whitespaces) }
    }

    /// `Text` cannot lay out a grid, and aligned columns wrap badly in a narrow pane, so
    /// each row becomes a bullet: the first cell in bold, then "Column: value" pairs.
    private static func tableLines(header: [String], rows: [[String]]) -> [AttributedString] {
        let separator = AttributedString(" · ")
        func joined(_ parts: [AttributedString]) -> AttributedString {
            var result = AttributedString()
            for (index, part) in parts.enumerated() {
                if index > 0 { result += separator }
                result += part
            }
            return result
        }
        guard !rows.isEmpty else {
            return [bold(joined(header.filter { !$0.isEmpty }.map(inline)))]
        }
        return rows.map { row in
            var parts: [AttributedString] = []
            for (column, cell) in row.enumerated() where !cell.isEmpty {
                if column == 0 {
                    parts.append(bold(inline(cell)))
                } else if column < header.count, !header[column].isEmpty {
                    parts.append(inline(header[column]) + AttributedString(": ") + inline(cell))
                } else {
                    parts.append(inline(cell))
                }
            }
            return AttributedString("• ") + joined(parts)
        }
    }

    // MARK: Lines

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
