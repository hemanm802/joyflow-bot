import JoyflowKit
import SwiftUI

struct SettingsScreen: View {
    @Environment(PhoneModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var pane: SettingsPane = .models

    private enum SettingsPane: String, CaseIterable, Identifiable {
        case models, review, computer, voice
        var id: String { rawValue }
        var title: String {
            switch self {
            case .models: "Models"
            case .review: "Permissions"
            case .computer: "Computer"
            case .voice: "Voice"
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Section", selection: $pane) {
                    ForEach(SettingsPane.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                switch pane {
                case .models:
                    ModelsSettings()
                case .review:
                    ReviewSettings()
                case .computer:
                    ComputerSettings()
                case .voice:
                    VoiceSettings()
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.chrome)
                        .frame(minHeight: 44)
                }
            }
        }
        .accessibilityIdentifier("ios.settings")
    }
}

private struct ModelsSettings: View {
    @Environment(PhoneModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Section {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.raised)
                    Text(app.identityInitials)
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.identityName).font(.system(size: 16, weight: .semibold))
                    Text("On this device").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                }
            }
        } header: {
            Text("You")
        }
        Section {
            Picker("Theme", selection: $app.appearance) {
                ForEach(PhoneAppearance.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .onChange(of: app.appearance) { _, _ in app.persistSettings() }
        } header: {
            Text("Appearance")
        }
        Section {
            if app.endpoints.isEmpty {
                Text("Add a Gateway or OpenAI-compatible model.")
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(app.endpoints) { endpoint in
                Button {
                    app.selectEndpoint(endpoint.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(endpoint.name).foregroundStyle(Theme.textPrimary)
                            Text(endpoint.modelID).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        if app.activeEndpoint?.id == endpoint.id {
                            Image(systemName: "checkmark")
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(Theme.chrome)
                        }
                    }
                    .frame(minHeight: 44)
                }
            }
            Button("Add model") { app.addEndpoint() }
                .frame(minHeight: 44)
        } header: {
            Text("Models")
        }
        ForEach(app.endpoints) { endpoint in
            Section {
                TextField("Display name", text: nameBinding(endpoint.id))
                TextField(JoyflowKit.defaultModelID, text: modelBinding(endpoint.id))
                    .textInputAutocapitalization(.never)
                TextField("Base URL", text: urlBinding(endpoint.id))
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                SecureField("API key", text: keyBinding(for: endpoint))
                Text("Keys stay in Keychain, not in Project files.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            } header: {
                Text(endpoint.name)
            }
        }
    }

    private func keyBinding(for endpoint: ModelEndpoint) -> Binding<String> {
        Binding(
            get: { app.key(for: endpoint) },
            set: { app.setKey($0, for: endpoint) }
        )
    }

    private func nameBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { app.endpoints.first(where: { $0.id == id })?.name ?? "" },
            set: { value in
                if let index = app.endpoints.firstIndex(where: { $0.id == id }) {
                    app.endpoints[index].name = value
                    app.saveEndpoints()
                }
            }
        )
    }

    private func modelBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { app.endpoints.first(where: { $0.id == id })?.modelID ?? "" },
            set: { value in
                if let index = app.endpoints.firstIndex(where: { $0.id == id }) {
                    app.endpoints[index].modelID = value
                    app.saveEndpoints()
                }
            }
        )
    }

    private func urlBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { app.endpoints.first(where: { $0.id == id })?.baseURL ?? "" },
            set: { value in
                if let index = app.endpoints.firstIndex(where: { $0.id == id }) {
                    app.endpoints[index].baseURL = value
                    app.saveEndpoints()
                }
            }
        )
    }
}

private struct ReviewSettings: View {
    @Environment(PhoneModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Section {
            Picker("Permissions", selection: $app.defaultReview) {
                ForEach(ReviewAction.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .onChange(of: app.defaultReview) { _, _ in app.persistSettings() }
            Text(app.defaultReview.detail)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        } header: {
            Text("Permissions")
        }
    }
}

private struct ComputerSettings: View {
    @Environment(PhoneModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Section {
            Picker("Run on", selection: Binding(
                get: { app.computerIsLocal },
                set: { app.setComputerLocal($0) }
            )) {
                Text("Local").tag(true)
                Text("Cloud").tag(false)
            }
            .pickerStyle(.segmented)
            if app.computerIsLocal {
                Text("Workspace files on this device. Shell is unavailable on iOS.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Picker("Provider", selection: $app.computer) {
                    Text("Vercel").tag(ComputerChoice.vercel)
                    Text("E2B").tag(ComputerChoice.e2b)
                    Text("Modal").tag(ComputerChoice.modal)
                }
                .onChange(of: app.computer) { _, _ in app.persistSettings() }
                SecureField("Vercel token", text: tokenBinding(KeychainStore.vercelToken))
                TextField("Vercel team", text: tokenBinding(KeychainStore.vercelTeam))
                TextField("Vercel project", text: tokenBinding(KeychainStore.vercelProject))
                SecureField("E2B key", text: tokenBinding(KeychainStore.e2bKey))
                SecureField("Modal token", text: tokenBinding(KeychainStore.modalToken))
            }
        } header: {
            Text("Computer")
        }
    }

    private func tokenBinding(_ account: String) -> Binding<String> {
        Binding(
            get: { app.keychain.get(account) ?? "" },
            set: { _ = app.keychain.set($0, for: account) }
        )
    }
}

private struct VoiceSettings: View {
    @Environment(PhoneModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Section {
            Picker("Engine", selection: $app.speechEngine) {
                Text("Whisper API").tag(SpeechEngine.whisperAPI)
                Text("On-device (desktop)").tag(SpeechEngine.local)
            }
            .onChange(of: app.speechEngine) { _, _ in app.persistSettings() }
            TextField("Model", text: $app.speechModel)
                .textInputAutocapitalization(.never)
                .onChange(of: app.speechModel) { _, _ in app.persistSettings() }
            TextField("Base URL", text: $app.speechBaseURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .onChange(of: app.speechBaseURL) { _, _ in app.persistSettings() }
            SecureField("Whisper API key", text: Binding(
                get: { app.keychain.get(KeychainStore.whisperAPIKey) ?? "" },
                set: { _ = app.keychain.set($0, for: KeychainStore.whisperAPIKey) }
            ))
        } header: {
            Text("Voice")
        }
    }
}
