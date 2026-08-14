import JoyflowKit
import SwiftUI

struct ProjectsHome: View {
    var pushesChat = true
    @Environment(PhoneModel.self) private var app
    @Environment(PhoneChat.self) private var chat
    @State private var query = ""
    @State private var creating = false
    @State private var newName = ""
    @State private var renameTarget: ProjectManifest?
    @State private var renameDraft = ""
    @State private var deleteTarget: ProjectManifest?
    @State private var settingsOpen = false
    @State private var pluginsOpen = false

    @State private var openedID: UUID?

    private var listed: [ProjectManifest] {
        app.filteredProjects(query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            createButton
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            projectList
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Theme.surface.ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(removing: .sidebarToggle)
        .containerBackground(Theme.surface, for: .navigation)
        .navigationDestination(item: $openedID) { _ in
            ChatScreen()
        }
        .alert("New Project", isPresented: $creating) {
            TextField("Name", text: $newName)
            Button("Create") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    try? app.createProject(name: name)
                    chat.load(app: app)
                    if pushesChat { openedID = app.selectedProjectID }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Project", isPresented: renamePresented) {
            TextField("Name", text: $renameDraft)
            Button("Save") {
                if let renameTarget {
                    app.renameProject(renameTarget.id, to: renameDraft)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete \(deleteTarget?.name ?? "this project")?",
            isPresented: deletePresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let deleteTarget {
                    app.deleteProject(deleteTarget.id)
                    chat.load(app: app)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The project folder will be removed from this device.")
        }
        .sheet(isPresented: $settingsOpen) { SettingsScreen() }
        .sheet(isPresented: $pluginsOpen) { PluginsScreen() }
        .sheet(isPresented: Bindable(app).pairSheetOpen) { PairScreen() }
        .onAppear { chat.load(app: app) }
        .accessibilityIdentifier("ios.projects")
    }

    private var header: some View {
        HStack(spacing: 8) {
            if pushesChat {
                Text("Joyflow")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.chrome)
            }
            Spacer(minLength: 0)
            Button {
                newName = ""
                creating = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Theme.chrome)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create project")
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .padding(.top, pushesChat ? 2 : 8)
        .frame(minHeight: 44)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.chromeMuted)
                .symbolRenderingMode(.monochrome)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel("Search")
    }

    private var createButton: some View {
        Button {
            newName = ""
            creating = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                Text("Create new")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Theme.chrome)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create project")
    }

    @ViewBuilder
    private var projectList: some View {
        if listed.isEmpty {
            Text(query.isEmpty ? "No projects yet" : "No matches")
                .font(.system(size: 13))
                .foregroundStyle(Theme.chromeMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .accessibilityIdentifier("sidebar.empty")
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(listed) { project in
                        Button {
                            open(project)
                        } label: {
                            PhoneProjectRow(
                                project: project,
                                preview: app.previewLine(for: project),
                                selected: !pushesChat && app.selectedProjectID == project.id,
                                imageData: app.avatarData(for: project)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Rename") {
                                renameDraft = project.name
                                renameTarget = project
                            }
                            Menu("Picture") {
                                ForEach(ProjectMark.all) { mark in
                                    Button(mark.name) { app.setProjectMark(project.id, mark: mark) }
                                }
                            }
                            Button("Delete", role: .destructive) {
                                deleteTarget = project
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("sidebar.list")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(0.85))
                .frame(height: 1)
                .padding(.bottom, 6)
            footerRow(icon: "puzzlepiece.extension", title: "Plugins") {
                pluginsOpen = true
            }
            footerRow(icon: app.pairBinding == nil ? "link.badge.plus" : "link", title: "Pair desktop") {
                app.pairSheetOpen = true
            }
            Button {
                settingsOpen = true
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Theme.card)
                        Text(app.identityInitials)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.chrome)
                    }
                    .frame(width: 28, height: 28)
                    Text(app.identityName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.chromeMuted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Account")
            .padding(.bottom, 10)
        }
        .padding(.top, 4)
    }

    private func footerRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.chromeMuted)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func open(_ project: ProjectManifest) {
        app.select(project.id)
        chat.load(app: app)
        if pushesChat {
            openedID = project.id
        }
    }

    private var renamePresented: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private var deletePresented: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }
}

private struct PhoneProjectRow: View {
    var project: ProjectManifest
    var preview: String
    var selected: Bool
    var imageData: Data?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ProjectOrb(id: project.id, size: 32, imageData: imageData, icon: project.icon)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(project.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 6)
                    Text(project.updatedAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Theme.chromeMuted)
                }
                Text(preview)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.chromeMuted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(selected ? Theme.selection : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }
}

