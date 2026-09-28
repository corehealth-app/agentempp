import Foundation

/// The words for each way a meal capture can stop. One message per cause,
/// so the patient knows what to do next.
enum MealCaptureCopy {
    static func message(
        for failure: MealCaptureFailure,
        language: SupportedAppLanguage
    ) -> String {
        RegistrationCopy.string(key(for: failure), language: language)
    }

    static func key(for failure: MealCaptureFailure) -> String.LocalizationValue {
        switch failure {
        case .offline: "registration.live.failure.offline"
        case .unavailable: "registration.live.failure.unavailable"
        case .subscriptionRequired: "registration.live.failure.subscription"
        case .invalidInput: "registration.live.failure.invalid-input"
        case .audioTooLong: "registration.live.failure.audio-too-long"
        case .fileTooLarge: "registration.live.failure.file-too-large"
        case .unsupportedFile: "registration.live.failure.unsupported-file"
        case .unreadableMedia: "registration.live.failure.unreadable"
        case .nothingRecognized: "registration.live.failure.nothing-recognized"
        case .processingFailed: "registration.live.failure.processing"
        case .processingTimedOut: "registration.live.failure.processing-timeout"
        case .uploadRejected: "registration.live.failure.upload"
        case .permissionDenied: "registration.live.failure.permission"
        case .captureUnavailable: "registration.live.failure.capture-unavailable"
        }
    }

    static func phaseKey(
        _ phase: MealDraftPhase,
        channel: MealSourceChannel?
    ) -> String.LocalizationValue? {
        switch phase {
        case .uploading: "registration.live.phase.uploading"
        case .processing:
            channel?.isAudio == true
                ? "registration.live.phase.transcribing"
                : "registration.live.phase.analyzing"
        case .reading: "registration.live.phase.reading"
        case .idle, .review, .failed: nil
        }
    }

    static func basisKey(for item: MealDraftReview.Item) -> String.LocalizationValue {
        if item.hasTypedQuantity { return "registration.review.basis.stated" }
        guard item.candidate.quantityG != nil else {
            return "registration.review.basis.missing"
        }
        switch item.candidate.requestBasis {
        case .stated: return "registration.review.basis.stated"
        case .visualEstimate: return "registration.review.basis.visual"
        case .portionReference: return "registration.review.basis.reference"
        case nil: return "registration.review.basis.missing"
        }
    }

    static func blockerKey(_ blocker: MealDraftReview.Blocker) -> String.LocalizationValue {
        switch blocker {
        case .noItems: "registration.review.blocker.no-items"
        case .invalidName: "registration.review.blocker.name"
        case .missingQuantity, .invalidQuantity: "registration.review.blocker.quantity"
        case .unconfirmed: "registration.review.blocker.unconfirmed"
        }
    }

    /// "1:05" — elapsed and limit of a recording.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}
