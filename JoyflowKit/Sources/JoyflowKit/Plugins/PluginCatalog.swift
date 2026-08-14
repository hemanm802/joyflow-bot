import Foundation

public enum PluginSection: String, Sendable, CaseIterable {
    case featured = "Featured"
    case agentOrchestration = "Agent Orchestration"
    case workspace = "Workspace"
    case communication = "Communication"
}

public enum PluginCatalog {
    /// Featured marketplace tiles shown first in Plugins.
    public static let featured: [ComposioToolkit] = [
        .init(slug: "gmail", name: "Gmail", description: "Connect to Gmail via Google's remote MCP server"),
        .init(
            slug: "googlecalendar",
            name: "Google Calendar",
            description: "Connect to Google Calendar via Google's remote MCP"
        ),
        .init(slug: "googledrive", name: "Google Drive", description: "Connect to Google Drive via Google's remote MCP"),
        .init(slug: "granola", name: "Granola", description: "Your meetings in your workflow"),
        .init(slug: "arize", name: "Arize", description: "Add Arize AX observability to LLM applications"),
        .init(slug: "atlan", name: "Atlan", description: "Atlan is the context layer for enterprise AI"),
        .init(slug: "awsagents", name: "AWS Agents", description: "Build, deploy, and operate AI agents on AWS"),
        .init(slug: "awssagemaker", name: "AWS SageMaker", description: "Build, train, and deploy AI models with AWS"),
    ]

    /// Already-bundled workspace connectors.
    public static let extras: [ComposioToolkit] = [
        .init(slug: "slack", name: "Slack", description: "Channels, DMs, and search"),
        .init(slug: "notion", name: "Notion", description: "Notes, databases, and pages"),
        .init(slug: "github", name: "GitHub", description: "Repos, issues, and pull requests"),
        .init(slug: "linear", name: "Linear", description: "Issues and project tracking"),
        .init(slug: "figma", name: "Figma", description: "Files, comments, and components"),
        .init(slug: "discord", name: "Discord", description: "Servers, channels, and messages"),
        .init(slug: "outlook", name: "Outlook", description: "Mail and calendar"),
        .init(slug: "jira", name: "Jira", description: "Issues and sprints"),
        .init(slug: "composio", name: "Composio", description: "Connect and operate 1000+ apps"),
        .init(slug: "context7", name: "Context7", description: "Up-to-date library docs for agents"),
        .init(slug: "trello", name: "Trello", description: "Boards, lists, and cards"),
        .init(slug: "asana", name: "Asana", description: "Tasks and team projects"),
        .init(slug: "dropbox", name: "Dropbox", description: "Files and shared folders"),
        .init(slug: "twitter", name: "X", description: "Posts, DMs, and search"),
        .init(slug: "hubspot", name: "HubSpot", description: "CRM, deals, and contacts"),
        .init(slug: "zoom", name: "Zoom", description: "Meetings and recordings"),
        .init(slug: "stripe", name: "Stripe", description: "Payments and customers"),
        .init(slug: "airtable", name: "Airtable", description: "Bases, tables, and records"),
        .init(slug: "salesforce", name: "Salesforce", description: "CRM objects and reports"),
        .init(slug: "twilio", name: "Twilio", description: "SMS, voice, and verify"),
        .init(slug: "confluence", name: "Confluence", description: "Spaces, pages, and comments"),
        .init(slug: "clickup", name: "ClickUp", description: "Tasks, docs, and sprints"),
        .init(slug: "googlesheets", name: "Google Sheets", description: "Spreadsheets and ranges"),
        .init(slug: "googledocs", name: "Google Docs", description: "Documents and comments"),
        .init(slug: "microsoftteams", name: "Microsoft Teams", description: "Chats, channels, and meetings"),
        .init(slug: "telegram", name: "Telegram", description: "Bots, chats, and messages"),
        .init(slug: "youtube", name: "YouTube", description: "Videos, playlists, and comments"),
        .init(slug: "linkedin", name: "LinkedIn", description: "Profiles, posts, and messaging"),
        .init(slug: "vercel", name: "Vercel", description: "Projects, deploys, and domains"),
        .init(slug: "supabase", name: "Supabase", description: "Database, auth, and storage"),
        .init(slug: "intercom", name: "Intercom", description: "Inbox, users, and articles"),
        .init(slug: "box", name: "Box", description: "Files and collaboration"),
    ]

    public static var allBundled: [ComposioToolkit] { featured + extras }

    public static var featuredSlugs: [String] { featured.map(\.slug) }
    public static var extraSlugs: [String] { extras.map(\.slug) }
    public static var bundledSlugs: [String] { allBundled.map(\.slug) }

    public static func contains(_ slug: String) -> Bool {
        allBundled.contains { $0.slug.caseInsensitiveCompare(slug) == .orderedSame }
    }

    public static func search(_ query: String) -> [ComposioToolkit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return allBundled }
        return allBundled.filter {
            $0.slug.lowercased().contains(needle) || $0.name.lowercased().contains(needle)
        }
    }

    public static func section(for slug: String) -> PluginSection {
        switch slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "gmail", "googlecalendar", "googledrive", "granola":
            .featured
        case "arize", "atlan", "awsagents", "awssagemaker", "composio", "context7":
            .agentOrchestration
        case "slack", "discord", "outlook", "microsoftteams", "telegram", "twitter":
            .communication
        default:
            .workspace
        }
    }

    public static func tools(in section: PluginSection, matching query: String) -> [ComposioToolkit] {
        search(query).filter { self.section(for: $0.slug) == section }
    }
}
