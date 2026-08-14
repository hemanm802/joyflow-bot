import AppKit
import JoyflowKit
import SwiftUI

struct ResourcesPane: View {
    @Environment(AppModel.self) private var app
    var project: ProjectManifest
    @State private var linkTitle = ""
    @State private var linkURL = ""
    @State private var error: String?
    @State private var addingLink = false
    @State private var fileError: String?

    var body: some View {
        let store = app.resources(for: project)
        let links = (try? store.links()) ?? []
        let folders = (try? store.folders()) ?? []
        let documents = (try? store.documents()) ?? []
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let shown = fileError ?? app.resourceError {
                    Text(shown)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.danger)
                }
                fileGroup(title: "Links", empty: "No links yet.") {
                    if links.isEmpty && !addingLink {
                        emptyLine("No links yet.")
                    }
                    ForEach(links) { link in
                        fileRow(
                            icon: "link",
                            title: link.title,
                            subtitle: link.url
                        ) {
                            try? store.removeLink(id: link.id)
                            app.reload()
                        }
                    }
                    if addingLink {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Title", text: $linkTitle)
                                .textFieldStyle(.plain)
                            TextField("https://", text: $linkURL)
                                .textFieldStyle(.plain)
                            if let error {
                                Text(error).foregroundStyle(Theme.danger).font(.caption)
                            }
                            HStack {
                                Button("Cancel") {
                                    addingLink = false
                                    error = nil
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Button("Add") { addLink(store) }
                                    .buttonStyle(.plain)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .font(.system(size: 12))
                        }
                        .padding(12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        Button {
                            addingLink = true
                        } label: {
                            Label("Add link", systemImage: "plus")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                fileGroup(title: "Documents", empty: "No documents yet.") {
                    if documents.isEmpty {
                        emptyLine("No documents yet.")
                    }
                    ForEach(documents, id: \.self) { name in
                        fileRow(icon: "doc", title: name, subtitle: "In this project") {
                            try? store.removeDocument(named: name)
                            app.reload()
                        }
                    }
                    Button {
                        pickDocument(store)
                    } label: {
                        Label("Add document", systemImage: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }

                fileGroup(title: "Folders", empty: "No folders yet.") {
                    if folders.isEmpty {
                        emptyLine("No folders yet.")
                    }
                    ForEach(folders) { folder in
                        fileRow(
                            icon: "folder",
                            title: folder.name,
                            subtitle: folder.path.map { app.displayPath(URL(fileURLWithPath: $0)) } ?? "Attached folder"
                        ) {
                            try? store.removeFolder(id: folder.id)
                            app.resourceError = nil
                            app.reload()
                        }
                    }
                    Button {
                        pickFolder(store)
                    } label: {
                        Label("Add folder", systemImage: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func fileGroup<Content: View>(
        title: String,
        empty: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .tracking(0.6)
            content()
        }
        .accessibilityLabel(empty)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
    }

    private func fileRow(icon: String, title: String, subtitle: String, remove: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Remove", action: remove)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func addLink(_ store: ResourceStore) {
        do {
            try store.addLink(title: linkTitle, url: linkURL)
            linkTitle = ""
            linkURL = ""
            error = nil
            addingLink = false
            app.reload()
        } catch {
            self.error = "Enter a valid http(s) URL."
        }
    }

    private func pickDocument(_ store: ResourceStore) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Add document"
        if panel.runModal() == .OK, let url = panel.url {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            do {
                _ = try store.addDocument(from: url)
                fileError = nil
                app.reload()
            } catch {
                fileError = "Could not add that document."
            }
        }
    }

    private func pickFolder(_ store: ResourceStore) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Add folder"
        if panel.runModal() == .OK, let url = panel.url {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            do {
                _ = try store.addFolder(from: url)
                fileError = nil
                app.resourceError = nil
                app.reload()
            } catch {
                fileError = error.localizedDescription
            }
        }
    }
}
