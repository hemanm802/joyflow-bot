import Foundation

public enum ChatDraft {
    public static func shouldSend(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
