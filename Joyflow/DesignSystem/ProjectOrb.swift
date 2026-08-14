import AppKit
import JoyflowKit
import SwiftUI

struct ProjectOrb: View {
    var id: UUID
    var size: CGFloat = 32
    var imageData: Data?
    var icon: String = "stone"

    var body: some View {
        Group {
            if let imageData, let image = NSImage(data: imageData) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                markFace
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
        }
        .shadow(color: Color.black.opacity(0.2), radius: 1.5, y: 1)
        .accessibilityHidden(true)
    }

    private var markFace: some View {
        let mark = ProjectMark.resolved(icon: icon, projectID: id)
        return ZStack {
            shape.fill(Color(hex: mark.backgroundHex))
            Image("Logo")
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: size, height: size)
                .modifier(MarkComposite(ink: mark.ink))
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
    }
}

private struct MarkComposite: ViewModifier {
    var ink: MarkInk

    func body(content: Content) -> some View {
        switch ink {
        case .light:
            content.blendMode(.plusLighter)
        case .dark:
            content.colorInvert().blendMode(.multiply)
        }
    }
}
