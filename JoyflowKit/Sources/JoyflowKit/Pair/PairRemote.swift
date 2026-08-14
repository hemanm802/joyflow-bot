import CryptoKit
import Foundation

/// Public HTTPS origin of a paired Mac (`https://….trycloudflare.com` or `http://lan:port`).
public struct PairTarget: Equatable, Sendable {
    public var origin: URL
    public var code: String
    public var token: String

    public init(origin: URL, code: String, token: String) {
        self.origin = origin
        self.code = code
        self.token = token
    }
}

public struct PairChatRequest: Codable, Sendable, Equatable {
    public var projectID: UUID
    public var threadID: UUID
    public var message: ChatMessageRecord
    public var projectName: String

    public init(
        projectID: UUID,
        threadID: UUID,
        message: ChatMessageRecord,
        projectName: String = ""
    ) {
        self.projectID = projectID
        self.threadID = threadID
        self.message = message
        self.projectName = projectName
    }

    enum CodingKeys: String, CodingKey {
        case projectID, threadID, message, projectName
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectID = try container.decode(UUID.self, forKey: .projectID)
        threadID = try container.decode(UUID.self, forKey: .threadID)
        message = try container.decode(ChatMessageRecord.self, forKey: .message)
        projectName = try container.decodeIfPresent(String.self, forKey: .projectName) ?? ""
    }
}

public struct PairControlStatus: Codable, Sendable, Equatable {
    public var streaming: Bool
    public var text: String
    public var reasoning: String
    public var activity: String?
    public var steps: [String]
    public var approval: PendingApproval?
    public var error: String?
    public var projectID: UUID?
    public var threadID: UUID?

    public init(
        streaming: Bool = false,
        text: String = "",
        reasoning: String = "",
        activity: String? = nil,
        steps: [String] = [],
        approval: PendingApproval? = nil,
        error: String? = nil,
        projectID: UUID? = nil,
        threadID: UUID? = nil
    ) {
        self.streaming = streaming
        self.text = text
        self.reasoning = reasoning
        self.activity = activity
        self.steps = steps
        self.approval = approval
        self.error = error
        self.projectID = projectID
        self.threadID = threadID
    }
}

public enum PairSeal {
    public static func wrap(_ data: Data, token: String) throws -> Data {
        let sealed = try AES.GCM.seal(data, using: key(token))
        guard let combined = sealed.combined else {
            throw JoyflowStoreError.io("Could not seal pair data.")
        }
        return combined
    }

    public static func unwrap(_ data: Data, token: String) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key(token))
    }

    public static func wrapJSON<T: Encodable>(_ value: T, token: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try wrap(encoder.encode(value), token: token)
    }

    public static func unwrapJSON<T: Decodable>(_ type: T.Type, from data: Data, token: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: unwrap(data, token: token))
    }

    public static func topic(token: String) -> String {
        let digest = SHA256.hash(data: Data("joyflow-pair-v1.\(token)".utf8))
        return "jf" + digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private static func key(_ token: String) -> SymmetricKey {
        let digest = SHA256.hash(data: Data("joyflow-seal-v1.\(token)".utf8))
        return SymmetricKey(data: Data(digest))
    }
}

public enum PairRendezvous {
    public static let serviceURL = URL(string: "https://ntfy.sh")!

    private struct Notice: Codable {
        var origin: String
        var code: String
        var publishedAt: Date
    }

    public static func publish(origin: URL, code: String, token: String) async throws {
        var request = URLRequest(url: serviceURL.appendingPathComponent(PairSeal.topic(token: token)))
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("replace", forHTTPHeaderField: "X-Canonical")
        request.httpBody = try PairSeal.wrapJSON(
            Notice(origin: origin.absoluteString, code: code, publishedAt: Date()),
            token: token
        )
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            throw JoyflowStoreError.io("Could not publish the pair address.")
        }
    }

    public static func resolve(token: String) async throws -> URL? {
        var parts = URLComponents(
            url: serviceURL.appendingPathComponent(PairSeal.topic(token: token)).appendingPathComponent("json"),
            resolvingAgainstBaseURL: false
        )
        parts?.queryItems = [URLQueryItem(name: "poll", value: "1")]
        guard let url = parts?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status), !data.isEmpty else { return nil }
        var latest: URL?
        let lines = String(data: data, encoding: .utf8)?.split(whereSeparator: \.isNewline) ?? []
        for line in lines {
            guard let row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            else { continue }
            let blob: Data?
            if let message = row["message"] as? String {
                blob = Data(base64Encoded: message) ?? Data(message.utf8)
            } else {
                blob = nil
            }
            guard let blob,
                let notice = try? PairSeal.unwrapJSON(Notice.self, from: blob, token: token),
                let origin = URL(string: notice.origin)
            else { continue }
            latest = origin
        }
        return latest
    }
}

