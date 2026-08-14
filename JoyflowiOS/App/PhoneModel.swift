import Foundation
import JoyflowKit
import Observation
import SwiftUI
import UIKit

enum PhoneAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
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

struct PhoneSettings: Codable, Sendable {
    var appearance: String
    var defaultReview: String
    var computer: String
    var activeEndpointID: UUID?
    var speechEngine: String?
    var speechModel: String?
    var speechBaseURL: String?
}

@Observable
@MainActor
final class PhoneModel {
    var appearance: PhoneAppearance = .system
    var selectedProjectID: UUID?
    var selectedThreadID: UUID?
    var projects: [ProjectManifest] = []
    var endpoints: [ModelEndpoint] = []
    var activeEndpointID: UUID?
    var defaultReview: ReviewAction = .ask
    var computer: ComputerChoice = .local
    private var rememberedCloud: ComputerChoice = .vercel
    var speechEngine: SpeechEngine = .whisperAPI
    var speechModel: String = SpeechSettings.defaultCloudModel
    var speechBaseURL: String = SpeechSettings.defaultCloudBaseURL
    var soulDraft = ""
    var instructionsDraft = ""
    var pairStatus = ""
    var pairError: String?
    var pairSheetOpen = false
    var pairBusy = false
    var runOnPairedMac = true
    var store: FileProjectStore
    var endpointStore: EndpointStore
    var keychain = KeychainStore(service: "dev.joyflow.Joyflow.ios")
    var composioAccounts: [String: String] = [:]
    var settingsURL: URL

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
        loadSettings()
        loadComposioAccounts()
    }

    var selected: ProjectManifest? {
        let id = ProjectSelection.resolve(current: selectedProjectID, available: projects.map(\.id))
        return projects.first { $0.id == id }
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

    var pairBinding: PairBinding? { PairSession.binding(in: store) }

    func previewLine(for project: ProjectManifest) -> String {
        (try? store.listThreads(projectID: project.id).first?.preview) ?? "No messages yet"
    }

    func chats(for project: ProjectManifest, current: UUID) -> [ThreadSummary] {
        var listed = (try? store.listThreads(projectID: project.id)) ?? []
        if !listed.contains(where: { $0.id == current }) {
            listed.insert(.draft(id: current), at: 0)
        }
        return listed
    }

    func filteredProjects(query: String) -> [ProjectManifest] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return projects }
        return projects.filter { $0.name.localizedCaseInsensitiveContains(needle) }
    }

    func reload() {
        projects = (try? store.listProjects()) ?? []
        endpoints = (try? endpointStore.load()) ?? []
        if selectedProjectID == nil {
            selectedProjectID = projects.first?.id
        }
        loadDrafts()
    }

    func select(_ id: UUID) {
        selectedProjectID = id
        selectedThreadID = store.resolveThreadID(projectID: id, preferred: nil)
        try? store.setActiveThread(projectID: id, threadID: selectedThreadID ?? UUID())
        loadDrafts()
    }

    func selectThread(_ threadID: UUID, in projectID: UUID) {
        selectedProjectID = projectID
        selectedThreadID = threadID
        try? store.setActiveThread(projectID: projectID, threadID: threadID)
        loadDrafts()
    }

    @discardableResult
    func startThread(in projectID: UUID) -> UUID {
        let id = UUID()
        selectedProjectID = projectID
        selectedThreadID = id
        try? store.setActiveThread(projectID: projectID, threadID: id)
        return id
    }

    func createProject(name: String) throws {
        let project = try store.createProject(name: name)
        reload()
        select(project.id)
    }

    func renameProject(_ id: UUID, to name: String) {
        try? store.renameProject(id: id, name: name)
        reload()
    }

    func deleteProject(_ id: UUID) {
        try? store.deleteProject(id: id)
        if selectedProjectID == id { selectedProjectID = nil }
        reload()
    }

    func setProjectMark(_ id: UUID, mark: ProjectMark) {
        try? store.setMark(projectID: id, icon: mark.iconValue)
        reload()
    }

    func avatarData(for project: ProjectManifest) -> Data? {
        store.avatarData(projectID: project.id)
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

    func notes(for project: ProjectManifest) -> [NoteRecord] {
        (try? store.notes(projectID: project.id)) ?? []
    }

    func addNote(title: String, body: String) {
        guard let id = selected?.id else { return }
        _ = try? store.writeNote(projectID: id, title: title, body: body)
        reload()
    }

    func resources(for project: ProjectManifest) -> ResourceStore {
        ResourceStore(layout: store.layout(for: project.id))
    }

    func addEndpoint() {
        let endpoint = ModelEndpoint(name: "Gateway", modelID: "openai/gpt-4.1")
        endpoints.append(endpoint)
        if activeEndpointID == nil { activeEndpointID = endpoint.id }
        saveEndpoints()
        persistSettings()
    }

    func saveEndpoints() {
        try? endpointStore.save(endpoints)
    }

    func selectEndpoint(_ id: UUID) {
        activeEndpointID = id
        persistSettings()
    }

    var activeEndpoint: ModelEndpoint? {
        endpoints.first(where: { $0.id == activeEndpointID }) ?? endpoints.first
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

    func speechSettings() -> SpeechSettings {
        SpeechSettings(
            engine: speechEngine,
            apiKey: keychain.get(KeychainStore.whisperAPIKey) ?? "",
            model: speechModel,
            baseURL: speechBaseURL,
            localModelID: LocalWhisperCatalog.tinyEN.id,
            localModelDirectory: store.rootURL.appendingPathComponent("Whisper")
        )
    }

    func persistSettings() {
        let payload = PhoneSettings(
            appearance: appearance.rawValue,
            defaultReview: defaultReview.rawValue,
            computer: computer.rawValue,
            activeEndpointID: activeEndpointID,
            speechEngine: speechEngine.rawValue,
            speechModel: speechModel,
            speechBaseURL: speechBaseURL
        )
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: settingsURL)
        }
    }

    func loadSettings() {
        guard let data = try? Data(contentsOf: settingsURL),
            let payload = try? JSONDecoder().decode(PhoneSettings.self, from: data)
        else { return }
        appearance = PhoneAppearance(rawValue: payload.appearance) ?? .system
        defaultReview = ReviewAction(rawValue: payload.defaultReview) ?? .ask
        computer = ComputerChoice(rawValue: payload.computer) ?? .local
        if computer != .local { rememberedCloud = computer }
        activeEndpointID = payload.activeEndpointID
        if let engine = payload.speechEngine, let parsed = SpeechEngine(rawValue: engine) {
            speechEngine = parsed
        }
        if let model = payload.speechModel, !model.isEmpty { speechModel = model }
        if let base = payload.speechBaseURL, !base.isEmpty { speechBaseURL = base }
    }

    func persistComposioAccounts() {
        let data = try? JSONSerialization.data(withJSONObject: composioAccounts, options: [.prettyPrinted, .sortedKeys])
        try? data?.write(to: store.rootURL.appendingPathComponent("composio-accounts.json"))
    }

    func loadComposioAccounts() {
        let url = store.rootURL.appendingPathComponent("composio-accounts.json")
        if let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        {
            composioAccounts = object
        }
    }

    func rememberComposioAccount(toolkit: String, id: String) {
        composioAccounts[toolkit.lowercased()] = id
        persistComposioAccounts()
    }

    func handleJoyflowURL(_ url: URL) {
        if url.host == "oauth" { return }
        pairSheetOpen = true
        Task { await acceptPairURL(url) }
    }

    func acceptPairURL(_ url: URL) async {
        if let envelope = PairSession.parse(url) ?? PairSession.parsePasted(url.absoluteString) {
            await accept(envelope)
            return
        }
        pairError = "This is not a Joyflow pair link."
    }

    func accept(_ envelope: PairEnvelope) async {
        pairBusy = true
        pairError = nil
        defer { pairBusy = false }
        do {
            _ = try await PairSession.accept(envelope, into: store)
            pairStatus = "Paired · \(envelope.offer.code)"
            reload()
        } catch {
            pairError = PairClient.displayMessage(for: error)
        }
    }

    func acceptPasted(_ raw: String) async {
        if let envelope = PairSession.parsePasted(raw) {
            await accept(envelope)
            return
        }
        if let code = PairSession.parseCode(raw) {
            await acceptTypedCode(code)
            return
        }
        pairError = "Copy the pair link or the 6-character code from the Mac, then tap Paste and pair."
    }

    func acceptTypedCode(_ code: String) async {
        pairBusy = true
        pairError = nil
        defer { pairBusy = false }
        do {
            let binding = try await PairSession.acceptCode(code, into: store)
            pairStatus = "Paired · \(binding.code)"
            reload()
        } catch {
            pairError = PairClient.displayMessage(for: error)
        }
    }

    func pasteAndPair() async {
        let raw = UIPasteboard.general.string ?? ""
        await acceptPasted(raw)
    }

    func pullFromDesktop() async {
        pairBusy = true
        defer { pairBusy = false }
        do {
            try await PairSession.pull(into: store)
            reload()
            pairStatus = "Updated from desktop"
            pairError = nil
        } catch {
            pairError = PairClient.displayMessage(for: error)
        }
    }

    func pushToDesktop() async {
        pairBusy = true
        defer { pairBusy = false }
        do {
            try await PairSession.push(from: store)
            pairStatus = "Sent to desktop"
            pairError = nil
        } catch {
            pairError = PairClient.displayMessage(for: error)
        }
    }

    var identityName: String {
        let name = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "iPhone" : name
    }

    var identityInitials: String {
        let parts = identityName.split(whereSeparator: \.isWhitespace)
        let letters = parts.prefix(2).compactMap(\.first)
        if letters.isEmpty { return "JF" }
        return String(letters).uppercased()
    }
}
