import Foundation

public enum SpeechEngine: String, Codable, Sendable, CaseIterable, Identifiable {
    case whisperAPI
    case local

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .whisperAPI: "Whisper API"
        case .local: "On this Mac"
        }
    }
}

public struct SpeechSettings: Sendable, Equatable {
    public var engine: SpeechEngine
    public var apiKey: String
    public var model: String
    public var baseURL: String
    public var localModelID: String
    public var localModelDirectory: URL

    public init(
        engine: SpeechEngine = .whisperAPI,
        apiKey: String = "",
        model: String = SpeechSettings.defaultCloudModel,
        baseURL: String = SpeechSettings.defaultCloudBaseURL,
        localModelID: String = LocalWhisperCatalog.tinyEN.id,
        localModelDirectory: URL
    ) {
        self.engine = engine
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.localModelID = localModelID
        self.localModelDirectory = localModelDirectory
    }

    public static let defaultCloudModel = "whisper-1"
    public static let cloudModels = ["whisper-1", "gpt-4o-transcribe", "gpt-4o-mini-transcribe"]
    public static let defaultCloudBaseURL = "https://api.openai.com/v1"
}

public enum TranscriptionError: Error, Equatable, Sendable {
    case emptyAudio
    case missingAPIKey
    case missingLocalModel
    case http(Int, String)
    case invalidResponse
}

public enum LocalWhisperCatalog {
    public struct Model: Sendable, Equatable, Identifiable {
        public var id: String
        public var displayName: String
        public var folderName: String
        public var variant: String
    }

    /// WhisperKit Core ML variant downloaded in Settings. Not ggml.
    public static let tinyEN = Model(
        id: "tiny.en",
        displayName: "Whisper Tiny (English)",
        folderName: "openai_whisper-tiny.en",
        variant: "tiny.en"
    )

    /// Files WhisperKit `loadModels` requires (see `detectModelURL` for MelSpectrogram/AudioEncoder/TextDecoder).
    public static let requiredCoreMLBundles = [
        "MelSpectrogram.mlmodelc",
        "AudioEncoder.mlmodelc",
        "TextDecoder.mlmodelc",
    ]

    public static let all: [Model] = [tinyEN]

    public static func model(id: String) -> Model {
        all.first { $0.id == id } ?? tinyEN
    }

    public static func folder(in root: URL, id: String) -> URL {
        root.appendingPathComponent(model(id: id).folderName, isDirectory: true)
    }

    public static func containsCoreML(at directory: URL) -> Bool {
        requiredCoreMLBundles.allSatisfy { name in
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
        }
    }

    /// True only when this directory (or a descendant) has the three WhisperKit Core ML bundles.
    public static func isInstalled(at directory: URL) -> Bool {
        resolvedModelFolder(in: directory) != nil
    }

    public static func resolvedModelFolder(in directory: URL) -> URL? {
        var stack = [directory]
        var visited = 0
        while let dir = stack.popLast(), visited < 64 {
            visited += 1
            if containsCoreML(at: dir) { return dir }
            let kids =
                (try? FileManager.default.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
            for kid in kids {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: kid.path, isDirectory: &isDir), isDir.boolValue {
                    stack.append(kid)
                }
            }
        }
        return nil
    }
}

public enum TranscriptionRequestBuilder {
    public static func cloudRequest(
        audio: Data,
        filename: String,
        mimeType: String,
        settings: SpeechSettings,
        boundary: String = "JoyflowBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    ) throws -> URLRequest {
        guard !audio.isEmpty else { throw TranscriptionError.emptyAudio }
        let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw TranscriptionError.missingAPIKey }
        guard let url = transcriptionsURL(from: settings.baseURL) else {
            throw TranscriptionError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(
            audio: audio,
            filename: filename,
            mimeType: mimeType,
            model: settings.model,
            boundary: boundary
        )
        return request
    }

    public static func transcriptionsURL(from raw: String) -> URL? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        if !value.hasSuffix("/v1") { value += "/v1" }
        return URL(string: value + "/audio/transcriptions")
    }

    public static func multipartBody(
        audio: Data,
        filename: String,
        mimeType: String,
        model: String,
        boundary: String
    ) -> Data {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        field("model", model)
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(
            Data(
                "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8
            )
        )
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(audio)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    public static func parseResponse(_ data: Data) throws -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranscriptionError.invalidResponse
        }
        if let error = obj["error"] as? [String: Any],
            let message = error["message"] as? String
        {
            throw TranscriptionError.http(0, message)
        }
        guard let text = obj["text"] as? String else { throw TranscriptionError.invalidResponse }
        return text
    }
}

public struct TranscriptionRouter: Sendable {
    public var transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    public var local: @Sendable (Data, SpeechSettings) async throws -> String

    public init(
        transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse),
        local: @escaping @Sendable (Data, SpeechSettings) async throws -> String
    ) {
        self.transport = transport
        self.local = local
    }

    public func transcribe(
        audio: Data,
        filename: String = "speech.wav",
        mimeType: String = "audio/wav",
        settings: SpeechSettings
    ) async throws -> String {
        guard !audio.isEmpty else { throw TranscriptionError.emptyAudio }
        switch settings.engine {
        case .whisperAPI:
            let request = try TranscriptionRequestBuilder.cloudRequest(
                audio: audio,
                filename: filename,
                mimeType: mimeType,
                settings: settings
            )
            let (data, response) = try await transport(request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                throw TranscriptionError.http(http.statusCode, errorMessage(in: data))
            }
            return try TranscriptionRequestBuilder.parseResponse(data)
        case .local:
            guard LocalWhisperCatalog.isInstalled(at: settings.localModelDirectory) else {
                throw TranscriptionError.missingLocalModel
            }
            return try await local(audio, settings)
        }
    }

    private func errorMessage(in data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = obj["error"] as? [String: Any],
            let message = error["message"] as? String
        {
            return message
        }
        return String(data: data, encoding: .utf8) ?? "transcription failed"
    }
}
