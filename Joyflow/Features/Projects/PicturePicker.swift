import AppKit
import JoyflowKit
import SwiftUI
import UniformTypeIdentifiers

struct PicturePicker: View {
    var project: ProjectManifest
    var imageData: Data?
    var onMark: (ProjectMark) -> Void
    var onPhoto: (URL) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Picture")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ProjectMark.all) { mark in
                    let selected = imageData == nil && ProjectMark.resolved(icon: project.icon, projectID: project.id).id == mark.id
                    Button {
                        onMark(mark)
                    } label: {
                        ProjectOrb(id: project.id, size: 40, icon: mark.iconValue)
                            .overlay {
                                if selected {
                                    RoundedRectangle(cornerRadius: 12.6, style: .continuous)
                                        .strokeBorder(Theme.textPrimary, lineWidth: 1.5)
                                        .padding(-3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(mark.name)
                    .accessibilityLabel(mark.name)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }

            Button(action: choosePhoto) {
                Text("Choose photo…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose photo")
        }
        .padding(14)
        .frame(width: 248)
        .background(Theme.card)
    }

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .webP, .gif, .tiff]
        panel.title = "Choose a project picture"
        if panel.runModal() == .OK, let url = panel.url {
            onPhoto(url)
        }
    }
}
