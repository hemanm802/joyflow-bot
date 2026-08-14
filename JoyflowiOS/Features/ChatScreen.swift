import JoyflowKit
import SwiftUI

struct ChatScreen: View {
    @Environment(PhoneModel.self) private var app
    @Environment(PhoneChat.self) private var chat
    @State private var draft = ""
    @State private var knowledgeOpen = false
    @State private var clearAllChats = false
    @State private var earlierOpen = false
    @State private var followStream = true
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let project = app.selected {
                transcript(project)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        PhoneComposer(
                            text: $draft,
                            projectName: project.name,
                            isStreaming: chat.isStreaming,
                            onSend: { send() },
                            onStop: { chat.stop(app: app) }
                        )
                        .focused($focused)
                    }
            } else {
                ContentUnavailableView {
                    Label {
                        Text("Select a project")
                    } icon: {
                        Image(systemName: "bubble.left")
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(Theme.chromeMuted)
                    }
                }
                .foregroundStyle(Theme.chromeMuted)
            }
        }
        .background(Theme.background)
        .navigationTitle(app.selected?.name ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(removing: .sidebarToggle)
        .tint(Theme.accent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    chat.startNewThread(app: app)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Theme.chrome)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(app.selected == nil)
                .accessibilityLabel("New chat")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("New chat") { chat.startNewThread(app: app) }
                    if let project = app.selected {
                        let chats = app.chats(for: project, current: chat.threadID)
                        if !chats.isEmpty {
                            Divider()
                            ForEach(chats) { item in
                                Button(item.title) {
                                    chat.openThread(item.id, in: project.id, app: app)
                                }
                            }
                        }
                    }
                    Divider()
                    Button("Clear this chat") { chat.clearCurrentThread(app: app) }
                    Button("Clear all chats", role: .destructive) { clearAllChats = true }
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 16, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Theme.chromeMuted)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .disabled(app.selected == nil)
                .accessibilityLabel("Chats")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    knowledgeOpen = true
                } label: {
                    Image(systemName: "text.book.closed")
                        .font(.system(size: 16, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Theme.chromeMuted)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(app.selected == nil)
                .accessibilityLabel("Knowledge")
            }
        }
        .confirmationDialog(
            "Clear every chat in this project?",
            isPresented: $clearAllChats,
            titleVisibility: .visible
        ) {
            Button("Clear all chats", role: .destructive) { chat.clearAllThreads(app: app) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Project knowledge and files stay. Only conversations are removed.")
        }
        .sheet(isPresented: $knowledgeOpen) {
            if let project = app.selected {
                KnowledgeScreen(project: project)
            }
        }
        .onAppear { chat.load(app: app) }
        .onChange(of: app.selectedProjectID) { _, _ in
            guard !chat.isStreaming else { return }
            chat.load(app: app)
        }
        .onChange(of: app.selectedThreadID) { _, _ in
            guard !chat.isStreaming else { return }
            chat.load(app: app)
        }
        .accessibilityIdentifier("ios.chat")
    }

    private func transcript(_ project: ProjectManifest) -> some View {
        let compact = ChatCompaction.apply(chat.messages)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if compact.isCompacted {
                        Button {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.88)) {
                                earlierOpen.toggle()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: earlierOpen ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(earlierOpen ? "Hide earlier" : "Earlier in this chat")
                                    .font(.system(size: 14, weight: .medium))
                                Text("\(compact.foldedCount)")
                                    .font(.system(size: 13).monospacedDigit())
                                Spacer()
                            }
                            .foregroundStyle(Theme.chromeMuted)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(Theme.raised, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Earlier in this chat")
                        if earlierOpen {
                            ForEach(compact.folded) { message in
                                bubbleStack(message)
                                    .opacity(0.72)
                            }
                        }
                        ForEach(compact.kept) { message in
                            bubbleStack(message)
                        }
                    } else {
                        ForEach(chat.messages) { message in
                            bubbleStack(message)
                        }
                    }
                    if let error = chat.errorText, !error.isEmpty,
                        chat.messages.last?.content != error
                    {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                    if chat.isStreaming || chat.pendingApproval != nil {
                        WorkSteps(steps: chat.liveSteps, startedAt: chat.streamStartedAt)
                    }
                    if !chat.liveAssistant.isEmpty {
                        MessageBubble(message: ChatMessageRecord(role: "assistant", content: chat.liveAssistant))
                    }
                    if let pending = chat.pendingApproval {
                        ApprovalCard(
                            approval: pending,
                            onAllow: { Task { await chat.allow(app: app) } },
                            onAlwaysAllow: {
                                app.defaultReview = .allow
                                app.persistSettings()
                                Task { await chat.allow(app: app) }
                            },
                            onDeny: { Task { await chat.deny(app: app) } }
                        )
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                TranscriptFollow.isPinnedToBottom(
                    contentOffsetY: geometry.contentOffset.y,
                    contentHeight: geometry.contentSize.height,
                    viewportHeight: geometry.containerSize.height
                )
            } action: { _, pinned in
                followStream = pinned
            }
            .onChange(of: chat.liveAssistant) { _, _ in
                if TranscriptFollow.shouldFollow(pinnedToBottom: followStream) {
                    proxy.scrollTo("end", anchor: .bottom)
                }
            }
            .onChange(of: chat.messages.count) { _, _ in
                if TranscriptFollow.shouldFollow(pinnedToBottom: followStream) {
                    proxy.scrollTo("end", anchor: .bottom)
                }
            }
        }
    }

    private func send() {
        let text = draft
        draft = ""
        Task { await chat.send(text: text, app: app) }
    }

    private func bubbleStack(_ message: ChatMessageRecord) -> some View {
        Group {
            if message.role == "assistant", let thought = message.reasoning, !thought.isEmpty {
                ThoughtBlock(text: thought)
            }
            MessageBubble(message: message) {
                chat.deleteMessage(id: message.id, app: app)
            }
        }
    }
}

