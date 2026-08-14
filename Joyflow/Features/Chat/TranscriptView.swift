import JoyflowKit
import SwiftUI

struct TranscriptView: View {
    var messages: [ChatMessageRecord]
    var live: String
    var reasoning: String
    var activity: String?
    var steps: [WorkStep] = []
    var isStreaming: Bool
    var startedAt: Date?
    var pending: PendingApproval?
    var onAllow: () -> Void
    var onAlwaysAllow: () -> Void
    var onDeny: () -> Void
    var onEdit: (ChatMessageRecord, String) -> Void
    var onCopy: (String) -> Void
    var onDelete: (ChatMessageRecord) -> Void
    @State private var earlierOpen = false
    @State private var followStream = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let compact = ChatCompaction.apply(messages)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let stamp = messages.first?.createdAt {
                        Text(stamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 4)
                    }
                    if compact.isCompacted {
                        earlierToggle(compact)
                        if earlierOpen {
                            ForEach(compact.folded) { message in
                                messageStack(message)
                                    .opacity(0.72)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        ForEach(compact.kept) { message in
                            messageStack(message)
                        }
                    } else {
                        ForEach(messages) { message in
                            messageStack(message)
                        }
                    }
                    if isStreaming || pending != nil {
                        WorkRail(steps: steps, startedAt: startedAt)
                    }
                    if !live.isEmpty {
                        TranscriptRow(
                            message: ChatMessageRecord(role: "assistant", content: live),
                            streaming: isStreaming,
                            showTimestamp: false,
                            onEdit: { _ in },
                            onCopy: { onCopy(live) },
                            onDelete: {}
                        )
                    }
                    if let pending {
                        ApprovalCard(
                            approval: pending,
                            onAllow: onAllow,
                            onAlwaysAllow: onAlwaysAllow,
                            onDeny: onDeny
                        )
                    }
                    Color.clear.frame(height: 1).id("transcript.end")
                }
                .padding(.horizontal, 28)
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
            .onChange(of: live) { _, _ in
                if TranscriptFollow.shouldFollow(pinnedToBottom: followStream) { scroll(proxy) }
            }
            .onChange(of: reasoning) { _, _ in
                if TranscriptFollow.shouldFollow(pinnedToBottom: followStream) { scroll(proxy) }
            }
            .onChange(of: messages.count) { _, _ in
                if TranscriptFollow.shouldFollow(pinnedToBottom: followStream) { scroll(proxy) }
            }
            .onAppear {
                followStream = true
                scroll(proxy)
            }
            .onChange(of: messages.count) { _, _ in
                if !ChatCompaction.apply(messages).isCompacted {
                    earlierOpen = false
                }
            }
        }
    }

    private func messageStack(_ message: ChatMessageRecord) -> some View {
        Group {
            if message.role == "assistant", let thought = message.reasoning, !thought.isEmpty {
                ThinkingBlock(text: thought, activity: nil, active: false, startedAt: nil)
            }
            TranscriptRow(
                message: message,
                streaming: false,
                onEdit: { onEdit(message, $0) },
                onCopy: { onCopy(message.content) },
                onDelete: { onDelete(message) }
            )
        }
    }

    private func earlierToggle(_ compact: CompactedHistory) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.88)) {
                earlierOpen.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: earlierOpen ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 10)
                Text(earlierOpen ? "Hide earlier" : "Earlier in this chat")
                    .font(.system(size: 12, weight: .medium))
                Text("·")
                Text("\(compact.foldedCount)")
                    .font(.system(size: 12).monospacedDigit())
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Theme.raised, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 560, alignment: .leading)
        .accessibilityLabel("Earlier in this chat")
        .accessibilityValue(earlierOpen ? "Expanded" : "Collapsed")
        .accessibilityHint("\(compact.foldedCount) earlier messages")
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        proxy.scrollTo("transcript.end", anchor: .bottom)
    }
}

