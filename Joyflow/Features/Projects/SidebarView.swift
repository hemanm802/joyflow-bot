import AppKit
import JoyflowKit
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var app
    @Environment(ChatRuntime.self) private var runtime
    @State private var renameTarget: ProjectManifest?
    @State private var renameDraft = ""
    @State private var deleteTarget: ProjectManifest?
    @State private var clearChatsTarget: ProjectManifest?
    @State private var pictureTarget: ProjectManifest?
    @State private var railHoverID: UUID?
    @State private var railHoverMidY: [UUID: CGFloat] = [:]
    @State private var accountMenuOpen = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var collapsed: Bool { app.sidebarCollapsed }

    var body: some View {
        @Bindable var app = app
        VStack(spacing: 0) {
            header
            if collapsed {
                railButton("magnifyingglass", help: "Search", label: "Search", action: app.openSearch)
                    .padding(.bottom, 4)
            } else {
                searchField
                    .padding(.horizontal, Theme.sidebarPad)
                    .padding(.bottom, 10)
            }

            projectList

            if collapsed {
                railFooter
            } else {
                sidebarFooter
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
        .onAppear { runtime.load(app: app) }
        .onChange(of: collapsed) { _, isCollapsed in
            if !isCollapsed {
                railHoverID = nil
                app.dismissRailPeek()
                app.closeRailSessions()
            }
        }
        .onChange(of: app.createProjectRequested) { _, requested in
            if requested {
                app.createProjectRequested = false
                create()
            }
        }
        .alert("Rename Project", isPresented: renamePresented) {
            TextField("Name", text: $renameDraft)
            Button("Save") {
                if let renameTarget {
                    app.renameProject(renameTarget.id, to: renameDraft)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .popover(item: $pictureTarget, arrowEdge: .trailing) { project in
            PicturePicker(
                project: project,
                imageData: app.avatarData(for: project),
                onMark: { mark in
                    app.setProjectMark(project.id, mark: mark)
                    pictureTarget = nil
                },
                onPhoto: { url in
                    app.setProjectAvatar(project.id, from: url)
                    pictureTarget = nil
                }
            )
        }
        .confirmationDialog(
            "Delete \(deleteTarget?.name ?? "this project")?",
            isPresented: deletePresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let deleteTarget {
                    app.deleteProject(deleteTarget.id)
                    runtime.load(app: app)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The project folder will be removed from this Mac.")
        }
        .confirmationDialog(
            "Clear every chat in \(clearChatsTarget?.name ?? "this project")?",
            isPresented: clearChatsPresented,
            titleVisibility: .visible
        ) {
            Button("Clear all chats", role: .destructive) {
                if let clearChatsTarget {
                    app.select(clearChatsTarget.id)
                    runtime.load(app: app)
                    runtime.clearAllThreads(app: app)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Project knowledge and files stay. Only conversations are removed.")
        }
    }

    private var renamePresented: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private var deletePresented: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    private var clearChatsPresented: Binding<Bool> {
        Binding(
            get: { clearChatsTarget != nil },
            set: { if !$0 { clearChatsTarget = nil } }
        )
    }

    @ViewBuilder
    private func projectMenu(_ project: ProjectManifest) -> some View {
        Button("Rename…") {
            renameDraft = project.name
            renameTarget = project
        }
        Button("Change Picture…") {
            pictureTarget = project
        }
        Button("Show in Finder") {
            app.revealProjectInFinder(project.id)
        }
        Button("Add Folder…") {
            _ = app.attachFolder(to: project)
        }
        Button("New Chat") {
            app.select(project.id)
            runtime.startNewThread(app: app)
        }
        Button("Clear Chats…") {
            clearChatsTarget = project
        }
        Divider()
        Button("Delete…", role: .destructive) {
            deleteTarget = project
        }
    }

    private var header: some View {
        HStack(spacing: 2) {
            if collapsed {
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 72)
                iconButton("plus", help: "New Project", label: "Create new", action: beginNewChat)
            }
        }
        .padding(.trailing, collapsed ? 0 : 10)
        .frame(height: collapsed ? 34 : Theme.trafficClearance)
    }

    private var searchField: some View {
        Button(action: app.openSearch) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text("Search")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search")
    }

    @ViewBuilder
    private var projectList: some View {
        if app.filteredProjects.isEmpty {
            if collapsed {
                Spacer(minLength: 0)
            } else {
                Text(app.search.isEmpty ? "No projects yet" : "No matches")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, Theme.sidebarPad)
                    .padding(.top, 8)
                    .accessibilityIdentifier("sidebar.empty")
            }
        } else {
            ScrollView {
                LazyVStack(spacing: collapsed ? 4 : 2) {
                    ForEach(app.filteredProjects) { project in
                        Button {
                            app.select(project.id)
                            runtime.load(app: app)
                        } label: {
                            ProjectListRow(
                                project: project,
                                preview: app.previewLine(for: project),
                                selected: app.selectedProjectID == project.id,
                                compact: collapsed,
                                hot: railHoverID == project.id,
                                imageData: app.avatarData(for: project)
                            )
                        }
                        .buttonStyle(.plain)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: RailHoverMidYKey.self,
                                    value: [project.id: proxy.frame(in: .named("workspace")).midY]
                                )
                            }
                        }
                        .onHover { inside in
                            setRailHover(project.id, inside)
                        }
                        .contextMenu {
                            projectMenu(project)
                        }
                        .tint(Theme.tint)
                    }
                }
                .padding(.horizontal, collapsed ? Theme.sidebarRailInset : 8)
            }
            .onPreferenceChange(RailHoverMidYKey.self) { value in
                railHoverMidY = value
                if let id = railHoverID, let y = value[id] {
                    app.railPeekY = y
                }
            }
            .accessibilityIdentifier("sidebar.list")
            .onChange(of: app.selectedProjectID) { _, _ in
                runtime.load(app: app)
                app.loadDrafts()
            }
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                app.pluginsOpen = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 18)
                    Text("Plugins")
                        .font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Plugins")

            accountButton(compact: false)
                .padding(.bottom, 16)
        }
        .padding(.top, 8)
    }

    private var railFooter: some View {
        VStack(spacing: 10) {
            railButton("plus", help: "New Project", label: "Create new", action: beginNewChat)
                .background(
                    app.composingNewChat ? Theme.selection : Color.clear,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .accessibilityIdentifier("sidebar.rail.plus")
            accountButton(compact: true)
        }
        .padding(.bottom, 20)
        .padding(.top, 6)
    }

    private func accountButton(compact: Bool) -> some View {
        Button {
            accountMenuOpen.toggle()
        } label: {
            if compact {
                Glass.identityChip(size: Theme.identityChip, reduceTransparency: reduceTransparency) {
                    Text(identityInitials)
                        .font(.system(size: Theme.identityType, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
            } else {
                HStack(spacing: 10) {
                    avatar
                    Text(identityName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(height: 34)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .help("Account")
        .accessibilityLabel("Account")
        .accessibilityIdentifier(compact ? "sidebar.rail.account" : "sidebar.account")
        .popover(isPresented: $accountMenuOpen, arrowEdge: compact ? .trailing : .top) {
            AccountMenu {
                accountMenuOpen = false
            }
            .environment(app)
            .presentationBackground(Theme.card)
            .presentationCornerRadius(14)
        }
    }

    private var avatar: some View {
        Glass.identityChip(size: 28, reduceTransparency: reduceTransparency) {
            Text(identityInitials)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func iconButton(
        _ systemName: String,
        help: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label)
    }

    private func railButton(
        _ systemName: String,
        help: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: Theme.sidebarRailButton, height: Theme.sidebarRailButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label)
    }

    private var identityName: String { app.identityName }

    private var identityInitials: String { app.identityInitials }

    private func beginNewChat() {
        app.beginNewChat()
        runtime.load(app: app)
    }

    private func create() {
        beginNewChat()
    }

    private func setRailHover(_ id: UUID, _ inside: Bool) {
        if inside {
            railHoverID = id
            guard collapsed else { return }
            app.holdRailPeek(id, y: railHoverMidY[id])
            return
        }
        if railHoverID == id {
            railHoverID = nil
        }
        guard collapsed else { return }
        app.releaseRailPeek(id)
    }
}

private struct RailHoverMidYKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]

    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct ProjectListRow: View {
    var project: ProjectManifest
    var preview: String
    var selected: Bool
    var compact: Bool = false
    var hot: Bool = false
    var imageData: Data?

    var body: some View {
        Group {
            if compact {
                ProjectOrb(id: project.id, size: 44, imageData: imageData, icon: project.icon)
                    .frame(width: Theme.sidebarRailButton, height: Theme.sidebarRailButton)
            } else {
                HStack(alignment: .center, spacing: 10) {
                    ProjectOrb(id: project.id, size: 32, imageData: imageData, icon: project.icon)
                    projectCopy
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            selected
                ? Theme.selection
                : (hot ? Theme.selection.opacity(0.55) : Color.clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: compact ? 14 : 10, style: .continuous))
    }

    private var projectCopy: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(project.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                Text(project.updatedAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(preview)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }
}

struct ProjectHoverCard: View {
    var project: ProjectManifest
    var preview: String
    var chats: [ThreadSummary]
    var totalCount: Int
    var selectedThreadID: UUID?
    var imageData: Data?
    var onOpenChat: (UUID) -> Void
    var onSeeAll: () -> Void
    @State private var hot: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ProjectOrb(id: project.id, size: 28, imageData: imageData, icon: project.icon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(preview)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Rectangle()
                .fill(Theme.borderSubtle.opacity(0.7))
                .frame(height: 1)
                .padding(.vertical, 4)

            if chats.isEmpty {
                Text("No chats yet")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else {
                ForEach(chats) { chat in
                    sessionRow(chat)
                }
                if totalCount > 3 {
                    Button(action: onSeeAll) {
                        HStack(spacing: 8) {
                            Text("See all sessions")
                                .font(.system(size: 13, weight: .medium))
                            Text("\(totalCount)")
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            hot == "all" ? Theme.selection : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        hot = inside ? "all" : (hot == "all" ? nil : hot)
                    }
                    .accessibilityLabel("See all sessions")
                }
            }
        }
        .padding(6)
        .frame(width: 292, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.85), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.28), radius: 18, y: 8)
        .accessibilityIdentifier("sidebar.rail.peek")
        .accessibilityLabel(project.name)
    }

    private func sessionRow(_ chat: ThreadSummary) -> some View {
        let selected = chat.id == selectedThreadID
        return Button {
            onOpenChat(chat.id)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 12, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 16, height: 16)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(chat.title)
                            .font(.system(size: 13, weight: selected ? .semibold : .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(chat.updatedAt.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text(chat.preview)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                hot == chat.id.uuidString || selected ? Theme.selection : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hot = inside ? chat.id.uuidString : (hot == chat.id.uuidString ? nil : hot)
        }
    }
}
