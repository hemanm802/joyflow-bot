import JoyflowKit
import SwiftUI

struct NewChatPicker: View {
    @Environment(AppModel.self) private var app
    @Environment(ChatRuntime.self) private var runtime
    @FocusState private var focused: Bool
    @State private var highlight = 0

    var body: some View {
        @Bindable var app = app
        let offer = NewChatOffer.build(query: app.commandQuery, names: app.projects.map(\.name))
        let rows = menuRows(offer)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("To:")
                    .foregroundStyle(Theme.textSecondary)
                TextField("Search or create Projects", text: $app.commandQuery)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { activate(rows) }
                    .accessibilityLabel("Search or create Projects")
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 20)
            .frame(height: Theme.trafficClearance)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(0.85))
                    .frame(height: 1)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    Button {
                        run(row)
                    } label: {
                        rowLabel(row, index: index, selected: index == highlight)
                    }
                    .buttonStyle(.plain)
                }

                locationRow

                HStack {
                    Spacer()
                    hint("⇥", "add")
                    hint("↵", "open")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: 520, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.borderSubtle.opacity(0.75), lineWidth: 1)
            }
            .padding(.leading, 16)
            .padding(.top, 10)

            Spacer(minLength: 0)

            ComposerView(
                text: .constant(""),
                projectName: "Project",
                isStreaming: false,
                isRecording: false,
                isTranscribing: false,
                voiceError: nil,
                onAttach: {},
                onSend: {},
                onStop: {},
                onMic: {}
            )
            .disabled(true)
            .opacity(0.72)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .onAppear {
            focused = true
            highlight = 0
        }
        .onChange(of: app.commandQuery) { _, _ in highlight = 0 }
        .onKeyPress(.downArrow) {
            if !rows.isEmpty { highlight = min(rows.count - 1, highlight + 1) }
            return .handled
        }
        .onKeyPress(.upArrow) {
            highlight = max(0, highlight - 1)
            return .handled
        }
        .onKeyPress(.tab) {
            createNew(offer)
            return .handled
        }
        .onKeyPress(characters: .decimalDigits, phases: .down) { press in
            guard press.modifiers.contains(.command),
                let number = Int(press.characters),
                (1...9).contains(number),
                rows.indices.contains(number - 1)
            else { return .ignored }
            run(rows[number - 1])
            return .handled
        }
        .accessibilityIdentifier("chat.empty")
    }

    private struct Row: Identifiable {
        var id: String
        var title: String
        var project: ProjectManifest?
        var create: Bool
    }

    private func menuRows(_ offer: NewChatOffer) -> [Row] {
        var rows = [
            Row(id: "create", title: offer.createTitle, project: nil, create: true)
        ]
        for project in app.projects where offer.matches.contains(project.name) {
            rows.append(Row(id: project.id.uuidString, title: project.name, project: project, create: false))
        }
        return rows
    }

    private func rowLabel(_ row: Row, index: Int, selected: Bool) -> some View {
        HStack(spacing: 10) {
            if row.create {
                ZStack {
                    Circle().fill(Theme.raised)
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(width: 28, height: 28)
            } else if let project = row.project {
                ProjectOrb(
                    id: project.id,
                    size: 28,
                    imageData: app.avatarData(for: project),
                    icon: project.icon
                )
            }
            Text(row.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if index < 9 {
                HStack(spacing: 3) {
                    Text("⌘")
                    Text("\(index + 1)")
                }
                .font(.system(size: 11, weight: .medium).monospaced())
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(selected ? Theme.selection : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 6)
        .padding(.top, index == 0 ? 6 : 0)
    }

    private var locationRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(0.7))
                .frame(height: 1)
                .padding(.horizontal, 12)
                .padding(.top, 4)
            HStack(alignment: .center, spacing: 10) {
                Button(action: app.chooseProjectDestination) {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "folder")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Location")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                            Text(app.newProjectDestinationTitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            if app.newProjectDestination != nil {
                                Text(app.newProjectDestinationLabel)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        Spacer(minLength: 8)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose project folder")
                .accessibilityValue(app.newProjectDestinationLabel)
                Button("Choose…") { app.chooseProjectDestination() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityHidden(true)
                if app.newProjectDestination != nil {
                    Button("Reset") { app.clearProjectDestination() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityLabel("Use Joyflow folder")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.destination")
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10, weight: .medium).monospaced())
                .padding(.horizontal, 5)
                .frame(height: 18)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func activate(_ rows: [Row]) {
        guard rows.indices.contains(highlight) else { return }
        run(rows[highlight])
    }

    private func run(_ row: Row) {
        if row.create {
            createNew(NewChatOffer.build(query: app.commandQuery, names: app.projects.map(\.name)))
        } else if let project = row.project {
            app.select(project.id)
            runtime.load(app: app)
        }
    }

    private func createNew(_ offer: NewChatOffer) {
        _ = try? app.createProject(name: offer.createName)
        app.commandQuery = ""
        runtime.load(app: app)
    }
}
