import Foundation
import Testing

@testable import JoyflowKit

struct ProjectMarkTests {
    @Test func assignmentIsDeterministic() {
        let id = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!
        let first = ProjectMark.assigned(for: id)
        let again = ProjectMark.assigned(for: id)
        #expect(first == again)
        #expect(ProjectMark.all.contains(first))
    }

    @Test func differentIdsCanDiverge() {
        let a = ProjectMark.assigned(for: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let b = ProjectMark.assigned(for: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        #expect(a.id != b.id || a.backgroundHex != b.backgroundHex)
    }

    @Test func parseAndResolve() {
        #expect(ProjectMark.parse("mark.ink")?.id == "ink")
        #expect(ProjectMark.parse("stone") == nil)
        #expect(ProjectMark.parse("avatar") == nil)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        #expect(ProjectMark.resolved(icon: "mark.sea", projectID: id).id == "sea")
        #expect(ProjectMark.resolved(icon: "stone", projectID: id) == ProjectMark.assigned(for: id))
    }

    @Test func inkContrastsOnEveryField() {
        for mark in ProjectMark.all {
            let ratio = ColorTokens.contrastRatio(mark.ink.hex, mark.backgroundHex)
            #expect(ratio >= 4.5, "\(mark.id) contrast \(ratio)")
            for banned in ColorTokens.bannedTanHexes {
                #expect(mark.backgroundHex != banned)
            }
        }
    }

    @Test func tenBuiltInPictures() {
        #expect(ProjectMark.all.count == 10)
        #expect(Set(ProjectMark.all.map(\.id)).count == 10)
        #expect(ProjectMark.all.contains { $0.ink == .dark })
        #expect(ProjectMark.all.contains { $0.ink == .light })
        #expect(Set(ProjectMark.all.map(\.id)) == Set([
            "ink", "graphite", "navy", "indigo", "pine", "wine", "rust", "slate", "sea", "bone",
        ]))
    }

    @Test func vividFieldsAreSaturated() {
        for mark in ProjectMark.all where ProjectMark.vividIDs.contains(mark.id) {
            let chroma = ColorTokens.saturation(mark.backgroundHex)
            #expect(chroma >= 0.70, "\(mark.id) saturation \(chroma)")
        }
        #expect(ColorTokens.saturation(ProjectMark.parse("mark.navy")!.backgroundHex) > 0.80)
        #expect(ColorTokens.saturation(0x1A2744) < 0.70)
    }
}