/// Encrypted HTTPS mailbox. Phone and Mac only talk to `https://ntfy.sh`.
/// This is the out-of-the-box path: no LAN, no cloudflared, no ATS HTTP.
public enum PairMailbox {
    public static let marker = "mailbox://joyflow"

    public struct Job: Codable, Sendable, Equatable {
        public enum Action: String, Codable, Sendable, Equatable {
            case chat
            case allow
            case deny
            case stop
        }

        public var id: UUID
        public var action: Action
        public var request: PairChatRequest?
        public var approvalID: String?

        public init(id: UUID = UUID(), request: PairChatRequest) {
            self.id = id
            self.action = .chat
            self.request = request
            self.approvalID = nil
        }

        public init(
            id: UUID = UUID(),
            action: Action,
            request: PairChatRequest? = nil,
            approvalID: String? = nil
        ) {
            self.id = id
            self.action = action
            self.request = request
            self.approvalID = approvalID
        }

        public static func allow(_ id: String) -> Job {
            Job(action: .allow, approvalID: id)
        }

        public static func deny() -> Job {
            Job(action: .deny)
        }

        public static func stop() -> Job {
            Job(action: .stop)
        }

        enum CodingKeys: String, CodingKey {
            case id, action, request, approvalID
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            action = try container.decodeIfPresent(Action.self, forKey: .action) ?? .chat
            request = try container.decodeIfPresent(PairChatRequest.self, forKey: .request)
            approvalID = try container.decodeIfPresent(String.self, forKey: .approvalID)
        }
    }

    private struct Pack<T: Codable>: Codable {
        var sentAt: Date
        var value: T
    }

    private enum Kind: String {
        case snapshot = "s"
        case job = "j"
        case status = "e"
    }

    public static func publishSnapshot(_ snapshot: PairSnapshot, token: String) async throws {
        try await publish(snapshot, token: token, kind: .snapshot)
    }

    public static func latestSnapshot(token: String) async throws -> PairSnapshot? {
        try await latest(PairSnapshot.self, token: token, kind: .snapshot)
    }

    public static func publishJob(_ job: Job, token: String) async throws {
        try await publish(job, token: token, kind: .job)
    }

    public static func latestJob(token: String) async throws -> Job? {
        try await latest(Job.self, token: token, kind: .job)
    }

    public static func publishStatus(_ status: PairControlStatus, token: String) async throws {
        try await publish(status, token: token, kind: .status)
    }

    public static func latestStatus(token: String) async throws -> PairControlStatus? {
        try await latest(PairControlStatus.self, token: token, kind: .status)
    }

    private static func topic(_ token: String, _ kind: Kind) -> String {
        PairSeal.topic(token: token) + kind.rawValue
    }

    private static func publish<T: Codable>(_ value: T, token: String, kind: Kind) async throws {
        let sealed = try PairSeal.wrapJSON(Pack(sentAt: Date(), value: value), token: token)
        var request = URLRequest(url: PairRendezvous.serviceURL.appendingPathComponent(topic(token, kind)))
        request.httpMethod = "PUT"
        request.timeoutInterval = 20
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("joyflow-\(kind.rawValue).bin", forHTTPHeaderField: "Filename")
        request.setValue("replace", forHTTPHeaderField: "X-Canonical")
        request.httpBody = sealed
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            throw JoyflowStoreError.io("Could not reach the pair mailbox. Check internet on both devices.")
        }
    }

    private static func latest<T: Codable>(_ type: T.Type, token: String, kind: Kind) async throws -> T? {
        var parts = URLComponents(
            url: PairRendezvous.serviceURL.appendingPathComponent(topic(token, kind)).appendingPathComponent("json"),
            resolvingAgainstBaseURL: false
        )
        parts?.queryItems = [
            URLQueryItem(name: "poll", value: "1"),
            URLQueryItem(name: "since", value: "all"),
        ]
        guard let url = parts?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status), !data.isEmpty else { return nil }
        var newest: (Date, T)?
        let lines = String(data: data, encoding: .utf8)?.split(whereSeparator: \.isNewline) ?? []
        for line in lines {
            guard let row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            else { continue }
            guard let blob = try await blob(from: row) else { continue }
            guard let pack = try? PairSeal.unwrapJSON(Pack<T>.self, from: blob, token: token) else {
                continue
            }
            if let current = newest {
                if pack.sentAt > current.0 {
                    newest = (pack.sentAt, pack.value)
                }
            } else {
                newest = (pack.sentAt, pack.value)
            }
        }
        return newest?.1
    }

    private static func blob(from row: [String: Any]) async throws -> Data? {
        if let attachment = row["attachment"] as? [String: Any],
            let link = attachment["url"] as? String,
            let url = URL(string: link)
        {
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(status) else { return nil }
            return data
        }
        if let message = row["message"] as? String {
            return Data(base64Encoded: message) ?? Data(message.utf8)
        }
        return nil
    }
}

