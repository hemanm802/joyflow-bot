import Foundation

/// One run of visible text. `isCode` marks inline code; `visibleText` never includes backticks.
public struct KnowledgeSpan: Sendable, Equatable {
    public var text: String
    public var isCode: Bool
    public var url: String?

    public init(text: String, isCode: Bool, url: String? = nil) {
        self.text = text
        self.isCode = isCode
        self.url = url
    }

    public var visibleText: String { text }
    public var isLink: Bool { url != nil }
}

public struct KnowledgeListItem: Sendable, Equatable, Identifiable {
    public var id: Int
    public var spans: [KnowledgeSpan]
    public var ordinal: Int?

    public init(id: Int, spans: [KnowledgeSpan], ordinal: Int? = nil) {
        self.id = id
        self.spans = spans
        self.ordinal = ordinal
    }

    public var visibleText: String {
        spans.map(\.visibleText).joined()
    }
}

/// A display block parsed from knowledge markdown. Visible text has no `#` / `- ` markers.
public struct KnowledgeBlock: Sendable, Equatable, Identifiable {
    public var id: Int
    public var kind: Kind

    public enum Kind: Sendable, Equatable {
        case heading(level: Int, text: String)
        case paragraph([KnowledgeSpan])
        case list([KnowledgeListItem])
    }

    public init(id: Int, kind: Kind) {
        self.id = id
        self.kind = kind
    }

    public var visibleText: String {
        switch kind {
        case .heading(_, let text):
            text
        case .paragraph(let spans):
            spans.map(\.visibleText).joined()
        case .list(let items):
            items.map(\.visibleText).joined(separator: "\n")
        }
    }
}

/// UI-free markdown → display transform for Soul and other knowledge files.
public struct KnowledgeDocument: Sendable, Equatable {
    public var blocks: [KnowledgeBlock]

    public init(blocks: [KnowledgeBlock]) {
        self.blocks = blocks
    }

    public var headings: [String] {
        blocks.compactMap { block in
            if case .heading(_, let text) = block.kind { return text }
            return nil
        }
    }

    public var listItems: [KnowledgeListItem] {
        blocks.flatMap { block -> [KnowledgeListItem] in
            if case .list(let items) = block.kind { return items }
            return []
        }
    }

    public var links: [KnowledgeSpan] {
        allSpans.filter(\.isLink)
    }

    public var inlineCode: [String] {
        allSpans.filter(\.isCode).map(\.visibleText)
    }

    private var allSpans: [KnowledgeSpan] {
        blocks.flatMap { block -> [KnowledgeSpan] in
            switch block.kind {
            case .heading:
                []
            case .paragraph(let spans):
                spans
            case .list(let items):
                items.flatMap(\.spans)
            }
        }
    }

    public var visibleText: String {
        blocks.map(\.visibleText).joined(separator: "\n")
    }

