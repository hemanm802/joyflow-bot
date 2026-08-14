import Foundation

/// One semantic color with independent light and dark hexes.
public struct ColorTone: Sendable, Equatable {
    public var light: UInt32
    public var dark: UInt32

    public init(light: UInt32, dark: UInt32) {
        self.light = light
        self.dark = dark
    }
}

/// Neutral chrome. Dark type and accent are near-white. No limestone tan.
public enum ColorTokens {
    public static let bannedTanHexes: [UInt32] = [0xC4A37A, 0x8A6A3E, 0xF4F1EA]

    /// Typical AppKit menu fills used to lock control-tint contrast.
    public static let menuFill = ColorTone(light: 0xFFFFFF, dark: 0x2C2C2E)
    public static let menuLabel = ColorTone(light: 0x111111, dark: 0xFFFFFF)

    public static let background = ColorTone(light: 0xF5F5F7, dark: 0x0A0A0A)
    public static let surface = ColorTone(light: 0xF0F0F2, dark: 0x141414)
    public static let card = ColorTone(light: 0xFFFFFF, dark: 0x1C1C1E)
    public static let raised = ColorTone(light: 0xE8E8EC, dark: 0x2A2A2C)
    public static let selection = ColorTone(light: 0xE4E4E9, dark: 0x2F2F32)
    /// Link color in chat output only.
    public static let pop = ColorTone(light: 0x5D9DF7, dark: 0x5D9DF7)
    public static let onPop = ColorTone(light: 0x111111, dark: 0x111111)

    public static let textPrimary = ColorTone(light: 0x111111, dark: 0xFFFFFF)
    public static let textSecondary = ColorTone(light: 0x5C5C61, dark: 0xB0B0B5)

    public static let accent = ColorTone(light: 0x111111, dark: 0xFFFFFF)
    public static let onAccent = ColorTone(light: 0xFFFFFF, dark: 0x111111)
    /// Window/menu tint. Never near-white: a white tint paints NSMenu selection as a blank bar.
    public static let tint = ColorTone(light: 0x111111, dark: 0x0A84FF)
    public static let controlMuted = ColorTone(light: 0xE4E4E9, dark: 0x3A3A3C)
    public static let sendIdleFill = controlMuted
    public static let sendEnabledFill = accent
    public static let danger = ColorTone(light: 0xC5342B, dark: 0xFF6B66)
    public static let link = pop

    public static let borderSubtle = ColorTone(light: 0xD8D8DC, dark: 0x2E2E30)
    public static let borderStrong = ColorTone(light: 0xB4B4BA, dark: 0x3E3E42)

    public static var identityRoles: [ColorTone] {
        [background, surface, textPrimary, accent]
    }

    /// Body copy and chrome fills that must stay readable in both appearances.
    public static var readablePairs: [(foreground: ColorTone, background: ColorTone)] {
        [
            (textPrimary, background),
            (textPrimary, surface),
            (textPrimary, card),
            (textPrimary, raised),
            (textPrimary, controlMuted),
            (textSecondary, background),
            (textSecondary, surface),
            (textSecondary, card),
            (textSecondary, raised),
            (textSecondary, sendIdleFill),
            (onAccent, accent),
            (onAccent, sendEnabledFill),
            (onPop, pop),
            (danger, background),
            (danger, card),
            (menuLabel, menuFill),
        ]
    }

    public static func isNearWhite(_ hex: UInt32) -> Bool {
        let red = (hex >> 16) & 0xFF
        let green = (hex >> 8) & 0xFF
        let blue = hex & 0xFF
        return red >= 0xF5 && green >= 0xF5 && blue >= 0xF5
    }

    public static func relativeLuminance(_ hex: UInt32) -> Double {
        func linear(_ channel: Double) -> Double {
            let srgb = channel / 255
            return srgb <= 0.04045 ? srgb / 12.92 : pow((srgb + 0.055) / 1.055, 2.4)
        }
        let red = Double((hex >> 16) & 0xFF)
        let green = Double((hex >> 8) & 0xFF)
        let blue = Double(hex & 0xFF)
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    public static func contrastRatio(_ first: UInt32, _ second: UInt32) -> Double {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// sRGB saturation (chroma / max channel). Used to keep built-in marks vivid.
    public static func saturation(_ hex: UInt32) -> Double {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        let brightest = max(red, green, blue)
        let dullest = min(red, green, blue)
        guard brightest > 0 else { return 0 }
        return (brightest - dullest) / brightest
    }
}
