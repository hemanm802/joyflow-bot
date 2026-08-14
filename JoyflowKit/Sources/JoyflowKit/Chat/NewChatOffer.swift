import Foundation

/// Menu shown after + — create first, then matching projects.
public struct NewChatOffer: Sendable, Equatable {
    public var createTitle: String
    public var matches: [String]

    public init(createTitle: String, matches: [String]) {
        self.createTitle = createTitle
        self.matches = matches
    }

    public static func build(query: String, names: [String]) -> NewChatOffer {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let create = trimmed.isEmpty ? "Create new Project" : "Create “\(trimmed)”"
        let matches: [String]
        if trimmed.isEmpty {
            matches = names
        } else {
            matches = names.filter { $0.localizedCaseInsensitiveContains(trimmed) }
        }
        return NewChatOffer(createTitle: create, matches: matches)
    }

    public var createName: String {
        let prefix = "Create “"
        if createTitle.hasPrefix(prefix), createTitle.hasSuffix("”") {
            return String(createTitle.dropFirst(prefix.count).dropLast())
        }
        return "Untitled"
    }
}
