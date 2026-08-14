import AppKit
import Foundation

enum ScreenshotSupport {
    static var requestedAppearance: String? {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--appearance"), args.indices.contains(index + 1) {
            return args[index + 1]
        }
        return nil
    }

    static var requestedPane: String? {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--open-pane"), args.indices.contains(index + 1) {
            return args[index + 1]
        }
        return ProcessInfo.processInfo.environment["JOYFLOW_OPEN_PANE"]
    }

    static var requestedPath: String? {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--screenshot"), args.indices.contains(index + 1) {
            return args[index + 1]
        }
        return ProcessInfo.processInfo.environment["JOYFLOW_SCREENSHOT"]
    }

    @MainActor
    static func captureKeyWindow(to path: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let window = NSApp.windows
            .filter(\.isVisible)
            .max(by: { ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height) })
            ?? NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.windows.first
        guard let window else { return false }
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        guard let view = window.contentView else { return false }
        let bounds = view.bounds
        guard bounds.width > 8, bounds.height > 8 else { return false }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }

    private static var scheduled = false
    private static var hookInstalled = false

    static func installLaunchHook() {
        guard !hookInstalled else { return }
        hookInstalled = true
        NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                scheduleCaptureIfRequested()
            }
        }
        DispatchQueue.main.async {
            Task { @MainActor in
                scheduleCaptureIfRequested()
            }
        }
    }

    @MainActor
    static func scheduleCaptureIfRequested() {
        guard let path = requestedPath, !scheduled else { return }
        scheduled = true
        NSApp.activate(ignoringOtherApps: true)
        func attempt(_ remaining: Int) {
            if captureKeyWindow(to: path) || remaining <= 0 {
                Darwin.exit(0)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                attempt(remaining - 1)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            attempt(8)
        }
    }
}
