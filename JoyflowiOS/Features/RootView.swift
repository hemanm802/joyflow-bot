import JoyflowKit
import SwiftUI

struct RootView: View {
    @Environment(PhoneModel.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    ProjectsHome(pushesChat: false)
                        .navigationSplitViewColumnWidth(min: 248, ideal: 280, max: 340)
                } detail: {
                    ChatScreen()
                }
                .navigationSplitViewStyle(.balanced)
                .toolbar(removing: .sidebarToggle)
                .tint(Theme.accent)
                .accessibilityIdentifier("ios.split")
            } else {
                NavigationStack {
                    ProjectsHome(pushesChat: true)
                }
                .tint(Theme.accent)
            }
        }
        .background(Theme.surface.ignoresSafeArea())
        .tint(Theme.accent)
        .accessibilityIdentifier("ios.root")
    }
}
