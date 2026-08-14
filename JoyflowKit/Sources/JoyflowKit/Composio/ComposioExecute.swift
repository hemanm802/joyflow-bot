import Foundation

/// Build a Composio v3.1 execute call. Missing keys never produce an HTTP request.
public struct ComposioExecutePlan: Sendable, Equatable {
    public var request: ComposioRequest?
    public var cliArguments: [String]
    public var error: String?

    public init(request: ComposioRequest?, cliArguments: [String], error: String?) {
        self.request = request
        self.cliArguments = cliArguments
        self.error = error
    }

    public var ready: Bool { request != nil && error == nil }
}

public enum ComposioExecute: Sendable {
    public static let version = "latest"
    public static let cliName = "composio"

    public static func plan(
        apiKey: String?,
        toolSlug: String,
        connectedAccountID: String,
        arguments: [String: Any],
        userID: String = JoyflowKit.composioUserID,
        version: String = version
    ) -> ComposioExecutePlan {
        let slug = toolSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = connectedAccountID.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = encodeArguments(arguments)
        let cli = cliArguments(toolSlug: slug.isEmpty ? "TOOL" : slug, argumentsJSON: payload)
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else {
            return ComposioExecutePlan(
                request: nil,
                cliArguments: cli,
                error: "Add a Composio API key in Settings."
            )
        }
        guard !slug.isEmpty else {
            return ComposioExecutePlan(request: nil, cliArguments: cli, error: "Missing tool slug.")
        }
        guard !account.isEmpty else {
            return ComposioExecutePlan(
                request: nil,
                cliArguments: cli,
                error: "Missing connected account."
            )
        }
        let request = ComposioClient(apiKey: key, userID: userID).executeRequest(
            toolSlug: slug,
            connectedAccountID: account,
            arguments: arguments,
            version: version
        )
        return ComposioExecutePlan(request: request, cliArguments: cli, error: nil)
    }

    /// Official CLI: `composio execute SLUG -d '{...}'`
    public static func cliArguments(toolSlug: String, argumentsJSON: String) -> [String] {
        ["execute", toolSlug, "-d", argumentsJSON]
    }

    /// Official CLI: `composio link TOOLKIT`
    public static func cliLinkArguments(toolkit: String) -> [String] {
        ["link", toolkit]
    }

    public static func encodeArguments(_ arguments: [String: Any]) -> String {
        (try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    public static func parseArgumentsJSON(_ raw: String) -> [String: Any] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            let data = trimmed.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    public static func findCLI(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        let home = environment["HOME"] ?? NSHomeDirectory()
        var directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        directories.append(contentsOf: [
            home + "/.local/bin",
            home + "/.composio",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ])
        var seen: Set<String> = []
        for directory in directories where seen.insert(directory).inserted {
            let candidate = (directory as NSString).appendingPathComponent(cliName)
            if isExecutable(candidate) { return candidate }
        }
        return nil
    }
}

public protocol ComposioTransporting: Sendable {
    func send(_ request: ComposioRequest) async throws -> Data
}

public protocol ComposioProcessRunning: Sendable {
    func run(executable: String, arguments: [String]) async throws -> String
}

public struct URLSessionComposioTransport: ComposioTransporting {
    public init() {}

    public func send(_ request: ComposioRequest) async throws -> Data {
        guard let url = URL(string: request.url) else {
            throw JoyflowStoreError.invalidURL(request.url)
        }
        var outbound = URLRequest(url: url)
        outbound.httpMethod = request.method
        request.headers.forEach { outbound.setValue($1, forHTTPHeaderField: $0) }
        outbound.httpBody = request.body
        let (data, response) = try await URLSession.shared.data(for: outbound)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw JoyflowStoreError.io("composio \(http.statusCode): \(body)")
        }
        return data
    }
}

public struct LocalComposioProcess: ComposioProcessRunning {
    public init() {}

    public func run(executable: String, arguments: [String]) async throws -> String {
        let result = try ProcessLaunch.run(
            executable: URL(fileURLWithPath: executable),
            arguments: arguments,
            directory: nil,
            environment: nil
        )
        if result.status != 0 {
            throw JoyflowStoreError.io(
                "composio \(result.status): \(result.stderr.isEmpty ? result.stdout : result.stderr)"
            )
        }
        return result.stdout.isEmpty ? result.stderr : result.stdout
    }
}

public final class RecordingComposioTransport: ComposioTransporting, @unchecked Sendable {
    public var calls: [ComposioRequest] = []
    public var listResponse = Data("{\"items\":[]}".utf8)
    public var authConfigResponse = Data("{\"items\":[]}".utf8)
    public var linkResponse = Data("{}".utf8)
    public var executeResponse = Data("{\"successful\":true,\"error\":null}".utf8)

    public init() {}

    public func send(_ request: ComposioRequest) async throws -> Data {
        calls.append(request)
        if request.url.contains("/auth_configs") { return authConfigResponse }
        if request.method == "POST", request.url.contains("/connected_accounts/link") { return linkResponse }
        if request.method == "GET", request.url.contains("/connected_accounts") { return listResponse }
        return executeResponse
    }
}

public final class RecordingComposioProcess: ComposioProcessRunning, @unchecked Sendable {
    public var runs: [(executable: String, arguments: [String])] = []
    public var output = "ok"
    public var error: String?

    public init() {}

    public func run(executable: String, arguments: [String]) async throws -> String {
        runs.append((executable, arguments))
        if let error { throw JoyflowStoreError.io(error) }
        return output
    }
}
