import Foundation

/// Legacy two-stop pair. New chats use `ProjectMark` instead.
public struct GradientOrb: Sendable, Equatable {
    public var startHex: UInt32
    public var endHex: UInt32

    public init(startHex: UInt32, endHex: UInt32) {
        self.startHex = startHex
        self.endHex = endHex
    }

    public static let palette: [UInt32] = ProjectMark.all.map(\.backgroundHex)

    public static func colors(for id: UUID) -> GradientOrb {
        let mark = ProjectMark.assigned(for: id)
        return GradientOrb(startHex: mark.backgroundHex, endHex: mark.ink.hex)
    }
}
