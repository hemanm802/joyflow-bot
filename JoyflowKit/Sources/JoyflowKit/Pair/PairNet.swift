import Darwin
import Foundation
import Network

public enum PairLAN {
    public static let preferredPort: UInt16 = 8742
    public static let serviceType = "_joyflow._tcp."
    public static let serviceName = "Joyflow"

    public struct Endpoint: Equatable, Sendable, Hashable {
        public var host: String
        public var port: Int

        public init(host: String, port: Int) {
            self.host = host
            self.port = port
        }
    }

    public static func advertisedIPv4() -> String? {
        advertisedIPv4s().first
    }

    /// Outbound address first (the network the Mac actually uses), then every other LAN IPv4.
    public static func advertisedIPv4s() -> [String] {
        var result: [String] = []
        if let outbound = outboundIPv4() {
            result.append(outbound)
        }
        for ip in interfaceIPv4s() where !result.contains(ip) {
            result.append(ip)
        }
        return result
    }

    public static func outboundIPv4() -> String? {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(53).bigEndian
        addr.sin_addr.s_addr = inet_addr("1.1.1.1")
        let connected = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
            }
        }
        guard connected == 0 else { return nil }
        var local = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.stride)
        let named = withUnsafeMutablePointer(to: &local) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard named == 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &local.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
            return nil
        }
        let ip = String(cString: buffer)
        guard !ip.hasPrefix("127.") else { return nil }
        return ip
    }

    public static func interfaceIPv4s() -> [String] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return [] }
        defer { freeifaddrs(ifaddr) }
        var found: [String] = []
        var ptr = ifaddr
        while let iface = ptr {
            defer { ptr = iface.pointee.ifa_next }
            let flags = Int32(iface.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            guard let addr = iface.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let ip = String(cString: hostname)
            let name = String(cString: iface.pointee.ifa_name)
            guard Self.isPairable(ip: ip, interface: name) else { continue }
            if !found.contains(ip) { found.append(ip) }
        }
        return found
    }

    public static func isPairable(ip: String, interface: String) -> Bool {
        if ip.hasPrefix("127.") || ip.hasPrefix("169.254.") { return false }
        if interface.hasPrefix("utun") || interface.hasPrefix("awdl") || interface.hasPrefix("llw") {
            return false
        }
        if interface.hasPrefix("anpi") || interface.hasPrefix("ap") || interface.hasPrefix("bridge") {
            return false
        }
        return interface.hasPrefix("en")
    }

    public static func hosts(from value: String?) -> [String] {
        (value ?? "")
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map { String($0) }
            .filter { !$0.isEmpty }
    }
}

public struct PairFetch: Sendable {
    public var snapshot: PairSnapshot
    public var token: String?

    public init(snapshot: PairSnapshot, token: String? = nil) {
        self.snapshot = snapshot
        self.token = token
    }
}

public enum PairClient {
    public static func snapshot(host: String, port: Int, code: String, token: String?) async throws -> PairSnapshot {
        try await fetch(host: host, port: port, code: code, token: token).snapshot
    }

    public static func snapshot(_ target: PairTarget) async throws -> PairSnapshot {
        try await fetch(target).snapshot
    }

    public static func ping(_ target: PairTarget) async throws {
        var request = URLRequest(url: target.origin.appending(path: "v1/health"))
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        let (data, response) = try await session.data(for: request)
        try throwIfNeeded(data: data, response: response)
    }

    public static func firstReachable(_ targets: [PairTarget]) async throws -> PairTarget {
        guard !targets.isEmpty else {
            throw JoyflowStoreError.io(reachError)
        }
        return try await withThrowingTaskGroup(of: PairTarget.self) { group in
            for target in targets {
                group.addTask {
                    try await ping(target)
                    return target
                }
            }
            var lastError: any Error = JoyflowStoreError.io(reachError)
            while let result = await group.nextResult() {
                switch result {
                case .success(let target):
                    group.cancelAll()
                    return target
                case .failure(let error):
                    lastError = error
                }
            }
            throw lastError
        }
    }

