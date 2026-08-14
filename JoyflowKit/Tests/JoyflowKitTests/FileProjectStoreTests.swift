import Foundation
import Testing

@testable import JoyflowKit

struct FileProjectStoreTests {
    private func tempStore() throws -> (FileProjectStore, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("joyflow-tests-\(UUID().uuidString)")
        let store = try FileProjectStore(rootURL: url)
        return (store, url)
    }

    @Test func createWritesRequiredEntries() throws {
        let (store, root) = try tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try store.createProject(name: "Alpha")
        let layout = store.layout(for: project.id)
        #expect(Set(layout.existingEntries()) == Set(ProjectLayout.requiredEntries))
        let soul = try store.readSoul(projectID: project.id)
        #expect(soul.contains("# Soul"))
        let data = try Data(contentsOf: layout.projectJSON)
        let decoded = try JSONDecoder.iso8601.decode(ProjectManifest.self, from: data)
        #expect(decoded.name == "Alpha")
        #expect(decoded.id == project.id)
        #expect(ProjectMark.isMarkIcon(project.icon))
    }

    @Test func commonsEnsureCreatesSkeleton() throws {
        let (store, root) = try tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.commons.ensure()
        #expect(FileManager.default.fileExists(atPath: store.commons.soul.path))
        #expect(FileManager.default.fileExists(atPath: store.commons.knowledge.path))
        #expect(FileManager.default.fileExists(atPath: store.commons.links.path))
        let soul = try String(contentsOf: store.commons.soul, encoding: .utf8)
        #expect(soul.contains("# Soul"))
    }

    @Test func roundTripAcrossReinit() throws {
        let (store, root) = try tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try store.createProject(name: "Beta")
        let note = try store.writeNote(
            projectID: project.id,
            title: "Standing decision",
            body: "Use limestone, not orange.",
            tags: ["design"]
        )
        _ = try store.appendMemory(projectID: project.id, text: "User prefers short replies.", source: "model")
        try store.linkCommons(projectID: project.id, id: "note:\(note.id)")

        let again = try FileProjectStore(rootURL: root)
        #expect(try again.listProjects().count == 1)
        let notes = try again.notes(projectID: project.id)
        #expect(notes.contains { $0.body.contains("limestone") && $0.title == "Standing decision" })
        let memories = try again.memories(projectID: project.id)
        #expect(memories.contains { $0.text.contains("short replies") })
        #expect(try again.linkedCommons(projectID: project.id) == ["note:\(note.id)"])
    }

    @Test func deleteRemovesDirectory() throws {
        let (store, root) = try tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try store.createProject(name: "Gone")
        let dir = store.layout(for: project.id).root
        #expect(FileManager.default.fileExists(atPath: dir.path))
        try store.deleteProject(id: project.id)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
        #expect(try store.listProjects().isEmpty)
    }

