import Foundation

/// The same fill the composer uses after a successful transcription.
public enum VoiceDraft {
    public static func fill(existing: String, transcript: String) -> String {
        let spoken = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return existing }
        let current = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty { return spoken }
        return current + " " + spoken
    }
}