    public static func fetch(host: String, port: Int, code: String, token: String?) async throws -> PairFetch {
        guard let origin = URL(string: "http://\(host):\(port)") else {
            throw JoyflowStoreError.io("That pair address is not valid.")
        }
        return try await fetch(PairTarget(origin: origin, code: code, token: token ?? ""))
    }

    public static func fetch(_ target: PairTarget) async throws -> PairFetch {
        var request = authorized(target, path: "/v1/snapshot")
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        try throwIfNeeded(data: data, response: response)
        let http = response as? HTTPURLResponse
        return PairFetch(
            snapshot: try PairSession.decodeSnapshot(data),
            token: http?.value(forHTTPHeaderField: "X-Joyflow-Token")
        )
    }

    public static func push(
        _ snapshot: PairSnapshot,
        host: String,
        port: Int,
        code: String,
        token: String?
    ) async throws {
        guard let origin = URL(string: "http://\(host):\(port)") else {
            throw JoyflowStoreError.io("That pair address is not valid.")
        }
        try await push(snapshot, to: PairTarget(origin: origin, code: code, token: token ?? ""))
    }

    public static func push(_ snapshot: PairSnapshot, to target: PairTarget) async throws {
        var request = authorized(target, path: "/v1/snapshot")
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try PairSession.encodeSnapshot(snapshot)
        let (data, response) = try await session.data(for: request)
        try throwIfNeeded(data: data, response: response)
    }

    public static func sendChat(_ requestBody: PairChatRequest, to target: PairTarget) async throws {
        var request = authorized(target, path: "/v1/control/chat")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(requestBody)
        let (data, response) = try await session.data(for: request)
        try throwIfNeeded(data: data, response: response)
    }

    public static func status(from target: PairTarget) async throws -> PairControlStatus {
        var request = authorized(target, path: "/v1/control/status")
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        try throwIfNeeded(data: data, response: response)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PairControlStatus.self, from: data)
    }

    public static func allow(id: String, on target: PairTarget) async throws {
        try await postControl(path: "/v1/control/allow", body: ["id": id], to: target)
    }

    public static func deny(on target: PairTarget) async throws {
        try await postControl(path: "/v1/control/deny", body: [:], to: target)
    }

    public static func stop(on target: PairTarget) async throws {
        try await postControl(path: "/v1/control/stop", body: [:], to: target)
    }

    private static func postControl(path: String, body: [String: String], to target: PairTarget) async throws {
        var request = authorized(target, path: path)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try throwIfNeeded(data: data, response: response)
    }

    private static func authorized(_ target: PairTarget, path: String) -> URLRequest {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let url = target.origin.appending(path: trimmed)
        var request = URLRequest(url: url)
        request.timeoutInterval = 16
        request.setValue(target.code, forHTTPHeaderField: "X-Joyflow-Code")
        if !target.token.isEmpty {
            request.setValue(target.token, forHTTPHeaderField: "X-Joyflow-Token")
        }
        return request
    }

    private static func throwIfNeeded(data: Data, response: URLResponse) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200...299).contains(status) { return }
        let body = String(data: data, encoding: .utf8) ?? ""
        if status == 401 || status == 403 {
            throw JoyflowStoreError.io(
                "That code does not match the desktop. Tap New code on the Mac and try again."
            )
        }
        throw JoyflowStoreError.io(displayMessage(status: status, body: body))
    }

    public static func displayMessage(for error: any Error) -> String {
        displayMessage(status: 0, body: error.localizedDescription)
    }

    public static func displayMessage(status: Int, body: String) -> String {
        let lowered = body.lowercased()
        if lowered.contains("app transport security") {
            return
                "iPhone blocked a local http address. Keep Joyflow open on the Mac and paste the link again — pairing now uses a secure mailbox and does not need the same Wi-Fi."
        }
        if body.contains("<!doctype") || body.contains("<html") || body.contains("Cloudflare Tunnel")
            || lowered.contains("trycloudflare") || body.contains("1033") || status == 530
            || status == 502 || status == 503 || status == 504
        {
            return reachError
        }
        if status == 0 || lowered.contains("could not connect") || lowered.contains("timed out") {
            return reachError
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.count > 180 { return reachError }
        return trimmed
    }

    public static let reachError =
        "Couldn't reach the Mac. Open Joyflow on the desktop, wait until Pair iPhone says Ready anywhere, then paste the new link."

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()
}

