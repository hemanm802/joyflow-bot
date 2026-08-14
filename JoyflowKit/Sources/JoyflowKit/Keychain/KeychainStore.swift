import Foundation
import Security

public struct KeychainStore: Sendable {
    public let service: String

    public init(service: String = JoyflowKit.bundleIdentifier) {
        self.service = service
    }

    @discardableResult
    public func set(_ value: String?, for account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return true }
        var attributes = base
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    public func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func modelAccount(_ id: UUID) -> String { "model.\(id.uuidString)" }
    public static let composioAccount = "composio.apiKey"

    public static func composioConnectedAccount(_ toolkit: String) -> String {
        "composio.connected.\(toolkit.lowercased())"
    }
    public static let vercelToken = "vercel.token"
    public static let vercelTeam = "vercel.teamId"
    public static let vercelProject = "vercel.projectId"
    public static let e2bKey = "e2b.apiKey"
    public static let modalToken = "modal.token"
    public static let whisperAPIKey = "speech.whisper.apiKey"
}
