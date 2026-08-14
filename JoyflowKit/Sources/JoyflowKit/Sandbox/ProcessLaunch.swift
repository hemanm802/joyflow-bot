import Foundation

enum ProcessLaunch {
    struct Result: Sendable {
        var status: Int32
        var stdout: String
        var stderr: String
    }

    static func run(
        executable: URL,
        arguments: [String],
        directory: URL?,
        environment: [String: String]?
    ) throws -> Result {
        #if os(macOS)
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        if let environment, !environment.isEmpty {
            var merged = ProcessInfo.processInfo.environment
            environment.forEach { merged[$0.key] = $0.value }
            process.environment = merged
        }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return Result(status: process.terminationStatus, stdout: stdout, stderr: stderr)
        #else
        throw JoyflowStoreError.io("shell is not available on this platform")
        #endif
    }
}

enum BookmarkAccess {
    static var creation: URL.BookmarkCreationOptions {
        #if os(macOS)
        [.withSecurityScope]
        #else
        []
        #endif
    }

    static var resolution: URL.BookmarkResolutionOptions {
        #if os(macOS)
        [.withSecurityScope]
        #else
        []
        #endif
    }
}
