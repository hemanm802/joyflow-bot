import Foundation
import Testing

@testable import JoyflowKit

struct AgentLoopTests {
    @Test func askDoesNotExecuteUntilAllowed() {
        let loop = AgentLoop(policy: PolicyEngine(defaultAction: .ask))
        let decision = loop.decide(toolName: "run_shell", arguments: "{\"command\":\"ls\"}")
        #expect(decision.action == .ask)
        let review = loop.review(toolName: "run_shell", arguments: "{\"command\":\"ls\"}")
        #expect(review.toolName == "run_shell")
    }

    @Test func emptySendDoesNotCreateMessage() {
        #expect(ChatDraft.shouldSend("") == false)
        #expect(ChatDraft.shouldSend("   ") == false)
        #expect(ChatDraft.shouldSend("hello") == true)
    }

    @Test func largeComposeDoesNotThrow() {
        let text = String(repeating: "a", count: 8000)
        #expect(ChatDraft.shouldSend(text))
        #expect(text.count == 8000)
    }

    @Test func newChatOfferListsCreateThenMatches() {
        let empty = NewChatOffer.build(query: "", names: ["Welcome", "Notes"])
        #expect(empty.createTitle == "Create new Project")
        #expect(empty.matches == ["Welcome", "Notes"])
        #expect(empty.createName == "Untitled")
        let typed = NewChatOffer.build(query: "  wel  ", names: ["Welcome", "Notes"])
        #expect(typed.createTitle == "Create “wel”")
        #expect(typed.matches == ["Welcome"])
        #expect(typed.createName == "wel")
    }

    @Test func composioExecuteUsesShippedPlan() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("joyflow-disp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileProjectStore(rootURL: root)
        let project = try store.createProject(name: "Tools")
        let computer = try ComputerRouter.computer(
            .local,
            workspace: store.layout(for: project.id).workspace,
            credentials: .empty
        )

        let closed = ToolDispatcher(store: store, projectID: project.id, computer: computer)
        let closedResult = try await closed.execute(
            name: "composio_execute",
            argumentsJSON: #"{"tool_slug":"GMAIL_FETCH_EMAILS","connected_account_id":"ca_1","arguments_json":"{}"}"#
        )
        #expect(closedResult.localizedCaseInsensitiveContains("composio") || closedResult.localizedCaseInsensitiveContains("key"))
        #expect(!closedResult.contains("error 2"))

        let transport = RecordingComposioTransport()
        let open = ToolDispatcher(
            store: store,
            projectID: project.id,
            computer: computer,
            composioKey: "secret",
            composioTransport: transport
        )
        let body = try await open.execute(
            name: "composio_execute",
            argumentsJSON: #"{"tool_slug":"GMAIL_FETCH_EMAILS","connected_account_id":"ca_1","arguments_json":"{\"limit\":2}"}"#
        )
        #expect(body.contains("successful"))
        #expect(transport.calls.count == 1)
        let request = try #require(transport.calls.first)
        #expect(request.url.hasSuffix("/tools/execute/GMAIL_FETCH_EMAILS"))
        let payload = try JSONSerialization.jsonObject(with: request.body!) as? [String: Any]
        #expect(payload?["connected_account_id"] as? String == "ca_1")
        #expect(payload?["version"] as? String == ComposioExecute.version)
    }

