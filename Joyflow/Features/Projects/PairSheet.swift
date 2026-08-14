import AppKit
import CoreImage.CIFilterBuiltins
import JoyflowKit
import SwiftUI

struct PairSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pair iPhone")
                .font(.system(size: 20, weight: .semibold))
            Text("Copy the link and paste it on the phone. The devices do not need the same Wi-Fi. Keep Joyflow open on this Mac.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let envelope = app.pairEnvelope {
                pairCard(envelope)
            }

            if let error = app.pairListenerError, !error.isEmpty {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("New code") {
                    copied = false
                    _ = app.beginPair()
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 460)
        .background(Theme.card)
        .onAppear {
            if app.pairEnvelope == nil {
                _ = app.beginPair()
            } else {
                app.startPublicPairLink()
            }
        }
        .accessibilityIdentifier("pair.sheet")
    }

    private func pairCard(_ envelope: PairEnvelope) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text(envelope.offer.code)
                    .font(.system(size: 32, weight: .semibold).monospaced())
                    .textSelection(.enabled)
                    .accessibilityIdentifier("pair.code")
                if let origin = envelope.origin {
                    Text("Ready anywhere · \(origin)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                } else if let host = PairLAN.hosts(from: envelope.host).first, let port = envelope.port {
                    Text("On this network · \(host):\(port)\nOpening a public link…")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("Join a network, or install cloudflared for pairing off Wi-Fi.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.danger)
                }
                Text(envelope.url.absoluteString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                    .lineLimit(4)
                Button(copied ? "Copied" : "Copy link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(envelope.url.absoluteString, forType: .string)
                    copied = true
                }
            }
            if let image = qrImage(for: envelope.url) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 112, height: 112)
                    .padding(6)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func qrImage(for url: URL) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
