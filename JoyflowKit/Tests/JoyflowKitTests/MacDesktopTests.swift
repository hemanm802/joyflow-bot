import Foundation
import Testing

@testable import JoyflowKit

struct MacDesktopTests {
    private let screens = [
        MacDesktop.DisplayInfo(name: "Built-in Retina Display", isBuiltin: true, width: 1728, height: 1117, x: 0, y: 0),
        MacDesktop.DisplayInfo(name: "LG UltraFine", isBuiltin: false, width: 2560, height: 1440, x: -2560, y: 0),
    ]

    @Test func macbookQueryPicksBuiltin() {
        let picked = MacDesktop.resolveDisplay("macbook", in: screens)
        #expect(picked?.isBuiltin == true)
        #expect(picked?.name == "Built-in Retina Display")
        #expect(MacDesktop.resolveDisplay("built-in", in: screens)?.isBuiltin == true)
        #expect(MacDesktop.resolveDisplay("", in: screens)?.isBuiltin == true)
        #expect(MacDesktop.isBuiltinQuery("my MacBook screen"))
    }

    @Test func externalQueryPicksNonBuiltin() {
        let picked = MacDesktop.resolveDisplay("external monitor", in: screens)
        #expect(picked?.isBuiltin == false)
        #expect(picked?.name == "LG UltraFine")
        #expect(MacDesktop.resolveDisplay("LG", in: screens)?.name == "LG UltraFine")
    }

    @Test func matchAppFindsDia() {
        #expect(MacDesktop.matchApp("dia", in: ["Safari", "Dia", "Finder"]) == "Dia")
        #expect(MacDesktop.matchApp("Dia Browser", in: ["Dia"]) == "Dia")
        #expect(MacDesktop.matchApp("", in: ["Dia"]) == nil)
    }

    @Test func displaySummaryMarksMacBook() {
        #expect(screens[0].summary.contains("MacBook"))
        #expect(screens[0].summary.contains("1728×1117"))
        #expect(!screens[1].summary.contains("MacBook"))
    }

    @Test func osascriptIsNotDenylisted() {
        let engine = PolicyEngine(defaultAction: .allow)
        let script = PolicyRequest(
            toolName: "run_shell",
            arguments: #"{"command":"/usr/bin/osascript -e 'tell application \"Dia\" to activate'"}"#
        )
        #expect(engine.decide(script).action == .allow)
        #expect(
            engine.decide(
                PolicyRequest(toolName: "control_mac", arguments: #"{"action":"move_app","app":"Dia","display":"macbook"}"#)
            ).action == .allow
        )
        #expect(
            engine.decide(PolicyRequest(toolName: "run_shell", arguments: "rm -rf /usr/bin")).action == .deny
        )
    }

    @Test func controlMacIsACatalogTool() {
        #expect(ToolKind.isValidName("control_mac"))
        #expect(ToolCatalog.isMutating("control_mac"))
        #expect(ToolCatalog.definitions.contains { $0.name == "control_mac" })
        #expect(ReplyNudge.stepBudgetMessage.contains("Do not call tools"))
        let pending = PendingApproval(
            id: "1",
            toolName: "control_mac",
            arguments: #"{"action":"move_app","app":"Dia","display":"macbook"}"#,
            preview: "raw"
        )
        #expect(pending.displayTitle == "Move a Mac app")
        #expect(pending.displayDetail.contains("Dia"))
        #expect(pending.displayDetail.contains("macbook"))
    }

    @Test func dispatcherListDisplays() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "joyflow-desktop-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileProjectStore(rootURL: root)
        let project = try store.createProject(name: "Desk")
        let computer = try ComputerRouter.computer(
            .local,
            workspace: store.layout(for: project.id).workspace,
            credentials: .empty
        )
        let dispatcher = ToolDispatcher(store: store, projectID: project.id, computer: computer)
        let listed = try await dispatcher.execute(
            name: "control_mac",
            argumentsJSON: #"{"action":"list_displays"}"#
        )
        #if os(macOS)
        #expect(listed.contains("×"))
        #else
        #expect(listed.contains("Mac"))
        #endif
    }
}
