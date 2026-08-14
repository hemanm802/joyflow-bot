import Foundation

public struct ProjectLayout: Sendable, Equatable {
    public var root: URL

    public init(root: URL) {
        self.root = root
    }

    public var projectJSON: URL { root.appendingPathComponent("project.json") }
    public var soul: URL { root.appendingPathComponent("SOUL.md") }
    public var instructions: URL { root.appendingPathComponent("instructions.md") }
    public var knowledge: URL { root.appendingPathComponent("knowledge") }
    public var memories: URL { knowledge.appendingPathComponent("memories.md") }
    public var resources: URL { root.appendingPathComponent("resources") }
    public var links: URL { resources.appendingPathComponent("links.json") }
    public var folders: URL { resources.appendingPathComponent("folders.json") }
    public var documents: URL { resources.appendingPathComponent("documents") }
    public var skills: URL { root.appendingPathComponent("skills") }
    public var workspace: URL { root.appendingPathComponent("workspace") }
    public var threads: URL { root.appendingPathComponent("threads") }
    public var commons: URL { root.appendingPathComponent("commons.json") }
    public var avatar: URL { root.appendingPathComponent("avatar.png") }

    public static let requiredEntries = [
        "project.json",
        "SOUL.md",
        "instructions.md",
        "knowledge",
        "knowledge/memories.md",
        "resources/links.json",
        "resources/folders.json",
        "resources/documents",
        "skills",
        "workspace",
        "threads",
        "commons.json",
    ]

    public static func defaultSoul(projectName: String) -> String {
        """
        # Soul

        You are the teammate for \(projectName).

        - Keep durable facts in `knowledge/` instead of repeating yourself in chat.
        - Ask before acting on the computer or changing this file.
        - Prefer a short, direct voice. No filler.
        """
    }

    public static func defaultInstructions(projectName: String) -> String {
        """
        # Instructions

        Standing notes for \(projectName). Edit this file any time.
        """
    }

    public static func defaultMemories() -> String {
        """
        # Memories

        """
    }

    @discardableResult
    public static func create(at url: URL, manifest: ProjectManifest) throws -> ProjectLayout {
        let layout = ProjectLayout(root: url)
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try fm.createDirectory(at: layout.knowledge, withIntermediateDirectories: true)
        try fm.createDirectory(at: layout.resources, withIntermediateDirectories: true)
        try fm.createDirectory(at: layout.documents, withIntermediateDirectories: true)
        try fm.createDirectory(at: layout.skills, withIntermediateDirectories: true)
        try fm.createDirectory(at: layout.workspace, withIntermediateDirectories: true)
        try fm.createDirectory(at: layout.threads, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: layout.projectJSON)
        try Self.defaultSoul(projectName: manifest.name).write(to: layout.soul, atomically: true, encoding: .utf8)
        try Self.defaultInstructions(projectName: manifest.name)
            .write(to: layout.instructions, atomically: true, encoding: .utf8)
        try Self.defaultMemories().write(to: layout.memories, atomically: true, encoding: .utf8)
        try encoder.encode(LinkList()).write(to: layout.links)
        try encoder.encode(FolderList()).write(to: layout.folders)
        try encoder.encode(CommonsFile()).write(to: layout.commons)
        return layout
    }

    public func existingEntries() -> [String] {
        let fm = FileManager.default
        return Self.requiredEntries.filter { rel in
            fm.fileExists(atPath: root.appendingPathComponent(rel).path)
        }
    }
}
