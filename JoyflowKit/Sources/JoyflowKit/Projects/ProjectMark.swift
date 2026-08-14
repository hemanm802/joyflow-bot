import Foundation

public enum MarkInk: String, Sendable, Equatable, Codable {
    case light
    case dark

    public var hex: UInt32 {
        switch self {
        case .light: 0xFFFFFF
        case .dark: 0x111111
        }
    }
}

/// Built-in project picture: the Joyflow mark on a solid field.
public struct ProjectMark: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var backgroundHex: UInt32
    public var ink: MarkInk

    public init(id: String, name: String, backgroundHex: UInt32, ink: MarkInk) {
        self.id = id
        self.name = name
        self.backgroundHex = backgroundHex
        self.ink = ink
    }

    public var iconValue: String { "mark.\(id)" }

    public static let all: [ProjectMark] = [
        .init(id: "ink", name: "Ink", backgroundHex: 0x111111, ink: .light),
        .init(id: "graphite", name: "Graphite", backgroundHex: 0x2C2C30, ink: .light),
        .init(id: "navy", name: "Navy", backgroundHex: 0x1D4ED8, ink: .light),
        .init(id: "indigo", name: "Indigo", backgroundHex: 0x6D28D9, ink: .light),
        .init(id: "pine", name: "Pine", backgroundHex: 0x047857, ink: .light),
        .init(id: "wine", name: "Wine", backgroundHex: 0xBE123C, ink: .light),
        .init(id: "rust", name: "Rust", backgroundHex: 0xC2410C, ink: .light),
        .init(id: "slate", name: "Slate", backgroundHex: 0x4338CA, ink: .light),
        .init(id: "sea", name: "Sea", backgroundHex: 0x0E7490, ink: .light),
        .init(id: "bone", name: "Bone", backgroundHex: 0xFACC15, ink: .dark),
    ]

    public static let vividIDs: Set<String> = [
        "navy", "indigo", "pine", "wine", "rust", "slate", "sea", "bone",
    ]

    public static func parse(_ icon: String) -> ProjectMark? {
        guard icon.hasPrefix("mark.") else { return nil }
        let slug = String(icon.dropFirst(5))
        return all.first { $0.id == slug }
    }

    public static func assigned(for id: UUID) -> ProjectMark {
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return all[Int(hash % UInt64(all.count))]
    }

    public static func resolved(icon: String, projectID: UUID) -> ProjectMark {
        parse(icon) ?? assigned(for: projectID)
    }

    public static func isMarkIcon(_ icon: String) -> Bool {
        parse(icon) != nil
    }
}
