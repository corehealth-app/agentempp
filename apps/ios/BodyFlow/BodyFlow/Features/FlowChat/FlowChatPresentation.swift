import Foundation

enum FlowChatPresentation {
    static func canSubmit(_ text: String, isSending: Bool) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && value.count <= 4_000 && !isSending
    }

    static func isOverLimit(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count > 4_000
    }

    static func roleLabelKey(_ role: FlowMessageRole) -> String.LocalizationValue {
        role == .user ? "flow.role.user" : "flow.role.assistant"
    }
}

enum FlowChatScrollPolicy {
    static func shouldFollow(atEnd: Bool, initiatedSend: Bool) -> Bool { atEnd || initiatedSend }
    static func shouldAnimate(reduceMotion: Bool) -> Bool { !reduceMotion }
}
