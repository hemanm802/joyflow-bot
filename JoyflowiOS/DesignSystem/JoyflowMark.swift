import SwiftUI

struct JoyflowMark: View {
    var size: CGFloat = 28
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image("Logo")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .modifier(LightMarkInvert(enabled: colorScheme == .light))
            .accessibilityHidden(true)
    }
}

private struct LightMarkInvert: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.colorInvert()
        } else {
            content
        }
    }
}
