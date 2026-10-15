import Foundation
import Observation

enum PerformeBrandState: String, CaseIterable, Sendable {
    case idle, press, active, processing, success, error
}

enum PerformeOperationOutcome: Equatable {
    case ready, confirmed, failed, cancelled
}

/// Owned by one visible sheet in one authenticated shell. This projects
/// presentation only; it never decides whether an operation was persisted.
@MainActor @Observable
final class PerformeOperationPresentation {
    struct Token: Hashable { fileprivate let id = UUID() }
    struct Feedback: Equatable {
        let id: Token
        let result: BodyFlowHaptics.Result
    }
    enum Confirmation: Hashable {
        case registration(String), hydration(String), weight(Double, Date)
    }

    private var current: Token?
    private var finished = false
    private var closed = false
    private var presentedConfirmations: Set<Confirmation> = []
    private(set) var state: PerformeBrandState = .idle
    private(set) var outcome: PerformeOperationOutcome?
    private(set) var feedback: Feedback?
    private(set) var successToken: Token?

    @discardableResult func begin() -> Token {
        let token = Token()
        guard !closed else { return token }
        current = token
        finished = false
        state = .processing
        outcome = nil
        feedback = nil
        successToken = nil
        return token
    }

    func finish(_ token: Token, outcome: PerformeOperationOutcome, confirmation: Confirmation? = nil, isCancelled: Bool) {
        guard !closed, current == token, !finished else { return }
        finished = true
        let result = isCancelled ? .cancelled : outcome
        self.outcome = result
        switch result {
        case .ready, .cancelled: state = .active
        case .confirmed:
            guard let confirmation, presentedConfirmations.insert(confirmation).inserted else {
                state = .active
                return
            }
            state = .success
            successToken = token
            feedback = Feedback(id: token, result: .success)
        case .failed:
            state = .error
            feedback = Feedback(id: token, result: .failure)
        }
    }

    func expireSuccess(for token: Token) {
        guard current == token, state == .success else { return }
        state = .active
        successToken = nil
    }

    /// Capture controls can reset or report local permission/import failures
    /// before a network operation exists. They update the visible status only.
    func capturePhaseChanged(_ phase: MealDraftPhase) {
        guard !closed else { return }
        switch phase {
        case .idle:
            current = nil
            finished = true
            state = .active
            outcome = nil
            feedback = nil
            successToken = nil
        case .failed where state != .processing && state != .error:
            state = .error
            outcome = .failed
            feedback = nil
        default: break
        }
    }

    func invalidate() {
        closed = true
        current = nil
        state = .idle
        outcome = nil
        feedback = nil
        successToken = nil
        presentedConfirmations.removeAll()
    }
}

enum PerformeRegistrationProjection {
    static func meal(
        intent: RegistrationSheetOperationIntent,
        draft: MealDraftPhase,
        mutation: RegistrationMutationState,
        captureError: BodyFlowCapabilityError?
    ) -> PerformeOperationOutcome {
        switch intent {
        case .draftText, .draftMedia, .draftRetry:
            switch draft {
            case .review: return .ready
            case .failed: return .failed
            case .idle, .preparing, .uploading, .processing, .reading: return .cancelled
            }
        default:
            return registration(mutation, captureError: captureError)
        }
    }

    static func registration(_ mutation: RegistrationMutationState, captureError: BodyFlowCapabilityError?) -> PerformeOperationOutcome {
        if captureError != nil { return .failed }
        switch mutation {
        case .failed, .unavailable: return .failed
        case .succeeded(.confirm), .succeeded(.alreadyConfirmed): return .confirmed
        case .succeeded(.propose), .succeeded(.edit): return .ready
        case let .succeeded(.workoutCurrent(response)):
            return switch response.data.status {
            case "pending": .ready
            case "confirmed": .confirmed
            default: .cancelled
            }
        case .succeeded(.cancel), .idle, .submitting: return .cancelled
        }
    }

    /// The identity the confirmed presentation (brand success and its
    /// haptic) is shown for, once. Only a confirmation the server answered
    /// has one. An already saved record (`alreadyConfirmed`) also ends
    /// confirmed, but the edit or the cancellation the patient asked for was
    /// not applied, so it has none and nothing is celebrated.
    static func confirmation(
        for mutation: RegistrationMutationState
    ) -> PerformeOperationPresentation.Confirmation? {
        guard case .succeeded(.confirm) = mutation else { return nil }
        return mutation.receipt?.confirmedRegistrationID.map { .registration($0) }
    }
}
