import Foundation

/// Short-lived host offer. Token is the secret; the code is what a person types.
public struct PairOffer: Codable, Sendable, Equatable {
    public var version: Int
    public var code: String
    public var token: String
    public var createdAt: Date

    public init(version: Int = 1, code: String, token: String, createdAt: Date = Date()) {
        self.version = version
        self.code = code
        self.token = token
        self.createdAt = createdAt
    }
}

/// Host payload a guest can accept. Filesystem pair uses `rootPath`;
/// network pair uses a public `origin` and/or LAN `host`/`port`.
public struct PairEnvelope: Codable, Sendable, Equatable {
    public var offer: PairOffer
    public var rootPath: String
    public var host: String?
    public var port: Int?
    public var origin: String?

    public init(
        offer: PairOffer,
        rootPath: String,
        host: String? = nil,
        port: Int? = nil,
        origin: String? = nil
    ) {
        self.offer = offer
        self.rootPath = rootPath
        self.host = host
        self.port = port
        self.origin = origin
    }

    public var url: URL { PairSession.url(for: self) }
    public var usesNetwork: Bool {
        PairSession.usesNetwork(host: host, port: port) || PairSession.hasOrigin(origin)
    }

    public var targetOrigin: URL? { PairSession.origin(from: origin, host: host, port: port) }
}

/// Guest remembers the host so later pull/push use the same handshake.
public struct PairBinding: Codable, Sendable, Equatable {
    public var code: String
    public var token: String
    public var peerRootPath: String
    public var peerHost: String?
    public var peerPort: Int?
    public var peerOrigin: String?

    public init(
        code: String,
        token: String,
        peerRootPath: String,
        peerHost: String? = nil,
        peerPort: Int? = nil,
        peerOrigin: String? = nil
    ) {
        self.code = code
        self.token = token
        self.peerRootPath = peerRootPath
        self.peerHost = peerHost
        self.peerPort = peerPort
        self.peerOrigin = peerOrigin
    }

    public var usesNetwork: Bool {
        PairSession.usesNetwork(host: peerHost, port: peerPort) || PairSession.hasOrigin(peerOrigin)
    }

    public var usesMailbox: Bool { peerOrigin == PairMailbox.marker || peerRootPath == PairMailbox.marker }

    public var canRemoteControl: Bool { !token.isEmpty && (usesNetwork || usesMailbox) }

    public var targetOrigin: URL? {
        PairSession.origin(from: peerOrigin, host: peerHost, port: peerPort)
    }
}

public struct PairThreadPayload: Codable, Sendable, Equatable {
    public var id: UUID
    public var messages: [ChatMessageRecord]

    public init(id: UUID, messages: [ChatMessageRecord]) {
        self.id = id
        self.messages = messages
    }
}

public struct PairProjectPayload: Codable, Sendable, Equatable {
    public var manifest: ProjectManifest
    public var soul: String
    public var instructions: String
    public var notes: [NoteRecord]
    public var memories: [MemoryRecord]
    public var commons: [String]
    public var threads: [PairThreadPayload]
    public var avatar: Data?

    public init(
        manifest: ProjectManifest,
        soul: String,
        instructions: String,
        notes: [NoteRecord],
        memories: [MemoryRecord],
        commons: [String],
        threads: [PairThreadPayload],
        avatar: Data? = nil
    ) {
        self.manifest = manifest
        self.soul = soul
        self.instructions = instructions
        self.notes = notes
        self.memories = memories
        self.commons = commons
        self.threads = threads
        self.avatar = avatar
    }
}

/// Portable project+thread snapshot. Never includes settings, keychain, or API keys.
public struct PairSnapshot: Codable, Sendable, Equatable {
    public var version: Int
    public var projects: [PairProjectPayload]

    public init(version: Int = 1, projects: [PairProjectPayload]) {
        self.version = version
        self.projects = projects
    }
}

public enum PairSession {
    public static let offerFileName = "pair-offer.json"
    public static let bindingFileName = "pair-binding.json"
    public static let excludedRootFiles: Set<String> = [
        "settings.json",
        "composio-accounts.json",
        "models.json",
        offerFileName,
        bindingFileName,
    ]

