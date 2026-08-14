import AppKit
import JoyflowKit
import Foundation
import Observation
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Follow System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
    case models, review, computer, connectors, voice
    var id: String { rawValue }
    var title: String {
        switch self {
        case .models: "General"
        case .review: "Permissions"
        case .computer: "Computer"
        case .connectors: "Connectors"
        case .voice: "Voice"
        }
    }

    var systemImage: String {
        switch self {
        case .models: "gearshape"
        case .review: "checkmark.shield"
        case .computer: "desktopcomputer"
        case .connectors: "link"
        case .voice: "mic"
        }
    }
}

struct PersistedSettings: Codable, Sendable {
    var appearance: String
    var defaultReview: String
    var computer: String
    var activeEndpointID: UUID?
    var sidebarCollapsed: Bool?
    var sidebarWidth: Double?
    var speechEngine: String?
    var speechModel: String?
    var speechBaseURL: String?
    var localWhisperID: String?
    var projectDestinationPath: String?
    var projectDestinationBookmark: Data?
}

@Observable
@MainActor
final class AppModel {
    var appearance: AppAppearance = .system
    var selectedProjectID: UUID?
    var selectedThreadID: UUID?
    var inspectorVisible = false
    var sidebarWidth: CGFloat = Theme.sidebarWidth
    var sidebarDragging = false
    var railPeekID: UUID?
    var railPeekY: CGFloat = 0
    var railSessionsID: UUID?
    private var railPeekDismiss: Task<Void, Never>?
    private var railPeekFrozenID: UUID?

    func holdRailPeek(_ id: UUID, y: CGFloat? = nil) {
        if let y { railPeekY = y }
        guard railSessionsID == nil else { return }
        if railPeekFrozenID == id { return }
        railPeekFrozenID = nil
        railPeekDismiss?.cancel()
        railPeekID = id
    }

