import Foundation

/// Older turns folded into a short recap so the model and the UI stay light.
public struct CompactedHistory: Sendable, Equatable {
    public var summary: String?
    public var kept: [ChatMessageRecord]
    public var folded: [ChatMessageRecord]

    public var foldedCount: Int { folded.count }
    public var isCompacted: Bool { !folded.isEmpty }

    public init(summary: String?, kept: [ChatMessageRecord], folded: [ChatMessageRecord]) {
        self.summary = summary
        self.kept = kept
        self.folded = folded
    }
}

public enum ChatCompaction: Sendable {
    public static let keepRecent = 16
    public static let maxChars = 12_000
    public static let minFold = 4
    public static let lineLimit = 160

    public static func apply(_ messages: [ChatMessageRecord]) -> CompactedHistory {
        let total = characterCount(messages)
        guard messages.count >= keepRecent + minFold || total > maxChars else {
            return CompactedHistory(summary: nil, kept: messages, folded: [])
        }

        var foldEnd = max(0, messages.count - keepRecent)
        foldEnd = alignedFoldEnd(messages, proposed: foldEnd)

        while foldEnd < messages.count - 2, characterCount(Array(messages[foldEnd...])) > maxChars {
            var next = foldEnd + 2
            next = alignedFoldEnd(messages, proposed: next)
            if next <= foldEnd { break }
            foldEnd = next
        }

        if foldEnd < minFold || foldEnd >= messages.count {
            return CompactedHistory(summary: nil, kept: messages, folded: [])
        }

        let folded = Array(messages.prefix(foldEnd))
        let kept = Array(messages.suffix(from: foldEnd))
        return CompactedHistory(summary: summarize(folded), kept: kept, folded: folded)
    }

    public static func title(from messages: [ChatMessageRecord]) -> String {
        let raw = messages.first(where: { $0.role == "user" })?.content
            ?? messages.first?.content
            ?? ""
        return clipTitle(raw)
    }

    public static func preview(from messages: [ChatMessageRecord]) -> String {
        guard let last = messages.last else { return "New chat" }
        let line = plain(firstLine(last.content))
        return line.isEmpty ? "New chat" : line
    }

    public static func clipTitle(_ text: String) -> String {
        let line = plain(firstLine(text))
        if line.isEmpty { return "New chat" }
        if line.count <= 56 { return line }
        return String(line.prefix(55)) + "…"
    }

    public static func plain(_ text: String) -> String {
        var cleaned = text
        for mark in ["**", "__", "``", "`", "*", "_"] {
            cleaned = cleaned.replacingOccurrences(of: mark, with: "")
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Instruction prepended when older turns were folded.
    public static func promptBlock(summary: String) -> String {
        """
        Earlier in this chat was compacted. Treat it as prior context and keep going. Do not retell it unless asked.

        \(summary)
        """
    }

    private static func alignedFoldEnd(_ messages: [ChatMessageRecord], proposed: Int) -> Int {
        var foldEnd = min(max(0, proposed), messages.count)
        while foldEnd < messages.count, messages[foldEnd].role != "user" {
            foldEnd += 1
        }
        return foldEnd
    }

    private static func summarize(_ folded: [ChatMessageRecord]) -> String {
        folded.map { message in
            let who = message.role == "user" ? "User" : "Joyflow"
            return "\(who): \(clipLine(firstLine(message.content), limit: lineLimit))"
        }.joined(separator: "\n")
    }

    private static func characterCount(_ messages: [ChatMessageRecord]) -> Int {
        messages.reduce(0) { $0 + $1.content.count }
    }

    private static func firstLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func clipLine(_ text: String, limit: Int) -> String {
        if text.count <= limit { return text }
        return String(text.prefix(limit - 1)) + "…"
    }
}

public struct ThreadSummary: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var preview: String
    public var createdAt: Date
    public var updatedAt: Date
    public var messageCount: Int

    public init(
        id: UUID,
        title: String,
        preview: String,
        createdAt: Date,
        updatedAt: Date,
        messageCount: Int
    ) {
        self.id = id
        self.title = title
        self.preview = preview
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messageCount = messageCount
    }

    public static func draft(id: UUID, now: Date = Date()) -> ThreadSummary {
        ThreadSummary(
            id: id,
            title: "New chat",
            preview: "New chat",
            createdAt: now,
            updatedAt: now,
            messageCount: 0
        )
    }
}
