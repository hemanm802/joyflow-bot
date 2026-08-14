import Foundation

public enum ToolCatalog {
    public static let definitions: [ToolDefinition] = [
        tool("read_file", "Read a UTF-8 file from the computer", ["path": "string"], ["path"]),
        tool("write_file", "Write a UTF-8 file on the computer", ["path": "string", "contents": "string"], ["path", "contents"]),
        tool(
            "list_dir",
            "List a folder on this Mac. Home, Desktop, Documents, Code, and other user folders work. System folders stay blocked.",
            ["path": "string"],
            ["path"]
        ),
        tool("run_shell", "Run a shell command in the project workspace", ["command": "string"], ["command"]),
        tool("search_knowledge", "Search this Project and linked Commons", ["query": "string"], ["query"]),
        tool("write_note", "Add a durable note to knowledge/", ["title": "string", "body": "string"], ["title", "body"]),
        tool("write_memory", "Append a durable memory", ["text": "string"], ["text"]),
        tool("update_soul", "Replace SOUL.md after the user approves", ["text": "string"], ["text"]),
        tool("promote_to_commons", "Copy a note into Commons and link it", ["slug": "string"], ["slug"]),
        tool("list_wiki", "List knowledge titles", [:], []),
        tool("add_link", "Add a URL resource to the Project", ["title": "string", "url": "string"], ["title", "url"]),
        tool(
            "attach_folder",
            "Attach a folder on this Mac to the project so list/read/write can use it. Path must already exist.",
            ["name": "string", "path": "string"],
            ["name", "path"]
        ),
        tool(
            "composio_execute",
            "Execute a Composio tool. Account is resolved from connected apps for this Mac.",
            ["tool_slug": "string", "arguments_json": "string"],
            ["tool_slug"]
        ),
        tool(
            "control_mac",
            "Inspect or move apps on this Mac. Actions: list_displays, list_apps, move_app. For move_app pass app (for example Dia) and display (macbook, built-in, or a screen name). Do not wander the project folder for window tasks.",
            ["action": "string", "app": "string", "display": "string"],
            ["action"]
        ),
    ]

    public static func isMutating(_ name: String) -> Bool {
        ToolKind.mutating.contains(name)
    }

    private static func tool(
        _ name: String,
        _ description: String,
        _ properties: [String: String],
        _ required: [String]
    ) -> ToolDefinition {
        ToolDefinition(name: name, description: description, parametersJSON: .objectParams(properties, required: required))
    }
}

extension String {
    fileprivate static func objectParams(_ properties: [String: String], required: [String]) -> String {
        ToolDefinition.objectParams(properties, required: required)
    }
}
