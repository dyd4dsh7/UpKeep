import Foundation

/// Converts the HTML that Sparkle appcasts commonly use for release notes into the Markdown
/// subset `ReleaseNotesFormatter` renders, so headings, paragraphs, lists, emphasis, and
/// links keep their structure instead of running together once tags are removed.
enum ReleaseNotesHTML {
    /// True when the text contains common HTML tags. Plain text and Markdown (including
    /// `<https://…>` autolinks) are left alone.
    static func isHTML(_ text: String) -> Bool {
        let knownTag = /<\/?(?:p|br|hr|ul|ol|li|h[1-6]|div|span|b|strong|i|em|a|code|pre|blockquote|table|tr|td|th|section|font|small|img)\b[^>]*>/
            .ignoresCase()
        return text.contains(knownTag)
    }

    static func markdown(fromHTML html: String) -> String {
        let source = html
            .replacing(/<!--[\s\S]*?-->/, with: "")
            .replacing(/<script\b[^>]*>[\s\S]*?<\/script\s*>/.ignoresCase(), with: "")
            .replacing(/<style\b[^>]*>[\s\S]*?<\/style\s*>/.ignoresCase(), with: "")
        var writer = Writer()
        var index = source.startIndex
        for match in source.matches(of: /<(\/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*)>/) {
            writer.text(String(source[index..<match.range.lowerBound]))
            writer.tag(
                name: match.output.2.lowercased(),
                isClosing: !match.output.1.isEmpty,
                attributes: String(match.output.3)
            )
            index = match.range.upperBound
        }
        writer.text(String(source[index...]))
        return writer.result
    }

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

        private var output = ""
        private var atLineStart = true
        private var inlineMarkers: [InlineMarker] = []
        private var lists: [ListKind] = []
        private var links: [String?] = []

        var result: String {
            output
                .replacing(/[ \t]+\n/, with: "\n")
                .replacing(/\n{3,}/, with: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        mutating func text(_ raw: String) {
            let collapsed = raw.replacing(/\s+/, with: " ")
            var text = Self.escapeMarkdown(ReleaseNotesHTML.decodeEntities(collapsed))
            if atLineStart { text = String(text.drop { $0 == " " }) }
            guard !text.isEmpty else { return }
            let leading = text.prefix { $0 == " " }
            let visible = text.dropFirst(leading.count)
            output += leading
            guard !visible.isEmpty else { return }
            for index in inlineMarkers.indices where !inlineMarkers[index].isOpen {
                output += inlineMarkers[index].opening
                inlineMarkers[index].isOpen = true
            }
            output += visible
            atLineStart = false
        }

        mutating func tag(name: String, isClosing: Bool, attributes: String) {
            switch name {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                breakLines(2)
                if !isClosing {
                    output += String(repeating: "#", count: Int(String(name.last!)) ?? 1) + " "
                }
            case "p", "blockquote", "pre", "table":
                breakLines(2)
            case "div", "section", "header", "footer", "tr", "dl", "dt", "dd":
                breakLines(1)
            case "br":
                closeOpenMarkersForLineBreak()
                output += "\n"
                atLineStart = true
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
