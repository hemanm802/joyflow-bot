import Foundation
import Testing

@testable import JoyflowKit

struct LocalComputerTests {
    @Test func jailBlocksOutsideWorkspace() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("joyflow-ws-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let computer = LocalComputer(workspace: root)
        await #expect(throws: JoyflowStoreError.self) {
            try await computer.writeFile(path: "/usr/bin/joyflow-jail-test.txt", contents: Data("x".utf8))
        }
        try await computer.writeFile(path: "ok.txt", contents: Data("in".utf8))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("ok.txt").path))
    }

    @Test func listDirOutsideWorkspaceExplainsJail() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("joyflow-ws-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let computer = LocalComputer(workspace: root)
        do {
            _ = try await computer.list(path: "/System")
            Issue.record("expected protected path")
        } catch {
            let text = error.localizedDescription
            #expect(text.contains("protected"))
            #expect(text.contains("/System"))
            #expect(!text.contains("error 2"))
        }
        #expect(JoyflowStoreError.io("disk full").localizedDescription == "disk full")
        #expect(JoyflowStoreError.notFound("note").localizedDescription == "Could not find note.")
    }

    @Test func extraRootIsReadable() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("joyflow-ws-\(UUID().uuidString)")
        let extra = FileManager.default.temporaryDirectory.appendingPathComponent("joyflow-ex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: extra)
        }
        try "hello".write(to: extra.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let computer = LocalComputer(workspace: workspace, extraRoots: [extra])
        let data = try await computer.readFile(path: extra.appendingPathComponent("a.txt").path)
        #expect(String(data: data, encoding: .utf8) == "hello")
    }
}
