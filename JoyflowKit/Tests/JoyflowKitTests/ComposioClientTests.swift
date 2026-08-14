import Foundation
import Testing

@testable import JoyflowKit

struct ComposioClientTests {
    @Test func baseURLAndLinkRequest() throws {
        let client = ComposioClient(apiKey: "k")
        #expect(client.baseURL == "https://backend.composio.dev/api/v3.1")
        let auth = client.listAuthConfigsRequest(toolkit: "gmail")
        #expect(auth.method == "GET")
        #expect(auth.url.contains("/auth_configs"))
        let link = client.initiateLinkRequest(authConfigID: "ac_1")
        #expect(link.method == "POST")
        #expect(link.url.hasSuffix("/connected_accounts/link"))
        let body = try JSONSerialization.jsonObject(with: link.body!) as? [String: Any]
        #expect(body?["auth_config_id"] as? String == "ac_1")
        #expect(body?["user_id"] as? String == "joyflow-local")
        #expect(body?["callback_url"] as? String == "joyflow://oauth")
    }

    @Test func featuredIncludesCoreSlugs() {
        let slugs = Set(ComposioClient.featured.map(\.slug))
        #expect(slugs.isSuperset(of: ["gmail", "slack", "notion", "github"]))
    }

    @Test func executeRequiresAccount() throws {
        let request = ComposioClient(apiKey: "k").executeRequest(
            toolSlug: "GMAIL_FETCH_EMAILS",
            connectedAccountID: "ca_1",
            arguments: ["limit": 5]
        )
        #expect(ToolKind.isValidName("composio_execute"))
        #expect(request.method == "POST")
        #expect(request.url.hasSuffix("/tools/execute/GMAIL_FETCH_EMAILS"))
        #expect(request.url.contains("/api/v3.1/"))
        let body = try JSONSerialization.jsonObject(with: request.body!) as? [String: Any]
        #expect(body?["connected_account_id"] as? String == "ca_1")
        #expect(body?["version"] as? String == "latest")
        #expect(body?["user_id"] as? String == "joyflow-local")
        #expect((body?["arguments"] as? [String: Any])?["limit"] as? Int == 5)
    }

    @Test func executePlanFailsClosedWithoutKey() {
        let plan = ComposioExecute.plan(
            apiKey: "   ",
            toolSlug: "GMAIL_FETCH_EMAILS",
            connectedAccountID: "ca_1",
            arguments: [:]
        )
        #expect(plan.request == nil)
        #expect(plan.ready == false)
        #expect(plan.error?.contains("API key") == true)
        #expect(plan.cliArguments == ["execute", "GMAIL_FETCH_EMAILS", "-d", "{}"])
    }

    @Test func officialCLIIsExecuteDashD() {
        #expect(
            ComposioExecute.cliArguments(toolSlug: "GMAIL_FETCH_EMAILS", argumentsJSON: #"{"limit":1}"#)
                == ["execute", "GMAIL_FETCH_EMAILS", "-d", #"{"limit":1}"#]
        )
        #expect(ComposioExecute.cliLinkArguments(toolkit: "gmail") == ["link", "gmail"])
        #expect(
            ComposioExecute.findCLI(
                environment: ["PATH": "/nope", "HOME": "/nope-home"],
                isExecutable: { _ in false }
            ) == nil
        )
    }

    @Test func executePlanBuildsV31Request() throws {
        let plan = ComposioExecute.plan(
            apiKey: "secret",
            toolSlug: "SLACK_SEND_MESSAGE",
            connectedAccountID: "ca_9",
            arguments: ["text": "hi"]
        )
        #expect(plan.ready)
        #expect(plan.error == nil)
        let request = try #require(plan.request)
        #expect(request.method == "POST")
        #expect(request.url == "https://backend.composio.dev/api/v3.1/tools/execute/SLACK_SEND_MESSAGE")
        #expect(request.headers["x-api-key"] == "secret")
        let body = try JSONSerialization.jsonObject(with: request.body!) as? [String: Any]
        #expect(body?["connected_account_id"] as? String == "ca_9")
        #expect(body?["version"] as? String == "latest")
        #expect((body?["arguments"] as? [String: Any])?["text"] as? String == "hi")
    }

    @Test func missingKeyDoesNotMarkAdded() {
        let empty = PluginConnect.begin(apiKey: nil, authConfigID: "gmail")
        #expect(empty.markedAdded == false)
        #expect(empty.request == nil)
        let blank = PluginConnect.begin(apiKey: "   ", authConfigID: "gmail")
        #expect(blank.markedAdded == false)
        #expect(blank.request == nil)
    }

    @Test func connectLinkUsesShippedPath() throws {
        let result = PluginConnect.begin(apiKey: "k", authConfigID: "gmail")
        #expect(result.markedAdded == false)
        let request = try #require(result.request)
        #expect(request.method == "POST")
        #expect(request.url.hasSuffix("/connected_accounts/link"))
        let body = try JSONSerialization.jsonObject(with: request.body!) as? [String: Any]
        #expect(body?["auth_config_id"] as? String == "gmail")
        #expect(body?["user_id"] as? String == "joyflow-local")
        #expect(body?["callback_url"] as? String == "joyflow://oauth")
    }

    @Test func connectCompleteSendsLinkAndParsesAccount() async throws {
        let transport = RecordingComposioTransport()
        transport.authConfigResponse = Data(#"{"items":[{"id":"ac_gmail"}]}"#.utf8)
        transport.linkResponse = Data(
            #"{"redirect_url":"https://connect.composio.dev/x","connected_account_id":"ca_gmail"}"#.utf8
        )
        let outcome = try await PluginConnect.complete(
            apiKey: "k",
            toolkit: "gmail",
            transport: transport
        )
        #expect(outcome.payload.accountID == "ca_gmail")
        #expect(outcome.payload.redirectURL == "https://connect.composio.dev/x")
        #expect(outcome.authConfigID == "ac_gmail")
        #expect(transport.calls.count == 2)
        #expect(transport.calls[0].url.contains("/auth_configs"))
        #expect(transport.calls[1].url.hasSuffix("/connected_accounts/link"))
        let body = try JSONSerialization.jsonObject(with: transport.calls[1].body!) as? [String: Any]
        #expect(body?["auth_config_id"] as? String == "ac_gmail")
    }

    @Test func resolveAccountFromListPayload() {
        let data = Data(
            #"""
            {"items":[{"id":"ca_resolved","status":"ACTIVE","user_id":"joyflow-local","toolkit":{"slug":"gmail"}}]}
            """#.utf8
        )
        #expect(ComposioAccounts.toolkit(fromToolSlug: "GMAIL_FETCH_EMAILS") == "gmail")
        #expect(ComposioAccounts.resolve(data, toolSlug: "GMAIL_FETCH_EMAILS") == "ca_resolved")
        #expect(ComposioAccounts.resolve(data, toolSlug: "SLACK_SEND_MESSAGE") == nil)
    }
}
