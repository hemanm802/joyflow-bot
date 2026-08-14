import Foundation
import JoyflowKit
import Observation

struct WorkStep: Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
}

@Observable
@MainActor
final class PhoneChat {
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
        return URLSession(configuration: configuration)
    }()

    func load(app: PhoneModel) {
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
        if isStreaming, loadedProjectID == project.id, threadID == nextThread { return }
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
        pendingApproval = nil
        errorText = nil
    }

    func send(text: String, app: PhoneModel) async {
        guard ChatDraft.shouldSend(text), let project = app.selected else { return }
        inFlight?.cancel()
        errorText = nil
        let user = ChatMessageRecord(role: "user", content: text)
        messages.append(user)
        try? app.store.appendMessage(projectID: project.id, threadID: threadID, message: user)
        if app.runOnPairedMac, app.pairBinding?.canRemoteControl == true {
            let task = Task { await self.sendRemote(user, app: app, project: project) }
            inFlight = task
            await task.value
            return
        }
        await startReply(app: app, project: project)
    }

    func startNewThread(app: PhoneModel) {
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

    func openThread(_ id: UUID, in projectID: UUID, app: PhoneModel) {
        app.selectThread(id, in: projectID)
        load(app: app)
    }

    func deleteMessage(id: UUID, app: PhoneModel) {
        guard let project = app.selected else { return }
        messages = (try? app.store.deleteMessage(projectID: project.id, threadID: threadID, id: id)) ?? messages
    }

    func clearCurrentThread(app: PhoneModel) {
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
        pendingApproval = nil
        errorText = nil
    }

    func clearAllThreads(app: PhoneModel) {
        guard app.selected != nil else { return }
        inFlight?.cancel()
        inFlight = nil
        isStreaming = false
        if let project = app.selected {
            try? app.store.clearAllThreads(projectID: project.id)
        }
        startNewThread(app: app)
    }

    func stop(app: PhoneModel) {
        inFlight?.cancel()
        inFlight = nil
        isStreaming = false
        pendingApproval = nil
        if app.runOnPairedMac, let binding = app.pairBinding, binding.canRemoteControl {
            Task { await self.signalRemote(PairMailbox.Job.stop(), binding: binding) }
        }
        if let project = app.selected {
            finishAssistant(app: app, project: project)
        }
        liveActivity = nil
        liveSteps = []
        streamStartedAt = nil
    }

    func allow(app: PhoneModel) async {
        if app.runOnPairedMac, let binding = app.pairBinding, binding.canRemoteControl {
            let task = Task {
                await self.sendRemoteCommand(
                    PairMailbox.Job.allow(self.pendingApproval?.id ?? ""),
                    app: app,
                    binding: binding
                )
            }
            inFlight = task
            await task.value
            return
        }
        guard let pending = pendingApproval, let project = resumeProject ?? app.selected else { return }
        pendingApproval = nil
        var history = resumeHistory
        let client = resumeClient ?? GatewayClient(apiKey: "", model: "", baseURL: JoyflowKit.defaultGatewayURL)
        isStreaming = true
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
            fail(PairClient.displayMessage(for: error), app: app, project: project)
        }
    }

    func deny(app: PhoneModel) async {
        if app.runOnPairedMac, let binding = app.pairBinding, binding.canRemoteControl {
            let task = Task {
                await self.sendRemoteCommand(PairMailbox.Job.deny(), app: app, binding: binding)
            }
            inFlight = task
            await task.value
            return
        }
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

    private func sendRemote(
        _ user: ChatMessageRecord,
        app: PhoneModel,
        project: ProjectManifest
    ) async {
        guard let binding = app.pairBinding else {
            await startReply(app: app, project: project)
            return
        }
        isStreaming = true
        liveAssistant = ""
        liveReasoning = ""
        liveActivity = "Connecting to Mac"
        liveSteps = [WorkStep(id: Self.stableStepID(0), title: "Connecting to Mac")]
        streamStartedAt = Date()
        pendingApproval = nil
        let request = PairChatRequest(
            projectID: project.id,
            threadID: threadID,
            message: user,
            projectName: project.name
        )
        do {
            if Task.isCancelled {
                isStreaming = false
                return
            }
            if !binding.usesMailbox, let target = try? await PairSession.resolveTarget(for: binding) {
                do {
                    try await PairClient.sendChat(request, to: target)
                    await pollRemote(app: app, target: target)
                    return
                } catch {
                    liveActivity = "Waiting for Mac"
                    liveSteps = [WorkStep(id: Self.stableStepID(0), title: "Waiting for Mac")]
                }
            }
            try? await PairSession.push(from: app.store)
            try await PairMailbox.publishJob(PairMailbox.Job(request: request), token: binding.token)
            liveActivity = "Waiting for Mac"
            liveSteps = [WorkStep(id: Self.stableStepID(0), title: "Waiting for Mac")]
            await pollMailbox(app: app, binding: binding, sentIDs: Set(messages.map(\.id)))
        } catch {
            fail(PairClient.displayMessage(for: error), app: app, project: project)
        }
    }

    private func sendRemoteCommand(
        _ job: PairMailbox.Job,
        app: PhoneModel,
        binding: PairBinding
    ) async {
        isStreaming = true
        pendingApproval = nil
        liveActivity = "Updating Mac"
        do {
            if !binding.usesMailbox, let target = try? await PairSession.resolveTarget(for: binding) {
                do {
                    switch job.action {
                    case .allow:
                        try await PairClient.allow(id: job.approvalID ?? "", on: target)
                    case .deny:
                        try await PairClient.deny(on: target)
                    case .stop:
                        try await PairClient.stop(on: target)
                    case .chat:
                        break
                    }
                    if job.action != .stop {
                        await pollRemote(app: app, target: target)
                    }
                    return
                } catch {
                    liveActivity = "Waiting for Mac"
                }
            }
            try await PairMailbox.publishJob(job, token: binding.token)
            if job.action != .stop {
                await pollMailbox(app: app, binding: binding, sentIDs: Set(messages.map(\.id)))
            }
        } catch {
            if let project = app.selected {
                fail(PairClient.displayMessage(for: error), app: app, project: project)
            } else {
                errorText = PairClient.displayMessage(for: error)
                isStreaming = false
            }
        }
    }

    private func signalRemote(_ job: PairMailbox.Job, binding: PairBinding) async {
        try? await PairMailbox.publishJob(job, token: binding.token)
        if !binding.usesMailbox, let target = try? await PairSession.resolveTarget(for: binding) {
            switch job.action {
            case .stop:
                try? await PairClient.stop(on: target)
            case .allow:
                try? await PairClient.allow(id: job.approvalID ?? "", on: target)
            case .deny:
                try? await PairClient.deny(on: target)
            case .chat:
                break
            }
        }
    }

    private func pollRemote(app: PhoneModel, target: PairTarget) async {
        isStreaming = true
        var holdForApproval = false
        defer {
            if !holdForApproval {
                isStreaming = false
                liveActivity = nil
                streamStartedAt = nil
            }
        }
        do {
            while !Task.isCancelled {
                let status = try await PairClient.status(from: target)
                applyRemoteStatus(status)
                if await finishIfSettled(status, app: app) { return }
                if status.approval != nil {
                    holdForApproval = true
                    return
                }
                try await Task.sleep(for: .milliseconds(350))
            }
        } catch {
            if let project = app.selected {
                fail(PairClient.displayMessage(for: error), app: app, project: project)
            } else {
                errorText = error.localizedDescription
            }
        }
    }

    private func pollMailbox(
        app: PhoneModel,
        binding: PairBinding,
        sentIDs: Set<UUID>
    ) async {
        isStreaming = true
        var holdForApproval = false
        defer {
            if !holdForApproval {
                isStreaming = false
                liveActivity = nil
                streamStartedAt = nil
            }
        }
        for step in 0..<90 {
            if Task.isCancelled { return }
            if step > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            if let status = try? await PairMailbox.latestStatus(token: binding.token) {
                applyRemoteStatus(status)
                if await finishIfSettled(status, app: app, knownIDs: sentIDs) {
                    return
                }
                if status.approval != nil {
                    holdForApproval = true
                    return
                }
                continue
            }
            if await pullRemoteTranscript(app: app, knownIDs: sentIDs) {
                liveAssistant = ""
                liveReasoning = ""
                liveSteps = []
                return
            }
        }
        if let project = app.selected {
            fail(
                "The Mac did not pick up that chat. Keep Joyflow open on the desktop and try again.",
                app: app,
                project: project
            )
        } else {
            errorText = "The Mac did not pick up that chat."
            isStreaming = false
        }
    }

    private func applyRemoteStatus(_ status: PairControlStatus) {
        liveAssistant = status.text
        liveReasoning = status.reasoning
        liveActivity = status.activity
        pendingApproval = status.approval
        errorText = status.error
        liveSteps = status.steps.enumerated().map { index, title in
            WorkStep(id: Self.stableStepID(index), title: title)
        }
        if streamStartedAt == nil { streamStartedAt = Date() }
    }

    private func finishIfSettled(
        _ status: PairControlStatus,
        app: PhoneModel,
        knownIDs: Set<UUID>? = nil
    ) async -> Bool {
        guard !status.streaming, status.approval == nil else { return false }
        if let error = status.error, !error.isEmpty {
            if let project = app.selected ?? resumeProject {
                fail(error, app: app, project: project)
            } else {
                errorText = error
            }
            liveAssistant = ""
            liveReasoning = ""
            liveSteps = []
            return true
        }
        if await pullRemoteTranscript(app: app, knownIDs: knownIDs) {
            liveAssistant = ""
            liveReasoning = ""
            liveSteps = []
            return true
        }
        let text = status.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, let project = app.selected {
            liveAssistant = status.text
            liveReasoning = status.reasoning
            finishAssistant(app: app, project: project)
            return true
        }
        return false
    }

    private func pullRemoteTranscript(app: PhoneModel, knownIDs: Set<UUID>?) async -> Bool {
        try? await PairSession.pull(into: app.store)
        app.reload()
        refreshTranscript(app: app)
        let before = knownIDs ?? []
        return messages.contains { record in
            record.role == "assistant" && !before.contains(record.id)
        }
    }

    private func refreshTranscript(app: PhoneModel) {
        guard let project = app.selected else { return }
        messages = (try? app.store.messages(projectID: project.id, threadID: threadID)) ?? []
    }

    private static func stableStepID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012x", UInt64(index))) ?? UUID()
    }

    private func startReply(app: PhoneModel, project: ProjectManifest) async {
        guard let endpoint = app.activeEndpoint else {
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

    private func startingHistory(app: PhoneModel, project: ProjectManifest) -> [ChatMessage] {
        let resources = app.resources(for: project)
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
            linkedCommons: nil,
            links: (try? resources.links()) ?? [],
            documentNames: (try? resources.documents()) ?? [],
            folderNames: folders,
            earlierSummary: compact.summary
        )
        var history: [ChatMessage] = [ChatMessage(role: "system", content: system)]
        history += compact.kept.map { ChatMessage(role: $0.role, content: $0.content, reasoning: $0.reasoning) }
        return history
    }

    private func loop(app: PhoneModel, project: ProjectManifest, client: GatewayClient, history: [ChatMessage]) async {
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
                    finishAssistant(app: app, project: project)
                    return
                }
                let turn = try await stream(
                    client: client,
                    history: history,
                    tools: skipTools ? [] : ToolCatalog.definitions
                )
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
                                ChatMessage(
                                    role: "assistant",
                                    content: turn.text.isEmpty ? nil : turn.text,
                                    toolCalls: calls,
                                    reasoning: turn.reasoning.isEmpty ? nil : turn.reasoning
                                ),
                            ]
                            pendingApproval = AgentLoop().review(toolName: call.name, arguments: call.arguments)
                            pendingApproval?.id = call.id
                            pushStep("Waiting for approval")
                            return
                        }
                        pushStep("Working")
                        let result: String
                        do {
                            result = try await execute(call, app: app, project: project)
                        } catch {
                            result = error.localizedDescription
                        }
                        results.append((call, result))
                    }
                    history.append(
                        ChatMessage(
                            role: "assistant",
                            content: turn.text.isEmpty ? nil : turn.text,
                            toolCalls: calls,
                            reasoning: turn.reasoning.isEmpty ? nil : turn.reasoning
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
                finishAssistant(app: app, project: project)
                return
            }
            history.append(ChatMessage(role: "user", content: ReplyNudge.stepBudgetMessage))
            pushStep("Writing")
            let wrap = try await stream(client: client, history: history, tools: [])
            if let message = wrap.error {
                fail(message, app: app, project: project)
                return
            }
            if !wrap.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                liveAssistant = wrap.text
                if !wrap.reasoning.isEmpty { liveReasoning = wrap.reasoning }
                finishAssistant(app: app, project: project)
                return
            }
            fail(
                "I used too many steps without finishing. Say what you wanted again in one sentence.",
                app: app,
                project: project
            )
        } catch is CancellationError {
            finishAssistant(app: app, project: project)
        } catch {
            fail(PairClient.displayMessage(for: error), app: app, project: project)
        }
    }

    private struct StreamTurn {
        var text: String
        var reasoning: String
        var tools: PhoneToolAccumulator
        var error: String?
    }

    private func stream(
        client: GatewayClient,
        history: [ChatMessage],
        tools: [ToolDefinition]
    ) async throws -> StreamTurn {
        let request = try client.makeRequest(
            messages: history,
            tools: tools,
            stream: true,
            reasoningEffort: tools.isEmpty ? "low" : "medium",
            toolChoice: tools.isEmpty ? "none" : nil
        )
        let (bytes, response) = try await Self.session.bytes(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            var body = ""
            for try await line in bytes.lines { body += line }
            return StreamTurn(text: "", reasoning: "", tools: PhoneToolAccumulator(), error: "HTTP \(http.statusCode) \(body)")
        }
        var parser = StreamParser()
        var buffer = ""
        var assembled = PhoneToolAccumulator()
        var text = ""
        var reasoning = ""
        for try await line in bytes.lines {
            if Task.isCancelled { throw CancellationError() }
            buffer += line + "\n"
            for event in parser.parse(buffer: &buffer) {
                switch event {
                case .text(let chunk):
                    text += chunk
                    liveAssistant += chunk
                    pushStep("Writing")
                case .reasoning(let chunk):
                    reasoning += chunk
                    liveReasoning += chunk
                case .toolCall(let delta):
                    assembled.apply(delta)
                case .error(let message):
                    return StreamTurn(text: text, reasoning: reasoning, tools: assembled, error: message)
                case .finished, .reasoningDetail:
                    break
                }
            }
        }
        for event in parser.finish(buffer: &buffer) {
            if case .text(let chunk) = event {
                text += chunk
                liveAssistant += chunk
            }
            if case .reasoning(let chunk) = event {
                reasoning += chunk
                liveReasoning += chunk
            }
            if case .toolCall(let delta) = event { assembled.apply(delta) }
        }
        return StreamTurn(text: text, reasoning: reasoning, tools: assembled, error: nil)
    }

    private func execute(_ call: ToolCall, app: PhoneModel, project: ProjectManifest) async throws -> String {
        let writeRoot = try app.store.writeRoot(for: project.id)
        let computer = try ComputerRouter.computer(
            app.computer,
            workspace: writeRoot,
            extraRoots: app.resources(for: project).resolvedFolders().map(\.1),
            credentials: app.sandboxCredentials
        )
        let dispatcher = ToolDispatcher(
            store: app.store,
            projectID: project.id,
            computer: computer,
            composioKey: app.keychain.get(KeychainStore.composioAccount),
            composioAccounts: app.composioAccounts,
            lookupCLI: false
        )
        let result = try await dispatcher.execute(name: call.name, argumentsJSON: call.arguments)
        app.reload()
        return result
    }

    func pushStep(_ title: String) {
        if liveSteps.last?.title == title { return }
        liveSteps.append(WorkStep(id: UUID(), title: title))
        liveActivity = title
    }

    private func finishAssistant(app: PhoneModel, project: ProjectManifest) {
        let text = liveAssistant.trimmingCharacters(in: .whitespacesAndNewlines)
        let thought = liveReasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        liveAssistant = ""
        liveReasoning = ""
        liveActivity = nil
        liveSteps = []
        guard !text.isEmpty else { return }
        let record = ChatMessageRecord(
            role: "assistant",
            content: text,
            reasoning: thought.isEmpty ? nil : thought
        )
        messages.append(record)
        try? app.store.appendMessage(projectID: project.id, threadID: threadID, message: record)
    }

    private func fail(_ text: String, app: PhoneModel, project: ProjectManifest) {
        errorText = text
        isStreaming = false
        pendingApproval = nil
        let record = ChatMessageRecord(role: "assistant", content: text)
        messages.append(record)
        try? app.store.appendMessage(projectID: project.id, threadID: threadID, message: record)
        liveAssistant = ""
        liveReasoning = ""
        liveActivity = nil
        liveSteps = []
        streamStartedAt = nil
    }
}

struct PhoneToolAccumulator: Sendable {
    var calls: [Int: ToolCall] = [:]

    mutating func apply(_ delta: ToolCallDelta) {
        var current = calls[delta.index] ?? ToolCall(id: delta.id ?? UUID().uuidString, name: delta.name ?? "", arguments: "")
        if let id = delta.id { current.id = id }
        if let name = delta.name, !name.isEmpty { current.name = name }
        current.arguments += delta.argumentsFragment
        calls[delta.index] = current
    }

    var sortedCalls: [ToolCall] { calls.sorted(by: { $0.key < $1.key }).map(\.value) }
}
