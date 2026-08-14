import Testing

@testable import JoyflowKit

struct PolicyEngineTests {
    @Test func defaultIsAsk() {
        #expect(PolicyEngine().defaultAction == .ask)
        #expect(PolicyEngine().decide(PolicyRequest(toolName: "run_shell", arguments: "{\"command\":\"ls\"}")).action == .ask)
        #expect(PolicyEngine().decide(PolicyRequest(toolName: "read_file", arguments: "{}")).action == .allow)
        #expect(PolicyEngine().decide(PolicyRequest(toolName: "search_knowledge", arguments: "{}")).action == .allow)
    }

    @Test func denylistWinsOverAllowRule() {
        let engine = PolicyEngine(
            rules: [ReviewRule(pattern: "rm", action: .allow)],
            defaultAction: .allow
        )
        #expect(engine.decide(PolicyRequest(toolName: "run_shell", arguments: "rm -rf /")).action == .deny)
        #expect(engine.decide(PolicyRequest(toolName: "run_shell", arguments: "diskutil eraseDisk")).action == .deny)
        #expect(engine.decide(PolicyRequest(toolName: "run_shell", arguments: ":(){ :|:& };:")).action == .deny)
        #expect(engine.decide(PolicyRequest(toolName: "write_file", arguments: "/System/Library/x")).action == .deny)
    }

    @Test func toolNamesAreSafe() {
        for name in [
            "run_shell", "write_file", "read_file", "list_dir", "composio_execute", "write_note", "control_mac",
        ] {
            #expect(ToolKind.isValidName(name))
        }
        #expect(!ToolKind.isValidName("run.shell"))
    }

    @Test func updateSoulIsMutating() {
        #expect(ToolCatalog.isMutating("update_soul"))
    }

    @Test func permissionModesHaveTitlesAndCycle() {
        #expect(ReviewAction.ask.title == "Ask first")
        #expect(ReviewAction.allow.title == "Always allow")
        #expect(ReviewAction.deny.title == "Block")
        #expect(ReviewAction.ask.cycled == .allow)
        #expect(ReviewAction.allow.cycled == .deny)
        #expect(ReviewAction.deny.cycled == .ask)
        #expect(ReviewAction.allCases.count == 3)
    }

    @Test func approvalCopyUsesFolderPath() {
        let pending = PendingApproval(
            id: "1",
            toolName: "attach_folder",
            arguments: #"{"path":"/Users/robert/Desktop","name":"Desktop"}"#,
            preview: "raw"
        )
        #expect(pending.displayTitle == "Attach a folder")
        #expect(pending.displayDetail.contains("Desktop"))
        #expect(pending.displayDetail.contains("/Users/robert/Desktop"))
    }
}
