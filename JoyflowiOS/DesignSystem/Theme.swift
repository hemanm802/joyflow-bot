import JoyflowKit
import SwiftUI
import UIKit

enum Theme {
    static let background = Color(tone: ColorTokens.background)
    static let surface = Color(tone: ColorTokens.surface)
    static let card = Color(tone: ColorTokens.card)
    static let raised = Color(tone: ColorTokens.raised)
    static let textPrimary = Color(tone: ColorTokens.textPrimary)
    static let textSecondary = Color(tone: ColorTokens.textSecondary)
    static let accent = Color(tone: ColorTokens.accent)
    static let onAccent = Color(tone: ColorTokens.onAccent)
    /// Chrome icons: white in dark, ink in light. Never the link blue.
    static let tint = Color(tone: ColorTokens.accent)
    static let chrome = Color(tone: ColorTokens.textPrimary)
    static let chromeMuted = Color(tone: ColorTokens.textSecondary)
    static let selection = Color(tone: ColorTokens.selection)
    static let pop = Color(tone: ColorTokens.pop)
    static let controlMuted = Color(tone: ColorTokens.controlMuted)
    static let sendIdleFill = Color(tone: ColorTokens.sendIdleFill)
    static let sendEnabledFill = Color(tone: ColorTokens.sendEnabledFill)
    static let danger = Color(tone: ColorTokens.danger)
    static let link = Color(tone: ColorTokens.link)
    static let borderSubtle = Color(tone: ColorTokens.borderSubtle)
    static let bubbleRadius: CGFloat = 18
}

extension Color {
    init(tone: ColorTone) {
        self.init(
            uiColor: UIColor { traits in
                UIColor(hex: traits.userInterfaceStyle == .dark ? tone.dark : tone.light)
            }
        )
    }

    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
