import AppKit
import JoyflowKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(ChatRuntime.self) private var runtime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft = ""
    @State private var voice = VoiceCapture()
    @State private var clearAllChats = false
    @State private var chatsOpen = false

    var body: some View {
        Group {
            if ScreenshotSupport.requestedPane == "plugins" {
                PluginsSheet()
                    .environment(app)
            } else {
                workspace
            }
        }
        .background(Theme.background)
        .joyflowWindowChrome()
        .toolbar(removing: .title)
        .sheet(isPresented: Bindable(app).pluginsOpen) {
            PluginsSheet()
                .environment(app)
                .frame(width: 820, height: 620)
        }
        .sheet(isPresented: Bindable(app).aboutOpen) {
            AboutView()
        }
        .sheet(isPresented: Bindable(app).pairOpen) {
            PairSheet()
                .environment(app)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: app.inspectorVisible)
        .animation(
            app.sidebarDragging || reduceMotion ? nil : .easeInOut(duration: 0.26),
            value: app.displayedSidebarWidth
        )
        .confirmationDialog(
            "Clear every chat in this project?",
            isPresented: $clearAllChats,
            titleVisibility: .visible
        ) {
            Button("Clear all chats", role: .destructive) {
                runtime.clearAllThreads(app: app)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Project knowledge and files stay. Only conversations are removed.")
        }
        .onAppear(perform: configureLaunch)
    }

    private var workspace: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: app.displayedSidebarWidth)
                .frame(maxHeight: .infinity)
                .zIndex(1)
                .overlay(alignment: .trailing) {
                    SidebarResizeHandle()
                }

            chatColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if app.inspectorVisible, let project = app.selected {
                KnowledgeInspector(project: project)
                    .frame(maxHeight: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .coordinateSpace(name: "workspace")
        .background(Theme.background)
        .overlay(alignment: .topLeading) {
            if app.sidebarCollapsed {
                railPeekCard
            }
            if let sessionsID = app.railSessionsID,
                let project = app.projects.first(where: { $0.id == sessionsID })
            {
                railSessionsOverlay(for: project)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: app.railPeekID)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: app.railSessionsID)
        .overlay {
            if app.searchOpen {
                searchOverlay
            }
            if app.settingsOpen {
                settingsOverlay
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: app.searchOpen)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: app.settingsOpen)
    }

    @ViewBuilder
    private var railPeekCard: some View {
        if let id = app.railPeekID,
            let project = app.projects.first(where: { $0.id == id })
        {
            let all = (try? app.store.listThreads(projectID: project.id)) ?? []
            let bridge = Theme.sidebarRailInset
            HStack(alignment: .top, spacing: 0) {
                Color.clear
                    .frame(width: bridge, height: Theme.sidebarRailButton)
                    .contentShape(Rectangle())
                ProjectHoverCard(
                    project: project,
                    preview: app.previewLine(for: project),
                    chats: Array(all.prefix(3)),
                    totalCount: all.count,
                    selectedThreadID: runtime.threadID,
                    imageData: app.avatarData(for: project),
                    onOpenChat: { threadID in
                        runtime.openThread(threadID, in: project.id, app: app)
                        app.dismissRailPeek(freezing: id)
                    },
                    onSeeAll: {
                        app.openRailSessions(for: project.id)
                    }
                )
            }
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    app.holdRailPeek(id)
                } else {
                    app.releaseRailPeek(id)
                }
            }
            .padding(.leading, app.displayedSidebarWidth - bridge)
            .padding(.top, max(12, app.railPeekY - 28))
            .transition(
                reduceMotion
                    ? .opacity
                    : .opacity.combined(with: .scale(scale: 0.98, anchor: .leading))
            )
            .zIndex(4)
        }
    }

    private func railSessionsOverlay(for project: ProjectManifest) -> some View {
        let chats = (try? app.store.listThreads(projectID: project.id)) ?? []
        return ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: app.displayedSidebarWidth)
                    .allowsHitTesting(false)
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { app.closeRailSessions() }
            }
            ChatListMenu(
                chats: chats,
                currentID: runtime.threadID,
                onNew: {
                    app.select(project.id)
                    runtime.startNewThread(app: app)
                    app.closeRailSessions()
                },
                onOpen: { id in
                    runtime.openThread(id, in: project.id, app: app)
                    app.closeRailSessions()
                },
                onClear: {
                    app.select(project.id)
                    runtime.load(app: app)
                    runtime.clearCurrentThread(app: app)
                },
                onClearAll: {
                    app.select(project.id)
                    runtime.load(app: app)
                    app.closeRailSessions()
                    clearAllChats = true
                }
            )
            .padding(.leading, app.displayedSidebarWidth)
            .padding(.top, max(12, app.railPeekY - 28))
            .transition(
                reduceMotion
                    ? .opacity
                    : .opacity.combined(with: .scale(scale: 0.98, anchor: .leading))
            )
        }
        .zIndex(5)
    }

    private var searchOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { app.closeSearch() }
            CommandPalette()
                .padding(.horizontal, 28)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private var settingsOverlay: some View {
        ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .onTapGesture { app.closeSettings() }
            SettingsView(embedded: true, onClose: { app.closeSettings() })
                .environment(app)
                .frame(maxWidth: 960, maxHeight: 680)
                .padding(22)
                .shadow(color: Color.black.opacity(0.38), radius: 28, y: 12)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
        .onExitCommand { app.closeSettings() }
    }

    @ViewBuilder
    private var chatColumn: some View {
        if let project = app.selected {
            VStack(spacing: 0) {
                chatHeader(project)
                if runtime.messages.isEmpty
                    && runtime.liveAssistant.isEmpty
                    && runtime.liveReasoning.isEmpty
                    && !runtime.isStreaming
                    && runtime.pendingApproval == nil
                {
                    emptyChat(named: project.name)
                } else {
                    TranscriptView(
                        messages: runtime.messages,
                        live: runtime.liveAssistant,
                        reasoning: runtime.liveReasoning,
                        activity: runtime.liveActivity,
                        steps: runtime.liveSteps,
                        isStreaming: runtime.isStreaming,
                        startedAt: runtime.streamStartedAt,
                        pending: runtime.pendingApproval,
                        onAllow: { Task { await runtime.allow(app: app) } },
                        onAlwaysAllow: {
                            app.defaultReview = .allow
                            app.persistSettings()
                            Task { await runtime.allow(app: app) }
                        },
                        onDeny: { Task { await runtime.deny(app: app) } },
                        onEdit: { message, text in
                            Task { await runtime.editAndResend(id: message.id, text: text, app: app) }
                        },
                        onCopy: { text in
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        },
                        onDelete: { message in
                            runtime.deleteMessage(id: message.id, app: app)
                        }
                    )
                }
                ComposerView(
                    text: $draft,
                    projectName: project.name,
                    isStreaming: runtime.isStreaming,
                    isRecording: voice.isRecording,
                    isTranscribing: voice.isTranscribing,
                    voiceLevels: voice.levels,
                    voiceError: voice.errorText,
                    onAttach: { attachItem(to: project) },
                    onSend: send,
                    onStop: { runtime.stop(app: app) },
                    onMic: {
                        voice.toggle(
                            transcribe: { data in
                                try await app.transcriptionRouter().transcribe(audio: data, settings: app.speechSettings())
                            },
                            apply: { spoken in
                                draft = VoiceDraft.fill(existing: draft, transcript: spoken)
                            }
                        )
                    }
                )
            }
            .background(Theme.background)
            .overlay {
                if chatsOpen {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { chatsOpen = false }
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .topTrailing) {
                if chatsOpen {
                    chatMenuOverlay(for: project)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing))
                        )
                        .zIndex(2)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: chatsOpen)
            .onChange(of: app.selectedProjectID) { _, _ in chatsOpen = false }
        } else {
            NewChatPicker()
        }
    }

    private func chatHeader(_ project: ProjectManifest) -> some View {
        let chats = app.chats(for: project, current: runtime.threadID)
        let title = chats.first(where: { $0.id == runtime.threadID })?.title ?? "New chat"
        return HStack(spacing: 8) {
            ProjectOrb(id: project.id, size: 20, imageData: app.avatarData(for: project), icon: project.icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                runtime.startNewThread(app: app)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New chat")
            .accessibilityLabel("New chat")

            Button {
                chatsOpen.toggle()
            } label: {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 13, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(chatsOpen ? Theme.textPrimary : Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(chatsOpen ? Theme.raised : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(chatsOpen ? "" : "Chats")
            .accessibilityLabel("Chats")
            .accessibilityValue(chatsOpen ? "Open" : "Closed")

            Button {
                app.inspectorVisible.toggle()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(app.inspectorVisible ? Theme.textPrimary : Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Knowledge")
            .accessibilityLabel("Knowledge")
        }
        .padding(.horizontal, 20)
        .frame(height: Theme.trafficClearance)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(0.85))
                .frame(height: 1)
                .accessibilityIdentifier("chat.header.rule")
        }
    }

    private func chatMenuOverlay(for project: ProjectManifest) -> some View {
        let chats = app.chats(for: project, current: runtime.threadID)
        return VStack(spacing: 0) {
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.card)
                .offset(x: 46, y: 1)
                .allowsHitTesting(false)
            ChatListMenu(
                chats: chats,
                currentID: runtime.threadID,
                onNew: {
                    chatsOpen = false
                    runtime.startNewThread(app: app)
                },
                onOpen: { id in
                    chatsOpen = false
                    runtime.openThread(id, in: project.id, app: app)
                },
                onClear: {
                    chatsOpen = false
                    runtime.clearCurrentThread(app: app)
                },
                onClearAll: {
                    chatsOpen = false
                    clearAllChats = true
                }
            )
        }
        .padding(.trailing, 18)
        .padding(.top, Theme.trafficClearance - 6)
    }

    private func emptyChat(named name: String) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("chat.empty")
            .accessibilityLabel("Message \(name)")
    }

    private var commandPalette: some View {
        NewChatPicker()
    }

    private func attachItem(to project: ProjectManifest) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Add file or folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        let store = app.resources(for: project)
        do {
            if isDir.boolValue {
                _ = try store.addFolder(from: url)
            } else {
                _ = try store.addDocument(from: url)
            }
            app.resourceError = nil
            app.inspectorVisible = true
            app.reload()
        } catch {
            app.resourceError = error.localizedDescription
            app.inspectorVisible = true
        }
    }

    private func send() {
        let text = draft
        draft = ""
        Task { await runtime.send(text: text, app: app) }
    }

    private func configureLaunch() {
        if let appearance = ScreenshotSupport.requestedAppearance {
            app.appearance = appearance == "light" ? .light : .dark
        }
        if ScreenshotSupport.requestedPane == "plugins" {
            app.pluginsOpen = true
        }
        if ScreenshotSupport.requestedPane == "knowledge" {
            app.inspectorVisible = true
        }
        if ScreenshotSupport.requestedPane == "settings" {
            app.settingsOpen = true
        }
        ScreenshotSupport.scheduleCaptureIfRequested()
    }
}