    private static let codeAlphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    public static func makeCode(generator: () -> UInt8 = { UInt8.random(in: 0...255) }) -> String {
        String((0..<6).map { _ in codeAlphabet[Int(generator()) % codeAlphabet.count] })
    }

    public static func makeToken() -> String {
        UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
            + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    }

    public static func usesNetwork(host: String?, port: Int?) -> Bool {
        guard let host, !host.isEmpty, let port, port > 0 else { return false }
        return true
    }

    public static func hasOrigin(_ origin: String?) -> Bool {
        guard let origin, let url = URL(string: origin), let scheme = url.scheme else { return false }
        return scheme == "http" || scheme == "https"
    }

    public static func origin(from origin: String?, host: String?, port: Int?) -> URL? {
        if let origin, let url = URL(string: origin), url.scheme == "http" || url.scheme == "https" {
            return url
        }
        if let host = PairLAN.hosts(from: host).first, let port, port > 0 {
            return URL(string: "http://\(host):\(port)")
        }
        return nil
    }

    public static func url(for envelope: PairEnvelope) -> URL {
        var parts = URLComponents()
        parts.scheme = JoyflowKit.urlScheme
        parts.host = "pair"
        var items = [
            URLQueryItem(name: "code", value: envelope.offer.code),
            URLQueryItem(name: "token", value: envelope.offer.token),
        ]
        if let origin = envelope.origin, hasOrigin(origin) {
            items.append(URLQueryItem(name: "origin", value: origin))
        }
        if usesNetwork(host: PairLAN.hosts(from: envelope.host).first, port: envelope.port) {
            items.append(URLQueryItem(name: "host", value: envelope.host))
            items.append(URLQueryItem(name: "port", value: String(envelope.port ?? 0)))
        } else if envelope.origin == nil, !envelope.rootPath.isEmpty {
            items.append(URLQueryItem(name: "root", value: envelope.rootPath))
        }
        parts.queryItems = items
        return parts.url ?? URL(string: "\(JoyflowKit.urlScheme)://pair")!
    }

