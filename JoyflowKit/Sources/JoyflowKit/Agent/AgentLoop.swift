import Foundation

public struct PendingApproval: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var toolName: String
    public var arguments: String
    public var preview: String

    public init(id: String, toolName: String, arguments: String, preview: String) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
        self.preview = preview
    }

    public var displayTitle: String {
        switch toolName {
        case "attach_folder": "Attach a folder"
        case "write_file": "Write a file"
        case "run_shell": "Run a command"
        case "update_soul": "Update SOUL"
        case "promote_to_commons": "Promote to Commons"
        case "composio_execute": "Run a plugin"
        case "control_mac": "Move a Mac app"
        default: "Run \(toolName)"
        }
    }

    public var displayDetail: String {
        let parsed = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any]
        if let path = parsed?["path"] as? String, !path.isEmpty {
            let name = parsed?["name"] as? String
            if let name, !name.isEmpty { return "\(name)\n\(path)" }
            return path
        }
        if let command = parsed?["command"] as? String, !command.isEmpty {
            return command
        }
        if toolName == "control_mac" {
            let action = parsed?["action"] as? String ?? ""
            let app = parsed?["app"] as? String ?? ""
            let display = parsed?["display"] as? String ?? ""
            return [action, app, display].filter { !$0.isEmpty }.joined(separator: " → ")
        }
        let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? preview : trimmed
    }
}

public enum AgentEvent: Sendable, Equatable {
    case text(String)
    case toolStarted(String)
    case toolFinished(String, String)
    case needsApproval(PendingApproval)
    case finished
    case failed(String)
}

public struct AgentLoop: Sendable {
    public var policy: PolicyEngine
    public var maxSteps: Int
    public static let defaultMaxSteps = 8

    public init(policy: PolicyEngine = PolicyEngine(), maxSteps: Int = AgentLoop.defaultMaxSteps) {
        self.policy = policy
        self.maxSteps = maxSteps
    }

    public func decide(toolName: String, arguments: String) -> PolicyDecision {
        policy.decide(PolicyRequest(toolName: toolName, arguments: arguments))
    }

    public func review(toolName: String, arguments: String) -> PendingApproval {
        PendingApproval(
            id: UUID().uuidString,
            toolName: toolName,
            arguments: arguments,
            preview: "\(toolName)\n\(arguments)"
        )
    }
}

public struct ToolDispatcher: Sendable {
    public var store: FileProjectStore
    public var projectID: UUID
    public var computer: any SandboxProviding
    public var composioKey: String?
    public var composioTransport: (any ComposioTransporting)?
    public var composioAccounts: [String: String]
    public var composioCLIPath: String?
    public var lookupCLI: Bool
    public var composioProcess: (any ComposioProcessRunning)?

    public init(
        store: FileProjectStore,
        projectID: UUID,
        computer: any SandboxProviding,
        composioKey: String? = nil,
        composioTransport: (any ComposioTransporting)? = nil,
        composioAccounts: [String: String] = [:],
        composioCLIPath: String? = nil,
        lookupCLI: Bool = true,
        composioProcess: (any ComposioProcessRunning)? = nil
    ) {
        self.store = store
        self.projectID = projectID
        self.computer = computer
        self.composioKey = composioKey
        self.composioTransport = composioTransport
        self.composioAccounts = composioAccounts
        self.composioCLIPath = composioCLIPath
        self.lookupCLI = lookupCLI
        self.composioProcess = composioProcess
    }

    public func execute(name: String, argumentsJSON: String) async throws -> String {
        do {
            return ToolResultBudget.reduce(try await perform(name: name, argumentsJSON: argumentsJSON))
        } catch let error as JoyflowStoreError {
            return ToolResultBudget.reduce(error.localizedDescription)
        }
    }

