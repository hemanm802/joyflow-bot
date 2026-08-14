import JoyflowKit
import SwiftUI

enum CommandTab: String, CaseIterable, Identifiable {
    case all, projects, files, links, settings, plugins
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .projects: "Projects"
        case .files: "Files"
        case .links: "Links"
        case .settings: "Settings"
        case .plugins: "Plugins"
        }
    }
}

struct CommandHit: Identifiable {
    var id: String
    var tab: CommandTab
    var title: String
    var subtitle: String
    var systemImage: String?
    var projectID: UUID?
    var run: () -> Void
}

struct CommandPalette: View {
    @Environment(AppModel.self) private var app
    @Environment(ChatRuntime.self) private var runtime
    @FocusState private var queryFocused: Bool
    @State private var tab: CommandTab = .all
    @State private var highlight = 0

    var body: some View {
        @Bindable var app = app
        let hits = visibleHits
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                TextField("Search", text: $app.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($queryFocused)
                    .onSubmit { runHighlighted() }
                    .accessibilityLabel("Search")
            }
            .padding(.horizontal, 14)
            .frame(height: 44)

            Rectangle()
                .fill(Theme.borderSubtle.opacity(0.7))
                .frame(height: 1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(CommandTab.allCases) { item in
                        Button {
                            tab = item
                            highlight = 0
                        } label: {
                            Text(item.title)
                                .font(.system(size: 12, weight: tab == item ? .semibold : .medium))
                                .foregroundStyle(tab == item ? Theme.textPrimary : Theme.textSecondary)
                                .padding(.horizontal, 10)
                                .frame(height: 26)
                                .background(tab == item ? Theme.raised : Color.clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                        Button {
                            hit.run()
                            app.closeSearch()
                        } label: {
                            hitRow(hit, shortcut: index < 9 ? index + 1 : nil, selected: index == highlight)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
            .frame(maxHeight: 360)
        }
        .frame(width: 520)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.8), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 24, y: 10)
        .onAppear {
            queryFocused = true
            highlight = 0
        }
        .onChange(of: app.searchQuery) { _, _ in highlight = 0 }
        .onChange(of: tab) { _, _ in highlight = 0 }
        .onKeyPress(.escape) {
            app.closeSearch()
            return .handled
        }
        .onKeyPress(.downArrow) {
            if !hits.isEmpty { highlight = min(hits.count - 1, highlight + 1) }
            return .handled
        }
        .onKeyPress(.upArrow) {
            highlight = max(0, highlight - 1)
            return .handled
        }
        .onKeyPress(characters: .decimalDigits, phases: .down) { press in
            guard press.modifiers.contains(.command),
                let number = Int(press.characters),
                (1...9).contains(number),
                hits.indices.contains(number - 1)
            else { return .ignored }
            hits[number - 1].run()
            app.closeSearch()
            return .handled
        }
        .accessibilityIdentifier("search.palette")
    }

    private var visibleHits: [CommandHit] {
        let query = app.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return allHits.filter { hit in
            let tabOK: Bool = {
                if tab == .all {
                    return query.isEmpty
                        ? (hit.tab == .projects || hit.tab == .settings || hit.tab == .plugins)
                        : true
                }
                return hit.tab == tab
            }()
            let queryOK =
                query.isEmpty
                || hit.title.localizedCaseInsensitiveContains(query)
                || hit.subtitle.localizedCaseInsensitiveContains(query)
            return tabOK && queryOK
        }
    }

    private var allHits: [CommandHit] {
        var hits: [CommandHit] = [
            CommandHit(
                id: "new-project",
                tab: .projects,
                title: "New project",
                subtitle: "Start a chat",
                systemImage: "plus",
                projectID: nil,
                run: { [app, runtime] in
                    app.beginNewChat()
                    runtime.load(app: app)
                }
            )
        ]
        for project in app.projects {
            hits.append(
                CommandHit(
                    id: "project-\(project.id.uuidString)",
                    tab: .projects,
                    title: project.name,
                    subtitle: app.previewLine(for: project),
                    systemImage: nil,
                    projectID: project.id,
                    run: { [app, runtime] in
                        app.select(project.id)
                        runtime.load(app: app)
                    }
                )
            )
        }
        hits.append(
            CommandHit(
                id: "knowledge",
                tab: .settings,
                title: "Knowledge",
                subtitle: "Soul, notes, and files",
                systemImage: "book",
                projectID: nil,
                run: { app.inspectorVisible = true }
            )
        )
        hits.append(contentsOf: settingsHits)
        hits.append(
            CommandHit(
                id: "plugins",
                tab: .plugins,
                title: "Plugins",
                subtitle: "Marketplace",
                systemImage: "puzzlepiece.extension",
                projectID: nil,
                run: { app.pluginsOpen = true }
            )
        )
        hits.append(contentsOf: fileHits)
        hits.append(contentsOf: linkHits)
        return hits
    }

    private var settingsHits: [CommandHit] {
        [
            CommandHit(
                id: "settings-general",
                tab: .settings,
                title: "Settings: General",
                subtitle: "You, theme, and models",
                systemImage: "gearshape",
                projectID: nil,
                run: { app.openSettings(.models) }
            ),
            CommandHit(
                id: "settings-review",
                tab: .settings,
                title: "Settings: Review",
                subtitle: "Ask before acting",
                systemImage: "checkmark.shield",
                projectID: nil,
                run: { app.openSettings(.review) }
            ),
            CommandHit(
                id: "settings-computer",
                tab: .settings,
                title: "Settings: Computer",
                subtitle: "Local, Vercel, E2B, Modal",
                systemImage: "desktopcomputer",
                projectID: nil,
                run: { app.openSettings(.computer) }
            ),
            CommandHit(
                id: "settings-voice",
                tab: .settings,
                title: "Settings: Voice",
                subtitle: "Whisper API or local model",
                systemImage: "mic",
                projectID: nil,
                run: { app.openSettings(.voice) }
            ),
            CommandHit(
                id: "theme",
                tab: .settings,
                title: "Theme: \(app.appearance.title)",
                subtitle: "Settings · Appearance",
                systemImage: "circle.lefthalf.filled",
                projectID: nil,
                run: { app.openSettings(.models) }
            ),
        ]
    }

    private var fileHits: [CommandHit] {
        app.projects.flatMap { project -> [CommandHit] in
            let names = (try? app.resources(for: project).documents()) ?? []
            return names.map { name in
                CommandHit(
                    id: "file-\(project.id.uuidString)-\(name)",
                    tab: .files,
                    title: name,
                    subtitle: project.name,
                    systemImage: "doc",
                    projectID: project.id,
                    run: {
                        app.select(project.id)
                        app.inspectorVisible = true
                    }
                )
            }
        }
    }

    private var linkHits: [CommandHit] {
        app.projects.flatMap { project -> [CommandHit] in
            let links = (try? app.resources(for: project).links()) ?? []
            return links.map { link in
                CommandHit(
                    id: "link-\(link.id.uuidString)",
                    tab: .links,
                    title: link.title,
                    subtitle: link.url,
                    systemImage: "link",
                    projectID: project.id,
                    run: {
                        app.select(project.id)
                        app.inspectorVisible = true
                    }
                )
            }
        }
    }

    private func hitRow(_ hit: CommandHit, shortcut: Int?, selected: Bool) -> some View {
        HStack(spacing: 10) {
            if let projectID = hit.projectID, hit.systemImage == nil {
                ProjectOrb(
                    id: projectID,
                    size: 28,
                    imageData: app.projects.first { $0.id == projectID }.flatMap { app.avatarData(for: $0) },
                    icon: app.projects.first { $0.id == projectID }?.icon ?? "stone"
                )
            } else {
                ZStack {
                    Circle().fill(Theme.raised)
                    Image(systemName: hit.systemImage ?? "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(width: 28, height: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(hit.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let shortcut {
                HStack(spacing: 3) {
                    Text("⌘")
                    Text("\(shortcut)")
                }
                .font(.system(size: 11, weight: .medium).monospaced())
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(selected ? Theme.selection : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func runHighlighted() {
        let hits = visibleHits
        guard hits.indices.contains(highlight) else { return }
        hits[highlight].run()
        app.closeSearch()
    }
}
