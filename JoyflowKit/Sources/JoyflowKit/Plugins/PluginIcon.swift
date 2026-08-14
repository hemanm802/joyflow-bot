import Foundation

/// UI-free identity for a plugin mark. Views render `bundledImageData`; tests assert bytes.
public struct PluginIconRef: Sendable, Equatable {
    public var identifier: String
    public var fileName: String
    public var packSource: String

    public init(identifier: String, fileName: String, packSource: String) {
        self.identifier = identifier
        self.fileName = fileName
        self.packSource = packSource
    }
}

public enum PluginIcon {
    private static let catalog: [String: PluginIconRef] = [
        "gmail": .init(identifier: "plugin.gmail", fileName: "gmail.png", packSource: "iconify:logos"),
        "googlecalendar": .init(
            identifier: "plugin.googlecalendar",
            fileName: "googlecalendar.png",
            packSource: "iconify:logos"
        ),
        "googledrive": .init(identifier: "plugin.googledrive", fileName: "googledrive.png", packSource: "iconify:logos"),
        "granola": .init(identifier: "plugin.granola", fileName: "granola.png", packSource: "iconify:thesvg-color"),
        "arize": .init(identifier: "plugin.arize", fileName: "arize.png", packSource: "official-github"),
        "atlan": .init(identifier: "plugin.atlan", fileName: "atlan.png", packSource: "official-github"),
        "awsagents": .init(identifier: "plugin.awsagents", fileName: "awsagents.png", packSource: "iconify:logos"),
        "awssagemaker": .init(
            identifier: "plugin.awssagemaker",
            fileName: "awssagemaker.png",
            packSource: "iconify:skill-icons"
        ),
        "slack": .init(identifier: "plugin.slack", fileName: "slack.png", packSource: "iconify:logos"),
        "notion": .init(identifier: "plugin.notion", fileName: "notion.png", packSource: "iconify:logos"),
        "github": .init(identifier: "plugin.github", fileName: "github.png", packSource: "iconify:logos"),
        "linear": .init(identifier: "plugin.linear", fileName: "linear.png", packSource: "iconify:logos"),
        "figma": .init(identifier: "plugin.figma", fileName: "figma.png", packSource: "iconify:logos"),
        "discord": .init(identifier: "plugin.discord", fileName: "discord.png", packSource: "iconify:logos"),
        "outlook": .init(identifier: "plugin.outlook", fileName: "outlook.png", packSource: "iconify:vscode-icons"),
        "jira": .init(identifier: "plugin.jira", fileName: "jira.png", packSource: "iconify:logos"),
        "composio": .init(identifier: "plugin.composio", fileName: "composio.png", packSource: "iconify:thesvg-color"),
        "context7": .init(identifier: "plugin.context7", fileName: "context7.png", packSource: "iconify:vscode-icons"),
        "trello": .init(identifier: "plugin.trello", fileName: "trello.png", packSource: "iconify:logos"),
        "asana": .init(identifier: "plugin.asana", fileName: "asana.png", packSource: "iconify:logos"),
        "dropbox": .init(identifier: "plugin.dropbox", fileName: "dropbox.png", packSource: "iconify:logos"),
        "twitter": .init(identifier: "plugin.twitter", fileName: "twitter.png", packSource: "iconify:logos"),
        "hubspot": .init(identifier: "plugin.hubspot", fileName: "hubspot.png", packSource: "iconify:simple-icons"),
        "zoom": .init(identifier: "plugin.zoom", fileName: "zoom.png", packSource: "iconify:logos"),
        "stripe": .init(identifier: "plugin.stripe", fileName: "stripe.png", packSource: "iconify:logos"),
        "airtable": .init(identifier: "plugin.airtable", fileName: "airtable.png", packSource: "iconify:logos"),
        "salesforce": .init(identifier: "plugin.salesforce", fileName: "salesforce.png", packSource: "iconify:logos"),
        "twilio": .init(identifier: "plugin.twilio", fileName: "twilio.png", packSource: "iconify:logos"),
        "confluence": .init(identifier: "plugin.confluence", fileName: "confluence.png", packSource: "iconify:logos"),
        "clickup": .init(identifier: "plugin.clickup", fileName: "clickup.png", packSource: "iconify:simple-icons"),
        "googlesheets": .init(
            identifier: "plugin.googlesheets",
            fileName: "googlesheets.png",
            packSource: "iconify:simple-icons"
        ),
        "googledocs": .init(
            identifier: "plugin.googledocs",
            fileName: "googledocs.png",
            packSource: "iconify:simple-icons"
        ),
        "microsoftteams": .init(
            identifier: "plugin.microsoftteams",
            fileName: "microsoftteams.png",
            packSource: "iconify:logos"
        ),
        "telegram": .init(identifier: "plugin.telegram", fileName: "telegram.png", packSource: "iconify:logos"),
        "youtube": .init(identifier: "plugin.youtube", fileName: "youtube.png", packSource: "iconify:logos"),
        "linkedin": .init(identifier: "plugin.linkedin", fileName: "linkedin.png", packSource: "iconify:logos"),
        "vercel": .init(identifier: "plugin.vercel", fileName: "vercel.png", packSource: "iconify:simple-icons"),
        "supabase": .init(identifier: "plugin.supabase", fileName: "supabase.png", packSource: "iconify:simple-icons"),
        "intercom": .init(identifier: "plugin.intercom", fileName: "intercom.png", packSource: "iconify:simple-icons"),
        "box": .init(identifier: "plugin.box", fileName: "box.png", packSource: "iconify:simple-icons"),
    ]

    public static func lookup(_ slug: String) -> PluginIconRef? {
        catalog[normalize(slug)]
    }

    public static func identifier(for slug: String) -> String? {
        lookup(slug)?.identifier
    }

    public static func packSource(for slug: String) -> String? {
        lookup(slug)?.packSource
    }

    /// Raster bytes for a bundled slug. Nil when the slug is unknown or the PNG is missing.
    public static func bundledImageData(for slug: String) -> Data? {
        guard let ref = lookup(slug) else { return nil }
        let stem = (ref.fileName as NSString).deletingPathExtension
        let ext = (ref.fileName as NSString).pathExtension
        let urls = [
            Bundle.module.url(forResource: stem, withExtension: ext, subdirectory: "Plugins"),
            Bundle.module.url(forResource: stem, withExtension: ext),
        ]
        for url in urls.compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url), !data.isEmpty {
                return data
            }
        }
        return nil
    }

    public static func normalize(_ slug: String) -> String {
        slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