    public static func parse(_ markdown: String) -> KnowledgeDocument {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [KnowledgeBlock] = []
        var nextID = 0
        var index = 0

        func takeID() -> Int {
            defer { nextID += 1 }
            return nextID
        }

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }
            if let heading = heading(from: trimmed) {
                blocks.append(KnowledgeBlock(id: takeID(), kind: .heading(level: heading.level, text: heading.text)))
                index += 1
                continue
            }
            if let marker = listMarker(trimmed) {
                if let split = extractInlineNumbered(trimmed), split.items.count >= 2 {
                    appendParagraph(trimmed, into: &blocks, takeID: takeID)
                    index += 1
                    continue
                }
                var items: [KnowledgeListItem] = []
                items.append(
                    KnowledgeListItem(id: takeID(), spans: spans(from: marker.rest), ordinal: marker.ordinal)
                )
                index += 1
                while index < lines.count {
                    let itemLine = lines[index].trimmingCharacters(in: .whitespaces)
                    if itemLine.isEmpty { break }
                    guard let next = listMarker(itemLine) else { break }
                    if marker.ordinal != nil, next.ordinal == nil { break }
                    if marker.ordinal == nil, next.ordinal != nil { break }
                    items.append(
                        KnowledgeListItem(id: takeID(), spans: spans(from: next.rest), ordinal: next.ordinal)
                    )
                    index += 1
                }
                blocks.append(KnowledgeBlock(id: takeID(), kind: .list(items)))
                continue
            }
            var paragraph: [String] = [trimmed]
            index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                if next.isEmpty || heading(from: next) != nil || listMarker(next) != nil { break }
                paragraph.append(next)
                index += 1
            }
            appendParagraph(paragraph.joined(separator: " "), into: &blocks, takeID: takeID)
        }
        return KnowledgeDocument(blocks: blocks)
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        guard line.hasPrefix("#") else { return nil }
        var level = 0
        var rest = line
        while rest.hasPrefix("#") {
            level += 1
            rest.removeFirst()
        }
        guard (1...6).contains(level), rest.hasPrefix(" ") else { return nil }
        return (level, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func appendParagraph(
        _ text: String,
        into blocks: inout [KnowledgeBlock],
        takeID: () -> Int
    ) {
        if let split = extractInlineNumbered(text) {
            if let lead = split.lead {
                blocks.append(KnowledgeBlock(id: takeID(), kind: .paragraph(spans(from: lead))))
            }
            let items = split.items.enumerated().map { index, item in
                KnowledgeListItem(id: takeID(), spans: spans(from: item), ordinal: index + 1)
            }
            blocks.append(KnowledgeBlock(id: takeID(), kind: .list(items)))
            return
        }
        blocks.append(KnowledgeBlock(id: takeID(), kind: .paragraph(spans(from: text))))
    }

    public static func extractInlineNumbered(_ text: String) -> (lead: String?, items: [String])? {
        guard let regex = try? NSRegularExpression(pattern: #"(?:(?<=^)|(?<=\s))(\d{1,2})[.)]\s+"#)
        else { return nil }
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: full)
        guard matches.count >= 2 else { return nil }
        let ordinals: [Int] = matches.compactMap { match in
            Range(match.range(at: 1), in: text).flatMap { Int(text[$0]) }
        }
        guard ordinals.count == matches.count,
            zip(ordinals, ordinals.dropFirst()).allSatisfy({ $0 < $1 })
        else { return nil }

        var items: [String] = []
        for (index, match) in matches.enumerated() {
            guard let start = Range(match.range, in: text)?.upperBound else { continue }
            let end: String.Index
            if index + 1 < matches.count, let next = Range(matches[index + 1].range, in: text)?.lowerBound {
                end = next
            } else {
                end = text.endIndex
            }
            let body = text[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { items.append(body) }
        }
        guard items.count >= 2 else { return nil }
        let leadEnd = Range(matches[0].range, in: text)?.lowerBound ?? text.startIndex
        let lead = String(text[text.startIndex..<leadEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (lead.isEmpty ? nil : lead, items)
    }

    private static func listMarker(_ line: String) -> (ordinal: Int?, rest: String)? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return (nil, String(line.dropFirst(2)))
        }
        guard let regex = try? NSRegularExpression(pattern: #"^(\d{1,3})[.)]\s+"#),
            let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
            let full = Range(match.range, in: line),
            let numberRange = Range(match.range(at: 1), in: line)
        else { return nil }
        return (Int(line[numberRange]), String(line[full.upperBound...]))
    }

    private static func spans(from line: String) -> [KnowledgeSpan] {
        var result: [KnowledgeSpan] = []
        var current = ""
        var inCode = false
        for character in line {
            if character == "`" {
                result.append(contentsOf: emit(current, isCode: inCode))
                current = ""
                inCode.toggle()
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty || result.isEmpty {
            result.append(contentsOf: emit(current, isCode: inCode))
        }
        return result.filter { !$0.text.isEmpty || $0.isCode }
    }

    private static func emit(_ text: String, isCode: Bool) -> [KnowledgeSpan] {
        if isCode { return [KnowledgeSpan(text: text, isCode: true)] }
        return splitLinks(text)
    }

    private static func splitLinks(_ text: String) -> [KnowledgeSpan] {
        guard !text.isEmpty else { return [] }
        let markdown = try? NSRegularExpression(
            pattern: #"\[([^\[\]]+)\]\((https?://[^)\s]+)\)"#
        )
        let bare = try? NSRegularExpression(pattern: #"https?://[^\s<>)\]]+"#)
        var spans: [KnowledgeSpan] = []
        var cursor = text.startIndex
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        let mdMatches = markdown?.matches(in: text, range: full) ?? []
        var index = 0
        while cursor < text.endIndex {
            if index < mdMatches.count, let range = Range(mdMatches[index].range, in: text), range.lowerBound == cursor {
                let match = mdMatches[index]
                let label = Range(match.range(at: 1), in: text).map { String(text[$0]) } ?? ""
                let url = Range(match.range(at: 2), in: text).map { String(text[$0]) }
                spans.append(KnowledgeSpan(text: label, isCode: false, url: url))
                cursor = range.upperBound
                index += 1
                continue
            }
            let nextLink = index < mdMatches.count
                ? Range(mdMatches[index].range, in: text)?.lowerBound ?? text.endIndex
                : text.endIndex
            let chunk = String(text[cursor..<nextLink])
            if let bare {
                spans.append(contentsOf: splitBareURLs(chunk, regex: bare))
            } else if !chunk.isEmpty {
                spans.append(KnowledgeSpan(text: chunk, isCode: false))
            }
            cursor = nextLink
        }
        return spans
    }

    private static func splitBareURLs(_ text: String, regex: NSRegularExpression) -> [KnowledgeSpan] {
        guard !text.isEmpty else { return [] }
        var spans: [KnowledgeSpan] = []
        var cursor = text.startIndex
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: full) {
            guard let range = Range(match.range, in: text) else { continue }
            if cursor < range.lowerBound {
                spans.append(KnowledgeSpan(text: String(text[cursor..<range.lowerBound]), isCode: false))
            }
            var url = String(text[range])
            while url.last == "." || url.last == "," || url.last == ";" {
                url.removeLast()
            }
            spans.append(KnowledgeSpan(text: url, isCode: false, url: url))
            cursor = text.index(range.lowerBound, offsetBy: url.count)
        }
        if cursor < text.endIndex {
            spans.append(KnowledgeSpan(text: String(text[cursor...]), isCode: false))
        }
        return spans
    }
}
