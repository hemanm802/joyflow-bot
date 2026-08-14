import Foundation

public enum ThreadEditError: Error, Equatable, Sendable {
    case messageNotFound
    case notUserMessage
    case emptyText
}

/// Rewrites a user turn and drops every later message in the same thread.
public enum ThreadEdit {
    public static func apply(
        messages: [ChatMessageRecord],
        id: UUID,
        text: String
    ) throws -> [ChatMessageRecord] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ThreadEditError.emptyText }
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            throw ThreadEditError.messageNotFound
        }
        guard messages[index].role == "user" else { throw ThreadEditError.notUserMessage }
        var kept = Array(messages.prefix(index + 1))
        kept[index].content = trimmed
        return kept
    }

    /// The user text the next assistant turn must answer after an edit.
    public static func resendPrompt(from messages: [ChatMessageRecord]) -> String? {
        messages.last(where: { $0.role == "user" })?.content
    }

    /// Removes one user or assistant turn. Later messages stay.
    public static func delete(
        messages: [ChatMessageRecord],
        id: UUID
    ) throws -> [ChatMessageRecord] {
        guard messages.contains(where: { $0.id == id }) else {
            throw ThreadEditError.messageNotFound
        }
        return messages.filter { $0.id != id }
    }
}
