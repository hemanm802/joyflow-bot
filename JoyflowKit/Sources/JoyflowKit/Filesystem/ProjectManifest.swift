import Foundation

public struct ProjectManifest: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var icon: String
    public var createdAt: Date
    public var updatedAt: Date
    public var modelID: String?

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String = "stone",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        modelID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.modelID = modelID
    }
}

public struct NoteRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var slug: String
    public var body: String
    public var tags: [String]
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        slug: String,
        body: String,
        tags: [String] = [],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.slug = slug
        self.body = body
        self.tags = tags
        self.updatedAt = updatedAt
    }
}

public struct MemoryRecord: Codable, Sendable, Equatable {
    public var text: String
    public var createdAt: Date
    public var source: String

    public init(text: String, createdAt: Date = Date(), source: String = "user") {
        self.text = text
        self.createdAt = createdAt
        self.source = source
    }
}

public struct CommonsFile: Codable, Sendable, Equatable {
    public var linked: [String]

    public init(linked: [String] = []) {
        self.linked = linked
    }
}

public struct ChatMessageRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var role: String
    public var content: String
    public var reasoning: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        role: String,
        content: String,
        reasoning: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.createdAt = createdAt
    }
}

public enum JoyflowStoreError: Error, Equatable, Sendable, LocalizedError {
    case notFound(String)
    case invalidURL(String)
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let item):
            "Could not find \(item)."
        case .invalidURL(let url):
            "Invalid URL: \(url)."
        case .io(let message):
            message
        }
    }

    public static func outsideWorkspace(_ path: String) -> JoyflowStoreError {
        .io(
            "Can't open \(path) — it's outside this project's workspace. Attach that folder first, or list files inside the project workspace."
        )
    }
}
