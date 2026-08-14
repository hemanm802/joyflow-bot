import Foundation
import Testing

@testable import JoyflowKit

struct SandboxProviderTests {
    @Test func createSpecs() {
        let session = RecordingHTTPSession()
        let client = HTTPSandboxClient(session: session)
        let vercel = VercelProvider(token: "t", teamID: "team", projectID: "prj", client: client)
        #expect(vercel.createSpec().createURL.contains("api.vercel.com"))
        #expect(vercel.createSpec().headers["Authorization"] == "Bearer t")
        let e2b = E2BProvider(apiKey: "e2b_x", client: client)
        #expect(e2b.createSpec().createURL.contains("api.e2b.app"))
        #expect(e2b.createSpec().headers["X-API-Key"] == "e2b_x")
        let modal = ModalProvider(token: "m", client: client)
        #expect(modal.createSpec().createURL.contains("api.modal.com"))
        #expect(modal.createSpec().headers["Authorization"] == "Bearer m")
        #expect(ComputerChoice.allCases.map(\.title) == ["This Mac", "Vercel", "E2B", "Modal"])
    }

    @Test func providersHitHTTPClient() async throws {
        let session = RecordingHTTPSession()
        let client = HTTPSandboxClient(session: session)
        let vercel = VercelProvider(token: "t", teamID: "team", projectID: "prj", client: client)
        _ = try await vercel.exec(command: "ls", cwd: nil, env: [:])
        try await vercel.seed(files: [])
        await vercel.teardown()
        #expect(!session.calls.isEmpty)

        let e2bSession = RecordingHTTPSession()
        let e2b = E2BProvider(apiKey: "k", client: HTTPSandboxClient(session: e2bSession))
        _ = try await e2b.exec(command: "ls", cwd: nil, env: [:])
        await e2b.teardown()
        #expect(e2bSession.calls.count >= 2)

        let modalSession = RecordingHTTPSession()
        let modal = ModalProvider(token: "k", client: HTTPSandboxClient(session: modalSession))
        _ = try await modal.exec(command: "ls", cwd: nil, env: [:])
        await modal.teardown()
        #expect(modalSession.calls.count >= 2)
    }

    @Test func sessionTeardownOnError() async throws {
        let sandbox = RecordingSandbox()
        await sandbox.setExecError("boom")
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("joyflow-art-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dest) }
        await #expect(throws: JoyflowStoreError.self) {
            _ = try await SandboxSession.run(sandbox, files: [], command: "x", collect: [], into: dest)
        }
        let events = await sandbox.recorded()
        #expect(events.contains("teardown"))
    }

    @Test func routerLocalIsNotCloud() {
        let local = ComputerRouter.route(.local, credentials: .empty)
        #expect(local.isLocal)
        #expect(local.spec == nil)
        #expect(local.choice == .local)

        let vercel = ComputerRouter.route(
            .vercel,
            credentials: SandboxCredentials(vercelToken: "t", vercelTeam: "team", vercelProject: "prj")
        )
        #expect(!vercel.isLocal)
        #expect(vercel.choice == .vercel)
        #expect(vercel.spec?.createURL.contains("api.vercel.com") == true)
        #expect(vercel.spec?.headers["Authorization"] == "Bearer t")

        let e2b = ComputerRouter.route(.e2b, credentials: SandboxCredentials(e2bKey: "e2b_x"))
        #expect(e2b.spec?.createURL.contains("api.e2b.app") == true)

        let modal = ComputerRouter.route(.modal, credentials: SandboxCredentials(modalToken: "m"))
        #expect(modal.spec?.createURL.contains("api.modal.com") == true)
    }

    @Test func routerComputerLocalWritesWorkspace() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("joyflow-route-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let computer = try ComputerRouter.computer(.local, workspace: root, credentials: .empty)
        #expect(computer.id == "local")
        try await computer.writeFile(path: "ok.txt", contents: Data("in".utf8))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("ok.txt").path))
    }

    @Test func routerCloudDoesNotInstantiateOnlyLocalComputer() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("joyflow-cloud-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let session = RecordingHTTPSession()
        let computer = try ComputerRouter.computer(
            .vercel,
            workspace: root,
            credentials: SandboxCredentials(vercelToken: "t", vercelTeam: "team", vercelProject: "prj"),
            session: session
        )
        #expect(computer.id == "vercel")
        try await computer.writeFile(path: "ghost.txt", contents: Data("x".utf8))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("ghost.txt").path))
        #expect(session.calls.contains { $0.url.contains("api.vercel.com") })
    }

    @Test func routerCloudFailsClosedWithoutToken() {
        #expect(throws: JoyflowStoreError.self) {
            _ = try ComputerRouter.computer(.vercel, workspace: URL(fileURLWithPath: "/tmp"), credentials: .empty)
        }
        #expect(throws: JoyflowStoreError.self) {
            _ = try ComputerRouter.computer(.e2b, workspace: URL(fileURLWithPath: "/tmp"), credentials: .empty)
        }
        #expect(throws: JoyflowStoreError.self) {
            _ = try ComputerRouter.computer(.modal, workspace: URL(fileURLWithPath: "/tmp"), credentials: .empty)
        }
    }

    @Test func artifactsLandInDestination() async throws {
        let sandbox = RecordingSandbox()
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("joyflow-art-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dest) }
        _ = try await SandboxSession.run(
            sandbox,
            files: [],
            command: "x",
            collect: ["out.txt"],
            into: dest
        )
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("out.txt").path))
    }
}
