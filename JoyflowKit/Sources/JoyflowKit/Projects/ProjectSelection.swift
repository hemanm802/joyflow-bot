import Foundation

public enum ProjectSelection {
    public static func filter(_ projects: [ProjectManifest], query: String) -> [ProjectManifest] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return projects }
        return projects.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    public static func resolve(current: UUID?, available: [UUID]) -> UUID? {
        if let current, available.contains(current) { return current }
        return available.first
    }
}
