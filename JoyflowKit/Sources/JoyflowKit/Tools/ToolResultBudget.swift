import Foundation

/// Shrinks tool results before they become the next-turn `tool` message.
/// Gmail-sized Composio dumps keep ids / from / to / subject / date / snippet
/// and stay well under the model’s 500_000-token prompt window.
public enum ToolResultBudget: Sendable {
    /// One tool result. Leaves most of the 500k-token window for history + reply.
    public static let maxCharacters = 80_000
    public static let snippetCharacters = 240
    public static let maxMessages = 80
    public static let modelTokenLimit = 500_000
    /// High-token estimate (JSON / HTML). `characters / 3` ≈ tokens.
    public static let conservativeCharsPerToken = 3

    public static func estimatedTokens(_ text: String) -> Int {
        let bytes = text.utf8.count
        guard bytes > 0 else { return 0 }
        return (bytes + conservativeCharsPerToken - 1) / conservativeCharsPerToken
    }

    public static func estimatedTokens(data: Data) -> Int {
        guard !data.isEmpty else { return 0 }
        return (data.count + conservativeCharsPerToken - 1) / conservativeCharsPerToken
    }

    public static func reduce(_ raw: String) -> String {
        guard raw.utf8.count > maxCharacters else { return raw }
        if let compact = compactEmailJSON(raw) {
            return enforceCap(compact)
        }
        if let compact = compactAnyJSON(raw) {
            return enforceCap(compact)
        }
        return enforceCap(raw)
    }

    public static func fitsModelWindow(_ text: String) -> Bool {
        estimatedTokens(text) < modelTokenLimit
    }

    public static func fitsModelWindow(data: Data) -> Bool {
        estimatedTokens(data: data) < modelTokenLimit
    }

    private static func enforceCap(_ text: String) -> String {
        guard text.utf8.count > maxCharacters else { return text }
        let note = "\n…[truncated for prompt budget]"
        let budget = max(0, maxCharacters - note.utf8.count)
        var bytes = Array(text.utf8.prefix(budget))
        while !bytes.isEmpty, String(bytes: bytes, encoding: .utf8) == nil {
            bytes.removeLast()
        }
        return (String(bytes: bytes, encoding: .utf8) ?? "") + note
    }

    private static func compactEmailJSON(_ raw: String) -> String? {
        guard let root = parseJSON(raw) else { return nil }
        let messages = findMessages(in: root)
        guard !messages.isEmpty else { return nil }

        var payload: [String: Any] = [
            "messages": messages.prefix(maxMessages).map(compactMessage),
            "message_count": messages.count,
        ]
        if messages.count > maxMessages {
            payload["omitted"] = messages.count - maxMessages
            payload["truncated"] = true
        }
        if let object = root as? [String: Any] {
            if let successful = object["successful"] {
                payload["successful"] = successful
            }
            if let error = object["error"], !(error is NSNull) {
                payload["error"] = error
            }
            if let token = firstString(object, keys: ["next_page_token", "nextPageToken", "page_token"]) {
                payload["next_page_token"] = token
            }
        }
        return encodeJSON(payload)
    }

    private static func compactAnyJSON(_ raw: String) -> String? {
        guard let root = parseJSON(raw) else { return nil }
        return encodeJSON(shrink(root, key: ""))
    }

    private static func findMessages(in value: Any) -> [[String: Any]] {
        if let array = value as? [Any] {
            let objects = array.compactMap { $0 as? [String: Any] }
            if !objects.isEmpty, objects.contains(where: isEmailLike) {
                return objects
            }
            for item in array {
                let found = findMessages(in: item)
                if !found.isEmpty { return found }
            }
            return []
        }
        guard let object = value as? [String: Any] else { return [] }
        if isEmailLike(object) { return [object] }
        for key in ["messages", "emails", "items", "threads"] {
            if let nested = object[key], !(nested is NSNull) {
                let found = findMessages(in: nested)
                if !found.isEmpty { return found }
            }
        }
        for key in ["data", "response", "result", "output", "payload"] {
            if let nested = object[key], !(nested is NSNull) {
                let found = findMessages(in: nested)
                if !found.isEmpty { return found }
            }
        }
        for nested in object.values {
            let found = findMessages(in: nested)
            if !found.isEmpty { return found }
        }
        return []
    }

