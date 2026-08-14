import Foundation
#if os(macOS)
import AppKit
import ApplicationServices
#endif

/// Inspect displays and move app windows on this Mac.
public enum MacDesktop: Sendable {
    public struct DisplayInfo: Sendable, Equatable {
        public var name: String
        public var isBuiltin: Bool
        public var width: Int
        public var height: Int
        public var x: Int
        public var y: Int

        public init(name: String, isBuiltin: Bool, width: Int, height: Int, x: Int, y: Int) {
            self.name = name
            self.isBuiltin = isBuiltin
            self.width = width
            self.height = height
            self.x = x
            self.y = y
        }

        public var summary: String {
            let tag = isBuiltin ? " (MacBook)" : ""
            return "\(name)\(tag) \(width)×\(height) at (\(x), \(y))"
        }
    }

    public static func resolveDisplay(_ query: String, in displays: [DisplayInfo]) -> DisplayInfo? {
        guard !displays.isEmpty else { return nil }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if needle.isEmpty || isBuiltinQuery(needle) {
            return displays.first(where: \.isBuiltin) ?? displays.first
        }
        if isExternalQuery(needle) {
            return displays.first(where: { !$0.isBuiltin }) ?? displays.last
        }
        return displays.first { $0.name.lowercased().contains(needle) }
    }

    public static func matchApp(_ query: String, in names: [String]) -> String? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }
        if let exact = names.first(where: { $0.lowercased() == needle }) { return exact }
        if let contains = names.first(where: { $0.lowercased().contains(needle) }) { return contains }
        if let reverse = names.first(where: { needle.contains($0.lowercased()) }) { return reverse }
        return nil
    }

    public static func isBuiltinQuery(_ query: String) -> Bool {
        let needle = query.lowercased()
        return needle == "macbook" || needle == "laptop" || needle == "this mac"
            || needle.contains("built") || needle.contains("macbook") || needle.contains("notebook")
    }

    public static func isExternalQuery(_ query: String) -> Bool {
        let needle = query.lowercased()
        return needle.contains("external") || needle.contains("studio") || needle.contains("monitor")
            || needle.contains("wide") || needle == "other"
    }

    public static func perform(action: String, app: String = "", display: String = "") throws -> String {
        #if os(macOS)
        switch action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "list_displays", "displays", "screens":
            return listDisplays()
        case "list_apps", "apps":
            return listApps()
        case "move_app", "move", "arrange":
            return try moveApp(app, to: display)
        default:
            throw JoyflowStoreError.io(
                "Unknown control_mac action. Use list_displays, list_apps, or move_app."
            )
        }
        #else
        throw JoyflowStoreError.io("Moving windows runs on the Mac desktop.")
        #endif
    }

    #if os(macOS)
    public static func currentDisplays() -> [DisplayInfo] {
        NSScreen.screens.enumerated().map { index, screen in
            let frame = screen.visibleFrame
            let name = screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName
            return DisplayInfo(
                name: name,
                isBuiltin: isBuiltin(screen),
                width: Int(frame.width.rounded()),
                height: Int(frame.height.rounded()),
                x: Int(frame.minX.rounded()),
                y: Int(frame.minY.rounded())
            )
        }
    }

    public static func runningAppNames() -> [String] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.localizedName)
            .sorted()
    }

    private static func listDisplays() -> String {
        let screens = currentDisplays()
        guard !screens.isEmpty else { return "No displays found." }
        return screens.map(\.summary).joined(separator: "\n")
    }

    private static func listApps() -> String {
        let names = runningAppNames()
        return names.isEmpty ? "No regular apps are running." : names.joined(separator: "\n")
    }

    private static func moveApp(_ rawName: String, to rawDisplay: String) throws -> String {
        let names = runningAppNames()
        var appName = matchApp(rawName, in: names)
        if appName == nil {
            try launch(rawName)
            appName = matchApp(rawName, in: runningAppNames()) ?? rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let appName, !appName.isEmpty else {
            throw JoyflowStoreError.io("Name the app to move, for example Dia.")
        }
        let screens = currentDisplays()
        guard let target = resolveDisplay(rawDisplay, in: screens) else {
            throw JoyflowStoreError.io("No display matched “\(rawDisplay)”. Try list_displays.")
        }
        if !AXIsProcessTrusted() {
            return """
                Joyflow needs Accessibility access to move \(appName).

                1. Open System Settings → Privacy & Security → Accessibility
                2. Turn Joyflow on
                3. Ask again to move \(appName) to the MacBook screen
                """
        }
        let script = moveScript(app: appName, display: target)
        let result = try ProcessLaunch.run(
            executable: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-e", script],
            directory: nil,
            environment: nil
        )
        if result.status != 0 {
            let detail = result.stderr.isEmpty ? result.stdout : result.stderr
            if detail.lowercased().contains("not allowed") || detail.contains("1002") || detail.contains("-25211")
            {
                return """
                    macOS blocked moving \(appName).

                    1. Open System Settings → Privacy & Security → Accessibility
                    2. Turn Joyflow on
                    3. Ask again
                    """
            }
            throw JoyflowStoreError.io(detail.isEmpty ? "Could not move \(appName)." : detail)
        }
        return "Moved \(appName) to \(target.name)\(target.isBuiltin ? " (MacBook)" : "")."
    }

    private static func launch(_ name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let result = try ProcessLaunch.run(
            executable: URL(fileURLWithPath: "/usr/bin/open"),
            arguments: ["-a", trimmed],
            directory: nil,
            environment: nil
        )
        if result.status != 0 {
            throw JoyflowStoreError.io("Could not open \(trimmed). Is it installed?")
        }
        Thread.sleep(forTimeInterval: 1.2)
    }

    private static func isBuiltin(_ screen: NSScreen) -> Bool {
        let name = screen.localizedName.lowercased()
        if name.contains("built-in") || name.contains("built in") || name.contains("macbook") {
            return true
        }
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return false }
        return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
    }

    private static func moveScript(app: String, display: DisplayInfo) -> String {
        let margin = 8
        let x = display.x + margin
        let width = max(640, display.width - margin * 2)
        let height = max(480, display.height - margin * 2)
        let cocoaTop = display.y + display.height - margin
        let desktopTop = Int((NSScreen.screens.map(\.frame.maxY).max() ?? 0).rounded())
        let axY = max(0, desktopTop - cocoaTop)
        let escaped = app.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
            tell application "System Events"
              if not (exists process "\(escaped)") then error "App is not running"
              tell process "\(escaped)"
                set frontmost to true
                if (count of windows) is 0 then error "No windows"
                repeat with w in windows
                  set position of w to {\(x), \(axY)}
                  set size of w to {\(width), \(height)}
                end repeat
              end tell
            end tell
            """
    }
    #endif
}
