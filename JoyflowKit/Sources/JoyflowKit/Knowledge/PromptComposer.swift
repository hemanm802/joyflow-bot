import Foundation

public struct PromptComposer: Sendable {
    public var maxFileChars: Int

    public init(maxFileChars: Int = 4000) {
        self.maxFileChars = maxFileChars
    }

    public func compose(
        projectName: String,
        soul: String,
        instructions: String,
        notes: [NoteRecord],
        memories: [MemoryRecord],
        linkedCommons: String?,
        links: [LinkResource],
        documentNames: [String],
        folderNames: [String] = [],
        earlierSummary: String? = nil
    ) -> String {
        var parts: [String] = []
        parts.append(
            """
            You are Joyflow, a local-first teammate for the Project “\(projectName)” on this Mac.
            Always answer the user's last message. Be specific. Do not stop at acknowledgement.
            You can work on this Mac the way the user asks: list, read, and write files in their folders (home, Desktop, Documents, Code, and any path they name) and run shell commands there. System locations stay off-limits. Shell, writes, window moves, and SOUL changes wait for approval.
            To move or inspect apps (Dia, Safari, a window onto the MacBook screen), use control_mac — list_displays, list_apps, then move_app. Do not use control_mac for files or coding.
            If you use a tool, keep going until you give a complete prose answer.
            If the user asks whether you can access their computer, say yes — this Mac, for the files and commands they ask about — and what still needs approval. Only call a tool when they ask you to look at or change something.
            Keep durable facts in knowledge files. Ask before changing SOUL.md. Prefer promoting reusable facts to Commons.
            If this prompt includes an earlier-in-this-chat recap, treat it as prior context and do not retell it unless asked.
            """
        )
        if let earlierSummary, !earlierSummary.isEmpty {
            parts.append("## Earlier in this chat\n\(clip(earlierSummary))")
        }
        parts.append("## Soul\n\(clip(soul))")
        parts.append("## Instructions\n\(clip(instructions))")
        if !notes.isEmpty {
            let rendered = notes.map { "### \($0.title)\n\(clip($0.body))" }.joined(separator: "\n\n")
            parts.append("## Knowledge\n\(rendered)")
        }
        if !memories.isEmpty {
            let rendered = memories.suffix(20).map(\.text).joined(separator: "\n- ")
            parts.append("## Memories\n- \(rendered)")
        }
        if let linkedCommons, !linkedCommons.isEmpty {
            parts.append("## Commons\n\(clip(linkedCommons))")
        }
        if !links.isEmpty {
            let rendered = links.map { "- \($0.title): \($0.url)" }.joined(separator: "\n")
            parts.append("## Links\n\(rendered)")
        }
        if !documentNames.isEmpty {
            parts.append("## Documents\n" + documentNames.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !folderNames.isEmpty {
            parts.append("## Folders\n" + folderNames.map { "- \($0)" }.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }

    private func clip(_ text: String) -> String {
        if text.count <= maxFileChars { return text }
        return String(text.prefix(maxFileChars)) + "\n…"
    }
}
