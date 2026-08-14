import Foundation
import Testing

@testable import JoyflowKit

struct ThreadEditTests {
    @Test func editFirstUserDropsLaterTurnsAndResendPromptIsEditedText() throws {
        let firstUser = ChatMessageRecord(role: "user", content: "Hello")
        let firstAssistant = ChatMessageRecord(role: "assistant", content: "Hi")
        let secondUser = ChatMessageRecord(role: "user", content: "Again")
        let secondAssistant = ChatMessageRecord(role: "assistant", content: "Still here")
        let rewritten = try ThreadEdit.apply(
            messages: [firstUser, firstAssistant, secondUser, secondAssistant],
            id: firstUser.id,
            text: "  Edited hello  "
        )
        #expect(rewritten.count == 1)
        #expect(rewritten[0].id == firstUser.id)
        #expect(rewritten[0].role == "user")
        #expect(rewritten[0].content == "Edited hello")
        #expect(ThreadEdit.resendPrompt(from: rewritten) == "Edited hello")
    }

    @Test func rejectsEmptyAndNonUser() {
        let user = ChatMessageRecord(role: "user", content: "Hi")
        let assistant = ChatMessageRecord(role: "assistant", content: "Hello")
        #expect(throws: ThreadEditError.emptyText) {
            try ThreadEdit.apply(messages: [user], id: user.id, text: "   ")
        }
        #expect(throws: ThreadEditError.notUserMessage) {
            try ThreadEdit.apply(messages: [user, assistant], id: assistant.id, text: "Nope")
        }
        #expect(throws: ThreadEditError.messageNotFound) {
            try ThreadEdit.apply(messages: [user], id: UUID(), text: "Missing")
        }
    }

    @Test func storeEditPersistsRewriteThenResendPrompt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("joyflow-edit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileProjectStore(rootURL: root)
        let project = try store.createProject(name: "Edit")
        let thread = UUID()
        let first = ChatMessageRecord(role: "user", content: "Original")
        try store.appendMessage(projectID: project.id, threadID: thread, message: first)
        try store.appendMessage(
            projectID: project.id,
            threadID: thread,
            message: ChatMessageRecord(role: "assistant", content: "Reply")
        )
        try store.appendMessage(
            projectID: project.id,
            threadID: thread,
            message: ChatMessageRecord(role: "user", content: "Follow up")
        )
        try store.appendMessage(
            projectID: project.id,
            threadID: thread,
            message: ChatMessageRecord(role: "assistant", content: "Second")
        )
        let rewritten = try store.editUserMessage(
            projectID: project.id,
            threadID: thread,
            id: first.id,
            text: "Please answer this instead"
        )
        let loaded = try store.messages(projectID: project.id, threadID: thread)
        #expect(loaded.map(\.content) == ["Please answer this instead"])
        #expect(ThreadEdit.resendPrompt(from: rewritten) == "Please answer this instead")
        #expect(ThreadEdit.resendPrompt(from: loaded) == loaded.last?.content)
    }

    @Test func deleteRemovesOnlyThatMessage() throws {
        let user = ChatMessageRecord(role: "user", content: "Keep asking")
        let assistant = ChatMessageRecord(role: "assistant", content: "Drop me")
        let later = ChatMessageRecord(role: "user", content: "Still here")
        let afterUser = try ThreadEdit.delete(messages: [user, assistant, later], id: user.id)
        #expect(afterUser.map(\.content) == ["Drop me", "Still here"])
        let afterAssistant = try ThreadEdit.delete(messages: [user, assistant, later], id: assistant.id)
        #expect(afterAssistant.map(\.content) == ["Keep asking", "Still here"])
        #expect(throws: ThreadEditError.messageNotFound) {
            try ThreadEdit.delete(messages: [user], id: UUID())
        }
    }
}

struct ChatCompactionTests {
    @Test func shortThreadStaysWhole() {
        let messages = (0..<6).map { index in
            ChatMessageRecord(
                role: index.isMultiple(of: 2) ? "user" : "assistant",
                content: "Turn \(index)"
            )
        }
        let compact = ChatCompaction.apply(messages)
        #expect(!compact.isCompacted)
        #expect(compact.kept.count == 6)
        #expect(compact.summary == nil)
    }

    @Test func longThreadFoldsOlderTurnsOnAUserBoundary() {
        var messages: [ChatMessageRecord] = []
        for index in 0..<24 {
            messages.append(
                ChatMessageRecord(
                    role: index.isMultiple(of: 2) ? "user" : "assistant",
                    content: "Turn \(index) " + String(repeating: "x", count: 40)
                )
            )
        }
        let compact = ChatCompaction.apply(messages)
        #expect(compact.isCompacted)
        #expect(compact.foldedCount >= ChatCompaction.minFold)
        #expect(compact.kept.first?.role == "user")
        #expect(compact.folded.count + compact.kept.count == messages.count)
        #expect(compact.summary?.contains("User:") == true)
        #expect(compact.summary?.contains("Joyflow:") == true)
        let title = ChatCompaction.title(from: messages)
        #expect(title.hasPrefix("Turn 0 "))
        #expect(!title.contains("**"))
    }

    @Test func hugeRecentStillFoldsUntilBudgetFits() {
        let huge = String(repeating: "w", count: 4_000)
        var messages: [ChatMessageRecord] = []
        for index in 0..<10 {
            messages.append(ChatMessageRecord(role: "user", content: "\(huge) \(index)"))
            messages.append(ChatMessageRecord(role: "assistant", content: "ok \(index)"))
        }
        let compact = ChatCompaction.apply(messages)
        #expect(compact.isCompacted)
        let keptChars = compact.kept.reduce(0) { $0 + $1.content.count }
        #expect(keptChars <= ChatCompaction.maxChars || compact.kept.count <= 4)
    }
}
