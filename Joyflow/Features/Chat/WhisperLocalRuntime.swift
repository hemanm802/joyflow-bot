import Foundation
import JoyflowKit
import WhisperKit

enum WhisperLocalRuntime {
    static func transcribe(audio: Data, folder: URL) async throws -> String {
        guard let modelFolder = LocalWhisperCatalog.resolvedModelFolder(in: folder) else {
            throw TranscriptionError.missingLocalModel
        }
        let wav = folder.appendingPathComponent("clip-\(UUID().uuidString).wav")
        try audio.write(to: wav)
        defer { try? FileManager.default.removeItem(at: wav) }
        let config = WhisperKitConfig(
            model: LocalWhisperCatalog.tinyEN.variant,
            modelFolder: modelFolder.path,
            download: false
        )
        let pipe = try await WhisperKit(config)
        let results = try await pipe.transcribe(audioPath: wav.path)
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { throw TranscriptionError.invalidResponse }
        return text
    }

    static func prefetch(into folder: URL) async throws {
        try await LocalWhisper.download(to: folder)
    }
}
