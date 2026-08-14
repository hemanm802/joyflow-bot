import AppKit
import JoyflowKit
import SwiftUI

enum Theme {
    static let background = Color(tone: ColorTokens.background)
    static let surface = Color(tone: ColorTokens.surface)
    static let card = Color(tone: ColorTokens.card)
    static let raised = Color(tone: ColorTokens.raised)
    static let pop = Color(tone: ColorTokens.pop)
    static let onPop = Color(tone: ColorTokens.onPop)

    static let textPrimary = Color(tone: ColorTokens.textPrimary)
    static let textSecondary = Color(tone: ColorTokens.textSecondary)

    static let accent = Color(tone: ColorTokens.accent)
    static let onAccent = Color(tone: ColorTokens.onAccent)
    static let tint = Color(tone: ColorTokens.tint)
    static let selection = Color(tone: ColorTokens.selection)
    static let controlMuted = Color(tone: ColorTokens.controlMuted)
    static let sendIdleFill = Color(tone: ColorTokens.sendIdleFill)
    static let sendEnabledFill = Color(tone: ColorTokens.sendEnabledFill)
    static let danger = Color(tone: ColorTokens.danger)
    static let link = Color(tone: ColorTokens.link)

    static let borderSubtle = Color(tone: ColorTokens.borderSubtle)
    static let borderStrong = Color(tone: ColorTokens.borderStrong)

    static let sidebarWidth: CGFloat = 248
    static let sidebarRailButton: CGFloat = LayoutTokens.sidebarRailButton
    static let sidebarRailInset: CGFloat = LayoutTokens.sidebarRailInset
    static let sidebarRailWidth: CGFloat = LayoutTokens.sidebarRailWidth
    static let identityChip: CGFloat = LayoutTokens.identityChip
    static let identityType: CGFloat = LayoutTokens.identityType
    static let sidebarMinExpanded: CGFloat = 212
    static let sidebarMaxWidth: CGFloat = 340
    static let sidebarCollapseAt: CGFloat = 148
    static let composerHeight: CGFloat = 48
    static let cardRadius: CGFloat = 14
    static let bubbleRadius: CGFloat = 16
    static let trafficClearance: CGFloat = 48
    static let inspectorWidth: CGFloat = 320
    static let sidebarPad: CGFloat = 12
}

extension Color {
    init(tone: ColorTone) {
        self.init(light: tone.light, dark: tone.dark)
    }

    init(light: UInt32, dark: UInt32) {
        self.init(light: Color(hex: light), dark: Color(hex: dark))
    }

    init(light: Color, dark: Color) {
        self = Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(isDark ? dark : light)
            })
    }

    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
