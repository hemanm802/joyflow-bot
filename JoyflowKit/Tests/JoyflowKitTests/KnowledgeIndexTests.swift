import Foundation
import Testing

@testable import JoyflowKit

struct KnowledgeIndexTests {
    @Test func searchFindsMatchingNoteOnly() {
        let notes = [
            NoteRecord(title: "Limestone", slug: "limestone", body: "Use limestone accent."),
            NoteRecord(title: "Other", slug: "other", body: "Unrelated fact."),
        ]
        let hits = KnowledgeIndex().search(notes: notes, memories: [], query: "limestone")
        #expect(hits.contains { $0.title == "Limestone" })
        #expect(!hits.contains { $0.title == "Other" })
    }
}

struct PromptComposerTests {
    @Test func includesSoulAndNoteAndOptionalCommons() {
        let composer = PromptComposer()
        let withCommons = composer.compose(
            projectName: "Alpha",
            soul: "# Soul\nBe brief.",
            instructions: "# Instructions\nShip.",
            notes: [NoteRecord(title: "Decision", slug: "decision", body: "Limestone.")],
            memories: [],
            linkedCommons: "Shared voice.",
            links: [LinkResource(title: "Docs", url: "https://example.com")],
            documentNames: ["brief.pdf"],
            folderNames: ["Notes — /tmp/notes"]
        )
        #expect(withCommons.contains("# Soul"))
        #expect(withCommons.contains("# Instructions"))
        #expect(withCommons.contains("Decision"))
        #expect(withCommons.contains("Shared voice."))
        #expect(withCommons.contains("https://example.com"))
        #expect(withCommons.contains("brief.pdf"))
        #expect(withCommons.contains("Notes — /tmp/notes"))

        let without = composer.compose(
            projectName: "Alpha",
            soul: "# Soul",
            instructions: "# Instructions",
            notes: [],
            memories: [],
            linkedCommons: nil,
            links: [],
            documentNames: []
        )
        #expect(!without.contains("## Commons"))
        #expect(without.contains("Always answer the user's last message"))
        #expect(without.contains("control_mac"))
        #expect(without.contains("this Mac, for the files and commands they ask about"))
    }
}

struct KnowledgeWriteTests {
    @Test func writeNoteMemoryAndPromote() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("joyflow-know-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileProjectStore(rootURL: root)
        let project = try store.createProject(name: "K")
        let first = try store.appendMemory(projectID: project.id, text: "Keep this")
        _ = try store.appendMemory(projectID: project.id, text: "And this")
        #expect(try store.memories(projectID: project.id).map(\.text).contains(first.text))
        let note = try store.writeNote(projectID: project.id, title: "Share me", body: "Reusable.")
        try store.commons.writeNote(note)
        try store.linkCommons(projectID: project.id, id: "note:\(note.id.uuidString)")
        #expect(try store.commons.notes().contains { $0.id == note.id })
        #expect(try store.linkedCommons(projectID: project.id).contains("note:\(note.id.uuidString)"))
    }
}

struct ProjectSelectionTests {
    @Test func filterIsCaseInsensitive() {
        let projects = [
            ProjectManifest(name: "Alpha"),
            ProjectManifest(name: "Beta"),
        ]
        let filtered = ProjectSelection.filter(projects, query: "alp")
        #expect(filtered.map(\.name) == ["Alpha"])
    }
}
