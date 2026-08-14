import CoreText
import Foundation

/// Shared chrome sizes. Collapsed rail is the button column plus inset —
/// wide enough for the traffic-light cluster and three stacked controls.
public enum LayoutTokens: Sendable {
    public static let sidebarRailButton: CGFloat = 56
    public static let sidebarRailInset: CGFloat = 16
    public static let sidebarRailWidth: CGFloat = sidebarRailButton + sidebarRailInset * 2
    public static let identityChip: CGFloat = 40
    public static let identityType: CGFloat = 13
    /// Account popout. Wide enough for “Permissions” + “Always allow” on one line.
    public static let accountMenuWidth: CGFloat = 288
    public static let accountMenuChrome: CGFloat = 96
    public static let accountMenuType: CGFloat = 13

    public static func accountMenuFitsOneLine(title: String, trailing: String) -> Bool {
        textWidth(title, size: accountMenuType) + textWidth(trailing, size: accountMenuType)
            + accountMenuChrome <= accountMenuWidth
    }

    public static func textWidth(_ text: String, size: CGFloat) -> CGFloat {
        #if canImport(CoreText)
        let font = CTFontCreateWithName("Helvetica Neue" as CFString, size, nil)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font]
        let attributed = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attributed)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        #else
        return CGFloat(text.count) * size * 0.62
        #endif
    }
}
