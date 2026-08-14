import Foundation

public struct SandboxFile: Sendable, Equatable {
    public var path: String
    public var contents: Data
    public init(path: String, contents: Data) {
        self.path = path
        self.contents = contents
    }
}

public struct SandboxExecResult: Sendable, Equatable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol SandboxProviding: Sendable {
    var id: String { get }
    var displayName: String { get }
    func seed(files: [SandboxFile]) async throws
    func exec(command: String, cwd: String?, env: [String: String]) async throws -> SandboxExecResult
    func readFile(path: String) async throws -> Data
    func writeFile(path: String, contents: Data) async throws
    func list(path: String) async throws -> [String]
    func collect(paths: [String]) async throws -> [SandboxFile]
    func teardown() async
}

public enum SandboxSession {
    public static func run(
        _ sandbox: any SandboxProviding,
        files: [SandboxFile],
        command: String,
        collect paths: [String],
        into destination: URL
    ) async throws -> [SandboxFile] {
        do {
            try await sandbox.seed(files: files)
            _ = try await sandbox.exec(command: command, cwd: nil, env: [:])
            let artifacts = try await sandbox.collect(paths: paths)
            for file in artifacts {
                let url = destination.appendingPathComponent(file.path)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try file.contents.write(to: url)
            }
            await sandbox.teardown()
            return artifacts
        } catch {
            await sandbox.teardown()
            throw error
        }
    }
}

public actor RecordingSandbox: SandboxProviding {
    public let id: String
    public let displayName: String
    public private(set) var events: [String] = []
    public var execError: String?

    public init(id: String = "fake", displayName: String = "Fake") {
        self.id = id
        self.displayName = displayName
    }

    public func seed(files: [SandboxFile]) async throws { events.append("seed:\(files.count)") }
    public func exec(command: String, cwd: String?, env: [String: String]) async throws -> SandboxExecResult {
        events.append("exec:\(command)")
        if let execError { throw JoyflowStoreError.io(execError) }
        return SandboxExecResult(exitCode: 0, stdout: "ok", stderr: "")
    }
    public func readFile(path: String) async throws -> Data {
        events.append("read:\(path)")
        return Data()
    }
    public func writeFile(path: String, contents: Data) async throws { events.append("write:\(path)") }
    public func list(path: String) async throws -> [String] {
        events.append("list:\(path)")
        return []
    }
    public func collect(paths: [String]) async throws -> [SandboxFile] {
        events.append("collect:\(paths.count)")
        return paths.map { SandboxFile(path: $0, contents: Data("artifact".utf8)) }
    }
    public func teardown() async { events.append("teardown") }
    public func setExecError(_ message: String?) { execError = message }
    public func recorded() -> [String] { events }
}
