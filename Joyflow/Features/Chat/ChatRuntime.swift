import Foundation
import JoyflowKit
import Observation

@Observable
@MainActor
final class ChatRuntime {
    var messages: [ChatMessageRecord] = []
    var liveAssistant = ""
    var liveReasoning = ""
    var liveActivity: String?
    var liveSteps: [WorkStep] = []
    var streamStartedAt: Date?
    var isStreaming = false
    var pendingApproval: PendingApproval?
    var threadID = UUID()
    var errorText: String?

    private var loadedProjectID: UUID?
    private var inFlight: Task<Void, Never>?
    private var resumeHistory: [ChatMessage] = []
    private var resumeClient: GatewayClient?
    private var resumeProject: ProjectManifest?

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 600
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    func load(app: AppModel) {
        guard let project = app.selected else {
            guard !isStreaming else { return }
            messages = []
            loadedProjectID = nil
            return
        }
        let nextThread = app.store.resolveThreadID(
            projectID: project.id,
            preferred: app.selectedThreadID
        )
        if isStreaming, loadedProjectID == project.id, threadID == nextThread {
            return
        }
        if isStreaming {
            inFlight?.cancel()
            inFlight = nil
            isStreaming = false
        }
        loadedProjectID = project.id
        threadID = nextThread
        if app.selectedThreadID != nextThread {
            app.selectedThreadID = nextThread
        }
        try? app.store.setActiveThread(projectID: project.id, threadID: nextThread)
        messages = (try? app.store.messages(projectID: project.id, threadID: threadID)) ?? []
        liveAssistant = ""
        liveReasoning = ""
        liveActivity = nil
        liveSteps = []
        streamStartedAt = nil
        pendingApproval = nil
        errorText = nil
    }

    func editAndResend(id: UUID, text: String, app: AppModel) async {
        guard let project = app.selected else { return }
        inFlight?.cancel()
        inFlight = nil
        isStreaming = false
        liveAssistant = ""
        liveReasoning = ""
        liveActivity = nil
        liveSteps = []
        streamStartedAt = nil
        pendingApproval = nil
        errorText = nil
        do {
            messages = try app.store.editUserMessage(
                projectID: project.id,
                threadID: threadID,
                id: id,
                text: text
            )
        } catch {
            fail(error.localizedDescription, app: app, project: project)
            return
        }
        guard ThreadEdit.resendPrompt(from: messages) != nil else { return }
        await startReply(app: app, project: project)
    }

    func send(text: String, app: AppModel) async {
        guard ChatDraft.shouldSend(text) else { return }
        guard let project = app.selected else { return }
        errorText = nil
        let user = ChatMessageRecord(role: "user", content: text)
        messages.append(user)
        try? app.store.appendMessage(projectID: project.id, threadID: threadID, message: user)

        await startReply(app: app, project: project)
    }

