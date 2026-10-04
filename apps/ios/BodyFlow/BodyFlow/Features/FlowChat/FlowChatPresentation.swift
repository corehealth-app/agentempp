import Foundation

enum FlowChatPresentation {
    static func canSubmit(_ text: String, isSending: Bool) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && value.count <= 4_000 && !isSending
    }

    static func isOverLimit(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count > 4_000
    }

    /// The ready-made questions of a first conversation, in display order.
    static let suggestionKeys: [String.LocalizationValue] = [
        "flow.suggestion.day", "flow.suggestion.dinner", "flow.suggestion.workout",
    ]

    /// The questions are offered only where a tap cannot destroy anything:
    /// the composer is empty or still holds one of the questions. A draft the
    /// person typed (it survives leaving and reopening the chat) is never
    /// replaced. They stay out of the way of a load error and of
    /// accessibility text sizes, where the empty state is the invitation and
    /// the composer alone.
    static func showsSuggestions(
        composer: String,
        suggestions: [String],
        isAccessibilitySize: Bool,
        hasError: Bool
    ) -> Bool {
        guard !isAccessibilitySize, !hasError, !suggestions.isEmpty else { return false }
        let draft = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        return draft.isEmpty || suggestions.contains(draft)
    }

    static func roleLabelKey(_ role: FlowMessageRole) -> String.LocalizationValue {
        role == .user ? "flow.role.user" : "flow.role.assistant"
    }
}

enum FlowChatScrollPolicy {
    static func shouldFollow(atEnd: Bool, initiatedSend: Bool) -> Bool { atEnd || initiatedSend }
    static func shouldAnimate(reduceMotion: Bool) -> Bool { !reduceMotion }
}
