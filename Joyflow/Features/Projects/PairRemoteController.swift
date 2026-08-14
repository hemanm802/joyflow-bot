import Foundation
import JoyflowKit

/// Thread-safe inbox the pair listener writes into and the UI loop drains.
nonisolated final class PairControlBox: @unchecked Sendable {
    private let lock = NSLock()
    private var inbox: [PairChatRequest] = []
    private var allowID: String?
    private var denyRequested = false
    private var stopRequested = false
    private var status = PairControlStatus()

    func enqueue(_ request: PairChatRequest) {
        lock.withLock { inbox.append(request) }
    }

    func requestAllow(_ id: String) {
        lock.withLock { allowID = id }
    }

    func requestDeny() {
        lock.withLock { denyRequested = true }
    }

    func requestStop() {
        lock.withLock { stopRequested = true }
    }

    func publish(_ status: PairControlStatus) {
        lock.withLock { self.status = status }
    }

    func snapshot() -> PairControlStatus {
        lock.withLock { status }
    }

    func drain() -> (chats: [PairChatRequest], allow: String?, deny: Bool, stop: Bool) {
        lock.withLock {
            let chats = inbox
            inbox = []
            let allow = allowID
            allowID = nil
            let deny = denyRequested
            denyRequested = false
            let stop = stopRequested
            stopRequested = false
            return (chats, allow, deny, stop)
        }
    }
}

@MainActor
final class PairRemoteController {
    private let box: PairControlBox
    private var pump: Task<Void, Never>?

    init(box: PairControlBox) {
        self.box = box
    }

    func start(app: AppModel, runtime: ChatRuntime) {
        pump?.cancel()
        pump = Task { [box] in
            var lastJobID: UUID?
            var wasStreaming = false
            var lastStatus = PairControlStatus()
            var lastStatusAt = Date.distantPast
            app.publishMailboxSnapshot()
            while !Task.isCancelled {
                let status = runtime.controlStatus()
                box.publish(status)
                if let offer = PairSession.currentOffer(in: app.store) {
                    await Self.ingestMailboxJob(
                        offer: offer,
                        lastJobID: &lastJobID,
                        box: box,
                        store: app.store
                    )
                    let now = Date()
                    let finished = wasStreaming && !status.streaming
                    let important =
                        finished
                        || status.approval != lastStatus.approval
                        || status.error != lastStatus.error
                    if important || (status.streaming && now.timeIntervalSince(lastStatusAt) >= 1) {
                        lastStatus = status
                        lastStatusAt = now
                        let token = offer.token
                        Task.detached {
                            try? await PairMailbox.publishStatus(status, token: token)
                        }
                    }
                    if finished {
                        app.publishMailboxSnapshot()
                    }
                }
                let work = box.drain()
                if work.stop {
                    runtime.stop(app: app)
                }
                if work.deny {
                    await runtime.deny(app: app)
                }
                if let id = work.allow, runtime.pendingApproval?.id == id || runtime.pendingApproval != nil {
                    await runtime.allow(app: app)
                }
                for request in work.chats {
                    await runtime.ingestRemote(request, app: app)
                }
                wasStreaming = runtime.isStreaming
                try? await Task.sleep(for: .milliseconds(800))
            }
        }
    }

    private static func ingestMailboxJob(
        offer: PairOffer,
        lastJobID: inout UUID?,
        box: PairControlBox,
        store: FileProjectStore
    ) async {
        guard let job = try? await PairMailbox.latestJob(token: offer.token), job.id != lastJobID else {
            return
        }
        lastJobID = job.id
        switch job.action {
        case .chat:
            guard let request = job.request else { return }
            let existing =
                (try? store.messages(projectID: request.projectID, threadID: request.threadID)) ?? []
            if existing.contains(where: { $0.id == request.message.id }) { return }
            if let snapshot = try? await PairMailbox.latestSnapshot(token: offer.token) {
                try? PairSession.apply(snapshot, to: store)
            }
            box.enqueue(request)
        case .allow:
            box.requestAllow(job.approvalID ?? "")
        case .deny:
            box.requestDeny()
        case .stop:
            box.requestStop()
        }
    }

    func stop() {
        pump?.cancel()
        pump = nil
    }
}
