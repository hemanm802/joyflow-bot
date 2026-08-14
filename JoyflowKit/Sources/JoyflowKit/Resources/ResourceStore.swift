import Foundation

public struct ResourceStore: Sendable {
    public var layout: ProjectLayout
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(layout: ProjectLayout) {
        self.layout = layout
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    public func links() throws -> [LinkResource] {
        guard FileManager.default.fileExists(atPath: layout.links.path) else { return [] }
        return try decoder.decode(LinkList.self, from: Data(contentsOf: layout.links)).items
    }

    @discardableResult
    public func addLink(title: String, url: String, notes: String? = nil) throws -> LinkResource {
        guard let parsed = URL(string: url), let scheme = parsed.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            throw JoyflowStoreError.invalidURL(url)
        }
        var list = try links()
        let label = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = LinkResource(
            title: label.isEmpty ? (parsed.host ?? url) : label,
            url: url,
            notes: notes
        )
        list.append(item)
        try encoder.encode(LinkList(items: list)).write(to: layout.links)
        return item
    }

    public func removeLink(id: UUID) throws {
        let list = try links().filter { $0.id != id }
        try encoder.encode(LinkList(items: list)).write(to: layout.links)
    }

    public func folders() throws -> [FolderResource] {
        guard FileManager.default.fileExists(atPath: layout.folders.path) else { return [] }
        return try decoder.decode(FolderList.self, from: Data(contentsOf: layout.folders)).items
    }

    @discardableResult
    public func addFolder(name: String, bookmark: Data, path: String? = nil) throws -> FolderResource {
        try FileManager.default.createDirectory(
            at: layout.folders.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var list = try folders()
        let item = FolderResource(name: name, bookmark: bookmark, path: path)
        list.append(item)
        try encoder.encode(FolderList(items: list)).write(to: layout.folders)
        return item
    }

    @discardableResult
    public func addFolder(from url: URL) throws -> FolderResource {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw JoyflowStoreError.io("That isn’t a folder.")
        }
        let bookmark = try FolderBookmark.create(for: url)
        return try addFolder(name: url.lastPathComponent, bookmark: bookmark, path: url.path)
    }

    public func resolvedFolders() -> [(FolderResource, URL)] {
        ((try? folders()) ?? []).compactMap { item in
            guard let url = item.resolvedURL else { return nil }
            return (item, url)
        }
    }

    public func removeFolder(id: UUID) throws {
        let list = try folders().filter { $0.id != id }
        try encoder.encode(FolderList(items: list)).write(to: layout.folders)
    }

    @discardableResult
    public func addDocument(from source: URL) throws -> URL {
        try FileManager.default.createDirectory(at: layout.documents, withIntermediateDirectories: true)
        var dest = layout.documents.appendingPathComponent(source.lastPathComponent)
        var index = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = layout.documents.appendingPathComponent(
                "\(source.deletingPathExtension().lastPathComponent)-\(index).\(source.pathExtension)"
            )
            index += 1
        }
        try FileManager.default.copyItem(at: source, to: dest)
        return dest
    }

    public func documents() throws -> [String] {
        let items =
            (try? FileManager.default.contentsOfDirectory(atPath: layout.documents.path)) ?? []
        return items.filter { !$0.hasPrefix(".") }.sorted()
    }

    public func removeDocument(named name: String) throws {
        let url = layout.documents.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
