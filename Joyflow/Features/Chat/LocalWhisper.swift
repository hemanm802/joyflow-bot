import Foundation
import JoyflowKit
import WhisperKit

enum LocalWhisper {
    static func supportFolder(root: URL) -> URL {
        LocalWhisperCatalog.folder(in: root.appendingPathComponent("Whisper", isDirectory: true), id: LocalWhisperCatalog.tinyEN.id)
    }

    /// Downloads the WhisperKit Core ML variant. A ggml `model.bin` is not an install.
    static func download(to directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = try await WhisperKit.download(
            variant: LocalWhisperCatalog.tinyEN.variant,
            downloadBase: directory
        )
        guard LocalWhisperCatalog.isInstalled(at: directory) else {
            throw TranscriptionError.missingLocalModel
        }
    }

    static func transcribe(audio: Data, settings: SpeechSettings) async throws -> String {
        guard LocalWhisperCatalog.isInstalled(at: settings.localModelDirectory) else {
            throw TranscriptionError.missingLocalModel
        }
        return try await WhisperLocalRuntime.transcribe(audio: audio, folder: settings.localModelDirectory)
    }
}
