import JoyflowKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    var embedded = false
    var onClose: (() -> Void)?

    private var pane: SettingsPane {
        get { app.settingsPane }
        nonmutating set { app.settingsPane = newValue }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: embedded ? 22 : 0, style: .continuous))
        .overlay {
            if embedded {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.borderSubtle.opacity(0.85), lineWidth: 1)
            }
        }
        .modifier(SettingsWindowChrome(enabled: !embedded))
        .accessibilityIdentifier("settings.sheet")
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsPane.allCases) { item in
                Button {
                    app.settingsPane = item
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 18)
                        Text(item.title)
                            .font(.system(size: 13, weight: pane == item ? .semibold : .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(pane == item ? Theme.textPrimary : Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(
                        pane == item ? Theme.raised : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.nav.\(item.id)")
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 208)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.card)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(pane.title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                    .accessibilityLabel("Close settings")
                    .accessibilityIdentifier("settings.close")
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 18)

            Group {
                switch pane {
                case .models: ModelsPane()
                case .review: ReviewPane()
                case .computer: SandboxPane()
                case .connectors: ConnectorsPane()
                case .voice: VoicePane()
                }
            }
        }
        .background(Theme.card)
    }
}

private struct SettingsWindowChrome: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.joyflowWindowChrome()
        } else {
            content
        }
    }
}

struct SettingsSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            VStack(spacing: 0) {
                content()
            }
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

struct SettingsRow<Accessory: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.borderSubtle.opacity(0.7))
            .frame(height: 1)
            .padding(.leading, 16)
    }
}

struct SettingsChoice<Value: Equatable>: View {
    @Binding var value: Value
    var options: [(Value, String)]

