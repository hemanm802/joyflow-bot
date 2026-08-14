import Foundation
import Testing

@testable import JoyflowKit

struct TranscriptFollowTests {
    @Test func followOnlyWhenPinnedToBottom() {
        #expect(
            TranscriptFollow.isPinnedToBottom(
                contentOffsetY: 0,
                contentHeight: 2000,
                viewportHeight: 400
            ) == false
        )
        #expect(
            TranscriptFollow.shouldFollow(
                pinnedToBottom: TranscriptFollow.isPinnedToBottom(
                    contentOffsetY: 0,
                    contentHeight: 2000,
                    viewportHeight: 400
                )
            ) == false
        )
        #expect(
            TranscriptFollow.isPinnedToBottom(
                contentOffsetY: 1600,
                contentHeight: 2000,
                viewportHeight: 400
            )
        )
        #expect(
            TranscriptFollow.shouldFollow(
                pinnedToBottom: TranscriptFollow.isPinnedToBottom(
                    contentOffsetY: 1600,
                    contentHeight: 2000,
                    viewportHeight: 400
                )
            )
        )
        #expect(
            TranscriptFollow.isPinnedToBottom(
                contentOffsetY: 1560,
                contentHeight: 2000,
                viewportHeight: 400
            )
        )
    }

    @Test func permissionsModeFitsOneLine() {
        for mode in ReviewAction.allCases {
            #expect(LayoutTokens.accountMenuFitsOneLine(title: "Permissions", trailing: mode.title))
        }
        #expect(LayoutTokens.accountMenuWidth >= 280)
        #expect(ReviewAction.ask.title == "Ask first")
        #expect(ReviewAction.allow.title == "Always allow")
        #expect(ReviewAction.deny.title == "Block")
    }
}
