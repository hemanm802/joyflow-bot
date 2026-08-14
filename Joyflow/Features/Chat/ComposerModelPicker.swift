import JoyflowKit
import SwiftUI

struct ComposerModelPicker: View {
    @Binding var open: Bool
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button {
            open.toggle()
        } label: {
            HStack(spacing: 5) {
                Text(app.activeEndpoint?.name ?? "Model")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 112, alignment: .trailing)
                Image(systemName: open ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                (hovering || open) ? Theme.raised : Color.clear,
                in: Capsule()
            )
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if reduceMotion {
                hovering = inside
            } else {
                withAnimation(.easeOut(duration: 0.12)) { hovering = inside }
            }
        }
        .help(open ? "" : "Model and computer")
        .accessibilityLabel("Model")
        .accessibilityValue(app.activeEndpoint?.name ?? "None")
        .accessibilityIdentifier("composer.model")
    }
}

struct ComposerModelMenu: View {
    @Environment(AppModel.self) private var app
    var onDismiss: () -> Void
    @State private var hot: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if app.endpoints.isEmpty {
                row("empty", "cpu", "Add a model…", subtitle: "Settings · Models") {
                    app.openSettings(.models)
                    onDismiss()
                }
            } else {
                ForEach(app.endpoints) { endpoint in
                    row(
                        endpoint.id.uuidString,
                        "cpu",
                        endpoint.name,
                        subtitle: endpoint.modelID,
                        selected: app.activeEndpoint?.id == endpoint.id
                    ) {
                        app.selectEndpoint(endpoint.id)
                        onDismiss()
                    }
                }
            }

            Rectangle()
                .fill(Theme.borderSubtle.opacity(0.7))
                .frame(height: 1)
                .padding(.vertical, 6)

            row(
                "computer-local",
                "laptopcomputer",
                "Local",
                subtitle: "This Mac",
                selected: app.computerIsLocal
            ) {
                app.setComputerLocal(true)
            }
            row(
                "computer-cloud",
                "cloud",
                "Cloud",
                subtitle: app.computerIsLocal ? "Vercel, E2B, or Modal" : app.computer.title,
                selected: !app.computerIsLocal
            ) {
                app.setComputerLocal(false)
            }
        }
        .padding(6)
        .frame(width: 260)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.85), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.28), radius: 18, y: 8)
        .accessibilityIdentifier("composer.model.menu")
    }

    private func row(
        _ id: String,
        _ systemName: String,
        _ title: String,
        subtitle: String,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                hot == id ? Theme.selection : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hot = inside ? id : (hot == id ? nil : hot)
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("composer.model.row.\(id)")
    }
}
