import SwiftUI

extension View {
    func glassBackground(cornerRadius: CGFloat = Theme.cardRadius) -> some View {
        glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

enum Glass {
    static func chrome<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .glassBackground(cornerRadius: 18)
    }

    static func identityChip<Content: View>(
        size: CGFloat = Theme.identityChip,
        reduceTransparency: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let chip = content()
            .frame(width: size, height: size)
        return Group {
            if reduceTransparency {
                chip.background(Theme.raised, in: Circle())
            } else {
                chip.glassEffect(.regular.interactive(), in: Circle())
            }
        }
        .overlay {
            Circle().strokeBorder(Theme.borderSubtle.opacity(0.55), lineWidth: 0.6)
        }
    }
}