    public static func parse(_ url: URL) -> PairEnvelope? {
        guard url.scheme?.lowercased() == JoyflowKit.urlScheme else { return nil }
        let host = url.host ?? url.pathComponents.drop(while: { $0 == "/" }).first
        guard host == "pair" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }
        guard let code = value("code"), !code.isEmpty,
            let token = value("token"), !token.isEmpty
        else { return nil }
        let root = value("root") ?? ""
        let peerHost = value("host")
        let peerPort = value("port").flatMap(Int.init)
        let origin = value("origin")
        return PairEnvelope(
            offer: PairOffer(code: code, token: token),
            rootPath: root,
            host: peerHost,
            port: peerPort,
            origin: origin
        )
    }

    public static func parsePasted(_ raw: String) -> PairEnvelope? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let envelope = parse(url) {
            return envelope
        }
        guard let range = trimmed.range(of: "\(JoyflowKit.urlScheme)://", options: .caseInsensitive)
        else { return nil }
        var slice = String(trimmed[range.lowerBound...])
        if let end = slice.firstIndex(where: { $0.isNewline || $0.isWhitespace }) {
            slice = String(slice[..<end])
        }
        if let url = URL(string: slice), let envelope = parse(url) {
            return envelope
        }
        if let encoded = slice.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
            let url = URL(string: encoded),
            let envelope = parse(url)
        {
            return envelope
        }
        return nil
    }

    public static func parseCode(_ raw: String) -> String? {
        let code = raw.uppercased().filter { codeAlphabet.contains($0) }
        return code.count == 6 ? code : nil
    }

    @discardableResult
    public static func offer(from store: FileProjectStore) throws -> PairEnvelope {
        let envelope = PairEnvelope(
            offer: PairOffer(code: makeCode(), token: makeToken()),
            rootPath: store.rootURL.path
        )
        try writeJSON(envelope.offer, to: store.rootURL.appendingPathComponent(offerFileName))
        return envelope
    }

    @discardableResult
    public static func accept(_ envelope: PairEnvelope, into store: FileProjectStore) throws -> PairBinding {
        if envelope.usesNetwork {
            throw JoyflowStoreError.io("This pair link has to be accepted over the local network.")
        }
        return try acceptFilesystem(envelope, into: store)
    }

    @discardableResult
    public static func accept(_ envelope: PairEnvelope, into store: FileProjectStore) async throws -> PairBinding {
        if envelope.usesNetwork || !envelope.offer.token.isEmpty {
            do {
                return try await acceptNetwork(envelope, into: store)
            } catch {
                if !envelope.rootPath.isEmpty {
                    return try acceptFilesystem(envelope, into: store)
                }
                throw error
            }
        }
        return try acceptFilesystem(envelope, into: store)
    }

    @discardableResult
    public static func acceptFilesystem(_ envelope: PairEnvelope, into store: FileProjectStore) throws -> PairBinding {
        let host = try FileProjectStore(rootURL: URL(fileURLWithPath: envelope.rootPath))
        let posted = try readJSON(PairOffer.self, from: host.rootURL.appendingPathComponent(offerFileName))
        guard posted.code == envelope.offer.code, posted.token == envelope.offer.token else {
            throw JoyflowStoreError.io("That code does not match the desktop. Tap New code on the Mac and try again.")
        }
        try sync(from: host, to: store)
        return try writeBinding(
            PairBinding(
                code: envelope.offer.code,
                token: envelope.offer.token,
                peerRootPath: envelope.rootPath
            ),
            into: store
        )
    }

    @discardableResult
    public static func acceptNetwork(_ envelope: PairEnvelope, into store: FileProjectStore) async throws
        -> PairBinding
    {
        if let snapshot = try? await PairMailbox.latestSnapshot(token: envelope.offer.token) {
            try apply(snapshot, to: store)
            return try writeBinding(mailboxBinding(from: envelope), into: store)
        }
        let extras = await candidateOrigins(for: envelope)
        if !extras.isEmpty {
            let target = try await PairClient.firstReachable(
                extras.map { PairTarget(origin: $0, code: envelope.offer.code, token: envelope.offer.token) }
            )
            try apply(try await PairClient.snapshot(target), to: store)
            return try writeBinding(makeBinding(from: target), into: store)
        }
        for _ in 0..<8 {
            try? await Task.sleep(for: .milliseconds(800))
            if let snapshot = try? await PairMailbox.latestSnapshot(token: envelope.offer.token) {
                try apply(snapshot, to: store)
                return try writeBinding(mailboxBinding(from: envelope), into: store)
            }
        }
        throw JoyflowStoreError.io(
            "Couldn't reach the Mac. Keep Joyflow open on the desktop and paste the link again."
        )
    }

    public static func mailboxBinding(from envelope: PairEnvelope) -> PairBinding {
        PairBinding(
            code: envelope.offer.code,
            token: envelope.offer.token,
            peerRootPath: PairMailbox.marker,
            peerOrigin: PairMailbox.marker
        )
    }

    public static func resolveTarget(for envelope: PairEnvelope) async throws -> PairTarget {
        try await PairClient.firstReachable(
            candidateOrigins(for: envelope).map {
                PairTarget(origin: $0, code: envelope.offer.code, token: envelope.offer.token)
            }
        )
    }

    public static func resolveTarget(for binding: PairBinding) async throws -> PairTarget {
        var origins: [URL] = []
        if !binding.token.isEmpty, let resolved = try? await PairRendezvous.resolve(token: binding.token) {
            origins.append(resolved)
        }
        if let stored = binding.targetOrigin, !origins.contains(stored) {
            origins.append(stored)
        }
        return try await PairClient.firstReachable(
            origins.map { PairTarget(origin: $0, code: binding.code, token: binding.token) }
        )
    }

    public static func candidateOrigins(for envelope: PairEnvelope) async -> [URL] {
        var origins: [URL] = []
        if let published = envelope.origin.flatMap(URL.init(string:)), hasOrigin(published.absoluteString) {
            origins.append(published)
        }
        if !envelope.offer.token.isEmpty, let resolved = try? await PairRendezvous.resolve(token: envelope.offer.token) {
            if !origins.contains(resolved) { origins.append(resolved) }
        }
        let port = envelope.port ?? Int(PairLAN.preferredPort)
        for host in PairLAN.hosts(from: envelope.host) {
            if let lan = origin(from: nil, host: host, port: port), !origins.contains(lan) {
                origins.append(lan)
            }
        }
        return origins
    }

    public static func makeBinding(from target: PairTarget) -> PairBinding {
        PairBinding(
            code: target.code,
            token: target.token,
            peerRootPath: target.origin.absoluteString,
            peerHost: target.origin.host,
            peerPort: target.origin.port,
            peerOrigin: target.origin.absoluteString
        )
    }

    @discardableResult
    public static func acceptCode(_ code: String, into store: FileProjectStore) async throws -> PairBinding {
        guard let parsed = parseCode(code) else {
            throw JoyflowStoreError.io("Type the 6-character code from the Mac.")
        }
        var endpoints = await PairBrowser.findHosts()
        for ip in PairLAN.advertisedIPv4s() {
            let fallback = PairLAN.Endpoint(host: ip, port: Int(PairLAN.preferredPort))
            if !endpoints.contains(fallback) {
                endpoints.append(fallback)
            }
        }
        if endpoints.isEmpty {
            endpoints = [PairLAN.Endpoint(host: "127.0.0.1", port: Int(PairLAN.preferredPort))]
        }
        var lastError: any Error = JoyflowStoreError.io(
            "Couldn't find the Mac on this Wi-Fi. Open Pair iPhone on the desktop and stay on the same network."
        )
        for endpoint in endpoints {
            do {
                let fetched = try await PairClient.fetch(
                    host: endpoint.host,
                    port: endpoint.port,
                    code: parsed,
                    token: nil
                )
                try apply(fetched.snapshot, to: store)
                return try writeBinding(
                    PairBinding(
                        code: parsed,
                        token: fetched.token ?? "",
                        peerRootPath: "http://\(endpoint.host):\(endpoint.port)",
                        peerHost: endpoint.host,
                        peerPort: endpoint.port
                    ),
                    into: store
                )
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    public static func binding(in store: FileProjectStore) -> PairBinding? {
        try? readJSON(PairBinding.self, from: store.rootURL.appendingPathComponent(bindingFileName))
    }

    public static func sync(from source: FileProjectStore, to dest: FileProjectStore) throws {
        try apply(try snapshot(from: source), to: dest)
    }

    public static func pull(into store: FileProjectStore) async throws {
        guard let binding = binding(in: store) else {
            throw JoyflowStoreError.io("this store is not paired")
        }
        if binding.usesMailbox {
            guard let snapshot = try await PairMailbox.latestSnapshot(token: binding.token) else {
                throw JoyflowStoreError.io("No snapshot from the Mac yet. Keep Joyflow open on the desktop.")
            }
            try apply(snapshot, to: store)
            return
        }
        if binding.usesNetwork {
            let target = try await resolveTarget(for: binding)
            try apply(try await PairClient.snapshot(target), to: store)
            if target.origin.absoluteString != binding.peerOrigin {
                _ = try writeBinding(makeBinding(from: target), into: store)
            }
            return
        }
        let peer = try FileProjectStore(rootURL: URL(fileURLWithPath: binding.peerRootPath))
        try sync(from: peer, to: store)
    }

    public static func push(from store: FileProjectStore) async throws {
        guard let binding = binding(in: store) else {
            throw JoyflowStoreError.io("this store is not paired")
        }
        if binding.usesMailbox {
            try await PairMailbox.publishSnapshot(try snapshot(from: store), token: binding.token)
            return
        }
        if binding.usesNetwork {
            try await PairClient.push(try snapshot(from: store), to: try await resolveTarget(for: binding))
            return
        }
        let peer = try FileProjectStore(rootURL: URL(fileURLWithPath: binding.peerRootPath))
        try sync(from: store, to: peer)
    }

    public static func encodeSnapshot(_ snapshot: PairSnapshot) throws -> Data {
        try encoder.encode(snapshot)
    }

    public static func decodeSnapshot(_ data: Data) throws -> PairSnapshot {
        try decoder.decode(PairSnapshot.self, from: data)
    }

    public static func writeBinding(_ binding: PairBinding, into store: FileProjectStore) throws -> PairBinding {
        try writeJSON(binding, to: store.rootURL.appendingPathComponent(bindingFileName))
        return binding
    }

    public static func currentOffer(in store: FileProjectStore) -> PairOffer? {
        try? readJSON(PairOffer.self, from: store.rootURL.appendingPathComponent(offerFileName))
    }

    public static func snapshot(from store: FileProjectStore) throws -> PairSnapshot {
        var projects: [PairProjectPayload] = []
        for manifest in try store.listProjects() {
            let layout = store.layout(for: manifest.id)
            let threadFiles =
                (try? FileManager.default.contentsOfDirectory(
                    at: layout.threads,
                    includingPropertiesForKeys: nil
                )) ?? []
            var threads: [PairThreadPayload] = []
            for file in threadFiles where file.pathExtension == "jsonl" {
                guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { continue }
                threads.append(
                    PairThreadPayload(
                        id: id,
                        messages: (try? store.messages(projectID: manifest.id, threadID: id)) ?? []
                    )
                )
            }
            projects.append(
                PairProjectPayload(
                    manifest: manifest,
                    soul: (try? store.readSoul(projectID: manifest.id)) ?? "",
                    instructions: (try? store.readInstructions(projectID: manifest.id)) ?? "",
                    notes: (try? store.notes(projectID: manifest.id)) ?? [],
                    memories: (try? store.memories(projectID: manifest.id)) ?? [],
                    commons: (try? store.linkedCommons(projectID: manifest.id)) ?? [],
                    threads: threads,
                    avatar: store.avatarData(projectID: manifest.id)
                )
            )
        }
        return PairSnapshot(projects: projects)
    }

    public static func apply(_ snapshot: PairSnapshot, to store: FileProjectStore) throws {
        let fm = FileManager.default
        for payload in snapshot.projects {
            let dir = store.projectsURL.appendingPathComponent(payload.manifest.id.uuidString)
            if !fm.fileExists(atPath: dir.appendingPathComponent("project.json").path) {
                try ProjectLayout.create(at: dir, manifest: payload.manifest)
            } else {
                try encoder.encode(payload.manifest).write(
                    to: ProjectLayout(root: dir).projectJSON,
                    options: .atomic
                )
            }
            try store.writeSoul(projectID: payload.manifest.id, text: payload.soul)
            try store.writeInstructions(projectID: payload.manifest.id, text: payload.instructions)
            if let avatar = payload.avatar, !avatar.isEmpty {
                try store.setAvatar(projectID: payload.manifest.id, data: avatar)
            }
            let layout = store.layout(for: payload.manifest.id)
            for note in payload.notes {
                try NoteMarkdown.write(
                    note,
                    to: layout.knowledge.appendingPathComponent("\(note.slug).md")
                )
            }
            try ProjectLayout.defaultMemories().write(to: layout.memories, atomically: true, encoding: .utf8)
            for memory in payload.memories {
                try MemoryMarkdown.append(memory, to: layout.memories)
            }
            try encoder.encode(CommonsFile(linked: payload.commons)).write(to: layout.commons, options: .atomic)
            for thread in payload.threads {
                let existing = (try? store.messages(projectID: payload.manifest.id, threadID: thread.id)) ?? []
                try store.replaceThread(
                    projectID: payload.manifest.id,
                    threadID: thread.id,
                    messages: mergeMessages(existing, thread.messages)
                )
            }
        }
    }

    public static func mergeMessages(
        _ existing: [ChatMessageRecord],
        _ incoming: [ChatMessageRecord]
    ) -> [ChatMessageRecord] {
        var byID: [UUID: ChatMessageRecord] = [:]
        for message in existing { byID[message.id] = message }
        for message in incoming { byID[message.id] = message }
        return byID.values.sorted {
            if $0.createdAt == $1.createdAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.createdAt < $1.createdAt
        }
    }

    public static func snapshotContainsSecret(_ snapshot: PairSnapshot, secret: String) -> Bool {
        let data = try? encoder.encode(snapshot)
        let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return text.contains(secret)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private static func readJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw JoyflowStoreError.notFound(url.lastPathComponent)
        }
        return try decoder.decode(type, from: Data(contentsOf: url))
    }
}
