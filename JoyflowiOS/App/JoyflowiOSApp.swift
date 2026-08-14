import JoyflowKit
import SwiftUI

@main
struct JoyflowiOSApp: App {
    @State private var app = PhoneModel()
    @State private var chat = PhoneChat()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(chat)
                .preferredColorScheme(app.appearance.colorScheme)
                .tint(Theme.accent)
                .onOpenURL { url in
                    app.handleJoyflowURL(url)
                    chat.load(app: app)
                }
        }
    }
}
