import JoyflowKit
import SwiftUI

@main
struct JoyflowApp: App {
    @State private var app = AppModel()
    @State private var runtime = ChatRuntime()
    @State private var pairRemote: PairRemoteController?

    init() {
        ScreenshotSupport.installLaunchHook()
    }

    var body: some Scene {
        WindowGroup(JoyflowKit.name) {
            RootView()
                .environment(app)
                .environment(runtime)
                .frame(minWidth: 640, minHeight: 420)
                .preferredColorScheme(app.appearance.colorScheme)
                .tint(Theme.tint)
                .background(Theme.background)
                .onAppear {
                    SparkleUpdater.shared.startIfNeeded()
                    ScreenshotSupport.scheduleCaptureIfRequested()
                    if pairRemote == nil {
                        let controller = PairRemoteController(box: app.pairControl)
                        controller.start(app: app, runtime: runtime)
                        pairRemote = controller
                    }
                    app.startPublicPairLink()
                }
                .onOpenURL { app.handleJoyflowURL($0) }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1240, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project") {
                    app.beginCreateProject()
                }
                .keyboardShortcut("n", modifiers: .command)

            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    SparkleUpdater.shared.checkForUpdates()
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    app.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
                Button("Plugins…") {
                    app.pluginsOpen = true
                }
                Button("Search") {
                    app.openSearch()
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(app)
                .environment(runtime)
                .frame(minWidth: 840, minHeight: 560)
                .preferredColorScheme(app.appearance.colorScheme)
                .tint(Theme.tint)
                .background(Theme.card)
        }
    }
}
