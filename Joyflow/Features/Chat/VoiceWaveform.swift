import SwiftUI

struct VoiceWaveform: View {
    var levels: [CGFloat]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 2.5
            let bar: CGFloat = 2
            let count = max(16, Int((proxy.size.width + spacing) / (bar + spacing)))
            let samples = Self.resample(levels, count: count)
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(Theme.textPrimary.opacity(0.82))
                        .frame(width: bar, height: height(samples[index], in: proxy.size.height))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(minHeight: 22)
        .accessibilityLabel("Recording")
    }

    private func height(_ level: CGFloat, in maxHeight: CGFloat) -> CGFloat {
        if reduceMotion { return 6 }
        let span = max(10, maxHeight - 2)
        return 3 + max(0, min(1, level)) * span
    }

    private static func resample(_ levels: [CGFloat], count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        if levels.isEmpty { return Array(repeating: CGFloat(0.08), count: count) }
        if levels.count == count { return levels }
        if levels.count > count { return Array(levels.suffix(count)) }
        let pad = Array(repeating: CGFloat(0.08), count: count - levels.count)
        return pad + levels
    }
}
