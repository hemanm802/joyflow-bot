import JoyflowKit
import SwiftUI
import UniformTypeIdentifiers

struct KnowledgeScreen: View {
    @Environment(PhoneModel.self) private var app
    var project: ProjectManifest
    @State private var section: KnowledgeTab = .soul
    @State private var noteTitle = ""
    @State private var noteBody = ""
    @State private var pickingFolder = false
    @State private var fileError: String?
    @Environment(\.dismiss) private var dismiss

    private enum KnowledgeTab: String, CaseIterable {
        case soul = "Soul"
        case notes = "Notes"
        case files = "Files"
    }

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Knowledge", selection: $section) {
                    ForEach(KnowledgeTab.allCases, id: \.self) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(16)
                Group {
                    switch section {
                    case .soul:
                        TextEditor(text: $app.soulDraft)
                            .font(.system(size: 16))
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 12)
                            .onChange(of: app.soulDraft) { _, _ in app.saveSoul() }
                    case .notes:
                        notes
                    case .files:
                        files
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Knowledge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.chrome)
                        .frame(minHeight: 44)
                }
            }
        }
        .presentationDetents([.large])
        .accessibilityIdentifier("ios.knowledge")
    }

    private var notes: some View {
        List {
            Section {
                TextField("Title", text: $noteTitle)
                TextField("Body", text: $noteBody, axis: .vertical)
                Button("Save note") {
                    let title = noteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { return }
                    app.addNote(title: title, body: noteBody)
                    noteTitle = ""
                    noteBody = ""
                }
                .frame(minHeight: 44)
            } header: {
                Text("New note")
            }
            Section {
                ForEach(app.notes(for: project)) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.title).font(.system(size: 16, weight: .semibold))
                        Text(note.body).font(.system(size: 14)).foregroundStyle(Theme.textSecondary).lineLimit(3)
                    }
                    .listRowBackground(Theme.card)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var files: some View {
        let store = app.resources(for: project)
        let docs = (try? store.documents()) ?? []
        let links = (try? store.links()) ?? []
        let folders = (try? store.folders()) ?? []
        return List {
            if let fileError {
                Section {
                    Text(fileError).foregroundStyle(Theme.danger)
                }
            }
            Section {
                if docs.isEmpty {
                    Text("Add files from the desktop project, or after a pair sync.")
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(docs, id: \.self) { name in
                    Label(name, systemImage: "doc")
                }
            } header: {
                Text("Documents")
            }
            Section {
                if folders.isEmpty {
                    Text("No folders yet.")
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(folders) { folder in
                    Label(folder.name, systemImage: "folder")
                }
                Button("Add folder") { pickingFolder = true }
                    .frame(minHeight: 44)
            } header: {
                Text("Folders")
            }
            Section {
                if links.isEmpty {
                    Text("No links yet.")
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(links, id: \.url) { link in
                    VStack(alignment: .leading) {
                        Text(link.title).font(.system(size: 15, weight: .medium))
                        Text(link.url).font(.system(size: 13)).foregroundStyle(Theme.link)
                    }
                }
            } header: {
                Text("Links")
            }
        }
        .scrollContentBackground(.hidden)
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped { url.stopAccessingSecurityScopedResource() }
                }
                do {
                    _ = try store.addFolder(from: url)
                    fileError = nil
                    app.reload()
                } catch {
                    fileError = error.localizedDescription
                }
            case .failure(let error):
                fileError = error.localizedDescription
            }
        }
    }
}
