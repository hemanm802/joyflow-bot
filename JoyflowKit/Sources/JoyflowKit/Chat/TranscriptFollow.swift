import Foundation

/// Whether the transcript should pin to the live answer.
/// Follow only when the user is already at (or back at) the bottom.
public enum TranscriptFollow: Sendable {
    public static let bottomSlop: CGFloat = 48

    public static func isPinnedToBottom(
        contentOffsetY: CGFloat,
        contentHeight: CGFloat,
        viewportHeight: CGFloat,
        slop: CGFloat = bottomSlop
    ) -> Bool {
        let maxOffset = max(0, contentHeight - viewportHeight)
        return contentOffsetY >= maxOffset - slop
    }

    public static func shouldFollow(pinnedToBottom: Bool) -> Bool {
        pinnedToBottom
    }
}
