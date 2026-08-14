import Foundation

public struct ComposioToolkit: Sendable, Equatable, Identifiable, Codable {
    public var slug: String
    public var name: String
    public var description: String
    public var id: String { slug }

    public init(slug: String, name: String, description: String) {
        self.slug = slug
        self.name = name
        self.description = description
    }
}

public struct ComposioRequest: Sendable, Equatable {
    public var method: String
    public var url: String
    public var headers: [String: String]
    public var body: Data?
}

public struct ComposioClient: Sendable {
    public var apiKey: String
    public var baseURL: String
    public var userID: String

    public init(
        apiKey: String,
        baseURL: String = JoyflowKit.composioBaseURL,
        userID: String = JoyflowKit.composioUserID
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.userID = userID
    }

    public func listToolkitsRequest() -> ComposioRequest {
        ComposioRequest(
            method: "GET",
            url: baseURL + "/toolkits",
            headers: ["x-api-key": apiKey, "Accept": "application/json"],
            body: nil
        )
    }

    public func listAuthConfigsRequest(toolkit: String) -> ComposioRequest {
        ComposioRequest(
            method: "GET",
            url: baseURL + "/auth_configs?toolkit_slug=\(toolkit)",
            headers: ["x-api-key": apiKey, "Accept": "application/json"],
            body: nil
        )
    }

    public func initiateLinkRequest(authConfigID: String, callbackURL: String = "joyflow://oauth") -> ComposioRequest {
        let body: [String: Any] = [
            "auth_config_id": authConfigID,
            "user_id": userID,
            "callback_url": callbackURL,
        ]
        return ComposioRequest(
            method: "POST",
            url: baseURL + "/connected_accounts/link",
            headers: [
                "x-api-key": apiKey,
                "Content-Type": "application/json",
                "Accept": "application/json",
            ],
            body: try? JSONSerialization.data(withJSONObject: body)
        )
    }

    public func listConnectedAccountsRequest() -> ComposioRequest {
        ComposioRequest(
            method: "GET",
            url: baseURL + "/connected_accounts?user_ids=\(userID)",
            headers: ["x-api-key": apiKey, "Accept": "application/json"],
            body: nil
        )
    }

    public func executeRequest(
        toolSlug: String,
        connectedAccountID: String,
        arguments: [String: Any],
        version: String = ComposioExecute.version,
        userID: String? = nil
    ) -> ComposioRequest {
        let body: [String: Any] = [
            "connected_account_id": connectedAccountID,
            "arguments": arguments,
            "version": version,
            "user_id": userID ?? self.userID,
        ]
        return ComposioRequest(
            method: "POST",
            url: baseURL + "/tools/execute/\(toolSlug)",
            headers: [
                "x-api-key": apiKey,
                "Content-Type": "application/json",
                "Accept": "application/json",
            ],
            body: try? JSONSerialization.data(withJSONObject: body)
        )
    }

    public static var featured: [ComposioToolkit] { PluginCatalog.allBundled }
}
