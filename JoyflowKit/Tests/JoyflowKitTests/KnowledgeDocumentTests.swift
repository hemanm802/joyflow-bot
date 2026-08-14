import Foundation
import Testing

@testable import JoyflowKit

struct KnowledgeDocumentTests {
    @Test func defaultSoulRendersStructuredDisplay() {
        let source = ProjectLayout.defaultSoul(projectName: "Welcome")
        let document = KnowledgeDocument.parse(source)

        #expect(document.headings.contains("Soul"))
        #expect(document.headings.allSatisfy { !$0.hasPrefix("#") })

        let items = document.listItems.map(\.visibleText)
        #expect(!items.isEmpty)
        #expect(items.allSatisfy { !$0.hasPrefix("- ") && !$0.hasPrefix("* ") })

        #expect(document.inlineCode.contains("knowledge/"))
        #expect(!document.visibleText.contains("`knowledge/`"))
        #expect(!document.visibleText.hasPrefix("#"))
    }

    @Test func emptyMarkdownHasNoBlocks() {
        #expect(KnowledgeDocument.parse("").blocks.isEmpty)
        #expect(KnowledgeDocument.parse("   \n\n").blocks.isEmpty)
    }

    @Test func parsesMarkdownAndBareLinks() {
        let document = KnowledgeDocument.parse(
            "See [Joyflow](https://joyflow.dev) and https://example.com/docs."
        )
        let links = document.links
        #expect(links.count == 2)
        #expect(links[0].text == "Joyflow")
        #expect(links[0].url == "https://joyflow.dev")
        #expect(links[1].text == "https://example.com/docs")
        #expect(links[1].url == "https://example.com/docs")
        #expect(!document.visibleText.contains("["))
        #expect(!document.visibleText.contains("]("))
        #expect(ColorTokens.link.dark == 0x5D9DF7)
        #expect(ColorTokens.link.light == 0x5D9DF7)
    }

    @Test func numberedLinesBecomeAStackedList() {
        let document = KnowledgeDocument.parse(
            """
            Dia is open, but I can't move it yet.

            1. Open System Settings → Privacy & Security → Accessibility
            2. Turn Joyflow on
            3. Ask me again to move Dia to the MacBook screen

            Displays I can see: Built-in Retina Display.
            """
        )
        let lists = document.blocks.compactMap { block -> [KnowledgeListItem]? in
            if case .list(let items) = block.kind { return items }
            return nil
        }
        #expect(lists.count == 1)
        #expect(lists[0].map(\.ordinal) == [1, 2, 3])
        #expect(lists[0][0].visibleText.contains("System Settings"))
        #expect(lists[0][1].visibleText == "Turn Joyflow on")
        #expect(!document.visibleText.contains("1. Open"))
        let paragraphs = document.blocks.compactMap { block -> String? in
            if case .paragraph(let spans) = block.kind { return spans.map(\.visibleText).joined() }
            return nil
        }
        #expect(paragraphs.contains { $0.contains("Dia is open") })
        #expect(paragraphs.contains { $0.contains("Built-in Retina") })
    }

    @Test func inlineNumberedStepsSplitIntoAList() {
        let document = KnowledgeDocument.parse(
            "1. Open System Settings → Privacy & Security → Accessibility 2. Turn Joyflow on 3. Ask me again to move Dia to the MacBook screen"
        )
        guard case .list(let items) = document.blocks.first?.kind else {
            Issue.record("expected a numbered list")
            return
        }
        #expect(items.count == 3)
        #expect(items.map(\.ordinal) == [1, 2, 3])
        #expect(items[0].visibleText.contains("System Settings"))
        #expect(items[1].visibleText == "Turn Joyflow on")
        #expect(items[2].visibleText.contains("Ask me again"))
    }
}

struct SoulStoreRoundTripTests {
    @Test func uniqueSoulWordingSurvivesRead() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "joyflow-soul-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileProjectStore(rootURL: root)
        let project = try store.createProject(name: "Roundtrip")
        let unique = "soul-marker-\(UUID().uuidString)"
        try store.writeSoul(projectID: project.id, text: unique)
        #expect(try store.readSoul(projectID: project.id) == unique)
    }
}