struct TranscriptRow: View {
    var message: ChatMessageRecord
    var streaming: Bool
    var showTimestamp: Bool = true
    var onEdit: (String) -> Void
    var onCopy: () -> Void
    var onDelete: () -> Void
    @State private var hovering = false
    @State private var editing = false
    @State private var draft = ""
    @State private var copied = false
    @State private var copyReset: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isUser: Bool { message.role == "user" }
    private var showMeta: Bool { hovering && !editing && !streaming && showTimestamp }

    var body: some View {
        HStack(spacing: 0) {
            if isUser { Spacer(minLength: 72) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                bubble
                metaRow
            }
            .frame(maxWidth: 560, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 72) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .onHover { hovering = $0 }
        .onDisappear { copyReset?.cancel() }
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            if isUser {
                metaButton("square.and.pencil", label: "Edit") {
                    draft = message.content
                    editing = true
                }
            } else {
                metaButton(
                    copied ? "checkmark" : "square.on.square",
                    label: copied ? "Copied" : "Copy"
                ) {
                    copy()
                }
            }
            metaButton("trash", label: "Delete") {
                onDelete()
            }
        }
        .opacity(showMeta ? 1 : 0)
        .offset(y: showMeta ? 0 : 3)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: showMeta)
        .allowsHitTesting(showMeta)
        .padding(.horizontal, 4)
        .accessibilityHidden(!showMeta)
    }

    private func metaButton(_ system: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(QuietIconStyle(reduceMotion: reduceMotion))
        .help(label)
        .accessibilityLabel(label)
    }

    private func copy() {
        onCopy()
        if reduceMotion {
            copied = true
        } else {
            withAnimation(.easeOut(duration: 0.16)) { copied = true }
        }
        copyReset?.cancel()
        copyReset = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled else { return }
            if reduceMotion {
                copied = false
            } else {
                withAnimation(.easeOut(duration: 0.16)) { copied = false }
            }
        }
    }

    @ViewBuilder
    private var bubble: some View {
        if editing {
            VStack(alignment: .trailing, spacing: 8) {
                TextField("Message", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1...8)
                    .onSubmit(commitEdit)
                HStack(spacing: 8) {
                    Button("Cancel") { editing = false }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.textSecondary)
                    Button("Save") { commitEdit() }
                        .buttonStyle(.plain)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textPrimary)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .font(.system(size: 12))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.raised)
            .clipShape(RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
        } else if isUser {
            Text(message.content)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.raised)
                .clipShape(RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
        } else if streaming {
            ChatMarkdown(text: message.content, streaming: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
                .transaction { $0.animation = nil }
        } else {
            ChatMarkdown(text: message.content, streaming: false)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
        }
    }

    private func commitEdit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        editing = false
        onEdit(text)
    }

}

private struct QuietIconStyle: ButtonStyle {
    var reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1)
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ThinkingBlock: View {
    var text: String
    var activity: String?
    var active: Bool
    var startedAt: Date?
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .frame(width: 10)
                    Text("Thought")
                        .font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Thought")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")

            if expanded, !text.isEmpty {
                Text(text)
                    .font(.system(size: 13))
                    .italic()
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: 560, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 11)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Theme.borderSubtle)
                            .frame(width: 1.5)
                    }
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .padding(.leading, 4)
    }
}

struct WorkRail: View {
    var steps: [WorkStep]
    var startedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                ShimmerText(text: steps.last?.title ?? "Thinking", size: 12)
                if let startedAt {
                    ElapsedLabel(from: startedAt, running: true)
                }
                Spacer(minLength: 0)
            }

            if steps.count > 1 {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(steps.dropLast().enumerated()), id: \.element.id) { _, step in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Theme.textSecondary.opacity(0.45))
                                .frame(width: 4, height: 4)
                            Text(step.title)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary.opacity(0.78))
                        }
                        .transition(.opacity.combined(with: .offset(y: 5)))
                    }
                }
                .padding(.leading, 2)
            }
        }
        .padding(.leading, 4)
        .frame(maxWidth: 560, alignment: .leading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: steps.map(\.id))
        .accessibilityLabel(steps.last?.title ?? "Thinking")
    }
}

