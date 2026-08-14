import Foundation

public struct LinkResource: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var url: String
    public var notes: String?

    public init(id: UUID = UUID(), title: String, url: String, notes: String? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.notes = notes
    }
}

public struct FolderResource: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var bookmark: Data
    public var path: String?

    public init(id: UUID = UUID(), name: String, bookmark: Data, path: String? = nil) {
        self.id = id
        self.name = name
        self.bookmark = bookmark
        self.path = path
    }

    public var resolvedURL: URL? {
        FolderBookmark.resolve(bookmark: bookmark, path: path)
    }
}

public struct LinkList: Codable, Sendable, Equatable {
    public var items: [LinkResource]
    public init(items: [LinkResource] = []) { self.items = items }
}

public struct FolderList: Codable, Sendable, Equatable {
    public var items: [FolderResource]
    public init(items: [FolderResource] = []) { self.items = items }
}
