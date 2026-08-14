import Foundation

public struct CommonsStore: Sendable {
    public var root: URL

    public init(root: URL) {
        self.root = root
    }

    public var soul: URL { root.appendingPathComponent("SOUL.md") }
    public var instructions: URL { root.appendingPathComponent("instructions.md") }
    public var knowledge: URL { root.appendingPathComponent("knowledge") }
    public var resources: URL { root.appendingPathComponent("resources") }
    public var links: URL { resources.appendingPathComponent("links.json") }
    public var folders: URL { resources.appendingPathComponent("folders.json") }
    public var documents: URL { resources.appendingPathComponent("documents") }
    public var index: URL { root.appendingPathComponent("index.json") }

    public func ensure() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: knowledge, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        try fm.createDirectory(at: documents, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: soul.path) {
            try """
            # Soul

            Shared voice and boundaries for every Project that links Commons.
            """.write(to: soul, atomically: true, encoding: .utf8)
        }
        if !fm.fileExists(atPath: instructions.path) {
            try "# Commons\n\nReusable knowledge lives here.\n".write(
                to: instructions,
                atomically: true,
                encoding: .utf8
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if !fm.fileExists(atPath: links.path) {
            try encoder.encode(LinkList()).write(to: links)
        }
        if !fm.fileExists(atPath: folders.path) {
            try encoder.encode(FolderList()).write(to: folders)
        }
        if !fm.fileExists(atPath: index.path) {
            try encoder.encode(CommonsFile()).write(to: index)
        }
    }

    public func writeNote(_ note: NoteRecord) throws {
        try ensure()
        let url = knowledge.appendingPathComponent("\(note.slug).md")
        try NoteMarkdown.write(note, to: url)
    }

    public func notes() throws -> [NoteRecord] {
        try ensure()
        return try NoteMarkdown.loadAll(in: knowledge)
    }
}
