import Foundation
import Testing

@testable import JoyflowKit

struct TranscriptionTests {
    @Test func cloudRequestIsWhisperTranscriptionsMultipart() throws {
        let wav = AudioWAV.silent()
        #expect(wav.starts(with: Array("RIFF".utf8)))
        let settings = SpeechSettings(
            engine: .whisperAPI,
            apiKey: "sk-test",
            model: "whisper-1",
            baseURL: "https://api.openai.com/v1",
            localModelDirectory: FileManager.default.temporaryDirectory
        )
        let request = try TranscriptionRequestBuilder.cloudRequest(
            audio: wav,
            filename: "speech.wav",
            mimeType: "audio/wav",
            settings: settings,
            boundary: "JoyflowTestBoundary"
        )
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/audio/transcriptions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") == true)
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("name=\"model\""))
        #expect(body.contains("whisper-1"))
        #expect(body.contains("name=\"file\""))
        #expect(body.contains("filename=\"speech.wav\""))
        #expect(body.contains("Content-Type: audio/wav"))
        #expect((request.httpBody ?? Data()).count > 64)
    }

    @Test func routerCloudReturnsParsedText() async throws {
        let wav = AudioWAV.silent()
        let settings = SpeechSettings(
            engine: .whisperAPI,
            apiKey: "sk-live",
            model: "gpt-4o-transcribe",
            baseURL: "https://api.openai.com",
            localModelDirectory: FileManager.default.temporaryDirectory
        )
        nonisolated(unsafe) var captured: URLRequest?
        let router = TranscriptionRouter(
            transport: { request in
                captured = request
                let data = Data(#"{"text":"hello from cloud"}"#.utf8)
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (data, response)
            },
            local: { _, _ in "should not run" }
        )
        let phrase = try await router.transcribe(audio: wav, settings: settings)
        #expect(phrase == "hello from cloud")
        #expect(captured?.url?.path.hasSuffix("/audio/transcriptions") == true)
        #expect(captured?.httpMethod == "POST")
        #expect(VoiceDraft.fill(existing: "", transcript: phrase) == "hello from cloud")
    }

    @Test func localMissingModelFailsClosed() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("joyflow-no-whisper-\(UUID().uuidString)")
        let settings = SpeechSettings(engine: .local, localModelDirectory: missing)
        let router = TranscriptionRouter(
            transport: { _ in throw TranscriptionError.invalidResponse },
            local: { _, _ in "should not run" }
        )
        await #expect(throws: TranscriptionError.missingLocalModel) {
            try await router.transcribe(audio: AudioWAV.silent(), settings: settings)
        }
    }

    @Test func ggmlModelBinIsNotInstalled() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("joyflow-ggml-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data([0x01]).write(to: dir.appendingPathComponent("model.bin"))
        try Data([0x7B]).write(to: dir.appendingPathComponent("config.json"))
        #expect(!LocalWhisperCatalog.isInstalled(at: dir))
        #expect(LocalWhisperCatalog.resolvedModelFolder(in: dir) == nil)
        let settings = SpeechSettings(engine: .local, localModelDirectory: dir)
        let router = TranscriptionRouter(
            transport: { _ in throw TranscriptionError.invalidResponse },
            local: { _, _ in "should not run" }
        )
        await #expect(throws: TranscriptionError.missingLocalModel) {
            try await router.transcribe(audio: AudioWAV.silent(), settings: settings)
        }
    }

    @Test func coreMLBundlesCountAsInstalledAndFillComposer() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("joyflow-whisper-\(UUID().uuidString)")
        let nested = dir.appendingPathComponent("openai_whisper-tiny.en", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data([0x01]).write(to: dir.appendingPathComponent("model.bin"))
        #expect(!LocalWhisperCatalog.isInstalled(at: dir))
        for name in LocalWhisperCatalog.requiredCoreMLBundles {
            try FileManager.default.createDirectory(at: nested.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        #expect(LocalWhisperCatalog.containsCoreML(at: nested))
        #expect(LocalWhisperCatalog.isInstalled(at: dir))
        #expect(
            LocalWhisperCatalog.resolvedModelFolder(in: dir)?.standardizedFileURL.path
                == nested.standardizedFileURL.path
        )
        let settings = SpeechSettings(engine: .local, localModelDirectory: dir)
        let router = TranscriptionRouter(
            transport: { _ in throw TranscriptionError.invalidResponse },
            local: { _, _ in "known phrase" }
        )
        let spoken = try await router.transcribe(audio: AudioWAV.silent(), settings: settings)
        #expect(spoken == "known phrase")
        #expect(VoiceDraft.fill(existing: "Hi", transcript: spoken) == "Hi known phrase")
    }

    @Test func missingKeyAndEmptyAudioFail() {
        let settings = SpeechSettings(
            engine: .whisperAPI,
            apiKey: "",
            localModelDirectory: FileManager.default.temporaryDirectory
        )
        #expect(throws: TranscriptionError.missingAPIKey) {
            try TranscriptionRequestBuilder.cloudRequest(
                audio: AudioWAV.silent(),
                filename: "a.wav",
                mimeType: "audio/wav",
                settings: settings
            )
        }
        #expect(throws: TranscriptionError.emptyAudio) {
            try TranscriptionRequestBuilder.cloudRequest(
                audio: Data(),
                filename: "a.wav",
                mimeType: "audio/wav",
                settings: SpeechSettings(
                    engine: .whisperAPI,
                    apiKey: "k",
                    localModelDirectory: FileManager.default.temporaryDirectory
                )
            )
        }
    }
}
