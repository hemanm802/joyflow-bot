import AVFoundation
import Foundation
import JoyflowKit
import Observation

@Observable
@MainActor
final class VoiceCapture {
    var isRecording = false
    var isTranscribing = false
    var errorText: String?
    var levels: [CGFloat] = Array(repeating: 0.08, count: 48)

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var meterTask: Task<Void, Never>?
    private var lastAmplitude: CGFloat = 0.08

    func toggle(transcribe: @escaping (Data) async throws -> String, apply: @escaping (String) -> Void) {
        if isRecording {
            Task { await stopAndTranscribe(transcribe: transcribe, apply: apply) }
        } else {
            begin()
        }
    }

    private func begin() {
        errorText = nil
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else {
                    self.errorText = "Microphone access is required to talk."
                    return
                }
                self.startRecorder()
            }
        }
    }

    private func startRecorder() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("joyflow-mic-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()
            guard recorder.record() else {
                errorText = "Could not start the microphone."
                return
            }
            self.recorder = recorder
            fileURL = url
            isRecording = true
            startMeter()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func stopAndTranscribe(
        transcribe: @escaping (Data) async throws -> String,
        apply: @escaping (String) -> Void
    ) async {
        meterTask?.cancel()
        meterTask = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        lastAmplitude = 0.08
        levels = Array(repeating: 0.08, count: 48)
        guard let fileURL else {
            errorText = "No recording to transcribe."
            return
        }
        isTranscribing = true
        defer {
            isTranscribing = false
            try? FileManager.default.removeItem(at: fileURL)
            self.fileURL = nil
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let spoken = try await transcribe(data)
            apply(spoken)
        } catch {
            errorText = TranscriptionDisplay.message(for: error)
        }
    }
}

enum TranscriptionDisplay {
    static func message(for error: Error) -> String {
        if let typed = error as? TranscriptionError {
            switch typed {
            case .emptyAudio: return "That recording was empty."
            case .missingAPIKey: return "Add a Whisper API key in Settings."
            case .missingLocalModel: return "Download the local Whisper model in Settings."
            case .http(let status, let message): return "Transcription failed (\(status)): \(message)"
            case .invalidResponse: return "The transcription service returned an unreadable reply."
            }
        }
        return error.localizedDescription
    }
}

extension VoiceCapture {
    private func startMeter() {
        meterTask?.cancel()
        lastAmplitude = 0.08
        levels = Array(repeating: 0.08, count: 48)
        meterTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isRecording, let recorder = self.recorder else { return }
                recorder.updateMeters()
                let next = Self.smoothed(
                    previous: self.lastAmplitude,
                    average: recorder.averagePower(forChannel: 0),
                    peak: recorder.peakPower(forChannel: 0)
                )
                self.lastAmplitude = next
                var bars = self.levels
                if !bars.isEmpty { bars.removeFirst() }
                bars.append(next)
                self.levels = bars
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }

    private static func smoothed(previous: CGFloat, average: Float, peak: Float) -> CGFloat {
        let sample = min(1, amplitude(from: average) * 0.55 + amplitude(from: peak) * 0.45)
        return previous * 0.32 + sample * 0.68
    }

    private static func amplitude(from decibels: Float) -> CGFloat {
        let clamped = max(-50, min(0, decibels))
        let linear = (clamped + 50) / 50
        return CGFloat(pow(Double(linear), 1.3))
    }
}
