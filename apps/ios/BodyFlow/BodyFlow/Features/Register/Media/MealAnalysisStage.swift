import Foundation

/// The stage a meal analysis is really in, as the one loading block says it.
/// Only stages the app knows from its own calls: preparing the file, sending
/// it, the server looking at the photo or transcribing the audio, reading
/// the foods and — after the review — calculating. Never a percentage.
enum MealAnalysisStage: Equatable, Sendable, CaseIterable {
    case preparing
    case sending
    case photo
    case audio
    case reading
    case calculating

    /// The stage of a capture, or `nil` when nothing is being waited for.
    /// `isProposing`: the reviewed foods were sent and the proposal (the
    /// calculation) has not come back yet.
    static func resolve(
        phase: MealDraftPhase,
        channel: MealSourceChannel?,
        isProposing: Bool
    ) -> MealAnalysisStage? {
        switch phase {
        case .preparing: .preparing
        case .uploading: .sending
        case .processing: channel?.isAudio == true ? .audio : .photo
        case .reading: .reading
        case .review: isProposing ? .calculating : nil
        case .idle, .failed: nil
        }
    }

    /// The line of this stage (the wording reviewed for the capture).
    var lineKey: String.LocalizationValue {
        switch self {
        case .preparing: "registration.live.phase.preparing"
        case .sending: "registration.live.phase.uploading"
        case .photo: "registration.live.phase.analyzing"
        case .audio: "registration.live.phase.transcribing"
        case .reading: "registration.live.phase.reading"
        case .calculating: "registration.live.phase.calculating"
        }
    }

    /// The lines of the one continuous wait from the capture to the review.
    static let captureLines: [MealAnalysisStage] = [.preparing, .sending, .photo, .audio, .reading]

    /// Every line this stage's wait may show: the loader reserves their
    /// height so nothing moves when the line changes.
    var reservedLines: [MealAnalysisStage] {
        self == .calculating ? [.calculating] : Self.captureLines
    }

    /// The capture can be dropped while it travels; the calculation has no
    /// cancel (it never had one).
    var offersCancel: Bool { self != .calculating }

    /// While the file is prepared there is nothing to cancel yet: the
    /// action keeps its place, disabled.
    var isCancelEnabled: Bool { self != .preparing && offersCancel }
}

/// VoiceOver follows the wait: the loading block takes the focus once, when
/// it appears. A change of stage is read as the new value of the same
/// element and moves nothing.
enum MealAnalysisFocus {
    static func takesFocus(
        from previous: MealAnalysisStage?,
        to current: MealAnalysisStage?
    ) -> Bool {
        previous == nil && current != nil
    }
}