    @Test func composioExecuteResolvesAccountFromList() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("joyflow-resolve-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileProjectStore(rootURL: root)
        let project = try store.createProject(name: "Resolve")
        let computer = try ComputerRouter.computer(
            .local,
            workspace: store.layout(for: project.id).workspace,
            credentials: .empty
        )
        let transport = RecordingComposioTransport()
        transport.listResponse = Data(
            #"""
            {"items":[{"id":"ca_resolved","status":"ACTIVE","user_id":"joyflow-local","toolkit":{"slug":"gmail"}}]}
            """#.utf8
        )
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
            argumentsJSON: #"{"tool_slug":"GMAIL_FETCH_EMAILS","arguments_json":"{\"limit\":2}"}"#
        )
        #expect(body.contains("successful"))
        #expect(transport.calls.count == 2)
        #expect(transport.calls[0].method == "GET")
        #expect(transport.calls[0].url.contains("/connected_accounts"))
        #expect(transport.calls[1].url.hasSuffix("/tools/execute/GMAIL_FETCH_EMAILS"))
        let payload = try JSONSerialization.jsonObject(with: transport.calls[1].body!) as? [String: Any]
        #expect(payload?["connected_account_id"] as? String == "ca_resolved")
    }

    @Test func composioExecuteUsesOfficialCLIWhenNoKey() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("joyflow-cli-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileProjectStore(rootURL: root)
        let project = try store.createProject(name: "CLI")
        let computer = try ComputerRouter.computer(
            .local,
            workspace: store.layout(for: project.id).workspace,
            credentials: .empty
        )
        let process = RecordingComposioProcess()
        process.output = #"{"successful":true}"#
        let dispatcher = ToolDispatcher(
            store: store,
            projectID: project.id,
            computer: computer,
            composioCLIPath: "/usr/bin/composio",
            lookupCLI: false,
            composioProcess: process
        )
        let body = try await dispatcher.execute(
            name: "composio_execute",
            argumentsJSON: #"{"tool_slug":"GMAIL_FETCH_EMAILS","arguments_json":"{}"}"#
        )
        #expect(body.contains("successful"))
        #expect(process.runs.count == 1)
        #expect(process.runs[0].executable == "/usr/bin/composio")
        #expect(process.runs[0].arguments == ["execute", "GMAIL_FETCH_EMAILS", "-d", "{}"])
    }

    @Test func composioExecuteFailsClosedWithoutKeyOrCLI() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("joyflow-nocli-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileProjectStore(rootURL: root)
        let project = try store.createProject(name: "None")
        let computer = try ComputerRouter.computer(
            .local,
            workspace: store.layout(for: project.id).workspace,
            credentials: .empty
        )
        let dispatcher = ToolDispatcher(
            store: store,
            projectID: project.id,
            computer: computer,
            lookupCLI: false
        )
        let result = try await dispatcher.execute(
            name: "composio_execute",
            argumentsJSON: #"{"tool_slug":"GMAIL_FETCH_EMAILS","arguments_json":"{}"}"#
        )
        #expect(result.localizedCaseInsensitiveContains("composio") || result.localizedCaseInsensitiveContains("key"))
        #expect(!result.contains("error 2"))
    }

    @Test func dispatcherLocalWriteHitsWorkspaceNotCloud() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("joyflow-disp-local-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileProjectStore(rootURL: root)
        let project = try store.createProject(name: "Local")
        let workspace = store.layout(for: project.id).workspace
        let computer = try ComputerRouter.computer(.local, workspace: workspace, credentials: .empty)
        let dispatcher = ToolDispatcher(store: store, projectID: project.id, computer: computer)
        _ = try await dispatcher.execute(
            name: "write_file",
            argumentsJSON: #"{"path":"note.txt","contents":"hello"}"#
        )
        let text = try String(contentsOf: workspace.appendingPathComponent("note.txt"), encoding: .utf8)
        #expect(text == "hello")
    }

    @Test func dispatcherWorksOutsideWorkspaceWhenPolicyAllows() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "joyflow-disp-out-\(UUID().uuidString)"
        )
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(
            "joyflow-user-\(UUID().uuidString)"
        )
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try "alpha".write(to: outside.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
        let store = try FileProjectStore(rootURL: root)
        let project = try store.createProject(name: "Reach")
        let computer = try ComputerRouter.computer(
            .local,
            workspace: store.layout(for: project.id).workspace,
            credentials: .empty
        )
        #expect(ComputerAccess.allows(outside, workspace: store.layout(for: project.id).workspace, extraRoots: []))
        let dispatcher = ToolDispatcher(store: store, projectID: project.id, computer: computer)
        let listed = try await dispatcher.execute(
            name: "list_dir",
            argumentsJSON: #"{"path":"\#(outside.path)"}"#
        )
        #expect(listed.contains("note.txt"))
        let read = try await dispatcher.execute(
            name: "read_file",
            argumentsJSON: #"{"path":"\#(outside.appendingPathComponent("note.txt").path)"}"#
        )
        #expect(read == "alpha")
        let wrote = try await dispatcher.execute(
            name: "write_file",
            argumentsJSON: #"{"path":"\#(outside.appendingPathComponent("out.txt").path)","contents":"beta"}"#
        )
        #expect(wrote.contains("wrote"))
        #expect(try String(contentsOf: outside.appendingPathComponent("out.txt"), encoding: .utf8) == "beta")
        let shell = try await dispatcher.execute(
            name: "run_shell",
            argumentsJSON: #"{"command":"echo reach-ok"}"#
        )
        #expect(shell.contains("reach-ok"))
        let blocked = PolicyEngine(defaultAction: .allow).decide(
            PolicyRequest(toolName: "run_shell", arguments: #"{"command":"rm -rf /"}"#)
        )
        #expect(blocked.action == .deny)
        let system = try await dispatcher.execute(
            name: "list_dir",
            argumentsJSON: #"{"path":"/usr/bin"}"#
        )
        #expect(system.contains("protected"))
    }

    @Test func emptyReplyNeedsVisibleAnswerUntilTextArrives() {
        #expect(ReplyNudge.needsVisibleAnswer(text: "", tools: []))
        #expect(ReplyNudge.needsVisibleAnswer(text: "   ", tools: []))
        #expect(
            !ReplyNudge.needsVisibleAnswer(
                text: "",
                tools: [ToolCall(id: "1", name: "list_dir", arguments: "{}")]
            )
        )
        #expect(!ReplyNudge.needsVisibleAnswer(text: "Yes.", tools: []))
        #expect(ReplyNudge.userMessage.contains("Answer the user's last message"))
        #expect(ReplyNudge.stepBudgetMessage.contains("tool-step limit"))
    }
}