public final class PairServer: @unchecked Sendable {
    public private(set) var port: UInt16 = 0
    private let queue = DispatchQueue(label: "dev.joyflow.pair.server")
    private let lock = NSLock()
    private var offer: PairOffer
    private var listener: NWListener?
    private var service: NetService?
    private var keepalive = ServiceKeepalive()
    private let snapshot: @Sendable () throws -> PairSnapshot
    private let apply: @Sendable (PairSnapshot) throws -> Void
    private let status: @Sendable () -> PairControlStatus
    private let enqueueChat: @Sendable (PairChatRequest) throws -> Void
    private let allowRemote: @Sendable (String) throws -> Void
    private let denyRemote: @Sendable () throws -> Void
    private let stopRemote: @Sendable () throws -> Void

    public init(
        offer: PairOffer,
        preferredPort: UInt16 = PairLAN.preferredPort,
        snapshot: @escaping @Sendable () throws -> PairSnapshot,
        apply: @escaping @Sendable (PairSnapshot) throws -> Void,
        status: @escaping @Sendable () -> PairControlStatus = { PairControlStatus() },
        enqueueChat: @escaping @Sendable (PairChatRequest) throws -> Void = { _ in },
        allowRemote: @escaping @Sendable (String) throws -> Void = { _ in },
        denyRemote: @escaping @Sendable () throws -> Void = {},
        stopRemote: @escaping @Sendable () throws -> Void = {}
    ) throws {
        self.offer = offer
        self.snapshot = snapshot
        self.apply = apply
        self.status = status
        self.enqueueChat = enqueueChat
        self.allowRemote = allowRemote
        self.denyRemote = denyRemote
        self.stopRemote = stopRemote
        var lastError: any Error = JoyflowStoreError.io("Could not start the pair listener.")
        var chosen: UInt16 = preferredPort
        var started: NWListener?
        for candidate in preferredPort..<(preferredPort + 12) {
            do {
                let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: candidate)!)
                listener.newConnectionHandler = { [weak self] connection in
                    self?.serve(connection)
                }
                try Self.start(listener, queue: queue)
                started = listener
                chosen = candidate
                break
            } catch {
                lastError = error
            }
        }
        guard let listener = started else { throw lastError }
        self.listener = listener
        self.port = chosen
        publish(port: chosen)
    }

    public func updateOffer(_ offer: PairOffer) {
        lock.withLock { self.offer = offer }
    }

    public func currentOffer() -> PairOffer {
        lock.withLock { offer }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        service?.stop()
        service = nil
    }

    deinit { stop() }

    private func publish(port: UInt16) {
        let service = NetService(
            domain: "local.",
            type: PairLAN.serviceType,
            name: PairLAN.serviceName,
            port: Int32(port)
        )
        service.delegate = keepalive
        service.publish()
        self.service = service
    }

    private static func start(_ listener: NWListener, queue: DispatchQueue) throws {
        let box = ReadyBox()
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                box.complete(nil)
            case .failed(let error):
                box.complete(error)
            default:
                break
            }
        }
        listener.start(queue: queue)
        if let error = box.wait(timeout: 2) {
            listener.cancel()
            throw error
        }
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if error != nil {
                connection.cancel()
                return
            }
            var next = buffer
            if let data { next.append(data) }
            if let request = HTTPRequest.parse(next) {
                self.respond(request, on: connection)
                return
            }
            if isComplete || next.count > 8 * 1024 * 1024 {
                connection.cancel()
                return
            }
            self.receive(on: connection, buffer: next)
        }
    }

    private func respond(_ request: HTTPRequest, on connection: NWConnection) {
        let response: HTTPResponse
        do {
            response = try handle(request)
        } catch let error as JoyflowStoreError {
            let message = error.errorDescription ?? "Pair failed."
            let code = message.contains("does not match") ? 401 : 400
            response = HTTPResponse.text(code, message)
        } catch {
            response = HTTPResponse.text(500, error.localizedDescription)
        }
        connection.send(
            content: response.data,
            completion: .contentProcessed { _ in
                connection.cancel()
            }
        )
    }

    private func handle(_ request: HTTPRequest) throws -> HTTPResponse {
        if request.path == "/v1/health" || request.path == "/" {
            return HTTPResponse.json(200, Data(#"{"ok":true}"#.utf8))
        }
        try authorize(request)
        if request.path.hasPrefix("/v1/snapshot") {
            switch request.method {
            case "GET":
                let payload = try snapshot()
                return HTTPResponse(
                    status: 200,
                    headers: ["X-Joyflow-Token": currentOffer().token],
                    body: try PairSession.encodeSnapshot(payload)
                )
            case "POST":
                try apply(try PairSession.decodeSnapshot(request.body))
                return HTTPResponse.json(200, Data(#"{"ok":true}"#.utf8))
            default:
                return HTTPResponse.text(405, "Use GET or POST.")
            }
        }
        if request.path == "/v1/control/status", request.method == "GET" {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            return HTTPResponse.json(200, try encoder.encode(status()))
        }
        if request.path == "/v1/control/chat", request.method == "POST" {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            try enqueueChat(try decoder.decode(PairChatRequest.self, from: request.body))
            return HTTPResponse.json(200, Data(#"{"ok":true}"#.utf8))
        }
        if request.path == "/v1/control/allow", request.method == "POST" {
            let id = ((try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any])?["id"] as? String
            try allowRemote(id ?? "")
            return HTTPResponse.json(200, Data(#"{"ok":true}"#.utf8))
        }
        if request.path == "/v1/control/deny", request.method == "POST" {
            try denyRemote()
            return HTTPResponse.json(200, Data(#"{"ok":true}"#.utf8))
        }
        if request.path == "/v1/control/stop", request.method == "POST" {
            try stopRemote()
            return HTTPResponse.json(200, Data(#"{"ok":true}"#.utf8))
        }
        return HTTPResponse.text(404, "Not found.")
    }

    private func authorize(_ request: HTTPRequest) throws {
        let current = currentOffer()
        let code = request.header("X-Joyflow-Code") ?? request.query("code") ?? ""
        let token = request.header("X-Joyflow-Token") ?? request.query("token") ?? ""
        let codeOK = PairCrypto.equal(code.uppercased(), current.code.uppercased())
        guard codeOK else {
            throw JoyflowStoreError.io(
                "That code does not match the desktop. Tap New code on the Mac and try again."
            )
        }
        if !token.isEmpty {
            guard PairCrypto.equal(token, current.token) else {
                throw JoyflowStoreError.io(
                    "That code does not match the desktop. Tap New code on the Mac and try again."
                )
            }
        }
    }
}

public enum PairBrowser {
    public static func findHosts(timeout: TimeInterval = 2.4) async -> [PairLAN.Endpoint] {
        await withCheckedContinuation { continuation in
            let runner = BrowserRunner()
            runner.start(timeout: timeout) { endpoints in
                continuation.resume(returning: endpoints)
            }
        }
    }
}

enum PairCrypto {
    static func equal(_ left: String, _ right: String) -> Bool {
        let a = Array(left.utf8)
        let b = Array(right.utf8)
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for index in a.indices {
            diff |= a[index] ^ b[index]
        }
        return diff == 0
    }
}

private final class ServiceKeepalive: NSObject, NetServiceDelegate {}

private final class ReadyBox: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var error: (any Error)?
    private var done = false

    func complete(_ error: (any Error)?) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        self.error = error
        semaphore.signal()
    }

    func wait(timeout: TimeInterval) -> (any Error)? {
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            return JoyflowStoreError.io("The pair listener did not start.")
        }
        lock.lock()
        defer { lock.unlock() }
        return error
    }
}

private struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data
    var queryItems: [URLQueryItem]

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    func query(_ name: String) -> String? {
        queryItems.first(where: { $0.name == name })?.value
    }

    static func parse(_ data: Data) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = data.subdata(in: data.startIndex..<headerEnd.lowerBound)
        guard let text = String(data: head, encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        guard data.count >= bodyStart + length else { return nil }
        let target = String(parts[1])
        let pieces = URLComponents(string: target)
        return HTTPRequest(
            method: String(parts[0]).uppercased(),
            path: pieces?.path ?? target,
            headers: headers,
            body: data.subdata(in: bodyStart..<(bodyStart + length)),
            queryItems: pieces?.queryItems ?? []
        )
    }
}

private struct HTTPResponse {
    var status: Int
    var headers: [String: String]
    var body: Data

    var data: Data {
        var text = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "ERROR")\r\n"
        var merged = headers
        if merged["Content-Type"] == nil {
            merged["Content-Type"] = "text/plain; charset=utf-8"
        }
        merged["Content-Length"] = String(body.count)
        merged["Connection"] = "close"
        for (key, value) in merged.sorted(by: { $0.key < $1.key }) {
            text += "\(key): \(value)\r\n"
        }
        text += "\r\n"
        var payload = Data(text.utf8)
        payload.append(body)
        return payload
    }

    static func text(_ status: Int, _ message: String) -> HTTPResponse {
        HTTPResponse(status: status, headers: [:], body: Data(message.utf8))
    }

    static func json(_ status: Int, _ body: Data) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "application/json"], body: body)
    }
}

private final class BrowserRunner: NSObject, NetServiceBrowserDelegate, NetServiceDelegate, @unchecked Sendable {
    private var browser: NetServiceBrowser?
    private var services: [NetService] = []
    private var endpoints: Set<PairLAN.Endpoint> = []
    private var finish: (([PairLAN.Endpoint]) -> Void)?
    private var finished = false

    func start(timeout: TimeInterval, finish: @escaping ([PairLAN.Endpoint]) -> Void) {
        self.finish = finish
        Self.retain(self)
        DispatchQueue.main.async { [self] in
            let browser = NetServiceBrowser()
            browser.delegate = self
            self.browser = browser
            browser.searchForServices(ofType: PairLAN.serviceType, inDomain: "local.")
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [self] in
                self.complete()
            }
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        service.resolve(withTimeout: 1.6)
        services.append(service)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        if sender.port > 0 {
            for host in ipv4s(from: sender) {
                endpoints.insert(PairLAN.Endpoint(host: host, port: sender.port))
            }
            if let host = sender.hostName, endpoints.isEmpty {
                endpoints.insert(PairLAN.Endpoint(host: host, port: sender.port))
            }
        }
    }

    private func ipv4s(from service: NetService) -> [String] {
        guard let addresses = service.addresses else { return [] }
        var result: [String] = []
        for address in addresses {
            address.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                let sock = base.assumingMemoryBound(to: sockaddr.self)
                guard sock.pointee.sa_family == UInt8(AF_INET) else { return }
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let ok = getnameinfo(
                    sock,
                    socklen_t(sock.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                if ok == 0 {
                    let ip = String(cString: hostname)
                    if !ip.hasPrefix("127.") { result.append(ip) }
                }
            }
        }
        return result
    }

    private func complete() {
        guard !finished else { return }
        finished = true
        browser?.stop()
        finish?(Array(endpoints))
        finish = nil
        Self.release(self)
    }

    private static let retainLock = NSLock()
    nonisolated(unsafe) private static var live: [BrowserRunner] = []

    private static func retain(_ runner: BrowserRunner) {
        retainLock.withLock { live.append(runner) }
    }

    private static func release(_ runner: BrowserRunner) {
        retainLock.withLock { live.removeAll { $0 === runner } }
    }
}
