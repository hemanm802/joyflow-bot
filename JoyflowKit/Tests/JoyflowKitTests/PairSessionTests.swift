import Foundation
import Testing

@testable import JoyflowKit

struct PairSessionTests {
    private func tempStore() throws -> (FileProjectStore, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("joyflow-pair-\(UUID().uuidString)")
        return (try FileProjectStore(rootURL: url), url)
    }

    @Test func pairThenReadSameProjectAndMessages() async throws {
        let (host, hostRoot) = try tempStore()
        let (guest, guestRoot) = try tempStore()
        let (stranger, strangerRoot) = try tempStore()
        defer {
            try? FileManager.default.removeItem(at: hostRoot)
            try? FileManager.default.removeItem(at: guestRoot)
            try? FileManager.default.removeItem(at: strangerRoot)
        }

        let secret = "sk-live-SHOULD-NOT-TRAVEL-\(UUID().uuidString)"
        try Data(secret.utf8).write(to: host.rootURL.appendingPathComponent("settings.json"))
        try Data("{\"gmail\":\"\(secret)\"}".utf8).write(
            to: host.rootURL.appendingPathComponent("composio-accounts.json")
        )

        let project = try host.createProject(name: "Shared Desk")
        let thread = UUID()
        let first = ChatMessageRecord(role: "user", content: "hello from host")
        try host.appendMessage(projectID: project.id, threadID: thread, message: first)

        let envelope = try PairSession.offer(from: host)
        #expect(envelope.offer.code.count == 6)
        #expect(envelope.offer.token.count >= 32)
        #expect(envelope.rootPath == host.rootURL.path)

        let parsed = PairSession.parse(envelope.url)
        #expect(parsed?.offer.code == envelope.offer.code)
        #expect(parsed?.offer.token == envelope.offer.token)
        #expect(parsed?.rootPath == envelope.rootPath)

        let binding = try PairSession.acceptFilesystem(envelope, into: guest)
        #expect(binding.peerRootPath == host.rootURL.path)
        #expect(PairSession.binding(in: guest)?.token == envelope.offer.token)

        let listed = try guest.listProjects()
        #expect(listed.contains { $0.id == project.id && $0.name == "Shared Desk" })
        let messages = try guest.messages(projectID: project.id, threadID: thread)
        #expect(messages.contains { $0.id == first.id && $0.content == "hello from host" })

        #expect(try stranger.listProjects().isEmpty)
        #expect(PairSession.binding(in: stranger) == nil)

        let snapshot = try PairSession.snapshot(from: host)
        #expect(!PairSession.snapshotContainsSecret(snapshot, secret: secret))
        #expect(!PairSession.excludedRootFiles.isEmpty)
        let guestSoul = try guest.readSoul(projectID: project.id)
        #expect(!guestSoul.contains(secret))
        let guestJSON = try String(
            contentsOf: guest.layout(for: project.id).projectJSON,
            encoding: .utf8
        )
        #expect(!guestJSON.contains(secret))
        #expect(!FileManager.default.fileExists(atPath: guest.rootURL.appendingPathComponent("settings.json").path))

        let reply = ChatMessageRecord(role: "assistant", content: "ack from guest")
        try guest.appendMessage(projectID: project.id, threadID: thread, message: reply)
        try await PairSession.push(from: guest)
        let hostMessages = try host.messages(projectID: project.id, threadID: thread)
        #expect(hostMessages.contains { $0.id == first.id && $0.content == "hello from host" })
        #expect(hostMessages.contains { $0.id == reply.id && $0.content == "ack from guest" })

        let later = ChatMessageRecord(role: "user", content: "host again")
        try host.appendMessage(projectID: project.id, threadID: thread, message: later)
        try await PairSession.pull(into: guest)
        let guestAgain = try guest.messages(projectID: project.id, threadID: thread)
        #expect(guestAgain.contains { $0.id == later.id && $0.content == "host again" })
        #expect(guestAgain.contains { $0.id == reply.id })
    }