    private static func isEmailLike(_ object: [String: Any]) -> Bool {
        let keys = Set(object.keys.map { $0.lowercased() })
        let hasSubject = keys.contains("subject")
        let hasFrom = keys.contains("from") || keys.contains("sender") || keys.contains("fromemail")
            || keys.contains("sender_email")
        let hasID = keys.contains("id") || keys.contains("messageid") || keys.contains("message_id")
            || keys.contains("threadid")
        return hasSubject || (hasFrom && hasID)
    }

    private static func compactMessage(_ object: [String: Any]) -> [String: Any] {
        var row: [String: Any] = [:]
        if let id = firstString(
            object,
            keys: ["messageId", "message_id", "id", "threadId", "thread_id"]
        ) {
            row["id"] = id
        }
        if let from = firstString(object, keys: ["from", "sender", "fromEmail", "sender_email"]) {
            row["from"] = from
        }
        if let to = firstString(object, keys: ["to", "recipient", "toEmail", "to_email"]) {
            row["to"] = to
        }
        if let subject = firstString(object, keys: ["subject"]) {
            row["subject"] = subject
        }
        if let date = firstString(
            object,
            keys: ["date", "messageTimestamp", "timestamp", "internalDate", "receivedAt", "received_at"]
        ) {
            row["date"] = date
        }
        if let snippet = snippet(from: object) {
            row["snippet"] = snippet
        }
        return row
    }

    private static func snippet(from object: [String: Any]) -> String? {
        if let preview = object["preview"] as? [String: Any],
            let body = firstString(preview, keys: ["body", "text", "snippet"])
        {
            return clipSnippet(body)
        }
        if let preview = object["preview"] as? String {
            return clipSnippet(preview)
        }
        if let text = firstString(
            object,
            keys: ["snippet", "messageText", "text", "body", "preview"]
        ) {
            return clipSnippet(text)
        }
        return nil
    }

    private static func clipSnippet(_ text: String) -> String {
        let stripped = text.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        let collapsed = stripped.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if collapsed.count <= snippetCharacters { return collapsed }
        return String(collapsed.prefix(snippetCharacters - 1)) + "…"
    }

    private static func shrink(_ value: Any, key: String) -> Any {
        if let array = value as? [Any] {
            if array.compactMap({ $0 as? [String: Any] }).contains(where: isEmailLike) {
                return array.prefix(maxMessages).map { item -> Any in
                    if let object = item as? [String: Any], isEmailLike(object) {
                        return compactMessage(object)
                    }
                    return shrink(item, key: key)
                }
            }
            return array.prefix(maxMessages).map { shrink($0, key: key) }
        }
        if let object = value as? [String: Any] {
            var next: [String: Any] = [:]
            for (childKey, child) in object {
                next[childKey] = shrink(child, key: childKey)
            }
            return next
        }
        if let text = value as? String, shouldClip(key: key, text: text) {
            return clipSnippet(text)
        }
        return value
    }

    private static func shouldClip(key: String, text: String) -> Bool {
        guard text.utf8.count > snippetCharacters else { return false }
        let lowered = key.lowercased()
        let bulky = [
            "html", "text", "body", "raw", "content", "payload", "messagetext",
            "messagetexthtml", "messagehtml", "preview", "snippet", "data",
        ]
        return bulky.contains { lowered.contains($0) }
    }

    private static func firstString(_ object: [String: Any], keys: [String]) -> String? {
        let mapped = Dictionary(uniqueKeysWithValues: object.keys.map { ($0.lowercased(), $0) })
        for key in keys {
            if let real = mapped[key.lowercased()], let value = stringify(object[real]) {
                return value
            }
        }
        return nil
    }

    private static func stringify(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func parseJSON(_ raw: String) -> Any? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data)
        else { return nil }
        return object
    }

    private static func encodeJSON(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
            let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text
    }
}
