import Foundation

/// Converts the HTML that Sparkle appcasts commonly use for release notes into the Markdown
/// subset `ReleaseNotesFormatter` renders, so headings, paragraphs, lists, emphasis, and
/// links keep their structure instead of running together once tags are removed.
enum ReleaseNotesHTML {
    /// True when the text contains common HTML tags. Plain text and Markdown (including
    /// `<https://…>` autolinks) are left alone.
    static func isHTML(_ text: String) -> Bool {
        text.matches(of: /<\/?([a-zA-Z][a-zA-Z0-9]*)\b[^>]*>/).contains {
            htmlTagNames.contains($0.output.1.lowercased())
        }
    }

    static func markdown(fromHTML html: String) -> String {
        let source = removingHiddenContent(html)
        var writer = Writer(preservesText: false)
        var index = source.startIndex
        for match in source.matches(of: /<(\/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*)>/) {
            writer.text(String(source[index..<match.range.lowerBound]))
            writer.tag(
                name: match.output.2.lowercased(),
                isClosing: !match.output.1.isEmpty,
                attributes: String(match.output.3),
                original: String(match.output.0)
            )
            index = match.range.upperBound
        }
        writer.text(String(source[index...]))
        return writer.result
    }

    /// GitHub release bodies are Markdown that may embed HTML such as `<details>`,
    /// `<br>`, or `<img>`. Converts those tags and leaves the Markdown, code spans,
    /// fenced code blocks, and autolinks such as `<https://…>` as written.
    static func markdown(fromMarkdownWithHTML text: String) -> String {
        guard isHTML(text) else { return text }
        let source = removingHiddenContent(text)
        var writer = Writer(preservesText: true)
        var fence: Substring?
        for line in source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            if let open = fence {
                if trimmed.hasPrefix(open) { fence = nil }
                writer.text(line + "\n")
                continue
            }
            if let marker = trimmed.prefixMatch(of: /`{3,}|~{3,}/) {
                fence = marker.output
                writer.text(line + "\n")
                continue
            }
            // Table rows must stay on one line, so `<br>` and block tags become spaces.
            writer.isInTableRow = trimmed.hasPrefix("|")
            var index = line.startIndex
            for match in line.matches(of: /(`+[^`]*`+)|<(\/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*)>/) {
                writer.text(String(line[index..<match.range.lowerBound]))
                if match.output.1 != nil {
                    writer.text(String(match.output.0))
                } else if let name = match.output.3 {
                    writer.tag(
                        name: name.lowercased(),
                        isClosing: match.output.2?.isEmpty == false,
                        attributes: String(match.output.4 ?? ""),
                        original: String(match.output.0)
                    )
                }
                index = match.range.upperBound
            }
            writer.text(String(line[index...]) + "\n")
        }
        return writer.result
    }

    private static func removingHiddenContent(_ text: String) -> String {
        text
            .replacing(/<!--[\s\S]*?-->/, with: "")
            .replacing(/<script\b[^>]*>[\s\S]*?<\/script\s*>/.ignoresCase(), with: "")
            .replacing(/<style\b[^>]*>[\s\S]*?<\/style\s*>/.ignoresCase(), with: "")
    }

    /// Tags that are dropped (or converted) rather than kept as text. Anything else in
    /// angle brackets, such as a Markdown autolink, is kept when text is preserved.
    private static let htmlTagNames: Set<String> = [
        "a", "abbr", "b", "blockquote", "br", "center", "code", "dd", "del", "details", "div",
        "dl", "dt", "em", "font", "footer", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr",
        "i", "img", "ins", "kbd", "li", "mark", "ol", "p", "picture", "pre", "s", "section",
        "small", "source", "span", "strike", "strong", "sub", "summary", "sup", "table",
        "tbody", "td", "tfoot", "th", "thead", "tr", "u", "ul", "video"
    ]

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return text.replacing(/&(#[xX][0-9a-fA-F]{1,6}|#[0-9]{1,7}|[a-zA-Z]{2,8});/) { match in
            let entity = String(match.output.1)
            if entity.hasPrefix("#") {
                let isHex = entity.dropFirst().first.map { $0 == "x" || $0 == "X" } ?? false
                let digits = entity.dropFirst(isHex ? 2 : 1)
                if let value = UInt32(digits, radix: isHex ? 16 : 10),
                   let scalar = Unicode.Scalar(value), value != 0 {
                    return String(Character(scalar))
                }
                return String(match.output.0)
            }
            return namedEntities[entity] ?? String(match.output.0)
        }
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "ndash": "–", "mdash": "—", "hellip": "…", "bull": "•", "middot": "·",
        "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
        "copy": "©", "reg": "®", "trade": "™", "rarr": "→", "larr": "←"
    ]

    private struct Writer {
        private enum ListKind { case unordered, ordered(Int) }

        private struct InlineMarker {
            let kind: String
            let opening: String
            let closing: String
            /// Opening markers wait for the next visible text, so `<b> New</b>` becomes
            /// ` **New**` rather than `** New**`, which Markdown would not render.
            var isOpen = false
        }

        /// Markdown mode: text between tags is already Markdown, so it is kept verbatim
        /// instead of being whitespace-collapsed, entity-decoded, and escaped.
        let preservesText: Bool
        var isInTableRow = false
        private var output = ""
        private var atLineStart = true
        /// Set after a tag ends a line, so the source line's own newline is not added too.
        private var tagEndedLine = false
        private var inlineMarkers: [InlineMarker] = []
        private var lists: [ListKind] = []
        private var links: [String?] = []

        var result: String {
            output
                .replacing(/[ \t]+\n/, with: "\n")
                .replacing(/\n{3,}/, with: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        init(preservesText: Bool) {
            self.preservesText = preservesText
        }

        mutating func text(_ raw: String) {
            var text = raw
            if preservesText, tagEndedLine {
                text = String(text.drop { $0.isNewline })
            }
            if !preservesText {
                let collapsed = raw.replacing(/\s+/, with: " ")
                text = Self.escapeMarkdown(ReleaseNotesHTML.decodeEntities(collapsed))
                if atLineStart { text = String(text.drop { $0 == " " }) }
            }
            guard !text.isEmpty else { return }
            tagEndedLine = false
            let leading = text.prefix { $0.isWhitespace }
            let visible = text.dropFirst(leading.count)
            output += leading
            guard !visible.isEmpty else { return }
            for index in inlineMarkers.indices where !inlineMarkers[index].isOpen {
                output += inlineMarkers[index].opening
                inlineMarkers[index].isOpen = true
            }
            output += visible
            atLineStart = output.last?.isNewline == true
        }

        mutating func tag(name: String, isClosing: Bool, attributes: String, original: String) {
            guard ReleaseNotesHTML.htmlTagNames.contains(name) else {
                if preservesText { text(original) }
                return
            }
            if isInTableRow {
                switch name {
                case "b", "strong", "i", "em", "a": break
                case "br", "p", "div", "li", "hr":
                    text(" ")
                    return
                default:
                    return
                }
            }
            switch name {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                breakLines(2)
                if !isClosing {
                    output += String(repeating: "#", count: Int(String(name.last!)) ?? 1) + " "
                }
            case "p", "blockquote", "pre", "table":
                breakLines(2)
            case "div", "section", "header", "footer", "tr", "dl", "dt", "dd", "center":
                breakLines(1)
            case "details":
                breakLines(2)
            case "summary":
                if isClosing {
                    closeInline("b")
                    breakLines(2)
                } else {
                    breakLines(2)
                    openInline("b", opening: "**", closing: "**")
                }
            case "td", "th":
                if isClosing { output += " " }
            case "br":
                closeOpenMarkersForLineBreak()
                output += "\n"
                atLineStart = true
                tagEndedLine = true
            case "hr":
                breakLines(2)
                output += "---"
                breakLines(2)
            case "ul", "ol":
                if isClosing {
                    if !lists.isEmpty { lists.removeLast() }
                    breakLines(lists.isEmpty ? 2 : 1)
                } else {
                    breakLines(lists.isEmpty ? 2 : 1)
                    lists.append(name == "ol" ? .ordered(0) : .unordered)
                }
            case "li":
                breakLines(1)
                if !isClosing { startListItem() }
            case "b", "strong":
                isClosing ? closeInline("b") : openInline("b", opening: "**", closing: "**")
            case "i", "em":
                isClosing ? closeInline("i") : openInline("i", opening: "*", closing: "*")
            case "a":
                if isClosing {
                    if case .some(.some) = links.popLast() { closeInline("a") }
                } else {
                    let href = Self.webLink(in: attributes)
                    links.append(href)
                    if let href { openInline("a", opening: "[", closing: "](<\(href)>)") }
                }
            default:
                break
            }
        }

        private mutating func startListItem() {
            let depth = max(lists.count, 1)
            let indent = String(repeating: "  ", count: depth - 1)
            if case .ordered(let count) = lists.last {
                lists[lists.count - 1] = .ordered(count + 1)
                output += "\(indent)\(count + 1). "
            } else {
                output += "\(indent)- "
            }
            atLineStart = true
        }

        private mutating func openInline(_ kind: String, opening: String, closing: String) {
            inlineMarkers.append(InlineMarker(kind: kind, opening: opening, closing: closing))
        }

        private mutating func closeInline(_ kind: String) {
            guard let index = inlineMarkers.lastIndex(where: { $0.kind == kind }) else { return }
            let marker = inlineMarkers.remove(at: index)
            // A marker that never saw visible text is dropped entirely.
            guard marker.isOpen else { return }
            let trailing = output.reversed().prefix { $0 == " " }.count
            output.removeLast(trailing)
            output += marker.closing + String(repeating: " ", count: trailing)
        }

        /// Markdown emphasis and links cannot span lines, so close open markers before a
        /// line break and reopen them at the next visible text.
        private mutating func closeOpenMarkersForLineBreak() {
            trimTrailingSpaces()
            for index in inlineMarkers.indices.reversed() where inlineMarkers[index].isOpen {
                output += inlineMarkers[index].closing
                inlineMarkers[index].isOpen = false
            }
        }

        private mutating func breakLines(_ count: Int) {
            closeOpenMarkersForLineBreak()
            guard !output.isEmpty else { return }
            let existing = output.reversed().prefix { $0 == "\n" }.count
            if existing < count { output += String(repeating: "\n", count: count - existing) }
            atLineStart = true
            tagEndedLine = true
        }

        private mutating func trimTrailingSpaces() {
            while output.last == " " { output.removeLast() }
        }

        private static func webLink(in attributes: String) -> String? {
            guard let match = attributes.firstMatch(
                of: /href\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/.ignoresCase()
            ) else { return nil }
            let raw = match.output.1 ?? match.output.2 ?? match.output.3 ?? ""
            let href = ReleaseNotesHTML.decodeEntities(String(raw))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: " ", with: "%20")
                .replacingOccurrences(of: "<", with: "%3C")
                .replacingOccurrences(of: ">", with: "%3E")
            guard let scheme = URL(string: href)?.scheme?.lowercased(),
                  scheme == "https" || scheme == "http" else { return nil }
            return href
        }

        /// Text from HTML is literal, so escape characters Markdown would interpret.
        private static func escapeMarkdown(_ text: String) -> String {
            var escaped = ""
            for character in text {
                if "\\`*_[]#<>".contains(character) { escaped.append("\\") }
                escaped.append(character)
            }
            return escaped
        }
    }
}