    @Test func wrongTokenDoesNotImport() throws {
        let (host, hostRoot) = try tempStore()
        let (guest, guestRoot) = try tempStore()
        defer {
            try? FileManager.default.removeItem(at: hostRoot)
            try? FileManager.default.removeItem(at: guestRoot)
        }
        _ = try host.createProject(name: "Locked")
        var envelope = try PairSession.offer(from: host)
        envelope.offer.token = "forged-token"
        #expect(throws: JoyflowStoreError.self) {
            try PairSession.acceptFilesystem(envelope, into: guest)
        }
        #expect(try guest.listProjects().isEmpty)
    }

    @Test func unpairedPullFailsClosed() async throws {
        let (store, root) = try tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: JoyflowStoreError.self) {
            try await PairSession.pull(into: store)
        }
    }

    @Test func pairSealRoundTrips() throws {
        let token = PairSession.makeToken()
        let payload = Data("hello pair".utf8)
        let wrapped = try PairSeal.wrap(payload, token: token)
        #expect(wrapped != payload)
        #expect(try PairSeal.unwrap(wrapped, token: token) == payload)
        var failed = false
        do {
            _ = try PairSeal.unwrap(wrapped, token: "wrong-token-wrong-token-wrong-token")
        } catch {
            failed = true
        }
        #expect(failed)
    }

    @Test func pairURLWorksWithTokenOnly() {
        let envelope = PairEnvelope(
            offer: PairOffer(code: "AB23CD", token: "tokentokentoken"),
            rootPath: ""
        )
        let parsed = PairSession.parse(envelope.url)
        #expect(parsed?.offer.code == "AB23CD")
        #expect(parsed?.offer.token == "tokentokentoken")
        #expect(PairClient.displayMessage(status: 0, body: "App Transport Security policy requires the use of a secure connection.").contains("secure mailbox"))
    }

    @Test func pairClientHidesCloudflareHtml() {
        let html = "<!doctype html><title>Cloudflare Tunnel error | demo.trycloudflare.com</title>1033"
        let message = PairClient.displayMessage(status: 530, body: html)
        #expect(!message.contains("<html"))
        #expect(!message.contains("1033"))
        #expect(message.contains("Mac"))
    }

    @Test func pairLANSplitsAndPrefersOutbound() {
        #expect(PairLAN.hosts(from: "10.1.64.61,192.168.192.96") == ["10.1.64.61", "192.168.192.96"])
        #expect(PairLAN.isPairable(ip: "10.1.64.61", interface: "en14"))
        #expect(!PairLAN.isPairable(ip: "169.254.1.1", interface: "en0"))
        #expect(!PairLAN.isPairable(ip: "10.0.0.2", interface: "utun0"))
        let ips = PairLAN.advertisedIPv4s()
        #expect(!ips.isEmpty)
        if let outbound = PairLAN.outboundIPv4() {
            #expect(ips.first == outbound)
        }
    }

    @Test func pairURLIncludesPublicOrigin() {
        let envelope = PairEnvelope(
            offer: PairOffer(code: "AB23CD", token: "tokentokentoken"),
            rootPath: "",
            host: "192.168.1.20",
            port: 8742,
            origin: "https://demo.trycloudflare.com"
        )
        let parsed = PairSession.parse(envelope.url)
        #expect(parsed?.origin == "https://demo.trycloudflare.com")
        #expect(parsed?.targetOrigin?.host == "demo.trycloudflare.com")
        #expect(PairTunnel.parseOrigin(from: Data("ok https://abc-123.trycloudflare.com ready".utf8))?.host == "abc-123.trycloudflare.com")
    }

    @Test func parsePastedFindsLinkInNoise() {
        let envelope = PairEnvelope(
            offer: PairOffer(code: "AB23CD", token: "tokentokentoken"),
            rootPath: "",
            host: "192.168.1.20",
            port: 8742
        )
        let pasted = "Pair this:\n\(envelope.url.absoluteString)\nThanks"
        let parsed = PairSession.parsePasted(pasted)
        #expect(parsed?.offer.code == "AB23CD")
        #expect(parsed?.host == "192.168.1.20")
        #expect(parsed?.port == 8742)
        #expect(PairSession.parseCode("ab23cd") == "AB23CD")
    }

    @Test func networkPairCopiesProjects() async throws {
        let (host, hostRoot) = try tempStore()
        let (guest, guestRoot) = try tempStore()
        defer {
            try? FileManager.default.removeItem(at: hostRoot)
            try? FileManager.default.removeItem(at: guestRoot)
        }
        let project = try host.createProject(name: "Lan Desk")
        let thread = UUID()
        let first = ChatMessageRecord(role: "user", content: "hello over wifi")
        try host.appendMessage(projectID: project.id, threadID: thread, message: first)

        let offer = try PairSession.offer(from: host)
        let server = try PairServer(
            offer: offer.offer,
            preferredPort: 18742,
            snapshot: { try PairSession.snapshot(from: host) },
            apply: { try PairSession.apply($0, to: host) }
        )
        defer { server.stop() }

        var envelope = offer
        envelope.host = "127.0.0.1"
        envelope.port = Int(server.port)
        let binding = try await PairSession.accept(envelope, into: guest)
        #expect(binding.peerHost == "127.0.0.1")
        #expect(try guest.listProjects().contains { $0.id == project.id && $0.name == "Lan Desk" })
        let messages = try guest.messages(projectID: project.id, threadID: thread)
        #expect(messages.contains { $0.id == first.id && $0.content == "hello over wifi" })

        let reply = ChatMessageRecord(role: "assistant", content: "ack over wifi")
        try guest.appendMessage(projectID: project.id, threadID: thread, message: reply)
        try await PairSession.push(from: guest)
        let hostMessages = try host.messages(projectID: project.id, threadID: thread)
        #expect(hostMessages.contains { $0.id == reply.id })
    }

    @Test func pairChatRequestDecodesLegacyPayload() throws {
        let message = ChatMessageRecord(role: "user", content: "hello mac")
        let payload = """
            {"projectID":"\(message.id)","threadID":"\(message.id)","message":{"id":"\(message.id)","role":"user","content":"hello mac","createdAt":"2026-01-02T03:04:05Z"}}
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PairChatRequest.self, from: Data(payload.utf8))
        #expect(decoded.projectName.isEmpty)
        #expect(decoded.message.content == "hello mac")
        let named = PairChatRequest(
            projectID: decoded.projectID,
            threadID: decoded.threadID,
            message: message,
            projectName: "Desk"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let again = try decoder.decode(PairChatRequest.self, from: try encoder.encode(named))
        #expect(again.projectName == "Desk")
    }

    @Test func mailboxJobDecodesLegacyChatAndControlActions() throws {
        let message = ChatMessageRecord(role: "user", content: "run this")
        let request = PairChatRequest(
            projectID: UUID(),
            threadID: UUID(),
            message: message,
            projectName: "Phone"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let legacy = """
            {"id":"\(UUID())","request":\(String(data: try encoder.encode(request), encoding: .utf8)!)}
            """
        let chat = try decoder.decode(PairMailbox.Job.self, from: Data(legacy.utf8))
        #expect(chat.action == .chat)
        #expect(chat.request?.projectName == "Phone")

        let stop = try decoder.decode(
            PairMailbox.Job.self,
            from: try encoder.encode(PairMailbox.Job.stop())
        )
        #expect(stop.action == .stop)
        #expect(stop.request == nil)

        let allow = try decoder.decode(
            PairMailbox.Job.self,
            from: try encoder.encode(PairMailbox.Job.allow("tool-1"))
        )
        #expect(allow.action == .allow)
        #expect(allow.approvalID == "tool-1")
    }

    @Test func mergeMessagesUnionsByID() {
        let first = ChatMessageRecord(role: "user", content: "a")
        let second = ChatMessageRecord(role: "assistant", content: "b")
        let merged = PairSession.mergeMessages([first], [first, second])
        #expect(merged.count == 2)
        #expect(Set(merged.map(\.id)) == [first.id, second.id])
    }

    @Test func mobileChromeHexesMatchShippedTokens() {
        #expect(ColorTokens.background.dark == 0x0A0A0A)
        #expect(ColorTokens.background.light == 0xF5F5F7)
        #expect(ColorTokens.surface.dark == 0x141414)
        #expect(ColorTokens.surface.light == 0xF0F0F2)
        #expect(ColorTokens.card.light == 0xFFFFFF)
        #expect(ColorTokens.card.dark == 0x1C1C1E)
        #expect(ColorTokens.link.light == 0x5D9DF7)
        #expect(ColorTokens.link.dark == 0x5D9DF7)
        #expect(ColorTokens.pop.dark == ColorTokens.link.dark)
        let used = [
            ColorTokens.background, ColorTokens.surface, ColorTokens.card, ColorTokens.raised,
            ColorTokens.selection, ColorTokens.textPrimary, ColorTokens.textSecondary,
            ColorTokens.accent, ColorTokens.controlMuted, ColorTokens.borderSubtle,
        ].flatMap { [$0.light, $0.dark] }
        for banned in ColorTokens.bannedTanHexes {
            #expect(!used.contains(banned))
        }
    }
}
