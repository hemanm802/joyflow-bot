import Foundation

public struct KnowledgeHit: Sendable, Equatable {
    public var title: String
    public var snippet: String
    public var path: String
}

public struct KnowledgeIndex: Sendable {
    public init() {}

    public func search(notes: [NoteRecord], memories: [MemoryRecord], query: String) -> [KnowledgeHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        var hits: [KnowledgeHit] = []
        for note in notes where note.body.lowercased().contains(needle) || note.title.lowercased().contains(needle) {
            hits.append(KnowledgeHit(title: note.title, snippet: snippet(note.body, needle: needle), path: note.slug))
        }
        for memory in memories where memory.text.lowercased().contains(needle) {
            hits.append(KnowledgeHit(title: "Memory", snippet: snippet(memory.text, needle: needle), path: "memories"))
        }
        return hits
    }

    private func snippet(_ text: String, needle: String) -> String {
        let lower = text.lowercased()
        if let range = lower.range(of: needle) {
            let start = text.index(range.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
            let end = text.index(range.upperBound, offsetBy: 80, limitedBy: text.endIndex) ?? text.endIndex
            return String(text[start..<end])
        }
        return String(text.prefix(120))
    }
}
