import Foundation
import Testing

@testable import JoyflowKit

struct ResourceStoreTests {
    private func fixture() throws -> (FileProjectStore, ProjectManifest, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("joyflow-res-\(UUID().uuidString)")
        let store = try FileProjectStore(rootURL: root)
        let project = try store.createProject(name: "Res")
        return (store, project, root)
    }

    @Test func linkRoundTripAndRejectsBadURL() throws {
        let (store, project, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = ResourceStore(layout: store.layout(for: project.id))
        let link = try resources.addLink(title: "Example", url: "https://example.com", notes: "ref")
        let again = try FileProjectStore(rootURL: root)
        let loaded = try ResourceStore(layout: again.layout(for: project.id)).links()
        #expect(loaded.contains { $0.id == link.id && $0.url == "https://example.com" })
        #expect(throws: JoyflowStoreError.self) {
            try resources.addLink(title: "Bad", url: "not a url")
        }
        try resources.removeLink(id: link.id)
        #expect(try resources.links().isEmpty)
    }

    @Test func documentCopyAndFolderBookmark() throws {
        let (store, project, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = ResourceStore(layout: store.layout(for: project.id))
        let source = root.appendingPathComponent("src.txt")
        try "hello".write(to: source, atomically: true, encoding: .utf8)
        let dest = try resources.addDocument(from: source)
        #expect(FileManager.default.fileExists(atPath: dest.path))
        #expect(try resources.documents().contains(dest.lastPathComponent))
        let again = try FileProjectStore(rootURL: root)
        let listed = try ResourceStore(layout: again.layout(for: project.id)).documents()
        #expect(listed.contains("src.txt"))
        #expect(!listed.contains(where: { $0.hasPrefix(".") }))

        let folder = root.appendingPathComponent("attach")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try resources.addFolder(from: folder)
        let folders = try ResourceStore(layout: again.layout(for: project.id)).folders()
        #expect(folders.contains { $0.name == "attach" && !$0.bookmark.isEmpty && $0.path == folder.path })

        let resolved = try #require(folders[0].resolvedURL)
        #expect(resolved.standardizedFileURL.path == folder.standardizedFileURL.path)
        let computer = LocalComputer(workspace: store.layout(for: project.id).workspace, extraRoots: [resolved])
        try "x".write(to: folder.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
        let data = try computer.allowedURL(folder.appendingPathComponent("f.txt").path)
        #expect(FileManager.default.fileExists(atPath: data.path))
    }

    @Test func addFolderFromURLDoesNotNeedSecurityScope() throws {
        let (store, project, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("picked")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let resources = ResourceStore(layout: store.layout(for: project.id))
        let item = try resources.addFolder(from: folder)
        #expect(item.name == "picked")
        #expect(!item.bookmark.isEmpty)
        let resolved = try #require(item.resolvedURL)
        #expect(resolved.standardizedFileURL.path == folder.standardizedFileURL.path)
        #expect(resources.resolvedFolders().contains { $0.0.id == item.id })
    }
}
