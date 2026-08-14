import Foundation

public enum JoyflowKit {
    public static let name = "Joyflow"
    public static let bundleIdentifier = "dev.joyflow.Joyflow"
    public static let urlScheme = "joyflow"
    public static let defaultGatewayURL = "https://ai-gateway.vercel.sh/v1"
    public static let defaultModelID = "xai/grok-4.6"
    public static let composioBaseURL = "https://backend.composio.dev/api/v3.1"
    public static let composioUserID = "joyflow-local"
    public static let e2bBaseURL = "https://api.e2b.app"
    public static let applicationSupportFolder = "Joyflow"
    public static let legacyApplicationSupportFolder = "Cairn"

    /// Prefer `Joyflow/`. If only a leftover `Cairn/` folder exists, move it.
    public static func resolvedApplicationSupport(in parent: URL) throws -> URL {
        let dest = parent.appendingPathComponent(applicationSupportFolder)
        let legacy = parent.appendingPathComponent(legacyApplicationSupportFolder)
        let fm = FileManager.default
        if !fm.fileExists(atPath: dest.path), fm.fileExists(atPath: legacy.path) {
            try fm.moveItem(at: legacy, to: dest)
        }
        return dest
    }
}