    @Test func createUsesChosenDestination() throws {
        let (store, root) = try tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let dest = root.appendingPathComponent("picked")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let project = try store.createProject(name: "On Disk", destination: dest)
        let folder = dest.appendingPathComponent("On Disk")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("project.json").path))
        #expect(store.layout(for: project.id).root.standardizedFileURL.path == folder.standardizedFileURL.path)
        #expect(try store.listProjects().contains { $0.id == project.id && $0.name == "On Disk" })
        try store.writeSoul(projectID: project.id, text: "# Soul\n\nExternal.\n")
        #expect(try store.readSoul(projectID: project.id).contains("External"))
        try store.deleteProject(id: project.id)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(try store.listProjects().isEmpty)
    }

    @Test func destinationNameCollisionGetsSuffix() throws {
        let (store, root) = try tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let dest = root.appendingPathComponent("picked")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        _ = try store.createProject(name: "Clash", destination: dest)
        let second = try store.createProject(name: "Clash", destination: dest)
        #expect(store.layout(for: second.id).root.lastPathComponent == "Clash 2")
        #expect(FileProjectStore.folderName(from: "a/b:c") == "a-b-c")
    }

    @Test func writeRootUsesChosenDestination() async throws {
        let (store, root) = try tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let dest = root.appendingPathComponent("picked")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let project = try store.createProject(name: "On Disk", destination: dest)
        let writeRoot = try store.writeRoot(for: project.id)
        #expect(writeRoot.standardizedFileURL.path.hasPrefix(dest.standardizedFileURL.path))
        #expect(writeRoot.lastPathComponent == "workspace")
        let computer = LocalComputer(workspace: writeRoot)
        let dispatcher = ToolDispatcher(store: store, projectID: project.id, computer: computer)
        let wrote = try await dispatcher.execute(
            name: "write_file",
            argumentsJSON: #"{"path":"note.txt","contents":"from dest"}"#
        )
        #expect(wrote == "wrote")
        let listed = try await dispatcher.execute(name: "list_dir", argumentsJSON: #"{"path":"."}"#)
        #expect(listed.contains("note.txt"))
        let file = writeRoot.appendingPathComponent("note.txt")
        #expect(try String(contentsOf: file, encoding: .utf8) == "from dest")
        let blocked = try await dispatcher.execute(
            name: "list_dir",
            argumentsJSON: #"{"path":"/usr/bin"}"#
        )
        #expect(blocked.localizedCaseInsensitiveContains("protected"))
        #expect(!blocked.contains("error 2"))
    }

    @Test func writeRootCreatesDefaultFolder() async throws {
        let (store, root) = try tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try store.createProject(name: "Inbox")
        let writeRoot = try store.writeRoot(for: project.id)
        #expect(writeRoot.lastPathComponent == "workspace")
        #expect(writeRoot.path.contains(project.id.uuidString))
        #expect(FileManager.default.fileExists(atPath: writeRoot.path))
        let dispatcher = ToolDispatcher(
            store: store,
            projectID: project.id,
            computer: LocalComputer(workspace: writeRoot)
        )
        _ = try await dispatcher.execute(
            name: "write_file",
            argumentsJSON: #"{"path":"hello.txt","contents":"default"}"#
        )
        #expect(try String(contentsOf: writeRoot.appendingPathComponent("hello.txt"), encoding: .utf8) == "default")
        let listed = try await dispatcher.execute(name: "list_dir", argumentsJSON: #"{"path":"."}"#)
        #expect(listed.contains("hello.txt"))
        let blocked = try await dispatcher.execute(
            name: "write_file",
            argumentsJSON: #"{"path":"/usr/bin/joyflow-outside.txt","contents":"nope"}"#
        )
        #expect(blocked.localizedCaseInsensitiveContains("protected"))
        #expect(!blocked.contains("error 2"))
        #expect(!FileManager.default.fileExists(atPath: "/usr/bin/joyflow-outside.txt"))
    }

    @Test func writeRootUsesAttachedFolderOnExistingProject() async throws {
        let (store, root) = try tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try store.createProject(name: "Existing")
        let defaultRoot = try store.writeRoot(for: project.id)
        #expect(defaultRoot.lastPathComponent == "workspace")
        let attached = root.appendingPathComponent("user-folder")
        try FileManager.default.createDirectory(at: attached, withIntermediateDirectories: true)
        _ = try ResourceStore(layout: store.layout(for: project.id)).addFolder(from: attached)
        let writeRoot = try store.writeRoot(for: project.id)
        #expect(writeRoot.standardizedFileURL.path == attached.standardizedFileURL.path)
        let extras = ResourceStore(layout: store.layout(for: project.id)).resolvedFolders().map(\.1)
        let dispatcher = ToolDispatcher(
            store: store,
            projectID: project.id,
            computer: LocalComputer(workspace: writeRoot, extraRoots: extras)
        )
        let wrote = try await dispatcher.execute(
            name: "write_file",
            argumentsJSON: #"{"path":"from-attach.txt","contents":"hello"}"#
        )
        #expect(wrote == "wrote")
        #expect(try String(contentsOf: attached.appendingPathComponent("from-attach.txt"), encoding: .utf8) == "hello")
        let listed = try await dispatcher.execute(name: "list_dir", argumentsJSON: #"{"path":"."}"#)
        #expect(listed.contains("from-attach.txt"))
    }

    @Test func attachFolderToolPersistsAndOpensWriteRoot() async throws {
        let (store, root) = try tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try store.createProject(name: "Attach")
        let attached = root.appendingPathComponent("via-tool")
        try FileManager.default.createDirectory(at: attached, withIntermediateDirectories: true)
        let dispatcher = ToolDispatcher(
            store: store,
            projectID: project.id,
            computer: LocalComputer(workspace: try store.writeRoot(for: project.id))
        )
        let result = try await dispatcher.execute(
            name: "attach_folder",
            argumentsJSON: #"{"name":"via-tool","path":"\#(attached.path)"}"#
        )
        #expect(result.contains("attached"))
        #expect(result.contains("via-tool"))
        let folders = try ResourceStore(layout: store.layout(for: project.id)).folders()
        #expect(folders.contains { $0.name == "via-tool" && $0.path == attached.path })
        let writeRoot = try store.writeRoot(for: project.id)
        #expect(writeRoot.standardizedFileURL.path == attached.standardizedFileURL.path)
    }

    @Test func chosenDestinationSurvivesRelaunch() throws {
        let (store, root) = try tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let dest = root.appendingPathComponent("picked")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let project = try store.createProject(name: "Keep", destination: dest)
        let folder = dest.appendingPathComponent("Keep")
        let again = try FileProjectStore(rootURL: root)
        #expect(try again.listProjects().contains { $0.id == project.id && $0.name == "Keep" })
        #expect(again.layout(for: project.id).root.standardizedFileURL.path == folder.standardizedFileURL.path)
        try again.writeSoul(projectID: project.id, text: "# Soul\n\nAfter relaunch.\n")
        #expect(try again.readSoul(projectID: project.id).contains("After relaunch"))
    }

    @Test func listSortsByUpdatedAt() throws {
        let (store, root) = try tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try store.createProject(name: "Older")
        _ = try store.createProject(name: "Newer")
        try store.writeSoul(projectID: first.id, text: "# Soul\n\nUpdated.\n")
        let listed = try store.listProjects()
        let older = listed.first { $0.name == "Older" }
        let newer = listed.first { $0.name == "Newer" }
        #expect(older != nil && newer != nil)
        #expect(older!.updatedAt >= newer!.updatedAt)
    }

    @Test func memoriesAppendWithoutClobber() throws {
        let (store, root) = try tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try store.createProject(name: "Mem")
        _ = try store.appendMemory(projectID: project.id, text: "First")
        _ = try store.appendMemory(projectID: project.id, text: "Second")
        let texts = try store.memories(projectID: project.id).map(\.text)
        #expect(texts.contains("First"))
        #expect(texts.contains("Second"))
    }

    @Test func renameAndCustomAvatarRoundTrip() throws {
        let (store, root) = try tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try store.createProject(name: "Old")
        try store.renameProject(id: project.id, name: "  New Name  ")
        #expect(try store.project(id: project.id).name == "New Name")
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01, 0x02])
        try store.setAvatar(projectID: project.id, data: bytes)
        #expect(try store.project(id: project.id).icon == "avatar")
        #expect(store.avatarData(projectID: project.id) == bytes)
        try store.clearAvatar(projectID: project.id)
        #expect(ProjectMark.isMarkIcon(try store.project(id: project.id).icon))
        #expect(store.avatarData(projectID: project.id) == nil)
        try store.setMark(projectID: project.id, icon: "mark.ink")
        #expect(try store.project(id: project.id).icon == "mark.ink")
        #expect(store.avatarData(projectID: project.id) == nil)
        #expect(throws: JoyflowStoreError.self) {
            try store.renameProject(id: project.id, name: "   ")
        }
    }

    @Test func threadsListDeleteAndClear() throws {
        let (store, root) = try tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try store.createProject(name: "Chats")
        let first = UUID()
        let second = UUID()
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_700_000_100)
        try store.appendMessage(
            projectID: project.id,
            threadID: first,
            message: ChatMessageRecord(role: "user", content: "First chat hello", createdAt: older)
        )
        try store.appendMessage(
            projectID: project.id,
            threadID: first,
            message: ChatMessageRecord(role: "assistant", content: "Hi there", createdAt: older.addingTimeInterval(1))
        )
        try store.appendMessage(
            projectID: project.id,
            threadID: second,
            message: ChatMessageRecord(role: "user", content: "Fresh context", createdAt: newer)
        )
        try store.setActiveThread(projectID: project.id, threadID: second)
        let listed = try store.listThreads(projectID: project.id)
        #expect(listed.map(\.id) == [second, first])
        #expect(listed[0].title == "Fresh context")
        #expect(listed[1].preview.contains("Hi there"))
        #expect(store.activeThreadID(projectID: project.id) == second)
        #expect(store.resolveThreadID(projectID: project.id, preferred: nil) == second)

        let firstMessages = try store.messages(projectID: project.id, threadID: first)
        let assistant = try #require(firstMessages.first { $0.role == "assistant" })
        let after = try store.deleteMessage(projectID: project.id, threadID: first, id: assistant.id)
        #expect(after.map(\.role) == ["user"])
        try store.clearThread(projectID: project.id, threadID: first)
        #expect(try store.messages(projectID: project.id, threadID: first).isEmpty)
        try store.deleteThread(projectID: project.id, threadID: first)
        #expect(try store.listThreads(projectID: project.id).map(\.id) == [second])
        try store.clearAllThreads(projectID: project.id)
        #expect(try store.listThreads(projectID: project.id).isEmpty)
        #expect(store.activeThreadID(projectID: project.id) == nil)
    }

    @Test func ensureProjectCreatesThenIsIdempotent() throws {
        let (store, root) = try tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let created = try store.ensureProject(id: id, name: "From Phone")
        #expect(created.id == id)
        #expect(created.name == "From Phone")
        let again = try store.ensureProject(id: id, name: "Ignored")
        #expect(again.id == id)
        #expect(again.name == "From Phone")
        let thread = UUID()
        try store.appendMessage(
            projectID: id,
            threadID: thread,
            message: ChatMessageRecord(role: "user", content: "hello from phone")
        )
        let listed = try store.messages(projectID: id, threadID: thread)
        #expect(listed.map(\.content) == ["hello from phone"])
        let url = store.layout(for: id).threads.appendingPathComponent("\(thread.uuidString).jsonl")
        let extra = try String(contentsOf: url, encoding: .utf8) + "{not json}\n"
        try extra.write(to: url, atomically: true, encoding: .utf8)
        let skipped = try store.messages(projectID: id, threadID: thread)
        #expect(skipped.map(\.content) == ["hello from phone"])
    }

    @Test func soulWriteRoundTrip() throws {
        let (store, root) = try tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try store.createProject(name: "Voice")
        let text = "# Soul\n\nBe terse.\n"
        try store.writeSoul(projectID: project.id, text: text)
        #expect(try store.readSoul(projectID: project.id) == text)
    }

    @Test func threadJSONLRoundTrip() throws {
        let (store, root) = try tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try store.createProject(name: "Chat")
        let thread = UUID()
        try store.appendMessage(
            projectID: project.id,
            threadID: thread,
            message: ChatMessageRecord(role: "user", content: "Hello")
        )
        try store.appendMessage(
            projectID: project.id,
            threadID: thread,
            message: ChatMessageRecord(role: "assistant", content: "Hi")
        )
        let again = try FileProjectStore(rootURL: root)
        let messages = try again.messages(projectID: project.id, threadID: thread)
        #expect(messages.map(\.content) == ["Hello", "Hi"])
    }

    @Test func threadPreservesReasoningAndReadsLegacyLines() throws {
        let (store, root) = try tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try store.createProject(name: "Chat")
        let thread = UUID()
        try store.appendMessage(
            projectID: project.id,
            threadID: thread,
            message: ChatMessageRecord(
                role: "assistant",
                content: "Yes.",
                reasoning: "They asked if I can help."
            )
        )
        let url = store.layout(for: project.id).threads.appendingPathComponent("\(thread.uuidString).jsonl")
        let legacy =
            #"{"content":"Hi","role":"user","createdAt":"2026-08-13T13:49:42Z","id":"AABE9841-6660-437F-B855-FB0ACB3476F2"}"#
            + "\n"
        try (legacy + (try String(contentsOf: url, encoding: .utf8))).write(to: url, atomically: true, encoding: .utf8)
        let messages = try store.messages(projectID: project.id, threadID: thread)
        #expect(messages.first?.content == "Hi")
        #expect(messages.first?.reasoning == nil)
        #expect(messages.last?.content == "Yes.")
        #expect(messages.last?.reasoning == "They asked if I can help.")
    }
}

extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
