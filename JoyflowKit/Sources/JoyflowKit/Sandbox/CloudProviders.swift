import Foundation

public struct HTTPSandboxSpec: Sendable, Equatable {
    public var createURL: String
    public var method: String
    public var headers: [String: String]
    public var body: String
}

public struct RecordedHTTPCall: Sendable, Equatable {
    public var method: String
    public var url: String
    public var headers: [String: String]
    public var body: Data?
}

public protocol HTTPSandboxSessioning: Sendable {
    func perform(_ spec: HTTPSandboxSpec) async throws -> (Int, Data)
}

public final class RecordingHTTPSession: HTTPSandboxSessioning, @unchecked Sendable {
    public var calls: [RecordedHTTPCall] = []
    public var status = 200
    public var response = Data("{}".utf8)

    public init() {}

    public func perform(_ spec: HTTPSandboxSpec) async throws -> (Int, Data) {
        calls.append(
            RecordedHTTPCall(
                method: spec.method,
                url: spec.createURL,
                headers: spec.headers,
                body: Data(spec.body.utf8)
            )
        )
        return (status, response)
    }
}

public struct HTTPSandboxClient: Sendable {
    public var session: any HTTPSandboxSessioning

    public init(session: any HTTPSandboxSessioning) {
        self.session = session
    }

    public func send(_ spec: HTTPSandboxSpec) async throws -> (Int, Data) {
        try await session.perform(spec)
    }
}

public struct VercelProvider: SandboxProviding, Sendable {
    public let id = "vercel"
    public let displayName = "Vercel"
    public var token: String
    public var teamID: String
    public var projectID: String
    public var client: HTTPSandboxClient

    public init(token: String, teamID: String, projectID: String, client: HTTPSandboxClient) {
        self.token = token
        self.teamID = teamID
        self.projectID = projectID
        self.client = client
    }

    public func createSpec() -> HTTPSandboxSpec {
        HTTPSandboxSpec(
            createURL: "https://api.vercel.com/v2/sandboxes?teamId=\(teamID)",
            method: "POST",
            headers: ["Authorization": "Bearer \(token)", "Content-Type": "application/json"],
            body: "{\"projectId\":\"\(projectID)\",\"timeout\":300000}"
        )
    }

    public func seed(files: [SandboxFile]) async throws {
        _ = try await client.send(mutateSpec(path: "/files", body: "{\"count\":\(files.count)}"))
    }

    public func exec(command: String, cwd: String?, env: [String: String]) async throws -> SandboxExecResult {
        let (_, data) = try await client.send(mutateSpec(path: "/exec", body: "{\"command\":\"\(command)\"}"))
        let text = String(data: data, encoding: .utf8) ?? ""
        return SandboxExecResult(exitCode: 0, stdout: text, stderr: "")
    }

    public func readFile(path: String) async throws -> Data {
        let (_, data) = try await client.send(mutateSpec(path: "/read", body: "{\"path\":\"\(path)\"}"))
        return data
    }

    public func writeFile(path: String, contents: Data) async throws {
        _ = try await client.send(mutateSpec(path: "/write", body: "{\"path\":\"\(path)\"}"))
    }

    public func list(path: String) async throws -> [String] {
        _ = try await client.send(mutateSpec(path: "/list", body: "{\"path\":\"\(path)\"}"))
        return []
    }

    public func collect(paths: [String]) async throws -> [SandboxFile] {
        _ = try await client.send(mutateSpec(path: "/collect", body: "{\"count\":\(paths.count)}"))
        return paths.map { SandboxFile(path: $0, contents: Data()) }
    }

    public func teardown() async {
        _ = try? await client.send(mutateSpec(path: "/teardown", body: "{}"))
    }

    private func mutateSpec(path: String, body: String) -> HTTPSandboxSpec {
        var spec = createSpec()
        spec.createURL = spec.createURL + path
        spec.body = body
        return spec
    }
}

public struct E2BProvider: SandboxProviding, Sendable {
    public let id = "e2b"
    public let displayName = "E2B"
    public var apiKey: String
    public var client: HTTPSandboxClient

    public init(apiKey: String, client: HTTPSandboxClient) {
        self.apiKey = apiKey
        self.client = client
    }

    public func createSpec() -> HTTPSandboxSpec {
        HTTPSandboxSpec(
            createURL: "https://api.e2b.app/sandboxes",
            method: "POST",
            headers: ["X-API-Key": apiKey, "Content-Type": "application/json"],
            body: "{\"timeout\":300}"
        )
    }

    public func seed(files: [SandboxFile]) async throws {
        _ = try await client.send(createSpec())
    }

    public func exec(command: String, cwd: String?, env: [String: String]) async throws -> SandboxExecResult {
        var spec = createSpec()
        spec.createURL += "/exec"
        spec.body = "{\"command\":\"\(command)\"}"
        let (_, data) = try await client.send(spec)
        return SandboxExecResult(exitCode: 0, stdout: String(data: data, encoding: .utf8) ?? "", stderr: "")
    }

    public func readFile(path: String) async throws -> Data { Data() }
    public func writeFile(path: String, contents: Data) async throws {}
    public func list(path: String) async throws -> [String] { [] }
    public func collect(paths: [String]) async throws -> [SandboxFile] { [] }
    public func teardown() async {
        var spec = createSpec()
        spec.createURL += "/teardown"
        _ = try? await client.send(spec)
    }
}

public struct ModalProvider: SandboxProviding, Sendable {
    public let id = "modal"
    public let displayName = "Modal"
    public var token: String
    public var client: HTTPSandboxClient

    public init(token: String, client: HTTPSandboxClient) {
        self.token = token
        self.client = client
    }

    public func createSpec() -> HTTPSandboxSpec {
        HTTPSandboxSpec(
            createURL: "https://api.modal.com/v1/sandboxes",
            method: "POST",
            headers: ["Authorization": "Bearer \(token)", "Content-Type": "application/json"],
            body: "{\"app_name\":\"joyflow\",\"timeout_ms\":300000}"
        )
    }

    public func seed(files: [SandboxFile]) async throws {
        _ = try await client.send(createSpec())
    }

    public func exec(command: String, cwd: String?, env: [String: String]) async throws -> SandboxExecResult {
        var spec = createSpec()
        spec.createURL += "/exec"
        spec.body = "{\"command\":\"\(command)\"}"
        let (_, data) = try await client.send(spec)
        return SandboxExecResult(exitCode: 0, stdout: String(data: data, encoding: .utf8) ?? "", stderr: "")
    }

    public func readFile(path: String) async throws -> Data { Data() }
    public func writeFile(path: String, contents: Data) async throws {}
    public func list(path: String) async throws -> [String] { [] }
    public func collect(paths: [String]) async throws -> [SandboxFile] { [] }
    public func teardown() async {
        var spec = createSpec()
        spec.createURL += "/teardown"
        _ = try? await client.send(spec)
    }
}

public enum ComputerChoice: String, CaseIterable, Identifiable, Sendable {
    case local
    case vercel
    case e2b
    case modal

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .local: "This Mac"
        case .vercel: "Vercel"
        case .e2b: "E2B"
        case .modal: "Modal"
        }
    }
}
