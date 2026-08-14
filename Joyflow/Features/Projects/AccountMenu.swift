import AppKit
import JoyflowKit
import SwiftUI

struct AccountMenu: View {
    @Environment(AppModel.self) private var app
    var onDismiss: () -> Void
    @State private var hot: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            row("appearance", "circle.lefthalf.filled", "Appearance", trailing: app.appearance.title, chevron: true) {
                cycleAppearance()
            }
            row("permissions", "checkmark.shield", "Permissions", trailing: app.defaultReview.title, chevron: true) {
                cyclePermissions()
            }
            row("pair", "iphone", "Pair iPhone") {
                _ = app.beginPair()
            }
            row("settings", "gearshape", "Settings") {
                app.openSettings()
            }
            row("plugins", "puzzlepiece.extension", "Plugins") {
                app.pluginsOpen = true
            }
            row("about", "info.circle", "About") {
                app.aboutOpen = true
            }
            row("coffee", "cup.and.saucer", "Buy me a coffee") {
                open(Self.coffeeURL)
            }
            row("help", "questionmark.circle", "Help Center") {
                open(Self.helpURL)
            }
            row("feedback", "megaphone", "Send Feedback") {
                open(Self.feedbackURL)
            }
        }
        .padding(6)
        .frame(width: LayoutTokens.accountMenuWidth)
        .accessibilityIdentifier("account.menu")
    }

    private func row(
        _ id: String,
        _ systemName: String,
        _ title: String,
        trailing: String? = nil,
        chevron: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            if id != "appearance" && id != "permissions" {
                onDismiss()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
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
        .accessibilityIdentifier("account.menu.\(id)")
    }

    private func cycleAppearance() {
        switch app.appearance {
        case .system: app.appearance = .light
        case .light: app.appearance = .dark
        case .dark: app.appearance = .system
        }
        app.persistSettings()
    }

    private func cyclePermissions() {
        app.defaultReview = app.defaultReview.cycled
        app.persistSettings()
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private static let helpURL = URL(string: "https://github.com/robzilla1738/joyflow-bot")!
    private static let feedbackURL = URL(string: "https://github.com/robzilla1738/joyflow-bot/issues")!
    private static let coffeeURL = URL(string: "https://buymeacoffee.com/robcourson")!
}