    func ingestRemote(_ request: PairChatRequest, app: AppModel) async {
        let name = request.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try app.store.ensureProject(id: request.projectID, name: name)
        } catch {
            fail(error.localizedDescription, app: app, project: app.selected)
            return
        }
        app.reload()
        app.selectThread(request.threadID, in: request.projectID)
        if isStreaming {
            inFlight?.cancel()
            inFlight = nil
            isStreaming = false
        }
        loadedProjectID = request.projectID
        threadID = request.threadID
        app.selectedThreadID = request.threadID
        try? app.store.setActiveThread(projectID: request.projectID, threadID: request.threadID)
        messages = (try? app.store.messages(projectID: request.projectID, threadID: request.threadID)) ?? []
        liveAssistant = ""
        liveReasoning = ""
        liveActivity = nil
        liveSteps = []
        streamStartedAt = nil
        pendingApproval = nil
        errorText = nil
        if !messages.contains(where: { $0.id == request.message.id }) {
            messages.append(request.message)
            do {
                try app.store.appendMessage(
                    projectID: request.projectID,
                    threadID: request.threadID,
                    message: request.message
                )
            } catch {
                fail(error.localizedDescription, app: app, project: app.selected)
                return
            }
        }
        guard let project = app.projects.first(where: { $0.id == request.projectID }) ?? app.selected else {
            return
        }
        await startReply(app: app, project: project)
    }

    func controlStatus() -> PairControlStatus {
        PairControlStatus(
            streaming: isStreaming,
            text: liveAssistant,
            reasoning: liveReasoning,
            activity: liveActivity,
            steps: liveSteps.map(\.title),
            approval: pendingApproval,
            error: errorText,
            projectID: loadedProjectID,
            threadID: threadID
        )
    }

    func startNewThread(app: AppModel) {
        guard let project = app.selected else { return }
        inFlight?.cancel()
        inFlight = nil
        isStreaming = false
        let id = app.startThread(in: project.id)
        loadedProjectID = project.id
        threadID = id
        messages = []
        liveAssistant = ""
        liveReasoning = ""
        liveActivity = nil
        liveSteps = []
        streamStartedAt = nil
        pendingApproval = nil
        errorText = nil
    }

    func openThread(_ id: UUID, in projectID: UUID, app: AppModel) {
        app.selectThread(id, in: projectID)
        load(app: app)
    }

    func deleteMessage(id: UUID, app: AppModel) {
        guard let project = app.selected else { return }
        do {
            messages = try app.store.deleteMessage(projectID: project.id, threadID: threadID, id: id)
        } catch {
            fail(error.localizedDescription, app: app, project: project)
        }
    }

    func clearCurrentThread(app: AppModel) {
        guard let project = app.selected else { return }
        inFlight?.cancel()
        inFlight = nil
        isStreaming = false
        try? app.store.clearThread(projectID: project.id, threadID: threadID)
        messages = []
        liveAssistant = ""
        liveReasoning = ""
        liveActivity = nil
        liveSteps = []
        streamStartedAt = nil
        pendingApproval = nil
        errorText = nil
    }

    func clearAllThreads(app: AppModel) {
        guard let project = app.selected else { return }
        inFlight?.cancel()
        inFlight = nil
        isStreaming = false
        try? app.store.clearAllThreads(projectID: project.id)
        startNewThread(app: app)
    }

    private func startReply(app: AppModel, project: ProjectManifest) async {
        guard let endpoint = app.endpoints.first(where: { $0.id == app.activeEndpointID }) ?? app.endpoints.first
        else {
            fail("Add a model in Settings first.", app: app, project: project)
            return
        }
        let key = app.key(for: endpoint)
        guard !key.isEmpty else {
            fail("Add an API key in Settings.", app: app, project: project)
            return
        }

        loadedProjectID = project.id
        let history = startingHistory(app: app, project: project)
        let client = GatewayClient(apiKey: key, model: endpoint.modelID, baseURL: endpoint.baseURL)
        inFlight?.cancel()
        let task = Task { await self.loop(app: app, project: project, client: client, history: history) }
        inFlight = task
        await task.value
    }

    func allow(app: AppModel) async {
        guard let pending = pendingApproval, let project = resumeProject ?? app.selected else { return }
        pendingApproval = nil
        var history = resumeHistory
        let client = resumeClient ?? GatewayClient(apiKey: "", model: "", baseURL: JoyflowKit.defaultGatewayURL)
        isStreaming = true
        streamStartedAt = streamStartedAt ?? Date()
        liveActivity = "Using \(pending.toolName)…"
        do {
            let result = try await execute(
                ToolCall(id: pending.id, name: pending.toolName, arguments: pending.arguments),
                app: app,
                project: project
            )
            history.append(
                ChatMessage(
                    role: "tool",
                    content: ToolResultBudget.reduce(result),
                    toolCallID: pending.id,
                    name: pending.toolName
                )
            )
            await loop(app: app, project: project, client: client, history: history)
        } catch {
            fail(error.localizedDescription, app: app, project: project)
        }
    }

    func deny(app: AppModel) async {
        guard let pending = pendingApproval, let project = resumeProject ?? app.selected else {
            pendingApproval = nil
            return
        }
        pendingApproval = nil
        var history = resumeHistory
        history.append(
            ChatMessage(
                role: "tool",
                content: "The user denied \(pending.toolName). Answer with what you already know.",
                toolCallID: pending.id,
                name: pending.toolName
            )
        )
        if let client = resumeClient {
            await loop(app: app, project: project, client: client, history: history)
        }
    }

    func deny() {
        pendingApproval = nil
        liveAssistant = ""
        liveReasoning = ""
        liveActivity = nil
        liveSteps = []
        streamStartedAt = nil
    }

    func stop(app: AppModel) {
        inFlight?.cancel()
        inFlight = nil
        isStreaming = false
        if let project = app.selected {
            finishAssistant(app: app, project: project, allowEmpty: false)
        }
        liveActivity = nil
        liveSteps = []
        streamStartedAt = nil
    }

    private func startingHistory(app: AppModel, project: ProjectManifest) -> [ChatMessage] {
        let resources = app.resources(for: project)
        let links = (try? resources.links()) ?? []
        let docs = (try? resources.documents()) ?? []
        let folders = resources.resolvedFolders().map { item, url in
            "\(item.name) — \(url.path)"
        }
        let compact = ChatCompaction.apply(messages)
        let system = PromptComposer().compose(
            projectName: project.name,
            soul: (try? app.store.readSoul(projectID: project.id)) ?? "",
            instructions: (try? app.store.readInstructions(projectID: project.id)) ?? "",
            notes: (try? app.store.notes(projectID: project.id)) ?? [],
            memories: (try? app.store.memories(projectID: project.id)) ?? [],
            linkedCommons: app.linkedCommonsText(for: project),
            links: links,
            documentNames: docs,
            folderNames: folders,
            earlierSummary: compact.summary
        )
        var history: [ChatMessage] = [ChatMessage(role: "system", content: system)]
        history += compact.kept.map { ChatMessage(role: $0.role, content: $0.content, reasoning: $0.reasoning) }
        return history
    }

    private func loop(app: AppModel, project: ProjectManifest, client: GatewayClient, history: [ChatMessage]) async {
        isStreaming = true
        liveAssistant = ""
        liveReasoning = ""
        liveActivity = nil
        liveSteps = []
        pushStep("Thinking")
        streamStartedAt = Date()
        resumeClient = client
        resumeProject = project
        defer {
            isStreaming = false
            liveActivity = nil
            streamStartedAt = nil
        }
        var history = history
        var skipTools = false
        var didNudge = false
        let policy = AgentLoop(policy: PolicyEngine(defaultAction: app.defaultReview))
        do {
            for _ in 0..<AgentLoop.defaultMaxSteps {
                if Task.isCancelled {
                    finishAssistant(app: app, project: project, allowEmpty: false)
                    return
                }
                let turn = try await stream(
                    client: client,
                    history: history,
                    tools: skipTools ? [] : ToolCatalog.definitions,
                    reasoningEffort: skipTools ? "low" : "medium"
                )
                if Task.isCancelled {
                    finishAssistant(app: app, project: project, allowEmpty: false)
                    return
                }
                if let message = turn.error {
                    fail(message, app: app, project: project)
                    return
                }
                let calls = turn.tools.sortedCalls
                if !calls.isEmpty {
                    var results: [(ToolCall, String)] = []
                    for call in calls {
                        let decision = policy.decide(toolName: call.name, arguments: call.arguments)
                        if decision.action == ReviewAction.deny {
                            results.append((call, "Denied \(call.name): \(decision.reason)"))
                            continue
                        }
                        if decision.action == ReviewAction.ask {
                            resumeHistory = history + [
                                assistantToolMessage(
                                    preface: turn.text,
                                    calls: calls,
                                    reasoning: turn.reasoning,
                                    details: turn.details
                                ),
                            ]
                            pendingApproval = AgentLoop().review(toolName: call.name, arguments: call.arguments)
                            pendingApproval?.id = call.id
                            pushStep("Waiting for approval")
                            return
                        }
                        noteTool(call.name)
                        let result: String
                        do {
                            result = try await execute(call, app: app, project: project)
                        } catch {
                            result = error.localizedDescription
                        }
                        results.append((call, result))
                    }
                    history.append(
                        assistantToolMessage(
                            preface: turn.text,
                            calls: calls,
                            reasoning: turn.reasoning,
                            details: turn.details
                        )
                    )
                    for (call, result) in results {
                        history.append(
                            ChatMessage(
                                role: "tool",
                                content: ToolResultBudget.reduce(result),
                                toolCallID: call.id,
                                name: call.name
                            )
                        )
                    }
                    liveAssistant = ""
                    if !liveReasoning.isEmpty, !liveReasoning.hasSuffix("\n") {
                        liveReasoning += "\n"
                    }
                    liveActivity = nil
                    skipTools = false
                    continue
                }
                if ReplyNudge.needsVisibleAnswer(text: turn.text, tools: calls) {
                    if !didNudge {
                        didNudge = true
                        skipTools = true
                        history.append(ChatMessage(role: "user", content: ReplyNudge.userMessage))
                        pushStep("Writing")
                        continue
                    }
                    fail("The model returned an empty reply. Try again.", app: app, project: project)
                    return
                }
                finishAssistant(app: app, project: project, allowEmpty: false)
                return
            }
            history.append(ChatMessage(role: "user", content: ReplyNudge.stepBudgetMessage))
            pushStep("Writing")
            let wrap = try await stream(
                client: client,
                history: history,
                tools: [],
                reasoningEffort: "low"
            )
            if let message = wrap.error {
                fail(message, app: app, project: project)
                return
            }
            if !wrap.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                liveAssistant = wrap.text
                if !wrap.reasoning.isEmpty { liveReasoning = wrap.reasoning }
                finishAssistant(app: app, project: project, allowEmpty: false)
                return
            }
            fail(
                "I used too many steps without finishing. Say what you wanted again in one sentence.",
                app: app,
                project: project
            )
        } catch is CancellationError {
            finishAssistant(app: app, project: project, allowEmpty: false)
        } catch {
            fail(error.localizedDescription, app: app, project: project)
        }
    }

    private struct StreamTurn {
        var text: String
        var reasoning: String
        var details: [ReasoningDetail]
        var tools: ToolAccumulator
        var error: String?
    }

    private func stream(
        client: GatewayClient,
        history: [ChatMessage],
        tools: [ToolDefinition],
        reasoningEffort: String
    ) async throws -> StreamTurn {
        let request = try client.makeRequest(
            messages: history,
            tools: tools,
            stream: true,
            reasoningEffort: reasoningEffort,
            toolChoice: tools.isEmpty ? "none" : nil
        )
        let outcome = try await Self.consume(request: request) { [weak self] text, reasoning in
            await self?.publish(text: text, reasoning: reasoning)
        }
        return StreamTurn(
            text: outcome.text,
            reasoning: outcome.reasoning,
            details: outcome.details,
            tools: outcome.tools,
            error: outcome.error
        )
    }

    private func publish(text: String, reasoning: String) {
        if !text.isEmpty {
            liveAssistant += text
            pushStep("Writing")
        }
        if !reasoning.isEmpty {
            liveReasoning += reasoning
            if liveSteps.isEmpty { pushStep("Thinking") }
        }
    }

    nonisolated private struct StreamOutcome: Sendable {
        var text: String
        var reasoning: String
        var details: [ReasoningDetail]
        var tools: ToolAccumulator
        var error: String?
    }

    nonisolated private static func consume(
        request: URLRequest,
        onDelta: @escaping @Sendable (String, String) async -> Void
    ) async throws -> StreamOutcome {
        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            var body = ""
            for try await line in bytes.lines { body += line }
            let event = StreamParser().parseHTTPError(status: http.statusCode, body: body)
            if case .error(let message) = event {
                return StreamOutcome(text: "", reasoning: "", details: [], tools: ToolAccumulator(), error: message)
            }
            return StreamOutcome(
                text: "",
                reasoning: "",
                details: [],
                tools: ToolAccumulator(),
                error: "HTTP \(http.statusCode)"
            )
        }
        var parser = StreamParser()
        var buffer = ""
        var assembled = ToolAccumulator()
        var bag = ReasoningBag()
        var text = ""
        var reasoning = ""
        var pendingText = ""
        var pendingReason = ""
        var lastFlush = ContinuousClock.now

        func apply(_ events: [StreamEvent]) -> String? {
            for event in events {
                switch event {
                case .text(let chunk):
                    text += chunk
                    pendingText += chunk
                case .reasoning(let chunk):
                    reasoning += chunk
                    pendingReason += chunk
                case .reasoningDetail(let detail):
                    bag.apply(detail)
                case .toolCall(let delta):
                    assembled.apply(delta)
                case .finished:
                    break
                case .error(let message):
                    return message
                }
            }
            return nil
        }

        func flush() async {
            guard !pendingText.isEmpty || !pendingReason.isEmpty else { return }
            let nextText = pendingText
            let nextReason = pendingReason
            pendingText = ""
            pendingReason = ""
            await onDelta(nextText, nextReason)
        }

        for try await line in bytes.lines {
            if Task.isCancelled { throw CancellationError() }
            buffer += line + "\n"
            if let message = apply(parser.parse(buffer: &buffer)) {
                await flush()
                return StreamOutcome(
                    text: text,
                    reasoning: reasoning,
                    details: bag.ordered,
                    tools: assembled,
                    error: message
                )
            }
            if ContinuousClock.now - lastFlush >= .milliseconds(32) {
                await flush()
                lastFlush = .now
            }
        }
        if let message = apply(parser.finish(buffer: &buffer)) {
            await flush()
            return StreamOutcome(
                text: text,
                reasoning: reasoning,
                details: bag.ordered,
                tools: assembled,
                error: message
            )
        }
        await flush()
        return StreamOutcome(
            text: text,
            reasoning: reasoning,
            details: bag.ordered,
            tools: assembled,
            error: nil
        )
    }

    private func execute(_ call: ToolCall, app: AppModel, project: ProjectManifest) async throws -> String {
        let writeRoot = try app.store.writeRoot(for: project.id)
        let computer = try ComputerRouter.computer(
            app.computer,
            workspace: writeRoot,
            extraRoots: extraRoots(app: app, project: project),
            credentials: app.sandboxCredentials
        )
        let dispatcher = ToolDispatcher(
            store: app.store,
            projectID: project.id,
            computer: computer,
            composioKey: app.keychain.get(KeychainStore.composioAccount),
            composioAccounts: app.composioAccounts
        )
        let result = try await dispatcher.execute(name: call.name, argumentsJSON: call.arguments)
        app.reload()
        return result
    }

    private func extraRoots(app: AppModel, project: ProjectManifest) -> [URL] {
        app.resources(for: project).resolvedFolders().map(\.1)
    }

    private func assistantToolMessage(
        preface: String,
        calls: [ToolCall],
        reasoning: String,
        details: [ReasoningDetail]
    ) -> ChatMessage {
        ChatMessage(
            role: "assistant",
            content: preface.isEmpty ? nil : preface,
            toolCalls: calls,
            reasoning: reasoning.isEmpty ? nil : reasoning,
            reasoningDetails: details.isEmpty ? nil : details
        )
    }

    private func noteTool(_ name: String) {
        pushStep(Self.stepTitle(forTool: name))
        let line = "Using \(name)…"
        if liveReasoning.isEmpty {
            liveReasoning = line
        } else if !liveReasoning.contains(line) {
            liveReasoning += "\n" + line
        }
    }

    func pushStep(_ title: String) {
        if liveSteps.last?.title == title { return }
        liveSteps.append(WorkStep(id: UUID(), title: title))
        liveActivity = title
    }

    private static func stepTitle(forTool name: String) -> String {
        switch name {
        case "read_file": "Reading a file"
        case "write_file": "Writing a file"
        case "list_dir": "Listing files"
        case "run_shell": "Running a command"
        case "search_knowledge": "Searching knowledge"
        case "write_note": "Saving a note"
        case "write_memory": "Saving a memory"
        case "update_soul": "Updating SOUL"
        case "promote_to_commons": "Promoting to Commons"
        case "list_wiki": "Listing notes"
        case "add_link": "Adding a link"
        case "attach_folder": "Attaching a folder"
        case "composio_execute": "Using a connector"
        case "control_mac": "Moving a window"
        default: "Working"
        }
    }

    private func finishAssistant(app: AppModel, project: ProjectManifest, allowEmpty: Bool) {
        let text = liveAssistant.trimmingCharacters(in: .whitespacesAndNewlines)
        let thought = liveReasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        liveAssistant = ""
        liveReasoning = ""
        liveActivity = nil
        liveSteps = []
        guard !text.isEmpty else {
            if !allowEmpty { return }
            return
        }
        let record = ChatMessageRecord(
            role: "assistant",
            content: text,
            reasoning: thought.isEmpty ? nil : thought
        )
        messages.append(record)
        try? app.store.appendMessage(projectID: project.id, threadID: threadID, message: record)
    }

    private func fail(_ text: String, app: AppModel, project: ProjectManifest?) {
        errorText = text
        isStreaming = false
        pendingApproval = nil
        let thought = liveReasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        liveAssistant = ""
        liveReasoning = ""
        liveActivity = nil
        liveSteps = []
        guard let project else { return }
        let record = ChatMessageRecord(
            role: "assistant",
            content: text,
            reasoning: thought.isEmpty ? nil : thought
        )
        messages.append(record)
        try? app.store.appendMessage(projectID: project.id, threadID: threadID, message: record)
    }
}

struct WorkStep: Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
}

nonisolated struct ToolAccumulator: Sendable {
    var calls: [Int: ToolCall] = [:]

    mutating func apply(_ delta: ToolCallDelta) {
        var current = calls[delta.index] ?? ToolCall(id: delta.id ?? UUID().uuidString, name: delta.name ?? "", arguments: "")
        if let id = delta.id { current.id = id }
        if let name = delta.name, !name.isEmpty { current.name = name }
        current.arguments += delta.argumentsFragment
        calls[delta.index] = current
    }

    var first: ToolCall? { sortedCalls.first }
    var sortedCalls: [ToolCall] { calls.sorted(by: { $0.key < $1.key }).map(\.value) }
}