    private func perform(name: String, argumentsJSON: String) async throws -> String {
        let args = (try? JSONSerialization.jsonObject(with: Data(argumentsJSON.utf8)) as? [String: Any]) ?? [:]
        switch name {
        case "read_file":
            let data = try await computer.readFile(path: string(args, "path"))
            return String(data: data, encoding: .utf8) ?? ""
        case "write_file":
            try await computer.writeFile(path: string(args, "path"), contents: Data(string(args, "contents").utf8))
            return "wrote"
        case "list_dir":
            return try await computer.list(path: string(args, "path", fallback: ".")).joined(separator: "\n")
        case "run_shell":
            let result = try await computer.exec(command: string(args, "command"), cwd: nil, env: [:])
            return "exit \(result.exitCode)\n\(result.stdout)\n\(result.stderr)"
        case "search_knowledge":
            let notes = try store.notes(projectID: projectID)
            let memories = try store.memories(projectID: projectID)
            let hits = KnowledgeIndex().search(notes: notes, memories: memories, query: string(args, "query"))
            return hits.map { "\($0.title): \($0.snippet)" }.joined(separator: "\n")
        case "write_note":
            let note = try store.writeNote(
                projectID: projectID,
                title: string(args, "title"),
                body: string(args, "body")
            )
            return "wrote note \(note.slug)"
        case "write_memory":
            _ = try store.appendMemory(projectID: projectID, text: string(args, "text"), source: "model")
            return "remembered"
        case "update_soul":
            try store.writeSoul(projectID: projectID, text: string(args, "text"))
            return "updated soul"
        case "promote_to_commons":
            return try promote(slug: string(args, "slug"))
        case "list_wiki":
            return try store.notes(projectID: projectID).map(\.title).joined(separator: "\n")
        case "add_link":
            try ResourceStore(layout: store.layout(for: projectID)).addLink(
                title: string(args, "title"),
                url: string(args, "url")
            )
            return "added link"
        case "attach_folder":
            let path = string(args, "path")
            let url = URL(fileURLWithPath: path)
            let item = try ResourceStore(layout: store.layout(for: projectID)).addFolder(from: url)
            let label = string(args, "name")
            return "attached \(label.isEmpty ? item.name : label) at \(url.path)"
        case "composio_execute":
            return try await executeComposio(args)
        case "control_mac":
            return try MacDesktop.perform(
                action: string(args, "action"),
                app: string(args, "app"),
                display: string(args, "display")
            )
        default:
            return "unknown tool \(name)"
        }
    }

    private func executeComposio(_ args: [String: Any]) async throws -> String {
        let slug = string(args, "tool_slug")
        let parsed = ComposioExecute.parseArgumentsJSON(string(args, "arguments_json"))
        let json = ComposioExecute.encodeArguments(parsed)
        var account = string(args, "connected_account_id")
        let toolkit = ComposioAccounts.toolkit(fromToolSlug: slug)
        if account.isEmpty {
            account = composioAccounts[toolkit] ?? ""
        }
        let transport = composioTransport ?? URLSessionComposioTransport()
        if account.isEmpty, let key = composioKey, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let listed = try await transport.send(ComposioClient(apiKey: key).listConnectedAccountsRequest())
            account = ComposioAccounts.resolve(listed, toolSlug: slug) ?? ""
        }
        let plan = ComposioExecute.plan(
            apiKey: composioKey,
            toolSlug: slug,
            connectedAccountID: account,
            arguments: parsed
        )
        if let request = plan.request {
            let data = try await transport.send(request)
            return String(data: data, encoding: .utf8) ?? ""
        }
        if let binary = resolvedCLI() {
            let process = composioProcess ?? LocalComposioProcess()
            return try await process.run(
                executable: binary,
                arguments: ComposioExecute.cliArguments(toolSlug: slug, argumentsJSON: json)
            )
        }
        throw JoyflowStoreError.io(plan.error ?? "Composio is not configured.")
    }

    private func resolvedCLI() -> String? {
        if let composioCLIPath { return composioCLIPath.isEmpty ? nil : composioCLIPath }
        guard lookupCLI else { return nil }
        return ComposioExecute.findCLI()
    }

    private func promote(slug: String) throws -> String {
        let notes = try store.notes(projectID: projectID)
        guard let note = notes.first(where: { $0.slug == slug }) else {
            throw JoyflowStoreError.notFound("note \(slug)")
        }
        try store.commons.writeNote(note)
        try store.linkCommons(projectID: projectID, id: "note:\(note.id.uuidString)")
        return "promoted \(slug)"
    }

    private func string(_ args: [String: Any], _ key: String, fallback: String = "") -> String {
        args[key] as? String ?? fallback
    }
}
