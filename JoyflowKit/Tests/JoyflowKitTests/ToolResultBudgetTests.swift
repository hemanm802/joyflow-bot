import Foundation
import Testing

@testable import JoyflowKit

struct ToolResultBudgetTests {
    @Test func hugeGmailJSONKeepsFieldsAndFitsBudget() {
        let raw = Self.gmailPayload(messages: 220, htmlChars: 12_000)
        #expect(ToolResultBudget.estimatedTokens(raw) > ToolResultBudget.modelTokenLimit)

        let reduced = ToolResultBudget.reduce(raw)
        #expect(reduced.utf8.count <= ToolResultBudget.maxCharacters)
        #expect(ToolResultBudget.fitsModelWindow(reduced))
        #expect(ToolResultBudget.estimatedTokens(reduced) < ToolResultBudget.modelTokenLimit)

        #expect(reduced.contains("msg-0"))
        #expect(reduced.contains("alice@example.com"))
        #expect(reduced.contains("bob@example.com"))
        #expect(reduced.contains("Invoice 0"))
        #expect(reduced.contains("2026-01-02"))
        #expect(reduced.contains("Payment due"))
        #expect(!reduced.contains("<html"))
        #expect(!reduced.contains(String(repeating: "X", count: 1_000)))
    }

    @Test func dispatcherReducesComposioExecuteBody() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "joyflow-budget-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileProjectStore(rootURL: root)
        let project = try store.createProject(name: "Mail")
        let computer = try ComputerRouter.computer(
            .local,
            workspace: store.layout(for: project.id).workspace,
            credentials: .empty
        )
        let raw = Self.gmailPayload(messages: 180, htmlChars: 10_000)
        #expect(ToolResultBudget.estimatedTokens(raw) > ToolResultBudget.modelTokenLimit)

        let transport = RecordingComposioTransport()
        transport.executeResponse = Data(raw.utf8)
        let dispatcher = ToolDispatcher(
            store: store,
            projectID: project.id,
            computer: computer,
            composioKey: "secret",
            composioTransport: transport,
            lookupCLI: false
        )
        let body = try await dispatcher.execute(
            name: "composio_execute",
            argumentsJSON:
                #"{"tool_slug":"GMAIL_FETCH_EMAILS","connected_account_id":"ca_1","arguments_json":"{\"limit\":180}"}"#
        )
        #expect(transport.calls.contains { $0.url.hasSuffix("/tools/execute/GMAIL_FETCH_EMAILS") })
        #expect(body.utf8.count <= ToolResultBudget.maxCharacters)
        #expect(ToolResultBudget.fitsModelWindow(body))
        #expect(body.contains("Invoice 1"))
        #expect(body.contains("alice@example.com"))
        #expect(body.contains("msg-1"))
    }

    @Test func nextTurnRequestStaysUnderModelWindow() throws {
        let raw = Self.gmailPayload(messages: 200, htmlChars: 12_000)
        let reduced = ToolResultBudget.reduce(raw)
        let client = GatewayClient(apiKey: "k", model: JoyflowKit.defaultModelID)
        let tools = ToolCatalog.definitions

        let bloated = try client.makeRequest(
            messages: Self.nextTurnHistory(toolBody: raw),
            tools: tools,
            stream: true
        )
        let bloatedBody = bloated.httpBody ?? Data()
        #expect(ToolResultBudget.estimatedTokens(data: bloatedBody) > ToolResultBudget.modelTokenLimit)

        let request = try client.makeRequest(
            messages: Self.nextTurnHistory(toolBody: reduced),
            tools: tools,
            stream: true
        )
        let body = request.httpBody ?? Data()
        #expect(!body.isEmpty)
        #expect(ToolResultBudget.fitsModelWindow(data: body))
        #expect(ToolResultBudget.estimatedTokens(data: body) < ToolResultBudget.modelTokenLimit)

        let text = String(data: body, encoding: .utf8) ?? ""
        #expect(text.contains("what's in my email"))
        #expect(text.contains("Invoice 2"))
        #expect(text.contains("composio_execute"))
        print(
            "PROMPT_BUDGET raw_tokens=\(ToolResultBudget.estimatedTokens(raw)) raw_chars=\(raw.utf8.count) reduced_tokens=\(ToolResultBudget.estimatedTokens(reduced)) reduced_chars=\(reduced.utf8.count) bloated_request_tokens=\(ToolResultBudget.estimatedTokens(data: bloatedBody)) reduced_request_tokens=\(ToolResultBudget.estimatedTokens(data: body)) model_limit=\(ToolResultBudget.modelTokenLimit)"
        )
    }

    @Test func smallComposioSuccessPassesThrough() {
        let small = #"{"successful":true,"error":null,"data":{"ok":1}}"#
        #expect(ToolResultBudget.reduce(small) == small)
    }

    @Test func genericOversizeTextIsClipped() {
        let blob = String(repeating: "slack dump ", count: 40_000)
        #expect(blob.utf8.count > ToolResultBudget.maxCharacters)
        let reduced = ToolResultBudget.reduce(blob)
        #expect(reduced.utf8.count <= ToolResultBudget.maxCharacters)
        #expect(reduced.contains("truncated for prompt budget"))
        #expect(ToolResultBudget.fitsModelWindow(reduced))
    }

    private static func nextTurnHistory(toolBody: String) -> [ChatMessage] {
        [
            ChatMessage(role: "system", content: "You are Joyflow."),
            ChatMessage(role: "user", content: "what's in my email"),
            ChatMessage(
                role: "assistant",
                toolCalls: [
                    ToolCall(
                        id: "call_gmail",
                        name: "composio_execute",
                        arguments: #"{"tool_slug":"GMAIL_FETCH_EMAILS","arguments_json":"{\"limit\":50}"}"#
                    ),
                ]
            ),
            ChatMessage(
                role: "tool",
                content: toolBody,
                toolCallID: "call_gmail",
                name: "composio_execute"
            ),
        ]
    }

    static func gmailPayload(messages: Int, htmlChars: Int) -> String {
        let htmlPad = String(repeating: "X", count: htmlChars)
        var items: [[String: Any]] = []
        items.reserveCapacity(messages)
        for index in 0..<messages {
            items.append(
                [
                    "messageId": "msg-\(index)",
                    "threadId": "thr-\(index)",
                    "sender": "alice@example.com",
                    "to": "bob@example.com",
                    "subject": "Invoice \(index)",
                    "messageTimestamp": "2026-01-02T15:04:05Z",
                    "preview": ["body": "Payment due for invoice \(index)"],
                    "messageText": "Please pay invoice \(index). " + htmlPad,
                    "messageTextHtml": "<html><body>\(htmlPad)</body></html>",
                ]
            )
        }
        let root: [String: Any] = [
            "successful": true,
            "error": NSNull(),
            "data": [
                "next_page_token": "page-2",
                "messages": items,
            ],
        ]
        let data = try! JSONSerialization.data(withJSONObject: root)
        return String(data: data, encoding: .utf8)!
    }
}
