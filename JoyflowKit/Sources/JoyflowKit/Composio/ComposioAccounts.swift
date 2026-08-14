import Foundation

public struct ComposioConnectedAccount: Sendable, Equatable {
    public var id: String
    public var toolkit: String
    public var userID: String
    public var status: String

    public init(id: String, toolkit: String, userID: String, status: String) {
        self.id = id
        self.toolkit = toolkit
        self.userID = userID
        self.status = status
    }

    public var isActive: Bool {
        let value = status.lowercased()
        return value.isEmpty || value == "active" || value == "enabled" || value == "connected" || value == "success"
    }
}

public enum ComposioAccounts: Sendable {
    public static func toolkit(fromToolSlug slug: String) -> String {
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let head = trimmed.split(separator: "_").first else { return trimmed.lowercased() }
        return String(head).lowercased()
    }

    public static func parse(_ data: Data) -> [ComposioConnectedAccount] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        return rows(in: root).compactMap(account(from:))
    }

    public static func resolve(
        _ data: Data,
        toolSlug: String,
        userID: String = JoyflowKit.composioUserID
    ) -> String? {
        resolve(parse(data), toolkit: toolkit(fromToolSlug: toolSlug), userID: userID)
    }

    public static func resolve(
        _ accounts: [ComposioConnectedAccount],
        toolkit: String,
        userID: String = JoyflowKit.composioUserID
    ) -> String? {
        let wanted = toolkit.lowercased()
        let matches = accounts.filter { $0.isActive && $0.toolkit.lowercased() == wanted }
        if let mine = matches.first(where: { $0.userID == userID || $0.userID.isEmpty }) {
            return mine.id
        }
        return matches.first?.id
    }

    private static func rows(in root: Any) -> [[String: Any]] {
        if let items = root as? [String: Any] {
            if let nested = items["items"] as? [[String: Any]] { return nested }
            if let data = items["data"] as? [[String: Any]] { return data }
            if let data = items["data"] as? [String: Any], let nested = data["items"] as? [[String: Any]] {
                return nested
            }
            if let nested = items["connected_accounts"] as? [[String: Any]] { return nested }
        }
        return root as? [[String: Any]] ?? []
    }

    private static func account(from row: [String: Any]) -> ComposioConnectedAccount? {
        let id = string(row["id"]) ?? string(row["connected_account_id"]) ?? string(row["nanoId"])
        guard let id, !id.isEmpty else { return nil }
        var toolkit = string(row["toolkit_slug"]) ?? string(row["appName"]) ?? ""
        if toolkit.isEmpty, let nested = row["toolkit"] as? [String: Any] {
            toolkit = string(nested["slug"]) ?? string(nested["name"]) ?? ""
        }
        return ComposioConnectedAccount(
            id: id,
            toolkit: toolkit.lowercased(),
            userID: string(row["user_id"]) ?? string(row["userId"]) ?? "",
            status: string(row["status"]) ?? ""
        )
    }

    private static func string(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        return nil
    }
}
