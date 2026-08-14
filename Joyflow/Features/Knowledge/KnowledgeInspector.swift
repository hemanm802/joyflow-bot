import JoyflowKit
import SwiftUI

struct KnowledgeInspector: View {
    @Environment(AppModel.self) private var app
    var project: ProjectManifest
    @State private var section: Section = .soul
    @State private var editingSoul = false
    @State private var soulEdit = ""

    private enum Section: String, CaseIterable, Hashable {
        case soul = "Soul"
        case notes = "Notes"
        case files = "Files"
    }

    var body: some View {
        @Bindable var app = app
        VStack(spacing: 0) {
            header
            tabs
            Group {
                switch section {
                case .soul:
                    soulPane
                case .notes:
                    notesList
                case .files:
                    ResourcesPane(project: project)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: Theme.inspectorWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.surface)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(0.7))
                .frame(width: 1)
        }
    }

    private var header: some View {
        HStack {
            Text("Knowledge")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button {
                app.inspectorVisible = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(Theme.card, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Hide knowledge")
        }
        .padding(.horizontal, 14)
        .frame(height: Theme.trafficClearance)
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(Section.allCases, id: \.self) { item in
                Button {
                    section = item
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 12, weight: section == item ? .semibold : .medium))
                        .foregroundStyle(section == item ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(section == item ? Theme.card : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            if section == .soul {
                Button(editingSoul ? "Done" : "Edit") {
                    if editingSoul {
                        finishSoulEdit()
                    } else {
                        soulEdit = app.soulDraft
                        editingSoul = true
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityLabel(editingSoul ? "Done" : "Edit")
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var soulPane: some View {
        if editingSoul {
            VStack(alignment: .leading, spacing: 8) {
                Text("SOUL.md")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .tracking(0.6)
                TextEditor(text: $soulEdit)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel("Soul")
                HStack {
                    Button("Cancel") {
                        soulEdit = app.soulDraft
                        editingSoul = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button("Save") { finishSoulEdit() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .padding(14)
        } else {
            SoulReader(markdown: app.soulDraft)
        }
    }

    private func finishSoulEdit() {
        app.soulDraft = soulEdit
        app.saveSoul()
        editingSoul = false
    }

    private var notesList: some View {
        let notes = app.notes(for: project)
        let memories = app.memories(for: project)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if notes.isEmpty && memories.isEmpty {
                    Text("Notes the model writes will land here.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !notes.isEmpty {
                    sectionLabel("Notes")
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(note.body)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(3)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                if !memories.isEmpty {
                    sectionLabel("Memories")
                    ForEach(Array(memories.enumerated()), id: \.offset) { _, memory in
                        Text(memory.text)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.vertical, 2)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .tracking(0.6)
    }
}

struct SoulReader: View {
    var markdown: String

    var body: some View {
        let document = KnowledgeDocument.parse(markdown)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if document.blocks.isEmpty {
                    Text("This project has no soul yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(document.blocks) { block in
                    switch block.kind {
                    case .heading(_, let text):
                        Text(text)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.top, 2)
                    case .paragraph(let spans):
                        KnowledgeInlineText(spans: spans, size: 13)
                            .fixedSize(horizontal: false, vertical: true)
                    case .list(let items):
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                HStack(alignment: .top, spacing: 10) {
                                    if let ordinal = item.ordinal {
                                        Text("\(ordinal).")
                                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                                            .foregroundStyle(Theme.textSecondary)
                                            .frame(minWidth: 18, alignment: .trailing)
                                            .padding(.top, 1)
                                    } else {
                                        Circle()
                                            .fill(Theme.textPrimary)
                                            .frame(width: 5, height: 5)
                                            .padding(.top, 6)
                                    }
                                    KnowledgeInlineText(spans: item.spans, size: 13)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.vertical, 10)
                                if index < items.count - 1 {
                                    Rectangle()
                                        .fill(Theme.borderSubtle.opacity(0.7))
                                        .frame(height: 1)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel("Soul")
    }
}

struct KnowledgeInlineText: View {
    var spans: [KnowledgeSpan]
    var size: CGFloat

    var body: some View {
        Text(attributed)
            .font(.system(size: size))
            .tint(Theme.link)
            .lineSpacing(3)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for span in spans {
            var piece = AttributedString(span.visibleText)
            if span.isCode {
                piece.font = .system(size: size, design: .monospaced)
                piece.foregroundColor = Theme.textPrimary
            } else if let raw = span.url, let dest = URL(string: raw) {
                piece.link = dest
                piece.foregroundColor = Theme.link
                piece.underlineStyle = .single
            } else {
                piece.foregroundColor = Theme.textPrimary
            }
            result += piece
        }
        return result
    }
}