struct ShimmerText: View {
    var text: String
    var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 60 : 1.0 / 30, paused: reduceMotion)) { timeline in
            let cycle = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.55) / 1.55
            let start = cycle * 1.7 - 0.35
            Text(text)
                .font(.system(size: size, weight: .medium))
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
        .accessibilityHidden(true)
    }
}

struct ElapsedLabel: View {
    var from: Date
    var running: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: running ? 1 : 60)) { timeline in
            let seconds = max(0, Int(timeline.date.timeIntervalSince(from)))
            if seconds > 0 {
                Text(Self.format(seconds))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary.opacity(0.78))
            }
        }
        .accessibilityHidden(true)
    }

    private static func format(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }
}

struct ChatMarkdown: View {
    var text: String
    var streaming: Bool

    var body: some View {
        let document = KnowledgeDocument.parse(text)
        VStack(alignment: .leading, spacing: 12) {
            if document.blocks.isEmpty {
                ChatInlineMarkdown(text: text, size: 15)
            } else {
                ForEach(document.blocks) { block in
                    switch block.kind {
                    case .heading(_, let heading):
                        ChatInlineMarkdown(text: heading, size: 16, weight: .semibold)
                            .padding(.top, 2)
                    case .paragraph(let spans):
                        ChatInlineMarkdown(text: spans.map(\.text).joined(), size: 15)
                    case .list(let items):
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(item.ordinal.map { "\($0)." } ?? "•")
                                        .font(.system(size: 15, weight: .medium).monospacedDigit())
                                        .foregroundStyle(Theme.textSecondary)
                                        .frame(minWidth: 18, alignment: .trailing)
                                    ChatInlineMarkdown(text: item.visibleText, size: 15)
                                }
                                .accessibilityLabel(
                                    (item.ordinal.map { "\($0). " } ?? "") + item.visibleText
                                )
                                .padding(.top, index == 0 ? 2 : 0)
                            }
                        }
                    }
                }
            }
            if streaming {
                StreamCaret()
                    .padding(.top, 1)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ChatInlineMarkdown: View {
    var text: String
    var size: CGFloat
    var weight: Font.Weight = .regular

    var body: some View {
        Text(Self.attributed(text, size: size))
            .font(.system(size: size, weight: weight))
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.link)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static func attributed(_ markdown: String, size: CGFloat) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible
        guard var parsed = try? AttributedString(markdown: markdown, options: options) else {
            return AttributedString(markdown)
        }
        for run in parsed.runs {
            if run.link != nil {
                parsed[run.range].foregroundColor = Theme.link
                parsed[run.range].underlineStyle = .single
            } else if run.inlinePresentationIntent?.contains(.code) == true {
                parsed[run.range].font = .system(size: size, design: .monospaced)
                parsed[run.range].foregroundColor = Theme.textPrimary
            }
        }
        return parsed
    }
}

struct StreamCaret: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: reduceMotion ? 60 : 0.53)) { timeline in
            let on = reduceMotion || Int(timeline.date.timeIntervalSinceReferenceDate / 0.53) % 2 == 0
            Capsule()
                .fill(Theme.textPrimary)
                .frame(width: 1.5, height: 13)
                .opacity(on ? 1 : 0)
        }
        .accessibilityHidden(true)
    }
}

