import Foundation

/// Whether a computer tool may touch a path. User-asked home and scratch
/// folders are in; SIP-style system locations stay out.
public enum ComputerAccess: Sendable {
    public static let protectedPrefixes = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
        "/Library/Apple",
        "/private/var/db",
        "/private/etc",
        "/etc",
        "/dev",
        "/cores",
    ]

    public static func isProtected(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return protectedPrefixes.contains { prefix in
            path == prefix || path.hasPrefix(prefix + "/")
        }
    }

    public static func allows(_ url: URL, workspace: URL, extraRoots: [URL]) -> Bool {
        let target = url.standardizedFileURL
        if isInside(target, root: workspace.standardizedFileURL) { return true }
        for extra in extraRoots where isInside(target, root: extra.standardizedFileURL) {
            return true
        }
        return !isProtected(target)
    }

    public static func denyReason(_ url: URL) -> String? {
        guard isProtected(url) else { return nil }
        return "Can't open \(url.path) — it's a protected system location."
    }

    public static func isInside(_ url: URL, root: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }
}