    private var label: String {
        options.first(where: { $0.0 == value })?.1 ?? "Choose"
    }

    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button(option.1) { value = option.0 }
            }
        } label: {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.borderSubtle.opacity(0.9), lineWidth: 1)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct SettingsPill: View {
    var title: String
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(enabled ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.borderSubtle.opacity(0.9), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct SettingsField: View {
    var title: String
    var prompt: String
    var secure: Bool = false
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Group {
                if secure {
                    SecureField(prompt, text: $text)
                } else {
                    TextField(prompt, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.borderSubtle.opacity(0.8), lineWidth: 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct ModelsPane: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        @Bindable var app = app
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsSection(title: "You") {
                    HStack(spacing: 12) {
                        Glass.identityChip(size: 40, reduceTransparency: reduceTransparency) {
                            Text(app.identityInitials)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.identityName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Text("On this Mac")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }

                SettingsSection(title: "iPhone") {
                    SettingsRow(
                        title: "Pair iPhone",
                        subtitle: "Share a short code so the phone reads the same projects and threads."
                    ) {
                        SettingsPill(title: "Pair…") { app.beginPair() }
                    }
                }

                SettingsSection(title: "Appearance") {
                    SettingsRow(title: "Theme") {
                        SettingsChoice(
                            value: $app.appearance,
                            options: AppAppearance.allCases.map { ($0, $0.title) }
                        )
                    }
                }

                SettingsSection(title: "Model") {
                    SettingsRow(
                        title: "Active model",
                        subtitle: app.endpoints.isEmpty ? "Add a model to start chatting." : nil
                    ) {
                        if !app.endpoints.isEmpty {
                            SettingsChoice(
                                value: $app.activeEndpointID,
                                options: app.endpoints.map { (Optional($0.id), $0.name) }
                            )
                        }
                        SettingsPill(title: "Add model") { app.addEndpoint() }
                    }
                }

                ForEach($app.endpoints) { $endpoint in
                    SettingsSection(title: endpoint.name) {
                        SettingsField(title: "Display name", prompt: "Gateway", text: $endpoint.name)
                        SettingsDivider()
                        SettingsField(title: "Model id", prompt: JoyflowKit.defaultModelID, text: $endpoint.modelID)
                        SettingsDivider()
                        SettingsField(title: "Base URL", prompt: "https://…", text: $endpoint.baseURL)
                        SettingsDivider()
                        SettingsField(
                            title: "API key",
                            prompt: "API key",
                            secure: true,
                            text: keyBinding(for: endpoint)
                        )
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .onChange(of: app.activeEndpointID) { _, _ in app.persistSettings() }
        .onChange(of: app.appearance) { _, _ in app.persistSettings() }
        .onChange(of: app.endpoints) { _, _ in app.saveEndpoints() }
        .scrollIndicators(.never)
    }

    private func keyBinding(for endpoint: ModelEndpoint) -> Binding<String> {
        Binding(
            get: { app.key(for: endpoint) },
            set: { app.setKey($0, for: endpoint) }
        )
    }
}

struct ReviewPane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsSection(title: "Permissions") {
                    SettingsRow(
                        title: "When Joyflow wants to act",
                        subtitle: app.defaultReview.detail
                    ) {
                        SettingsChoice(
                            value: $app.defaultReview,
                            options: ReviewAction.allCases.map { ($0, $0.title) }
                        )
                    }
                    SettingsDivider()
                    SettingsRow(
                        title: "Allow is always available",
                        subtitle: "In Ask first, every prompt has Allow, Always allow, and Deny. Destructive commands stay blocked."
                    ) {
                        EmptyView()
                    }
                    SettingsDivider()
                    SettingsRow(
                        title: "Built-in denylist",
                        subtitle: "Erase-disk, rm -rf /, and other destructive commands cannot be allowed."
                    ) {
                        EmptyView()
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .onChange(of: app.defaultReview) { _, _ in app.persistSettings() }
        .scrollIndicators(.never)
    }
}

struct SandboxPane: View {
    @Environment(AppModel.self) private var app
    @State private var vercelToken = ""
    @State private var vercelTeam = ""
    @State private var vercelProject = ""
    @State private var e2bKey = ""
    @State private var modalToken = ""

    var body: some View {
        @Bindable var app = app
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsSection(title: "Computer") {
                    SettingsRow(
                        title: "Execution",
                        subtitle: "Let the teammate open files and run tasks. Review still checks everything first."
                    ) {
                        SettingsChoice(
                            value: $app.computer,
                            options: ComputerChoice.allCases.map { ($0, $0.title) }
                        )
                    }
                }

                SettingsSection(title: "Vercel") {
                    if app.keychain.get(KeychainStore.vercelToken) == nil {
                        SettingsRow(
                            title: "Token",
                            subtitle: "Add a Vercel token to use disposable sandboxes."
                        ) {
                            EmptyView()
                        }
                        SettingsDivider()
                    }
                    SettingsField(title: "Token", prompt: "Token", secure: true, text: $vercelToken)
                    SettingsDivider()
                    SettingsField(title: "Team id", prompt: "Team id", text: $vercelTeam)
                    SettingsDivider()
                    SettingsField(title: "Project id", prompt: "Project id", text: $vercelProject)
                    SettingsDivider()
                    SettingsRow(title: "Save Vercel") {
                        SettingsPill(title: "Save") {
                            _ = app.keychain.set(vercelToken, for: KeychainStore.vercelToken)
                            _ = app.keychain.set(vercelTeam, for: KeychainStore.vercelTeam)
                            _ = app.keychain.set(vercelProject, for: KeychainStore.vercelProject)
                        }
                    }
                }

                SettingsSection(title: "E2B") {
                    SettingsField(title: "API key", prompt: "API key", secure: true, text: $e2bKey)
                    SettingsDivider()
                    SettingsRow(title: "Save E2B") {
                        SettingsPill(title: "Save") {
                            _ = app.keychain.set(e2bKey, for: KeychainStore.e2bKey)
                        }
                    }
                }

                SettingsSection(title: "Modal") {
                    SettingsField(title: "Token", prompt: "Token", secure: true, text: $modalToken)
                    SettingsDivider()
                    SettingsRow(title: "Save Modal") {
                        SettingsPill(title: "Save") {
                            _ = app.keychain.set(modalToken, for: KeychainStore.modalToken)
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .onChange(of: app.computer) { _, _ in app.persistSettings() }
        .scrollIndicators(.never)
    }
}

struct VoicePane: View {
    @Environment(AppModel.self) private var app
    @State private var apiKey = ""
    @State private var downloadError: String?
    @State private var downloading = false

    var body: some View {
        @Bindable var app = app
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsSection(title: "Engine") {
                    SettingsRow(
                        title: "Transcription",
                        subtitle: "Talk, then stop. Joyflow writes into the composer."
                    ) {
                        SettingsChoice(
                            value: $app.speechEngine,
                            options: SpeechEngine.allCases.map { ($0, $0.title) }
                        )
                    }
                }

                SettingsSection(title: "Whisper API") {
                    SettingsRow(
                        title: "Endpoint",
                        subtitle: "POST /v1/audio/transcriptions. Use whisper-1 or gpt-4o-transcribe."
                    ) {
                        EmptyView()
                    }
                    SettingsDivider()
                    SettingsField(title: "API key", prompt: "API key", secure: true, text: $apiKey)
                    SettingsDivider()
                    SettingsField(title: "Base URL", prompt: "https://…", text: $app.speechBaseURL)
                    SettingsDivider()
                    SettingsRow(title: "Model") {
                        SettingsChoice(
                            value: $app.speechModel,
                            options: SpeechSettings.cloudModels.map { ($0, $0) }
                        )
                    }
                    SettingsDivider()
                    SettingsRow(title: "Save key") {
                        SettingsPill(title: "Save") {
                            _ = app.keychain.set(apiKey, for: KeychainStore.whisperAPIKey)
                        }
                    }
                }

                SettingsSection(title: "On this Mac") {
                    SettingsRow(
                        title: LocalWhisperCatalog.tinyEN.displayName,
                        subtitle: LocalWhisperCatalog.isInstalled(at: app.speechSettings().localModelDirectory)
                            ? "Downloaded. Ready to transcribe offline."
                            : "Not downloaded yet. About 75 MB."
                    ) {
                        SettingsPill(
                            title: downloading ? "Downloading…" : "Download",
                            enabled: !downloading
                        ) {
                            Task { await downloadModel() }
                        }
                    }
                    if let downloadError {
                        SettingsDivider()
                        SettingsRow(title: "Download failed", subtitle: downloadError) {
                            EmptyView()
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .onAppear {
            apiKey = app.keychain.get(KeychainStore.whisperAPIKey) ?? ""
        }
        .onChange(of: app.speechEngine) { _, _ in app.persistSettings() }
        .onChange(of: app.speechModel) { _, _ in app.persistSettings() }
        .onChange(of: app.speechBaseURL) { _, _ in app.persistSettings() }
        .scrollIndicators(.never)
    }

    private func downloadModel() async {
        downloading = true
        downloadError = nil
        do {
            try await LocalWhisper.download(to: app.speechSettings().localModelDirectory)
        } catch {
            downloadError = error.localizedDescription
        }
        downloading = false
    }
}

struct ConnectorsPane: View {
    @Environment(AppModel.self) private var app
    @State private var composioKey = ""

    var body: some View {
        ScrollView {
            SettingsSection(title: "Composio") {
                SettingsRow(
                    title: "API key",
                    subtitle: app.keychain.get(KeychainStore.composioAccount) == nil
                        ? "Add a Composio key to connect apps."
                        : "Saved on this Mac."
                ) {
                    EmptyView()
                }
                SettingsDivider()
                SettingsField(title: "Key", prompt: "Composio API key", secure: true, text: $composioKey)
                SettingsDivider()
                SettingsRow(title: "Save key") {
                    SettingsPill(title: "Save") {
                        _ = app.keychain.set(composioKey, for: KeychainStore.composioAccount)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.never)
    }
}
