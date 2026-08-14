import JoyflowKit
import SwiftUI
import UIKit

struct ProjectOrb: View {
    var id: UUID
    var size: CGFloat = 40
    var imageData: Data?
    var icon: String = "stone"

    var body: some View {
        Group {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
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