public final class PairTunnel: @unchecked Sendable {
    public private(set) var origin: URL?
    #if os(macOS)
    private var process: Process?
    private var logHandle: FileHandle?
    #endif
    private var log = Data()
    private var boundPort: UInt16 = 0
    private let lock = NSLock()

    public init() {}

    deinit { stop() }

    public var isRunning: Bool {
        #if os(macOS)
        lock.withLock { process?.isRunning == true }
        #else
        false
        #endif
    }

    public static func cloudflaredLaunchPath() -> String? {
        #if os(macOS)
        let names = [
            "/opt/homebrew/bin/cloudflared",
            "/usr/local/bin/cloudflared",
            "/opt/homebrew/opt/cloudflared/bin/cloudflared",
        ]
        for path in names where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent("cloudflared").path
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
        #else
        return nil
        #endif
    }

    public func start(localPort: UInt16) async throws -> URL {
        #if os(macOS)
        if isRunning, boundPort == localPort, let existing = origin {
            if await Self.isHealthy(existing) { return existing }
        }
        stop()
        guard let binary = Self.cloudflaredLaunchPath() else {
            throw JoyflowStoreError.io(
                "Install cloudflared to pair off this Wi-Fi: brew install cloudflared"
            )
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = [
            "tunnel", "--no-autoupdate", "--url", "http://127.0.0.1:\(localPort)",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] file in
            let chunk = file.availableData
            guard !chunk.isEmpty else { return }
            self?.consume(chunk)
        }
        try process.run()
        lock.withLock {
            self.process = process
            self.logHandle = handle
            self.boundPort = localPort
            self.log = Data()
            self.origin = nil
        }

        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline, process.isRunning {
            if let url = lock.withLock({ origin }), await Self.isHealthy(url) {
                return url
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        stop()
        throw JoyflowStoreError.io(
            "Could not open a public pair link. Keep Joyflow open and tap New code."
        )
        #else
        throw JoyflowStoreError.io("Public pair tunnels run on the Mac.")
        #endif
    }

    public func stop() {
        #if os(macOS)
        lock.withLock {
            logHandle?.readabilityHandler = nil
            logHandle = nil
            process?.terminate()
            process = nil
            origin = nil
            boundPort = 0
        }
        #else
        lock.withLock { origin = nil }
        #endif
    }

    private func consume(_ chunk: Data) {
        lock.lock()
        log.append(chunk)
        if log.count > 64_000 {
            log.removeFirst(log.count - 32_000)
        }
        if origin == nil {
            origin = Self.parseOrigin(from: log)
        }
        lock.unlock()
    }

    public static func isHealthy(_ origin: URL) async -> Bool {
        var request = URLRequest(url: origin.appending(path: "v1/health"))
        request.httpMethod = "GET"
        request.timeoutInterval = 4
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return ((response as? HTTPURLResponse)?.statusCode ?? 0) == 200
    }

    public static func parseOrigin(from data: Data) -> URL? {
        let text = String(data: data, encoding: .utf8) ?? ""
        guard
            let match = text.range(
                of: "https://[a-z0-9-]+\\.trycloudflare\\.com",
                options: .regularExpression
            )
        else { return nil }
        return URL(string: String(text[match]))
    }
}
