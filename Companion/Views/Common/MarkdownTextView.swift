import SwiftUI

/// A block of Markdown: heading, paragraph, list, or code.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case list(items: [String])
    case orderedList(items: [String])
    case code(text: String)

    var text: String {
        switch self {
        case .heading(_, let text), .paragraph(let text), .code(let text):
            return text
        case .list(let items), .orderedList(let items):
            return items.joined(separator: "\n")
        }
    }
}

/// Splits Markdown into blocks for `MarkdownTextView`.
///
/// The parser covers the constructs that server instructions use:
/// headings, paragraphs, bullet and numbered lists, and code fences.
/// It removes image syntax and keeps the alt text,
/// so rendering never loads a remote image.
enum MarkdownBlockParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var listItems: [String] = []
        var orderedItems: [String] = []
        var codeLines: [String]?
        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(text: paragraphLines.joined(separator: " ")))
            paragraphLines = []
        }
        func flushLists() {
            if !listItems.isEmpty {
                blocks.append(.list(items: listItems))
                listItems = []
            }
            if !orderedItems.isEmpty {
                blocks.append(.orderedList(items: orderedItems))
                orderedItems = []
            }
        }
        func flushAll() {
            flushParagraph()
            flushLists()
        }

        for rawLine in markdown.components(separatedBy: "\n") {
            if codeLines != nil {
                if rawLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    blocks.append(.code(text: (codeLines ?? []).joined(separator: "\n")))
                    codeLines = nil
                } else {
                    codeLines?.append(rawLine)
                }
                continue
            }

            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushAll()
                codeLines = []
            } else if trimmed.isEmpty {
                flushAll()
            } else if let heading = heading(in: trimmed) {
                flushAll()
                blocks.append(
                    .heading(level: heading.level, text: strippingImages(heading.text)))
            } else if let item = unorderedItem(in: trimmed) {
                flushParagraph()
                if !orderedItems.isEmpty {
                    blocks.append(.orderedList(items: orderedItems))
                    orderedItems = []
                }
                listItems.append(strippingImages(item))
            } else if let item = orderedItem(in: trimmed) {
                flushParagraph()
                if !listItems.isEmpty {
                    blocks.append(.list(items: listItems))
                    listItems = []
                }
                orderedItems.append(strippingImages(item))
            } else {
                flushLists()
                paragraphLines.append(strippingImages(trimmed))
            }
        }

        if let codeLines {
            blocks.append(.code(text: codeLines.joined(separator: "\n")))
        }
        flushAll()
        return blocks
    }

    /// Replaces image syntax with placeholder text, so no image loads.
    static func strippingImages(_ text: String) -> String {
        var result = text
        for pattern in [#"!\[([^\]]*)\]\([^)]*\)"#, #"!\[([^\]]*)\]\[[^\]]*\]"#] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(
                in: result, range: range, withTemplate: "[Image: $1]")
        }
        return result.replacingOccurrences(of: "[Image: ]", with: "[Image]")
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
        var level = 0
        for character in line {
            guard character == "#" else { break }
            level += 1
        }
        guard level >= 1, level <= 6 else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " || rest.first == "\t" else { return nil }
        return (level, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func unorderedItem(in line: String) -> String? {
        guard let first = line.first, "-*+".contains(first) else { return nil }
        let rest = line.dropFirst()
        guard rest.first == " " || rest.first == "\t" else { return nil }
        return rest.trimmingCharacters(in: .whitespaces)
    }

    private static func orderedItem(in line: String) -> String? {
        var index = line.startIndex
        while index < line.endIndex, line[index].isNumber {
            index = line.index(after: index)
        }
        guard index > line.startIndex, index < line.endIndex,
            line[index] == "." || line[index] == ")"
        else { return nil }
        let rest = line[line.index(after: index)...]
        guard rest.first == " " || rest.first == "\t" else { return nil }
        return rest.trimmingCharacters(in: .whitespaces)
    }
}

/// Renders Markdown blocks with inline formatting.
///
/// Remote images never load: the parser replaces image syntax
/// with placeholder text before rendering.
struct MarkdownTextView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(
                Array(MarkdownBlockParser.parse(markdown).enumerated()), id: \.offset
            ) { _, block in
                blockView(block)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(headingFont(level: level))
        case .paragraph(let text):
            Text(inline(text))
        case .list(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(inline(item))
                    }
                }
            }
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(index + 1).")
                        Text(inline(item))
                    }
                }
            }
        case .code(let text):
            Text(text)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .title3.bold()
        case 2: return .headline
        default: return .subheadline.bold()
        }
    }

    private func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options))
            ?? AttributedString(text)
    }
}
