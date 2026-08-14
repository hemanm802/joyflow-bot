import JoyflowKit
import SwiftUI
import UIKit

struct PairScreen: View {
    @Environment(PhoneModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var pasted = ""
    @State private var code = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Copy the link from Pair iPhone on the Mac, or scan the QR code. It works on this Wi-Fi or over the internet. After pair, chats run on the Mac.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let binding = app.pairBinding {
                        pairedCard(binding)
                    }

                    pasteCard
                    codeCard

                    if let error = app.pairError, !error.isEmpty {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(5)
                            .accessibilityIdentifier("ios.pair.error")
                    }

                    if !app.pairStatus.isEmpty {
                        Text(app.pairStatus)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("Pair desktop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.chrome)
                }
            }
            .disabled(app.pairBusy)
            .overlay {
                if app.pairBusy {
                    ProgressView()
                        .controlSize(.large)
                }
            }
        }
        .accessibilityIdentifier("ios.pair")
    }

    private func pairedCard(_ binding: PairBinding) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paired")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(binding.code)
                .font(.system(size: 22, weight: .semibold).monospaced())
            Toggle("Run chats on the Mac", isOn: Bindable(app).runOnPairedMac)
                .tint(Theme.chrome)
            HStack(spacing: 10) {
                pairButton("Pull from desktop") {
                    Task { await app.pullFromDesktop() }
                }
                pairButton("Push to desktop") {
                    Task { await app.pushToDesktop() }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var pasteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste pair link")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Button {
                Task { await app.pasteAndPair() }
            } label: {
                Text("Paste and pair")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .foregroundStyle(Theme.chrome)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ios.pair.paste")

            TextField("joyflow://pair?…", text: $pasted, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.none)
                .lineLimit(3...6)
                .padding(12)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            pairButton("Accept link") {
                Task { await app.acceptPasted(pasted) }
            }
            .accessibilityIdentifier("ios.pair.accept")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var codeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Or type the Mac code")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            TextField("AB12CD", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(12)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onChange(of: code) { _, value in
                    let filtered = value.uppercased().filter { $0.isLetter || $0.isNumber }
                    if filtered != value { code = String(filtered.prefix(6)) }
                    else if value.count > 6 { code = String(value.prefix(6)) }
                }
            pairButton("Pair with code") {
                Task { await app.acceptTypedCode(code) }
            }
            .accessibilityIdentifier("ios.pair.code")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func pairButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .foregroundStyle(Theme.chrome)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
