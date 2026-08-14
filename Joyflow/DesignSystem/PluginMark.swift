import AppKit
import JoyflowKit
import SwiftUI

struct PluginMark: View {
    var slug: String
    var size: CGFloat = 36

    var body: some View {
        Group {
            if let data = PluginIcon.bundledImageData(for: slug),
                let image = NSImage(data: data)
            {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Theme.card)
                    .frame(width: size, height: size)
                    .overlay {
                        Text(String(slug.prefix(1)).uppercased())
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
            }
        }
        .accessibilityHidden(true)
    }
}
