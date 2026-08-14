import Foundation
import Testing

@testable import JoyflowKit

struct CommonsStoreTests {
    @Test func ensureIsIdempotent() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("joyflow-commons-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CommonsStore(root: url)
        try store.ensure()
        try store.ensure()
        #expect(FileManager.default.fileExists(atPath: store.soul.path))
        #expect(FileManager.default.fileExists(atPath: store.knowledge.path))
        #expect(FileManager.default.fileExists(atPath: store.links.path))
    }

    @Test func writeAndListNotes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("joyflow-commons-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CommonsStore(root: url)
        try store.writeNote(
            NoteRecord(title: "Shared", slug: "shared", body: "Reusable fact.")
        )
        let notes = try store.notes()
        #expect(notes.contains { $0.slug == "shared" && $0.body.contains("Reusable") })
    }
}