struct ApprovalCard: View {
    var approval: PendingApproval
    var onAllow: () -> Void
    var onAlwaysAllow: () -> Void
    var onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Joyflow wants to \(approval.displayTitle.lowercased())")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(approval.displayDetail)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                approvalButton("Allow", prominent: true, action: onAllow)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Allow once")
                approvalButton("Always allow", prominent: false, action: onAlwaysAllow)
                    .accessibilityLabel("Always allow")
                approvalButton("Deny", prominent: false, danger: true, action: onDeny)
                    .accessibilityLabel("Deny")
            }
        }
        .padding(14)
        .frame(maxWidth: 520, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.85), lineWidth: 1)
        }
    }

    private func approvalButton(
        _ title: String,
        prominent: Bool,
        danger: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(prominent ? Theme.onAccent : (danger ? Theme.danger : Theme.textPrimary))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(
                    prominent ? Theme.accent : Theme.raised,
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct ComposerView: View {
    @Binding var text: String
    var projectName: String
    var isStreaming: Bool
    var isRecording: Bool
    var isTranscribing: Bool
    var voiceLevels: [CGFloat] = []
    var voiceError: String?
    var onAttach: () -> Void
    var onSend: () -> Void
    var onStop: () -> Void
    var onMic: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var modelOpen = false

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private enum Action {
        case mic, send, stopVoice, stopTask, transcribe
    }

    private var action: Action {
        if isStreaming { return .stopTask }
        if isTranscribing { return .transcribe }
        if isRecording { return .stopVoice }
        if canSend { return .send }
        return .mic
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(action: onAttach) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add file or folder")
                .accessibilityLabel("Add file or folder")
                .disabled(isRecording)

                Group {
                    if isRecording {
                        VoiceWaveform(levels: voiceLevels)
                            .frame(maxWidth: .infinity)
                            .frame(height: 22)
                            .transition(.opacity)
                    } else {
                        TextField("Message \(projectName)", text: $text, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .lineLimit(1...5)
                            .onSubmit(onSend)
                            .accessibilityLabel("Message")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isRecording)

                HStack(spacing: 2) {
                    if !isRecording {
                        ComposerModelPicker(open: $modelOpen)
                    }
                    actionButton
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .padding(.vertical, 8)
            .frame(minHeight: Theme.composerHeight)
            .background(Theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.borderSubtle.opacity(0.55), lineWidth: 1))
            if let voiceError, !voiceError.isEmpty {
                Text(voiceError)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .padding(.top, 4)
        .overlay {
            if modelOpen {
                Color.clear
                    .frame(width: 2400, height: 2400)
                    .contentShape(Rectangle())
                    .onTapGesture { modelOpen = false }
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if modelOpen, !isRecording {
                VStack(spacing: 0) {
                    ComposerModelMenu { modelOpen = false }
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.card)
                        .offset(x: 78, y: -1)
                        .allowsHitTesting(false)
                }
                .padding(.trailing, 36)
                .padding(.bottom, Theme.composerHeight + 10)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing))
                )
                .zIndex(2)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: modelOpen)
        .onChange(of: isRecording) { _, recording in
            if recording { modelOpen = false }
        }
    }

    private var actionButton: some View {
        Button(action: runAction) {
            Group {
                if action == .transcribe {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: actionSymbol)
                        .font(.system(size: actionFont, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .foregroundStyle(actionArmed ? Theme.onAccent : Theme.textSecondary)
            .frame(width: 30, height: 30)
            .background(actionArmed ? Theme.sendEnabledFill : Theme.sendIdleFill, in: Circle())
        }
        .buttonStyle(ComposerActionStyle(reduceMotion: reduceMotion))
        .disabled(action == .transcribe)
        .help(actionHelp)
        .accessibilityLabel(actionHelp)
    }

    private var actionArmed: Bool {
        switch action {
        case .send, .stopVoice, .stopTask: true
        case .mic, .transcribe: false
        }
    }

    private var actionSymbol: String {
        switch action {
        case .mic: "mic"
        case .send: "arrow.up"
        case .stopVoice, .stopTask: "stop.fill"
        case .transcribe: "mic"
        }
    }

    private var actionFont: CGFloat {
        switch action {
        case .mic: 12
        case .send: 11
        case .stopVoice, .stopTask, .transcribe: 9
        }
    }

    private var actionHelp: String {
        switch action {
        case .mic: "Talk"
        case .send: "Send message"
        case .stopVoice: "Stop and transcribe"
        case .stopTask: "Stop"
        case .transcribe: "Transcribing"
        }
    }

    private func runAction() {
        switch action {
        case .mic, .stopVoice: onMic()
        case .send: onSend()
        case .stopTask: onStop()
        case .transcribe: break
        }
    }
}

private struct ComposerActionStyle: ButtonStyle {
    var reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
