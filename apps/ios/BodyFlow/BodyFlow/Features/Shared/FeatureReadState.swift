import Foundation

enum FeatureReadState<Value: Equatable & Sendable>: Equatable, Sendable {
    case idle
    case loading
    case loaded(Value)
    case empty
    case offline(previousValue: Value?)
    case failed(previousValue: Value?, error: BodyFlowCapabilityError)
    case unavailable
}

struct FeatureReadPresentation<Value: Equatable & Sendable>: Equatable, Sendable {
    let value: Value?
    let fullScreenState: ScreenState?
    let showsStaleBanner: Bool
}

extension FeatureReadState {
    var presentation: FeatureReadPresentation<Value> {
        switch self {
        case .idle:
            FeatureReadPresentation(
                value: nil,
                fullScreenState: nil,
                showsStaleBanner: false
            )
        case .loading:
            FeatureReadPresentation(
                value: nil,
                fullScreenState: .loading,
                showsStaleBanner: false
            )
        case let .loaded(value):
            FeatureReadPresentation(
                value: value,
                fullScreenState: nil,
                showsStaleBanner: false
            )
        case .empty:
            FeatureReadPresentation(
                value: nil,
                fullScreenState: .empty,
                showsStaleBanner: false
            )
        case let .offline(previousValue):
            stalePresentation(
                previousValue: previousValue,
                initialState: .offline
            )
        case let .failed(previousValue, _):
            stalePresentation(
                previousValue: previousValue,
                initialState: .recoverableError
            )
        case .unavailable:
            FeatureReadPresentation(
                value: nil,
                fullScreenState: .unavailable,
                showsStaleBanner: false
            )
        }
    }

    private func stalePresentation(
        previousValue: Value?,
        initialState: ScreenState
    ) -> FeatureReadPresentation<Value> {
        guard let previousValue else {
            return FeatureReadPresentation(
                value: nil,
                fullScreenState: initialState,
                showsStaleBanner: false
            )
        }

        return FeatureReadPresentation(
            value: previousValue,
            fullScreenState: nil,
            showsStaleBanner: true
        )
    }
}

enum FeatureMutationState<
    Attempt: Equatable & Sendable,
    Receipt: Equatable & Sendable
>: Equatable, Sendable {
    case idle
    case submitting(Attempt)
    case succeeded(Receipt)
    case failed(Attempt, BodyFlowCapabilityError)
    case unavailable

    var attempt: Attempt? {
        switch self {
        case .idle, .succeeded, .unavailable:
            nil
        case let .submitting(attempt),
             let .failed(attempt, _):
            attempt
        }
    }

    var receipt: Receipt? {
        guard case let .succeeded(receipt) = self else { return nil }
        return receipt
    }
}

enum RegistrationMutationAttempt: Equatable, Sendable {
    case propose(MutationAttempt<RegistrationProposalRequest>)
    case edit(MutationAttempt<RegistrationEditCommand>)
    case confirm(MutationAttempt<RegistrationIDCommand>)
    case cancel(MutationAttempt<RegistrationIDCommand>)

    /// The proposal an edit, confirmation or cancellation was sent for.
    var registrationID: String? {
        switch self {
        case .propose:
            nil
        case let .edit(attempt):
            attempt.payload.registrationID
        case let .confirm(attempt),
             let .cancel(attempt):
            attempt.payload.registrationID
        }
    }

    var operation: MutationOperation {
        switch self {
        case let .propose(attempt):
            attempt.operation
        case let .edit(attempt):
            attempt.operation
        case let .confirm(attempt):
            attempt.operation
        case let .cancel(attempt):
            attempt.operation
        }
    }
}

enum RegistrationMutationReceipt: Equatable, Sendable {
    case propose(RegistrationProposalResponse)
    case edit(RegistrationProposalResponse)
    case confirm(RegistrationConfirmationResponse)
    case cancel(RegistrationCancellationResponse)
    /// An owned current projection, possibly newer than an edit's receipt.
    /// Observing it never claims that this operation applied a mutation.
    case workoutCurrent(RegistrationProposalResponse)
    /// The server refused an edit or a cancellation with
    /// `409 registration_already_confirmed`: the record of this proposal was
    /// already saved (for example the confirmation went through and its
    /// response was lost). It carries only what the device knows, the id of
    /// the proposal; no confirmation response is made up.
    case alreadyConfirmed(registrationID: String)

    /// Absent for `alreadyConfirmed`, which has no success response.
    var requestID: String? {
        switch self {
        case let .propose(receipt),
             let .edit(receipt),
             let .workoutCurrent(receipt),
             let .cancel(receipt):
            receipt.meta.requestID
        case let .confirm(receipt):
            receipt.meta.requestID
        case .alreadyConfirmed:
            nil
        }
    }

    /// The registration a confirmed outcome is about, whichever way the
    /// device learned it was saved.
    var confirmedRegistrationID: String? {
        switch self {
        case let .confirm(receipt):
            receipt.data.registration.id
        case let .alreadyConfirmed(registrationID):
            registrationID
        case .propose, .edit, .cancel, .workoutCurrent:
            nil
        }
    }
}

typealias RegistrationMutationState = FeatureMutationState<
    RegistrationMutationAttempt,
    RegistrationMutationReceipt
>
typealias HydrationMutationState = FeatureMutationState<
    MutationAttempt<HydrationCommand>,
    HydrationReceipt
>
typealias WeightMutationState = FeatureMutationState<
    MutationAttempt<WeightCommand>,
    WeightDemoReceipt
>
typealias RoutineMutationState = FeatureMutationState<
    MutationAttempt<RoutineActionCommand>,
    RoutineActionResponse
>
