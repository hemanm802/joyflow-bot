import Foundation

public struct ChatMessage: Sendable, Equatable {
    public var role: String
    public var content: String?
    public var toolCallID: String?
    public var name: String?
    public var toolCalls: [ToolCall]?
    public var reasoning: String?
    public var reasoningDetails: [ReasoningDetail]?

    public init(
        role: String,
        content: String? = nil,
        toolCallID: String? = nil,
        name: String? = nil,
        toolCalls: [ToolCall]? = nil,
        reasoning: String? = nil,
        reasoningDetails: [ReasoningDetail]? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCallID = toolCallID
        self.name = name
        self.toolCalls = toolCalls
        self.reasoning = reasoning
        self.reasoningDetails = reasoningDetails
    }
}

public struct ReasoningDetail: Sendable, Equatable, Codable {
    public var type: String
    public var text: String?
    public var summary: String?
    public var data: String?
    public var signature: String?
    public var format: String?
    public var index: Int?

    public init(
        type: String,
        text: String? = nil,
        summary: String? = nil,
        data: String? = nil,
        signature: String? = nil,
        format: String? = nil,
        index: Int? = nil
    ) {
        self.type = type
        self.text = text
        self.summary = summary
        self.data = data
        self.signature = signature
        self.format = format
        self.index = index
    }

    public init?(json: [String: Any]) {
        guard let type = json["type"] as? String, !type.isEmpty else { return nil }
        self.type = type
        self.text = json["text"] as? String
        self.summary = json["summary"] as? String
        self.data = json["data"] as? String
        self.signature = json["signature"] as? String
        self.format = json["format"] as? String
        self.index = json["index"] as? Int
    }

    public mutating func append(_ other: ReasoningDetail) {
        if !other.type.isEmpty { type = other.type }
        if let value = other.text { text = (text ?? "") + value }
        if let value = other.summary { summary = (summary ?? "") + value }
        if let value = other.data { data = value }
        if let value = other.signature { signature = value }
        if let value = other.format { format = value }
        if let value = other.index { index = value }
    }
}

public struct ReasoningBag: Sendable, Equatable {
    public var details: [Int: ReasoningDetail] = [:]

    public init() {}

    public mutating func apply(_ detail: ReasoningDetail) {
        let index = detail.index ?? details.count
        var current = details[index] ?? ReasoningDetail(type: detail.type, format: detail.format, index: index)
        current.append(detail)
        current.index = index
        details[index] = current
    }

    public var ordered: [ReasoningDetail] {
        details.sorted(by: { $0.key < $1.key }).map(\.value)
    }
}

public struct ToolCall: Sendable, Equatable {
    public var id: String
    public var name: String
    public var arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

public struct ToolDefinition: Sendable, Equatable {
    public var name: String
    public var description: String
    public var parametersJSON: String

    public init(name: String, description: String, parametersJSON: String) {
        self.name = name
        self.description = description
        self.parametersJSON = parametersJSON
    }

    public static func objectParams(_ properties: [String: String], required: [String]) -> String {
        let props = properties.map { "\"\($0.key)\":{\"type\":\"\($0.value)\"}" }.joined(separator: ",")
        let req = required.map { "\"\($0)\"" }.joined(separator: ",")
        return "{\"type\":\"object\",\"properties\":{\(props)},\"required\":[\(req)]}"
    }
}

public struct GatewayClient: Sendable {
    public var apiKey: String
    public var baseURL: String
    public var model: String

    public init(apiKey: String, model: String, baseURL: String = JoyflowKit.defaultGatewayURL) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = Self.normalize(baseURL)
    }

    public static func normalize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        if !value.hasSuffix("/v1") { value += "/v1" }
        return value
    }

    public func completionsURL() -> URL? {
        URL(string: baseURL + "/chat/completions")
    }

    public func makeRequest(
        messages: [ChatMessage],
        tools: [ToolDefinition],
        stream: Bool,
        reasoningEffort: String = "medium",
        toolChoice: String? = nil
    ) throws -> URLRequest {
        guard let url = completionsURL() else { throw JoyflowStoreError.io("bad base URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        var body: [String: Any] = [
            "model": model,
            "stream": stream,
            "messages": messages.map(encode(message:)),
            "reasoning": [
                "enabled": reasoningEffort != "none",
                "effort": reasoningEffort,
            ],
        ]
        if let toolChoice {
            body["tool_choice"] = toolChoice
        }
        if !tools.isEmpty {
            body["tools"] = tools.map { tool -> [String: Any] in
                let params =
                    (try? JSONSerialization.jsonObject(with: Data(tool.parametersJSON.utf8)))
                    ?? ["type": "object", "properties": [:]]
                return [
                    "type": "function",
                    "function": [
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": params,
                    ],
                ]
            }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func encode(message: ChatMessage) -> [String: Any] {
        var obj: [String: Any] = ["role": message.role]
        if let content = message.content { obj["content"] = content }
        if let toolCallID = message.toolCallID { obj["tool_call_id"] = toolCallID }
        if let name = message.name { obj["name"] = name }
        if let toolCalls = message.toolCalls {
            obj["tool_calls"] = toolCalls.map { call in
                [
                    "id": call.id,
                    "type": "function",
                    "function": ["name": call.name, "arguments": call.arguments],
                ]
            }
        }
        if let reasoning = message.reasoning, !reasoning.isEmpty {
            obj["reasoning"] = reasoning
            obj["reasoning_content"] = reasoning
        }
        if let details = message.reasoningDetails, !details.isEmpty {
            obj["reasoning_details"] = details.map { detail -> [String: Any] in
                var item: [String: Any] = ["type": detail.type]
                if let value = detail.text { item["text"] = value }
                if let value = detail.summary { item["summary"] = value }
                if let value = detail.data { item["data"] = value }
                if let value = detail.signature { item["signature"] = value }
                if let value = detail.format { item["format"] = value }
                if let value = detail.index { item["index"] = value }
                return item
            }
        }
        return obj
    }
}

public struct ModelEndpoint: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var modelID: String
    public var baseURL: String

    public init(
        id: UUID = UUID(),
        name: String,
        modelID: String,
        baseURL: String = JoyflowKit.defaultGatewayURL
    ) {
        self.id = id
        self.name = name
        self.modelID = modelID
        self.baseURL = baseURL
    }
}

public struct EndpointStore: Sendable {
    public var fileURL: URL

    public init(rootURL: URL) {
        fileURL = rootURL.appendingPathComponent("models.json")
    }

    public func load() throws -> [ModelEndpoint] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([ModelEndpoint].self, from: Data(contentsOf: fileURL))
    }

    public func save(_ endpoints: [ModelEndpoint]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(endpoints).write(to: fileURL)
    }
}
