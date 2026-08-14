import Foundation
import Testing

@testable import JoyflowKit

struct JoyflowKitTests {
    @Test func productConstants() {
        #expect(JoyflowKit.name == "Joyflow")
        #expect(JoyflowKit.bundleIdentifier == "dev.joyflow.Joyflow")
        #expect(JoyflowKit.urlScheme == "joyflow")
        #expect(JoyflowKit.applicationSupportFolder == "Joyflow")
        #expect(JoyflowKit.defaultGatewayURL == "https://ai-gateway.vercel.sh/v1")
    }

    @Test func migratesLegacySupportFolder() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("joyflow-migrate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: parent) }
        let legacy = parent.appendingPathComponent(JoyflowKit.legacyApplicationSupportFolder)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try "ok".write(to: legacy.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)
        let dest = try JoyflowKit.resolvedApplicationSupport(in: parent)
        #expect(dest.lastPathComponent == "Joyflow")
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("marker.txt").path))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test func accentDiffersFromBackground() {
        #expect(ColorTokens.accent.dark != ColorTokens.background.dark)
        #expect(ColorTokens.accent.light != ColorTokens.background.light)
    }

    @Test func lightAndDarkSurfaceTokensDiffer() {
        #expect(ColorTokens.background.light != ColorTokens.background.dark)
        #expect(ColorTokens.surface.light != ColorTokens.surface.dark)
        #expect(ColorTokens.textPrimary.light != ColorTokens.textPrimary.dark)
        #expect(ColorTokens.raised.light != ColorTokens.card.light)
        #expect(ColorTokens.selection.light != ColorTokens.card.light)
        #expect(ColorTokens.selection.dark != ColorTokens.card.dark)
    }

    @Test func darkPrimaryAndAccentAreNearWhite() {
        #expect(ColorTokens.isNearWhite(ColorTokens.textPrimary.dark))
        #expect(ColorTokens.isNearWhite(ColorTokens.accent.dark))
        #expect(!ColorTokens.isNearWhite(ColorTokens.tint.light))
        #expect(!ColorTokens.isNearWhite(ColorTokens.tint.dark))
    }

    @Test func controlGlyphsContrastOnFills() {
        #expect(ColorTokens.contrastRatio(ColorTokens.onAccent.light, ColorTokens.accent.light) >= 4.5)
        #expect(ColorTokens.contrastRatio(ColorTokens.onAccent.dark, ColorTokens.accent.dark) >= 4.5)
        #expect(ColorTokens.sendIdleFill.light != ColorTokens.card.light)
        #expect(ColorTokens.sendEnabledFill.light == ColorTokens.accent.light)
        #expect(ColorTokens.sendEnabledFill.dark == ColorTokens.accent.dark)
        #expect(ColorTokens.controlMuted.dark != ColorTokens.card.dark)
    }

    @Test func identityRolesBanTanHexes() {
        let used = ColorTokens.identityRoles.flatMap { [$0.light, $0.dark] }
        for banned in ColorTokens.bannedTanHexes {
            #expect(!used.contains(banned), "banned tan \(String(banned, radix: 16)) still in identity roles")
        }
    }

    @Test func textIsReadableOnBackground() {
        #expect(ColorTokens.contrastRatio(ColorTokens.textPrimary.dark, ColorTokens.background.dark) >= 7)
        #expect(ColorTokens.contrastRatio(ColorTokens.textPrimary.light, ColorTokens.background.light) >= 7)
    }

    @Test func readablePairsMeetAA() {
        for pair in ColorTokens.readablePairs {
            let light = ColorTokens.contrastRatio(pair.foreground.light, pair.background.light)
            let dark = ColorTokens.contrastRatio(pair.foreground.dark, pair.background.dark)
            #expect(light >= 4.5, "light \(String(pair.foreground.light, radix: 16)) on \(String(pair.background.light, radix: 16)) is \(light)")
            #expect(dark >= 4.5, "dark \(String(pair.foreground.dark, radix: 16)) on \(String(pair.background.dark, radix: 16)) is \(dark)")
        }
    }

    @Test func popAccentIsTheSentBlue() {
        #expect(ColorTokens.pop.dark == 0x5D9DF7)
        #expect(ColorTokens.pop.light == 0x5D9DF7)
        #expect(ColorTokens.link.dark == 0x5D9DF7)
        #expect(ColorTokens.background.dark == 0x0A0A0A)
        #expect(ColorTokens.surface.dark == 0x141414)
    }

    @Test func railWidthMatchesButtonColumn() {
        #expect(
            LayoutTokens.sidebarRailWidth
                == LayoutTokens.sidebarRailButton + LayoutTokens.sidebarRailInset * 2
        )
        #expect(LayoutTokens.identityChip < LayoutTokens.sidebarRailButton)
        #expect(LayoutTokens.identityType > 9)
        #expect(LayoutTokens.identityChip >= 32)
        #expect(LayoutTokens.identityChip <= 44)
        #expect(LayoutTokens.sidebarRailWidth >= 80)
        #expect(LayoutTokens.sidebarRailButton >= 48)
    }

    @Test func controlTintStaysVisibleOnMenus() {
        #expect(ColorTokens.contrastRatio(ColorTokens.tint.light, ColorTokens.menuFill.light) >= 4.5)
        #expect(ColorTokens.contrastRatio(ColorTokens.tint.dark, ColorTokens.menuFill.dark) >= 3)
        #expect(ColorTokens.contrastRatio(0xFFFFFF, ColorTokens.tint.light) >= 4.5)
        #expect(ColorTokens.contrastRatio(0xFFFFFF, ColorTokens.tint.dark) >= 3)
        #expect(ColorTokens.tint.dark != ColorTokens.accent.dark)
    }
}
