import Foundation
import Testing

@testable import JoyflowKit

struct GatewayRequestTests {
    @Test func defaultBaseURL() {
        #expect(JoyflowKit.defaultGatewayURL == "https://ai-gateway.vercel.sh/v1")
        let client = GatewayClient(apiKey: "k", model: JoyflowKit.defaultModelID)
        #expect(client.completionsURL()?.absoluteString == "https://ai-gateway.vercel.sh/v1/chat/completions")
    }

    @Test func requestUsesBearerAndModel() throws {
        let client = GatewayClient(apiKey: "secret", model: "anthropic/claude-opus-4.8")
        let request = try client.makeRequest(
            messages: [ChatMessage(role: "user", content: "Hi")],
            tools: [],
            stream: true
        )
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
        #expect(body?["model"] as? String == "anthropic/claude-opus-4.8")
        #expect(body?["stream"] as? Bool == true)
        let reasoning = body?["reasoning"] as? [String: Any]
        #expect(reasoning?["enabled"] as? Bool == true)
        #expect(reasoning?["effort"] as? String == "medium")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
    }

    @Test func requestEncodesReasoningAndToolChoice() throws {
        let client = GatewayClient(apiKey: "secret", model: "xai/grok-4.6")
        let request = try client.makeRequest(
            messages: [
                ChatMessage(
                    role: "assistant",
                    content: nil,
                    toolCalls: [ToolCall(id: "c1", name: "list_dir", arguments: "{\"path\":\".\"}")],
                    reasoning: "Check the workspace.",
                    reasoningDetails: [
                        ReasoningDetail(
                            type: "reasoning.summary",
                            summary: "Check the workspace.",
                            format: "xai-responses-v1",
                            index: 0
                        ),
                    ],
                )
            ],
            tools: [],
            stream: true,
            toolChoice: "none"
        )
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
        #expect(body?["tool_choice"] as? String == "none")
        let messages = body?["messages"] as? [[String: Any]]
        #expect(messages?.first?["reasoning"] as? String == "Check the workspace.")
        #expect(messages?.first?["reasoning_content"] as? String == "Check the workspace.")
        let details = messages?.first?["reasoning_details"] as? [[String: Any]]
        #expect(details?.first?["summary"] as? String == "Check the workspace.")
    }

    @Test func endpointStoreDoesNotWriteKeys() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("joyflow-ep-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = EndpointStore(rootURL: root)
        try store.save([ModelEndpoint(name: "Default", modelID: JoyflowKit.defaultModelID)])
        let raw = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(!raw.contains("sk-"))
        #expect(!raw.lowercased().contains("apiKey"))
        #expect(try store.load().first?.modelID == JoyflowKit.defaultModelID)
    }
}