    func releaseRailPeek(_ id: UUID) {
        railPeekDismiss?.cancel()
        railPeekDismiss = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            if railPeekID == id, railSessionsID == nil {
                railPeekID = nil
            }
            if railPeekFrozenID == id {
                railPeekFrozenID = nil
            }
        }
    }

    func dismissRailPeek(freezing id: UUID? = nil) {
        railPeekDismiss?.cancel()
        railPeekID = nil
        railPeekFrozenID = id
    }

    func openRailSessions(for id: UUID) {
        railPeekDismiss?.cancel()
        railSessionsID = id
        railPeekID = nil
        railPeekFrozenID = id
    }

    func closeRailSessions() {
        railSessionsID = nil
    }

    var displayedSidebarWidth: CGFloat {
        if sidebarWidth < Theme.sidebarMinExpanded {
            return Theme.sidebarRailWidth
        }
        return min(Theme.sidebarMaxWidth, sidebarWidth)
    }

    var sidebarCollapsed: Bool { displayedSidebarWidth <= Theme.sidebarRailWidth + 1 }
    var createProjectRequested = false
    var composingNewChat = false
    var newProjectDestination: URL?
    var settingsOpenNonce = 0
    var settingsOpen = false
    var settingsPane: SettingsPane = .models
    var pluginsOpen = false
    var aboutOpen = false
    var searchOpen = false
    var searchQuery = ""
    var search = ""
    var commandQuery = ""
    var soulDraft = ""
    var instructionsDraft = ""
    var projects: [ProjectManifest] = []
    var endpoints: [ModelEndpoint] = []
    var activeEndpointID: UUID?
    var defaultReview: ReviewAction = .ask
    var computer: ComputerChoice = .local
    private var rememberedCloud: ComputerChoice = .vercel
    var speechEngine: SpeechEngine = .whisperAPI
    var speechModel: String = SpeechSettings.defaultCloudModel
    var speechBaseURL: String = SpeechSettings.defaultCloudBaseURL
    var localWhisperID: String = LocalWhisperCatalog.tinyEN.id
    var store: FileProjectStore
    var endpointStore: EndpointStore
    var settingsURL: URL
    var keychain = KeychainStore()
    var composioAccounts: [String: String] = [:]
    var pendingComposioToolkit: String?
    var pairOpen = false
    var pairEnvelope: PairEnvelope?
    var pairListenerError: String?
    var pairTunnelOrigin: String?
    var resourceError: String?
    private var pairServer: PairServer?
    private var pairTunnel = PairTunnel()
    let pairControl = PairControlBox()
    private var pairPublishTask: Task<Void, Never>?

    init(rootURL: URL? = nil) {
        let root: URL
        if let rootURL {
            root = rootURL
        } else {
            let parent = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            do {
                root = try JoyflowKit.resolvedApplicationSupport(in: parent)
            } catch {
                root = parent.appendingPathComponent(JoyflowKit.applicationSupportFolder)
            }
        }
        do {
            store = try FileProjectStore(rootURL: root)
        } catch {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            do {
                store = try FileProjectStore(rootURL: root)
            } catch {
                fatalError("Joyflow could not open its store: \(error)")
            }
        }
        endpointStore = EndpointStore(rootURL: root)
        settingsURL = root.appendingPathComponent("settings.json")
        reload()
        if projects.isEmpty {
            _ = try? createProject(name: "Welcome")
        }
        loadSettings()
        loadComposioAccounts()
        startPairListener()
    }

    var composioAccountsURL: URL {
        settingsURL.deletingLastPathComponent().appendingPathComponent("composio-accounts.json")
    }

    func rememberComposioAccount(toolkit: String, id: String) {
        let slug = toolkit.lowercased()
        composioAccounts[slug] = id
        _ = keychain.set(id, for: KeychainStore.composioConnectedAccount(slug))
        persistComposioAccounts()
    }

    func persistComposioAccounts() {
        let data = try? JSONSerialization.data(withJSONObject: composioAccounts, options: [.prettyPrinted, .sortedKeys])
        try? data?.write(to: composioAccountsURL)
    }

    func loadComposioAccounts() {
        if let data = try? Data(contentsOf: composioAccountsURL),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        {
            composioAccounts = object
        }
        for (toolkit, id) in composioAccounts {
            _ = keychain.set(id, for: KeychainStore.composioConnectedAccount(toolkit))
        }
    }

    func handleJoyflowURL(_ url: URL) {
        guard url.scheme == JoyflowKit.urlScheme else { return }
        if url.host == "oauth" {
            Task { await refreshComposioAccounts() }
            return
        }
        if url.host == "pair", let envelope = PairSession.parse(url) {
            do {
                _ = try PairSession.accept(envelope, into: store)
                reload()
            } catch {
                return
            }
        }
    }

    func startPairListener() {
        if pairServer != nil { return }
        let offer = PairSession.currentOffer(in: store) ?? (try? PairSession.offer(from: store).offer)
        guard let offer else { return }
        let store = self.store
        let control = pairControl
        do {
            pairServer = try PairServer(
                offer: offer,
                snapshot: { try PairSession.snapshot(from: store) },
                apply: { try PairSession.apply($0, to: store) },
                status: { control.snapshot() },
                enqueueChat: { control.enqueue($0) },
                allowRemote: { control.requestAllow($0) },
                denyRemote: { control.requestDeny() },
                stopRemote: { control.requestStop() }
            )
            pairListenerError = nil
        } catch {
            pairListenerError = error.localizedDescription
        }
    }

    @discardableResult
    func beginPair() -> PairEnvelope? {
        startPairListener()
        do {
            var envelope = try PairSession.offer(from: store)
            pairServer?.updateOffer(envelope.offer)
            envelope.host = PairLAN.advertisedIPv4s().joined(separator: ",")
            envelope.port = Int(pairServer?.port ?? PairLAN.preferredPort)
            envelope.origin = pairTunnelOrigin
            pairEnvelope = envelope
            pairOpen = true
            startPublicPairLink()
            publishMailboxSnapshot(token: envelope.offer.token)
            return envelope
        } catch {
            pairListenerError = error.localizedDescription
            return nil
        }
    }

    func startPublicPairLink() {
        guard let server = pairServer else { return }
        let offer = server.currentOffer()
        if pairTunnel.isRunning, let origin = pairTunnel.origin {
            applyPublicOrigin(origin, offer: offer)
            return
        }
        guard pairPublishTask == nil else { return }
        pairPublishTask = Task { [weak self] in
            guard let self else { return }
            defer { pairPublishTask = nil }
            do {
                let origin = try await pairTunnel.start(localPort: server.port)
                applyPublicOrigin(origin, offer: server.currentOffer())
            } catch {
                // LAN pair still works if the public tunnel is slow or blocked.
                if pairOpen, PairLAN.advertisedIPv4s().isEmpty {
                    pairListenerError = PairClient.displayMessage(for: error)
                }
            }
        }
    }

    func publishMailboxSnapshot(token: String? = nil) {
        let secret = token ?? PairSession.currentOffer(in: store)?.token
        guard let secret, !secret.isEmpty else { return }
        let store = self.store
        Task.detached {
            guard let snapshot = try? PairSession.snapshot(from: store) else { return }
            try? await PairMailbox.publishSnapshot(snapshot, token: secret)
        }
    }

    private func applyPublicOrigin(_ origin: URL, offer: PairOffer) {
        pairTunnelOrigin = origin.absoluteString
        pairListenerError = nil
        if var envelope = pairEnvelope {
            envelope.origin = origin.absoluteString
            pairEnvelope = envelope
        }
        Task {
            try? await PairRendezvous.publish(origin: origin, code: offer.code, token: offer.token)
        }
    }

    func refreshComposioAccounts() async {
        guard let key = keychain.get(KeychainStore.composioAccount),
            !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        do {
            let data = try await URLSessionComposioTransport()
                .send(ComposioClient(apiKey: key).listConnectedAccountsRequest())
            for account in ComposioAccounts.parse(data) where account.isActive {
                rememberComposioAccount(toolkit: account.toolkit, id: account.id)
            }
        } catch {
            return
        }
    }

    var filteredProjects: [ProjectManifest] {
        projects
    }

    func openSearch() {
        settingsOpen = false
        searchOpen = true
        searchQuery = ""
    }

    func closeSearch() {
        searchOpen = false
        searchQuery = ""
    }

    var identityName: String {
        let name = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Local" : name
    }

    var identityInitials: String {
        let parts = identityName.split(whereSeparator: \.isWhitespace)
        let letters = parts.prefix(2).compactMap(\.first)
        if letters.isEmpty { return "LC" }
        return String(letters).uppercased()
    }

    var selected: ProjectManifest? {
        if composingNewChat { return nil }
        let id = ProjectSelection.resolve(current: selectedProjectID, available: projects.map(\.id))
        return projects.first { $0.id == id }
    }

    func reload() {
        projects = (try? store.listProjects()) ?? []
        endpoints = (try? endpointStore.load()) ?? []
        if selectedProjectID == nil, !composingNewChat {
            selectedProjectID = projects.first?.id
        }
        loadDrafts()
    }

    func select(_ id: UUID) {
        composingNewChat = false
        selectedProjectID = id
        selectedThreadID = store.resolveThreadID(projectID: id, preferred: nil)
        try? store.setActiveThread(projectID: id, threadID: selectedThreadID ?? UUID())
        dismissRailPeek(freezing: id)
        closeRailSessions()
        loadDrafts()
    }

    func selectThread(_ threadID: UUID, in projectID: UUID) {
        composingNewChat = false
        selectedProjectID = projectID
        selectedThreadID = threadID
        try? store.setActiveThread(projectID: projectID, threadID: threadID)
        loadDrafts()
    }

    @discardableResult
    func startThread(in projectID: UUID) -> UUID {
        let id = UUID()
        composingNewChat = false
        selectedProjectID = projectID
        selectedThreadID = id
        try? store.setActiveThread(projectID: projectID, threadID: id)
        return id
    }

    func chats(for project: ProjectManifest, current: UUID) -> [ThreadSummary] {
        var listed = (try? store.listThreads(projectID: project.id)) ?? []
        if !listed.contains(where: { $0.id == current }) {
            listed.insert(.draft(id: current), at: 0)
        }
        return listed
    }

    func beginNewChat() {
        composingNewChat = true
        selectedProjectID = nil
        selectedThreadID = nil
        commandQuery = ""
    }

    var newProjectDestinationTitle: String {
        guard let url = newProjectDestination else { return "Joyflow folder" }
        return url.lastPathComponent.isEmpty ? displayPath(url) : url.lastPathComponent
    }

    var newProjectDestinationLabel: String {
        guard let url = newProjectDestination else { return "Inside Joyflow" }
        return displayPath(url)
    }

    func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if url.path.hasPrefix(home) {
            return "~" + url.path.dropFirst(home.count)
        }
        return url.path
    }

    func chooseProjectDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Joyflow will create the project folder here."
        panel.directoryURL = newProjectDestination
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        newProjectDestination = url
        persistSettings()
    }

    func clearProjectDestination() {
        newProjectDestination = nil
        persistSettings()
    }

    @discardableResult
    func attachFolder(to project: ProjectManifest) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Add folder"
        panel.message = "Joyflow can read and write files in this folder for this project."
        panel.prompt = "Add"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            _ = try resources(for: project).addFolder(from: url)
            resourceError = nil
            inspectorVisible = true
            reload()
            return true
        } catch {
            resourceError = error.localizedDescription
            inspectorVisible = true
            return false
        }
    }

    func revealProjectInFinder(_ id: UUID) {
        let url = store.layout(for: id).root
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func avatarData(for project: ProjectManifest) -> Data? {
        store.avatarData(projectID: project.id)
    }

    func renameProject(_ id: UUID, to name: String) {
        try? store.renameProject(id: id, name: name)
        reload()
    }

    func deleteProject(_ id: UUID) {
        try? store.deleteProject(id: id)
        if selectedProjectID == id {
            selectedProjectID = nil
        }
        reload()
        if let next = selected {
            select(next.id)
        }
    }

    func setProjectAvatar(_ id: UUID, from url: URL) {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return }
        try? store.setAvatar(projectID: id, data: data)
        reload()
    }

    func setProjectMark(_ id: UUID, mark: ProjectMark) {
        try? store.setMark(projectID: id, icon: mark.iconValue)
        reload()
    }

    func clearProjectAvatar(_ id: UUID) {
        try? store.clearAvatar(projectID: id)
        reload()
    }

    func beginCreateProject() {
        createProjectRequested = true
    }

    @discardableResult
    func createProject(name: String, destination: URL? = nil) throws -> ProjectManifest {
        let project = try store.createProject(name: name, destination: destination ?? newProjectDestination)
        reload()
        select(project.id)
        return project
    }

    func loadDrafts() {
        guard let id = selected?.id else {
            soulDraft = ""
            instructionsDraft = ""
            return
        }
        soulDraft = (try? store.readSoul(projectID: id)) ?? ""
        instructionsDraft = (try? store.readInstructions(projectID: id)) ?? ""
    }

    func saveSoul() {
        guard let id = selected?.id else { return }
        try? store.writeSoul(projectID: id, text: soulDraft)
    }

    func saveInstructions() {
        guard let id = selected?.id else { return }
        try? store.writeInstructions(projectID: id, text: instructionsDraft)
    }

    func openSettings(_ pane: SettingsPane? = nil) {
        if let pane { settingsPane = pane }
        closeSearch()
        settingsOpen = true
        settingsOpenNonce += 1
    }

    func closeSettings() {
        settingsOpen = false
    }

    func saveEndpoints() {
        try? endpointStore.save(endpoints)
    }

    func addEndpoint() {
        let endpoint = ModelEndpoint(name: "Gateway", modelID: "openai/gpt-4.1")
        endpoints.append(endpoint)
        if activeEndpointID == nil { activeEndpointID = endpoint.id }
        saveEndpoints()
        persistSettings()
    }

    var activeEndpoint: ModelEndpoint? {
        endpoints.first(where: { $0.id == activeEndpointID }) ?? endpoints.first
    }

    func selectEndpoint(_ id: UUID) {
        activeEndpointID = id
        persistSettings()
    }

    var computerIsLocal: Bool { computer == .local }

    var sandboxCredentials: SandboxCredentials {
        SandboxCredentials(
            vercelToken: keychain.get(KeychainStore.vercelToken),
            vercelTeam: keychain.get(KeychainStore.vercelTeam),
            vercelProject: keychain.get(KeychainStore.vercelProject),
            e2bKey: keychain.get(KeychainStore.e2bKey),
            modalToken: keychain.get(KeychainStore.modalToken)
        )
    }

    func setComputerLocal(_ local: Bool) {
        if local {
            if computer != .local { rememberedCloud = computer }
            computer = .local
        } else if computer == .local {
            computer = rememberedCloud
        }
        persistSettings()
    }

    func setKey(_ key: String, for endpoint: ModelEndpoint) {
        _ = keychain.set(key, for: KeychainStore.modelAccount(endpoint.id))
    }

    func key(for endpoint: ModelEndpoint) -> String {
        keychain.get(KeychainStore.modelAccount(endpoint.id)) ?? ""
    }

    func setSidebarWidth(_ width: CGFloat) {
        sidebarWidth = min(Theme.sidebarMaxWidth, max(Theme.sidebarRailWidth, width))
    }

    func finishSidebarDrag(_ width: CGFloat) {
        sidebarDragging = false
        if width < Theme.sidebarCollapseAt {
            sidebarWidth = Theme.sidebarRailWidth
        } else {
            sidebarWidth = min(Theme.sidebarMaxWidth, max(Theme.sidebarMinExpanded, width))
        }
        persistSettings()
    }

    func persistSettings() {
        let payload = PersistedSettings(
            appearance: appearance.rawValue,
            defaultReview: defaultReview.rawValue,
            computer: computer.rawValue,
            activeEndpointID: activeEndpointID,
            sidebarCollapsed: sidebarCollapsed,
            sidebarWidth: Double(sidebarWidth),
            speechEngine: speechEngine.rawValue,
            speechModel: speechModel,
            speechBaseURL: speechBaseURL,
            localWhisperID: localWhisperID,
            projectDestinationPath: newProjectDestination?.path,
            projectDestinationBookmark: destinationBookmark()
        )
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: settingsURL)
        }
    }

    func loadSettings() {
        guard let data = try? Data(contentsOf: settingsURL),
            let payload = try? JSONDecoder().decode(PersistedSettings.self, from: data)
        else { return }
        appearance = AppAppearance(rawValue: payload.appearance) ?? .system
        defaultReview = ReviewAction(rawValue: payload.defaultReview) ?? .ask
        computer = ComputerChoice(rawValue: payload.computer) ?? .local
        if computer != .local { rememberedCloud = computer }
        activeEndpointID = payload.activeEndpointID
        if let stored = payload.sidebarWidth {
            sidebarWidth = CGFloat(stored)
        } else if payload.sidebarCollapsed == true {
            sidebarWidth = Theme.sidebarRailWidth
        }
        if let engine = payload.speechEngine, let parsed = SpeechEngine(rawValue: engine) {
            speechEngine = parsed
        }
        if let model = payload.speechModel, !model.isEmpty { speechModel = model }
        if let base = payload.speechBaseURL, !base.isEmpty { speechBaseURL = base }
        if let local = payload.localWhisperID, !local.isEmpty { localWhisperID = local }
        newProjectDestination = resolvePersistedDestination(payload)
    }

    private func destinationBookmark() -> Data? {
        guard let url = newProjectDestination else { return nil }
        return try? FolderBookmark.create(for: url)
    }

    private func resolvePersistedDestination(_ payload: PersistedSettings) -> URL? {
        if let bookmark = payload.projectDestinationBookmark, let url = FolderBookmark.resolve(bookmark) {
            return url
        }
        guard let path = payload.projectDestinationPath, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return url
    }

    func speechSettings() -> SpeechSettings {
        SpeechSettings(
            engine: speechEngine,
            apiKey: keychain.get(KeychainStore.whisperAPIKey) ?? "",
            model: speechModel,
            baseURL: speechBaseURL,
            localModelID: localWhisperID,
            localModelDirectory: LocalWhisper.supportFolder(root: store.rootURL)
        )
    }

    func transcriptionRouter() -> TranscriptionRouter {
        TranscriptionRouter(
            transport: { try await URLSession.shared.data(for: $0) },
            local: { audio, settings in
                try await LocalWhisper.transcribe(audio: audio, settings: settings)
            }
        )
    }

    func resources(for project: ProjectManifest) -> ResourceStore {
        ResourceStore(layout: store.layout(for: project.id))
    }

    func notes(for project: ProjectManifest) -> [NoteRecord] {
        (try? store.notes(projectID: project.id)) ?? []
    }

    func memories(for project: ProjectManifest) -> [MemoryRecord] {
        (try? store.memories(projectID: project.id)) ?? []
    }

    func previewLine(for project: ProjectManifest) -> String {
        (try? store.listThreads(projectID: project.id).first?.preview) ?? "No messages yet"
    }

    func recentChats(for project: ProjectManifest, limit: Int = 3) -> [ThreadSummary] {
        Array(((try? store.listThreads(projectID: project.id)) ?? []).prefix(limit))
    }

    func linkedCommonsText(for project: ProjectManifest) -> String? {
        let ids = (try? store.linkedCommons(projectID: project.id)) ?? []
        guard !ids.isEmpty else { return nil }
        let soul = (try? String(contentsOf: store.commons.soul, encoding: .utf8)) ?? ""
        let notes = (try? store.commons.notes()) ?? []
        let bodies = notes.map { "### \($0.title)\n\($0.body)" }.joined(separator: "\n")
        return soul + "\n" + bodies
    }
}
