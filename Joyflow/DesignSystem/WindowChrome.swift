import SwiftUI

struct WindowChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbar(removing: .title)
            .background(Theme.background)
            .ignoresSafeArea(.container, edges: .top)
    }
}

extension View {
    func joyflowWindowChrome() -> some View {
        modifier(WindowChrome())
    }
}
