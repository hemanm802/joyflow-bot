import AppKit
import JoyflowKit
import SwiftUI

struct PluginsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var tab = Tab.marketplace
    @State private var query = ""
    @State private var added: Set<String> = []
    @State private var expanded: Set<PluginSection> = []

    enum Tab: String {
        case marketplace
        case yours
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 14)

            toolbar
                .padding(.horizontal, 22)
                .padding(.bottom, 16)

            if app.keychain.get(KeychainStore.composioAccount) == nil {
                Text("Add a Composio key in Settings to connect apps.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 12)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if tab == .marketplace {
                        section("Featured", .featured)
                        section("Agent Orchestration", .agentOrchestration)
                        section("Workspace", .workspace)
                        section("Communication", .communication)
                    } else {
                        yoursList
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
            }
        }
        .background(Theme.background)
        .accessibilityIdentifier("plugins.sheet")
        .onAppear {
            added.formUnion(app.composioAccounts.keys)
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 10) {
                JoyflowMark(size: 26)
                Text("Plugins")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Theme.card, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                tabChip("Marketplace", .marketplace)
                tabChip("Yours", .yours)
            }
            Spacer(minLength: 12)
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                TextField("Search plugins", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 12)
            .frame(width: 228, height: 32)
            .background(Theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.borderSubtle, lineWidth: 1))
        }
    }

    private func tabChip(_ title: String, _ value: Tab) -> some View {
        Button {
            tab = value
        } label: {
            Text(title)
                .font(.system(size: 13, weight: tab == value ? .semibold : .medium))
                .foregroundStyle(tab == value ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(tab == value ? Theme.raised : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func section(_ title: String, _ section: PluginSection) -> some View {
        let items = PluginCatalog.tools(in: section, matching: query)
        let limit = 4
        let showing = expanded.contains(section) || query.isEmpty == false ? items : Array(items.prefix(limit))
        let hidden = max(0, items.count - showing.count)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(showing) { toolkit in
                        PluginCard(toolkit: toolkit, added: added.contains(toolkit.slug)) {
                            connect(toolkit)
                        }
                    }
                }
                if hidden > 0 {
                    Button("Show \(hidden) more") {
                        expanded.insert(section)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var yoursList: some View {
        let mine = PluginCatalog.allBundled.filter { added.contains($0.slug) }
        if mine.isEmpty {
            Text("Nothing added yet.")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        } else {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(mine) { toolkit in
                    PluginCard(toolkit: toolkit, added: true) {}
                }
            }
        }
    }

    private func connect(_ toolkit: ComposioToolkit) {
        Task { await connectAsync(toolkit) }
    }

    private func connectAsync(_ toolkit: ComposioToolkit) async {
        let key = app.keychain.get(KeychainStore.composioAccount)
        do {
            let outcome = try await PluginConnect.complete(
                apiKey: key,
                toolkit: toolkit.slug,
                transport: URLSessionComposioTransport()
            )
            if let id = outcome.payload.accountID {
                app.rememberComposioAccount(toolkit: toolkit.slug, id: id)
                added.insert(toolkit.slug)
            }
            if let raw = outcome.payload.redirectURL, let url = URL(string: raw) {
                app.pendingComposioToolkit = toolkit.slug
                NSWorkspace.shared.open(url)
            }
        } catch {
            if let binary = ComposioExecute.findCLI() {
                app.pendingComposioToolkit = toolkit.slug
                _ = try? await LocalComposioProcess().run(
                    executable: binary,
                    arguments: ComposioExecute.cliLinkArguments(toolkit: toolkit.slug)
                )
                await app.refreshComposioAccounts()
                if app.composioAccounts[toolkit.slug] != nil {
                    added.insert(toolkit.slug)
                }
            }
        }
    }
}

struct PluginCard: View {
    var toolkit: ComposioToolkit
    var added: Bool
    var onAdd: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PluginMark(slug: toolkit.slug, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(toolkit.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(toolkit.description)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if added {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("Added")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Theme.textSecondary)
            } else {
                Button("Add", action: onAdd)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Theme.controlMuted, in: Capsule())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.borderSubtle, lineWidth: 1)
        )
    }
}
