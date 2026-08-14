import AppKit
import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            JoyflowMark(size: 64)
            Text("Joyflow")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Version \(version)")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            Text("A Mac teammate that lives in folders you keep.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Check for Updates…") {
                SparkleUpdater.shared.checkForUpdates()
            }
            .padding(.top, 4)
            Link("Buy me a coffee", destination: Self.coffeeURL)
                .font(.system(size: 13))
                .foregroundStyle(Theme.link)
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .padding(.top, 8)
        }
        .padding(28)
        .frame(width: 320)
        .background(Theme.background)
        .accessibilityIdentifier("about.sheet")
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private static let coffeeURL = URL(string: "https://buymeacoffee.com/robcourson")!
}