struct SidebarResizeHandle: View {
    @Environment(AppModel.self) private var app
    @State private var origin: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Theme.borderSubtle.opacity(0.45))
            .frame(width: 1)
            .padding(.vertical, 0)
            .frame(maxHeight: .infinity)
            .overlay {
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
            }
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if origin == nil {
                            origin = app.sidebarWidth
                            app.sidebarDragging = true
                        }
                        guard let origin else { return }
                        app.setSidebarWidth(origin + value.translation.width)
                    }
                    .onEnded { value in
                        let start = origin ?? app.sidebarWidth
                        origin = nil
                        app.finishSidebarDrag(start + value.translation.width)
                    }
            )
            .help("Drag to resize")
            .accessibilityLabel("Resize sidebar")
    }
}

private struct ChatListMenu: View {
    var chats: [ThreadSummary]
    var currentID: UUID
    var onNew: () -> Void
    var onOpen: (UUID) -> Void
    var onClear: () -> Void
    var onClearAll: () -> Void
    @State private var hot: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row("new", "plus", "New chat", subtitle: "Fresh context in this project") {
                onNew()
            }
            if !chats.isEmpty {
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(0.7))
                    .frame(height: 1)
                    .padding(.vertical, 6)
                ForEach(chats) { chat in
                    row(
                        chat.id.uuidString,
                        "bubble.left",
                        chat.title,
                        subtitle: chat.preview,
                        selected: chat.id == currentID
                    ) {
                        onOpen(chat.id)
                    }
                }
            }
            Rectangle()
                .fill(Theme.borderSubtle.opacity(0.7))
                .frame(height: 1)
                .padding(.vertical, 6)
            row("clear", "trash", "Clear this chat", subtitle: "Keep the project, empty this thread") {
                onClear()
            }
            row("clear-all", "trash", "Clear all chats…", subtitle: "Every conversation in this project", danger: true) {
                onClearAll()
            }
        }
        .padding(6)
        .frame(width: 260)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.85), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.28), radius: 18, y: 8)
        .accessibilityIdentifier("chat.list.menu")
    }

    private func row(
        _ id: String,
        _ systemName: String,
        _ title: String,
        subtitle: String,
        selected: Bool = false,
        danger: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(danger ? Theme.danger : Theme.textSecondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(danger ? Theme.danger : Theme.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                hot == id ? Theme.selection : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hot = inside ? id : (hot == id ? nil : hot)
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
