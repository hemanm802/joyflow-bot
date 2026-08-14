import Foundation

public struct LocalComputer: SandboxProviding, Sendable {
    public let id = "local"
    public let displayName = "This Mac"
    public var workspace: URL
    public var extraRoots: [URL]

    public init(workspace: URL, extraRoots: [URL] = []) {
        self.workspace = workspace.standardizedFileURL
        self.extraRoots = extraRoots.map(\.standardizedFileURL)
    }

    public func seed(files: [SandboxFile]) async throws {
        for file in files {
            try writeAllowed(path: file.path, contents: file.contents)
        }
    }

    public func exec(command: String, cwd: String?, env: [String: String]) async throws -> SandboxExecResult {
        let directory = resolvedDirectory(cwd)
        let result = try ProcessLaunch.run(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", command],
            directory: directory,
            environment: env.isEmpty ? nil : env
        )
        return SandboxExecResult(exitCode: result.status, stdout: result.stdout, stderr: result.stderr)
    }

    public func readFile(path: String) async throws -> Data {
        try Data(contentsOf: try allowedURL(path))
    }

    public func writeFile(path: String, contents: Data) async throws {
        try writeAllowed(path: path, contents: contents)
    }

    public func list(path: String) async throws -> [String] {
        let url = try allowedURL(path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw JoyflowStoreError.notFound(path)
        }
        guard isDir.boolValue else {
            throw JoyflowStoreError.io("\(path) is a file, not a folder.")
        }
        do {
            return try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
        } catch {
            throw JoyflowStoreError.io(error.localizedDescription)
        }
    }

    public func collect(paths: [String]) async throws -> [SandboxFile] {
        var files: [SandboxFile] = []
        for path in paths {
            files.append(SandboxFile(path: path, contents: try Data(contentsOf: try allowedURL(path))))
        }
        return files
    }

    public func teardown() async {}

    public func writeAllowed(path: String, contents: Data) throws {
        let url = try allowedURL(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url)
    }

    public func allowedURL(_ path: String) throws -> URL {
        let url: URL
        if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path).standardizedFileURL
        } else {
            url = workspace.appendingPathComponent(path).standardizedFileURL
        }
        if ComputerAccess.allows(url, workspace: workspace, extraRoots: extraRoots) {
            return url
        }
        if let reason = ComputerAccess.denyReason(url) {
            throw JoyflowStoreError.io(reason)
        }
        throw JoyflowStoreError.outsideWorkspace(path)
    }

    private func resolvedDirectory(_ cwd: String?) -> URL {
        if let cwd, let url = try? allowedURL(cwd) { return url }
        return workspace
    }
}
