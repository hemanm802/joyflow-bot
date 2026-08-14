import Foundation

/// After a reasoning-only or tool-only turn, force a user-visible answer.
public enum ReplyNudge {
    public static let userMessage =
        "Your previous turn had no user-visible answer. Answer the user's last message now in prose. Do not call tools."

    public static let stepBudgetMessage =
        "You hit the tool-step limit. Do not call tools. Tell the user what you already did, whether it worked, and the next concrete step they can take."

    public static func needsVisibleAnswer(text: String, tools: [ToolCall]) -> Bool {
        tools.isEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
