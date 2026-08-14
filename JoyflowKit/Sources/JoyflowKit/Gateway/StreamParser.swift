import Foundation

public enum StreamEvent: Sendable, Equatable {
    case text(String)
    case reasoning(String)
    case reasoningDetail(ReasoningDetail)
    case toolCall(ToolCallDelta)
    case finished
    case error(String)
}

public struct ToolCallDelta: Sendable, Equatable {
    public var index: Int
    public var id: String?
    public var name: String?
    public var argumentsFragment: String

    public init(index: Int, id: String?, name: String?, argumentsFragment: String) {
        self.index = index
        self.id = id
        self.name = name
        self.argumentsFragment = argumentsFragment
    }
}

public struct StreamParser: Sendable {
    public var insideThink = false

    public init() {}

    public mutating func parse(buffer: inout String) -> [StreamEvent] {
        var events: [StreamEvent] = []
        while let range = buffer.range(of: "\n") {
            let line = String(buffer[buffer.startIndex..<range.lowerBound])
            buffer.removeSubrange(buffer.startIndex...range.lowerBound)
            events.append(contentsOf: parseLine(line))
        }
        return events
    }

    public mutating func finish(buffer: inout String) -> [StreamEvent] {
        let leftover = buffer
        buffer = ""
        let trimmed = leftover.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return parseLine(trimmed)
    }

    public mutating func parseLine(_ raw: String) -> [StreamEvent] {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty || line.hasPrefix(":") { return [] }
        guard line.hasPrefix("data:") else { return [] }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return [.finished] }
        return parseJSON(payload)
    }

    public func parseHTTPError(status: Int, body: String) -> StreamEvent {
        if let data = body.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            if let err = obj["error"] as? [String: Any], let message = err["message"] as? String {
                return .error("HTTP \(status): \(message)")
            }
            if let message = obj["message"] as? String {
                return .error("HTTP \(status): \(message)")
            }
        }
        return .error("HTTP \(status): \(body)")
    }

    private mutating func parseJSON(_ payload: String) -> [StreamEvent] {
        guard let data = payload.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        if let error = obj["error"] as? [String: Any], let message = error["message"] as? String {
            return [.error(message)]
        }
        guard let choices = obj["choices"] as? [[String: Any]], let first = choices.first else { return [] }
        var events: [StreamEvent] = []
        let delta = (first["delta"] as? [String: Any]) ?? (first["message"] as? [String: Any]) ?? [:]
        events.append(contentsOf: extractReasoning(from: delta))
        events.append(contentsOf: extractContent(from: delta["content"]))
        if let refusal = Self.nonEmptyString(delta["refusal"]) {
            events.append(.text(refusal))
        }
        if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
            for call in toolCalls {
                let index = call["index"] as? Int ?? 0
                let function = call["function"] as? [String: Any] ?? [:]
                events.append(
                    .toolCall(
                        ToolCallDelta(
                            index: index,
                            id: call["id"] as? String,
                            name: function["name"] as? String,
                            argumentsFragment: function["arguments"] as? String ?? ""
                        )
                    )
                )
            }
        }
        if let reason = first["finish_reason"] as? String,
            ["stop", "tool_calls", "end_turn", "length"].contains(reason)
        {
            events.append(.finished)
        }
        return events
    }

    private func extractReasoning(from delta: [String: Any]) -> [StreamEvent] {
        var events: [StreamEvent] = []
        var visible: [String] = []
        if let text = Self.nonEmptyString(delta["reasoning"]) {
            visible.append(text)
        } else if let text = Self.nonEmptyString(delta["reasoning_content"]) {
            visible.append(text)
        } else if let text = Self.nonEmptyString(delta["thinking"]) {
            visible.append(text)
        } else if let object = delta["reasoning"] as? [String: Any],
            let text = Self.nonEmptyString(object["text"]) ?? Self.nonEmptyString(object["content"])
        {
            visible.append(text)
        }

        var detailText: [String] = []
        if let details = delta["reasoning_details"] as? [[String: Any]] {
            for raw in details {
                if let detail = ReasoningDetail(json: raw) {
                    events.append(.reasoningDetail(detail))
                    if let text = Self.nonEmptyString(detail.text) ?? Self.nonEmptyString(detail.summary) {
                        detailText.append(text)
                    }
                }
            }
        }

        if visible.isEmpty {
            visible = detailText
        }
        events.insert(contentsOf: visible.map { .reasoning($0) }, at: 0)
        return events
    }

    private mutating func extractContent(from raw: Any?) -> [StreamEvent] {
        var events: [StreamEvent] = []
        if let text = Self.nonEmptyString(raw) {
            events.append(contentsOf: splitThinkTags(text))
        } else if let parts = raw as? [[String: Any]] {
            for part in parts {
                let type = (part["type"] as? String) ?? "text"
                let text = Self.nonEmptyString(part["text"])
                    ?? Self.nonEmptyString(part["thinking"])
                    ?? Self.nonEmptyString(part["content"])
                guard let text else { continue }
                if type == "thinking" || type == "reasoning" {
                    events.append(.reasoning(text))
                } else {
                    events.append(contentsOf: splitThinkTags(text))
                }
            }
        }
        return events
    }

    private mutating func splitThinkTags(_ text: String) -> [StreamEvent] {
        var events: [StreamEvent] = []
        var remaining = text
        while !remaining.isEmpty {
            if insideThink {
                if let end = remaining.range(of: "</think>", options: .caseInsensitive) {
                    let body = String(remaining[remaining.startIndex..<end.lowerBound])
                    if !body.isEmpty { events.append(.reasoning(body)) }
                    remaining = String(remaining[end.upperBound...])
                    insideThink = false
                } else {
                    events.append(.reasoning(remaining))
                    remaining = ""
                }
            } else if let start = remaining.range(of: "<think>", options: .caseInsensitive) {
                let before = String(remaining[remaining.startIndex..<start.lowerBound])
                if !before.isEmpty { events.append(.text(before)) }
                remaining = String(remaining[start.upperBound...])
                insideThink = true
            } else {
                events.append(.text(remaining))
                remaining = ""
            }
        }
        return events
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        return text.isEmpty ? nil : text
    }
}