private struct MessageBubble: View {
    var message: ChatMessageRecord
    var onDelete: (() -> Void)?

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 48) }
            Group {
                if isUser {
                    Text(message.content)
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textPrimary)
                } else {
                    ChatMarkdown(text: message.content)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contextMenu {
                if let onDelete {
                    Button("Delete", role: .destructive, action: onDelete)
                }
            }
            .background(isUser ? Theme.raised : Theme.card, in: RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
            if !isUser { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .accessibilityIdentifier(isUser ? "ios.chat.user" : "ios.chat.assistant")
    }
}

private struct ThoughtBlock: View {
    var text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Thought")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(Theme.textSecondary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Thought")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded {
                Text(text)
                    .font(.system(size: 14))
                    .italic()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

private struct WorkSteps: View {
    var steps: [WorkStep]
    var startedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShimmerLabel(text: steps.last?.title ?? "Thinking")
            ForEach(Array(steps.dropLast())) { step in
                Text(step.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityLabel(steps.last?.title ?? "Thinking")
    }
}

private struct ShimmerLabel: View {
    var text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 60 : 1.0 / 30, paused: reduceMotion)) { timeline in
            let cycle = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.55) / 1.55
            let start = cycle * 1.7 - 0.35
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(
                    reduceMotion
                        ? AnyShapeStyle(Theme.textSecondary)
                        : AnyShapeStyle(
                            LinearGradient(
                                colors: [
                                    Theme.textSecondary.opacity(0.42),
                                    Theme.textPrimary,
                                    Theme.textSecondary.opacity(0.42),
                                ],
                                startPoint: UnitPoint(x: start, y: 0.5),
                                endPoint: UnitPoint(x: start + 0.38, y: 0.5)
                            )
                        )
                )
        }
    }
}

private struct ChatMarkdown: View {
    var text: String

    var body: some View {
        let document = KnowledgeDocument.parse(text)
        VStack(alignment: .leading, spacing: 12) {
            if document.blocks.isEmpty {
                inline(text, size: 16)
            } else {
                ForEach(document.blocks) { block in
                    switch block.kind {
                    case .heading(_, let heading):
                        inline(heading, size: 17)
                    case .paragraph(let spans):
                        inline(spans.map(\.text).joined(), size: 16)
                    case .list(let items):
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(items) { item in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(item.ordinal.map { "\($0)." } ?? "•")
                                        .font(.system(size: 16, weight: .medium).monospacedDigit())
                                        .foregroundStyle(Theme.textSecondary)
                                        .frame(minWidth: 20, alignment: .trailing)
                                    inline(item.visibleText, size: 16)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ markdown: String, size: CGFloat) -> some View {
        Text(Self.attributed(markdown, size: size))
            .font(.system(size: size))
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.link)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static func attributed(_ markdown: String, size: CGFloat) -> AttributedString {
        let clipped = String(markdown.prefix(20_000))
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible
        guard var parsed = try? AttributedString(markdown: clipped, options: options) else {
            return AttributedString(clipped)
        }
        for run in parsed.runs {
            if run.link != nil {
                parsed[run.range].foregroundColor = Theme.link
                parsed[run.range].underlineStyle = .single
            } else if run.inlinePresentationIntent?.contains(.code) == true {
                parsed[run.range].font = .system(size: size, design: .monospaced)
            }
        }
        return parsed
    }
}

private struct ApprovalCard: View {
    var approval: PendingApproval
    var onAllow: () -> Void
    var onAlwaysAllow: () -> Void
    var onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Joyflow wants to \(approval.displayTitle.lowercased())")
                .font(.system(size: 16, weight: .semibold))
            Text(approval.displayDetail)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
            VStack(spacing: 8) {
                Button(action: onAllow) {
                    Text("Allow")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                Button(action: onAlwaysAllow) {
                    Text("Always allow")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.chrome)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(Theme.raised, in: Capsule())
                }
                .buttonStyle(.plain)
                Button(action: onDeny) {
                    Text("Deny")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct PhoneComposer: View {
    @Binding var text: String
    var projectName: String
    var isStreaming: Bool
    var onSend: () -> Void
    var onStop: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message \(projectName)", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .lineLimit(1...6)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Button(action: isStreaming ? onStop : onSend) {
                Image(systemName: isStreaming ? "stop.fill" : (canSend ? "arrow.up" : "mic"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle((canSend || isStreaming) ? Theme.onAccent : Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(
                        (canSend || isStreaming) ? Theme.sendEnabledFill : Theme.sendIdleFill,
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isStreaming && !canSend)
            .accessibilityLabel(isStreaming ? "Stop" : (canSend ? "Send message" : "Talk"))
        }
        .padding(.leading, 6)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.borderSubtle.opacity(0.6), lineWidth: 1))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .background(Theme.background)
    }
}
