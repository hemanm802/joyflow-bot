import Foundation

/// Decide whether Add may start a connection. Missing keys never pretend success.
public struct PluginConnectResult: Sendable, Equatable {
    public var markedAdded: Bool
    public var request: ComposioRequest?

    public init(markedAdded: Bool, request: ComposioRequest?) {
        self.markedAdded = markedAdded
        self.request = request
    }
}

public struct PluginLinkPayload: Sendable, Equatable {
    public var redirectURL: String?
    public var accountID: String?

    public init(redirectURL: String? = nil, accountID: String? = nil) {
        self.redirectURL = redirectURL
        self.accountID = accountID
    }

    public var connected: Bool {
        if let accountID, !accountID.isEmpty { return true }
        return false
    }
}

public struct PluginConnectOutcome: Sendable, Equatable {
    public var payload: PluginLinkPayload
    public var authConfigID: String
    public var request: ComposioRequest?

    public init(payload: PluginLinkPayload, authConfigID: String, request: ComposioRequest?) {
        self.payload = payload
        self.authConfigID = authConfigID
        self.request = request
    }
}

public enum PluginConnect {
    public static func begin(
        apiKey: String?,
        authConfigID: String,
        userID: String = JoyflowKit.composioUserID
    ) -> PluginConnectResult {
        let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return PluginConnectResult(markedAdded: false, request: nil)
        }
        let request = ComposioClient(apiKey: trimmed, userID: userID)
            .initiateLinkRequest(authConfigID: authConfigID)
        return PluginConnectResult(markedAdded: false, request: request)
    }

    public static func parseAuthConfigIDs(_ data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let rows: [[String: Any]]
        if let object = root as? [String: Any] {
            rows = object["items"] as? [[String: Any]]
                ?? object["data"] as? [[String: Any]]
                ?? []
        } else {
            rows = root as? [[String: Any]] ?? []
        }
        return rows.compactMap { row in
            let id = row["id"] as? String ?? row["auth_config_id"] as? String
            return id?.isEmpty == false ? id : nil
        }
    }

    public static func parseLinkResponse(_ data: Data) -> PluginLinkPayload {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return PluginLinkPayload()
        }
        let nested = object["data"] as? [String: Any] ?? object
        let redirect = string(nested["redirect_url"]) ?? string(nested["redirectUrl"])
        let account = string(nested["connected_account_id"])
            ?? string(nested["connectedAccountId"])
            ?? string(nested["id"])
        return PluginLinkPayload(redirectURL: redirect, accountID: account)
    }

    /// GET auth configs, POST Connect Link, parse account + redirect. Never marks added without a response.
    public static func complete(
        apiKey: String?,
        toolkit: String,
        transport: any ComposioTransporting,
        userID: String = JoyflowKit.composioUserID
    ) async throws -> PluginConnectOutcome {
        let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            throw JoyflowStoreError.io("Add a Composio API key in Settings.")
        }
        let client = ComposioClient(apiKey: trimmed, userID: userID)
        let configs = try await transport.send(client.listAuthConfigsRequest(toolkit: toolkit))
        let authID = parseAuthConfigIDs(configs).first ?? toolkit
        let request = client.initiateLinkRequest(authConfigID: authID)
        let body = try await transport.send(request)
        return PluginConnectOutcome(
            payload: parseLinkResponse(body),
            authConfigID: authID,
            request: request
        )
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }
}
