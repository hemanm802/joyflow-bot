import JoyflowKit
import SwiftUI
import UIKit

struct PluginsScreen: View {
    @Environment(PhoneModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var status: String?
    @State private var busy: String?

    var body: some View {
        NavigationStack {
            List {
                if let status {
                    Section {
                        Text(status).foregroundStyle(Theme.textSecondary)
                    }
                }
                Section {
                    ForEach(PluginCatalog.featured, id: \.slug) { plugin in
                        pluginRow(plugin)
                    }
                } header: {
                    Text("Featured")
                }
                Section {
                    ForEach(PluginCatalog.extras, id: \.slug) { plugin in
                        pluginRow(plugin)
                    }
                } header: {
                    Text("Workspace")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Plugins")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.chrome)
                        .frame(minHeight: 44)
                }
            }
        }
        .accessibilityIdentifier("ios.plugins")
    }

    private func pluginRow(_ plugin: ComposioToolkit) -> some View {
        HStack(spacing: 12) {
            pluginMark(plugin.slug)
            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.name).font(.system(size: 16, weight: .medium))
                Text(plugin.description)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button(app.composioAccounts[plugin.slug] == nil ? "Connect" : "Connected") {
                Task { await connect(plugin) }
            }
            .disabled(busy != nil)
            .frame(minHeight: 44)
        }
    }

    private func pluginMark(_ slug: String) -> some View {
        Group {
            if let data = PluginIcon.bundledImageData(for: slug), let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "puzzlepiece.extension")
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: 32, height: 32)
    }

    private func connect(_ plugin: ComposioToolkit) async {
        busy = plugin.slug
        defer { busy = nil }
        let key = app.keychain.get(KeychainStore.composioAccount)
        let start = PluginConnect.begin(apiKey: key, authConfigID: plugin.slug)
        guard start.request != nil else {
            status = "Add a Composio API key on desktop Settings, then pair — connect stays fail-closed."
            return
        }
        do {
            let outcome = try await PluginConnect.complete(
                apiKey: key,
                toolkit: plugin.slug,
                transport: URLSessionComposioTransport()
            )
            if let account = outcome.payload.accountID, !account.isEmpty {
                app.rememberComposioAccount(toolkit: plugin.slug, id: account)
                status = "Connected \(plugin.name)."
            } else if let redirect = outcome.payload.redirectURL, let url = URL(string: redirect) {
                _ = await UIApplication.shared.open(url)
                status = "Finish connecting \(plugin.name) in the browser."
            } else {
                status = "Connect did not return an account."
            }
        } catch {
            status = error.localizedDescription
        }
    }
}
