import Foundation

public enum ReviewAction: String, Codable, Sendable, Equatable, CaseIterable {
    case ask
    case allow
    case deny

    public var title: String {
        switch self {
        case .ask: "Ask first"
        case .allow: "Always allow"
        case .deny: "Block"
        }
    }

    public var detail: String {
        switch self {
        case .ask: "Ask before writes, shell, and folder attaches."
        case .allow: "Run permitted actions without asking. The denylist still blocks destructive commands."
        case .deny: "Block writes, shell, and folder attaches. You can still allow a prompt by hand."
        }
    }

    public var cycled: ReviewAction {
        switch self {
        case .ask: .allow
        case .allow: .deny
        case .deny: .ask
        }
    }
}

public struct ReviewRule: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var pattern: String
    public var action: ReviewAction

    public init(id: UUID = UUID(), pattern: String, action: ReviewAction) {
        self.id = id
        self.pattern = pattern
        self.action = action
    }
}

public struct PolicyDecision: Sendable, Equatable {
    public var action: ReviewAction
    public var reason: String
}

public struct PolicyRequest: Sendable, Equatable {
    public var toolName: String
    public var arguments: String

    public var haystack: String {
        "\(toolName) \(arguments)".lowercased()
    }
}

public struct PolicyEngine: Sendable {
    public var rules: [ReviewRule]
    public var defaultAction: ReviewAction

    public init(rules: [ReviewRule] = [], defaultAction: ReviewAction = .ask) {
        self.rules = rules
        self.defaultAction = defaultAction
    }

    public func decide(_ request: PolicyRequest) -> PolicyDecision {
        if let hit = Denylist.match(request) {
            return PolicyDecision(action: .deny, reason: hit)
        }
        for rule in rules {
            let pattern = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pattern.isEmpty else { continue }
            if request.haystack.contains(pattern.lowercased()) {
                return PolicyDecision(action: rule.action, reason: "rule:\(pattern)")
            }
        }
        if !ToolKind.mutating.contains(request.toolName) {
            return PolicyDecision(action: .allow, reason: "read")
        }
        return PolicyDecision(action: defaultAction, reason: "default")
    }
}

public enum Denylist {
    public static let patterns: [String] = [
        "rm -rf /",
        "rm -rf /*",
        "diskutil erase",
        "mkfs",
        ":(){ :|:& };:",
        "/library/apple",
    ]

    public static func match(_ request: PolicyRequest) -> String? {
        let hay = request.haystack
        if let found = patterns.first(where: { hay.contains($0) }) {
            return "denylist:\(found)"
        }
        if request.toolName == "run_shell", destroysSystemPath(hay) {
            return "denylist:protected-path"
        }
        if request.toolName == "write_file" || request.toolName == "attach_folder",
            writesProtectedPath(request.arguments)
        {
            return "denylist:protected-path"
        }
        return nil
    }

    private static func destroysSystemPath(_ hay: String) -> Bool {
        let destructive = hay.contains("rm ") || hay.contains("rm\t") || hay.contains("unlink")
        guard destructive else { return false }
        return ["/system", "/usr", "/bin", "/sbin", "/library/apple"].contains { hay.contains($0) }
    }

    private static func writesProtectedPath(_ arguments: String) -> Bool {
        let lower = arguments.lowercased()
        let prefixes = ["/system", "/usr", "/bin", "/sbin", "/library/apple"]
        return prefixes.contains { lower.contains($0 + "/") || lower.contains($0 + "\"") || lower.hasSuffix($0) }
    }
}

public enum ToolKind {
    public static let computer: Set<String> = ["run_shell", "write_file", "read_file", "list_dir"]
    public static let mutating: Set<String> = [
        "run_shell", "write_file", "update_soul", "promote_to_commons", "attach_folder", "composio_execute",
        "control_mac",
    ]

    public static func isValidName(_ name: String) -> Bool {
        let regex = try? NSRegularExpression(pattern: "^[a-zA-Z0-9_-]+$")
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return regex?.firstMatch(in: name, range: range) != nil
    }
}
