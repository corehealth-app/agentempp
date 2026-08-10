import Foundation
import Observation

enum MealCaptureSource: Equatable, Sendable {
    case text(String)
    case photoDemonstration(label: String)
    case audioDemonstration(label: String)

    var detectionInput: MealDetectionInput {
        switch self {
        case let .text(value):
            .text(value)
        case let .photoDemonstration(label):
            .photoSample(label: label)
        case let .audioDemonstration(label):
            .audioSample(label: label)
        }
    }
}

enum MealRegistrationPhase: Equatable, Sendable {
    case capture
    case proposal
    case confirmed
    case cancelled
}

enum RegistrationAccessibilityFocusTarget: Hashable, Sendable {
    case operationSummary
}

@MainActor
@Observable
final class MealRegistrationModel {
    private let detector: any MealDetectionProviding
    private let registration: any RegistrationProviding
    private let invalidationCenter: FeatureInvalidationCenter
    private let attemptCoordinator: RegistrationAttemptCoordinator
    private let demonstrationTextLimit: ClosedRange<Int>?

    private var activeOwnership: FeatureLoadOwnership?
    private var activeDetectionSource: MealCaptureSource?
    private var operationSequence = 0

    let initialConsumedAt: Date
    private(set) var captureSource: MealCaptureSource?
    private(set) var detectedDraft: RegistrationProposalRequest?
    private(set) var currentProposal: RegistrationSnapshot?
    private(set) var confirmedRegistration: RegistrationSnapshot?
    private(set) var captureError: BodyFlowCapabilityError?
    private(set) var mutationState = RegistrationMutationState.idle
    private(set) var phase = MealRegistrationPhase.capture
    private(set) var accessibilityFocusTarget: RegistrationAccessibilityFocusTarget?

    var isSubmitting: Bool {
        if case .submitting = mutationState { true } else { false }
    }

    var canCreateNewProposal: Bool {
        phase == .capture && currentProposal == nil && detectedDraft != nil
    }

    init(
        detector: any MealDetectionProviding,
        registration: any RegistrationProviding,
        timeProvider: any TimeProviding,
        keyProvider: any IdempotencyKeyProviding,
        invalidationCenter: FeatureInvalidationCenter,
        demonstrationTextLimit: ClosedRange<Int>? = nil
    ) {
        self.detector = detector
        self.registration = registration
        self.invalidationCenter = invalidationCenter
        self.demonstrationTextLimit = demonstrationTextLimit
        attemptCoordinator = RegistrationAttemptCoordinator(
            timeProvider: timeProvider,
            keyProvider: keyProvider
        )
        initialConsumedAt = timeProvider.now
    }

    func submit(_ source: MealCaptureSource) async {
        if activeDetectionSource == source { return }
        guard !isSubmitting else { return }
        guard isValidDemonstrationInput(source) else {
            captureError = .invalidInput
            return
        }

        let operation = beginOperation(supersedingCurrent: true)
        activeDetectionSource = source
        captureSource = source
        captureError = nil
        accessibilityFocusTarget = nil

        await withTaskCancellationHandler {
            await detectAndPropose(source, operation: operation)
        } onCancel: {
            operation.ownership.invalidate()
        }

        finishCancelledOperationIfNeeded(operation)
    }

    func saveEdit(_ edit: MealProposalRequest) async {
        guard !isSubmitting, let currentProposal,
              currentProposal.status == "pending" else { return }

        do {
            let attempt = try attemptCoordinator.edit(
                registrationID: currentProposal.id,
                proposal: .meal(edit)
            )
            await runMutation(.edit(attempt))
        } catch {
            publishAttemptConstructionFailure(error)
        }
    }

    func confirm() async {
        guard !isSubmitting, let currentProposal else { return }

        do {
            await runMutation(.confirm(try attemptCoordinator.confirm(
                registrationID: currentProposal.id
            )))
        } catch {
            publishAttemptConstructionFailure(error)
        }
    }

    func cancel() async {
        guard !isSubmitting, let currentProposal else { return }

        do {
            await runMutation(.cancel(try attemptCoordinator.cancel(
                registrationID: currentProposal.id
            )))
        } catch {
            publishAttemptConstructionFailure(error)
        }
    }

    func retry() async {
        switch mutationState {
        case let .failed(attempt, _):
            await runMutation(attempt)
        case .idle, .submitting, .succeeded, .unavailable:
            if let captureSource, captureError != nil {
                await submit(captureSource)
            }
        }
    }

    func createNewProposalFromDraft() async {
        guard !isSubmitting, canCreateNewProposal, let detectedDraft else { return }
        do {
            await runMutation(.propose(try attemptCoordinator.propose(detectedDraft)))
        } catch {
            publishAttemptConstructionFailure(error)
        }
    }

    func startNewProposal() {
        activeOwnership?.invalidate()
        operationSequence += 1
        activeOwnership = nil
        activeDetectionSource = nil
        captureSource = nil
        detectedDraft = nil
        currentProposal = nil
        confirmedRegistration = nil
        captureError = nil
        mutationState = .idle
        phase = .capture
        accessibilityFocusTarget = nil
    }

    func discardSheet() {
        activeOwnership?.invalidate()
        operationSequence += 1
        activeOwnership = nil
        activeDetectionSource = nil
        accessibilityFocusTarget = nil
        if case .submitting = mutationState {
            mutationState = .idle
        }
    }

    func consumeAccessibilityFocus() {
        accessibilityFocusTarget = nil
    }

    private func detectAndPropose(
        _ source: MealCaptureSource,
        operation: ActiveMealOperation
    ) async {
        do {
            let draft = try await detector.detect(source.detectionInput)
            guard mayContinue(operation) else { return }
            detectedDraft = draft

            let attempt = try attemptCoordinator.propose(draft)
            let typedAttempt = RegistrationMutationAttempt.propose(attempt)
            mutationState = .submitting(typedAttempt)
            let response = try await registration.propose(attempt)
            publishSuccess(
                .propose(response),
                operation: operation
            )
        } catch is CancellationError {
            return
        } catch {
            publishCaptureFailure(error, operation: operation)
        }
    }

    private func runMutation(_ attempt: RegistrationMutationAttempt) async {
        guard !isSubmitting else { return }
        let operation = beginOperation(supersedingCurrent: true)
        mutationState = .submitting(attempt)
        captureError = nil
        accessibilityFocusTarget = nil

        await withTaskCancellationHandler {
            do {
                let receipt = try await perform(attempt)
                publishSuccess(receipt, operation: operation)
            } catch is CancellationError {
                return
            } catch {
                publishMutationFailure(
                    attempt,
                    error: error,
                    operation: operation
                )
            }
        } onCancel: {
            operation.ownership.invalidate()
        }

        finishCancelledOperationIfNeeded(operation)
    }

    private func perform(
        _ attempt: RegistrationMutationAttempt
    ) async throws -> RegistrationMutationReceipt {
        switch attempt {
        case let .propose(attempt):
            .propose(try await registration.propose(attempt))
        case let .edit(attempt):
            .edit(try await registration.edit(attempt))
        case let .confirm(attempt):
            .confirm(try await registration.confirm(attempt))
        case let .cancel(attempt):
            .cancel(try await registration.cancel(attempt))
        }
    }

    private func publishSuccess(
        _ receipt: RegistrationMutationReceipt,
        operation: ActiveMealOperation
    ) {
        guard claimPublication(operation) else { return }

        switch receipt {
        case let .propose(response):
            currentProposal = response.data
            confirmedRegistration = nil
            phase = .proposal
            invalidationCenter.record(.proposalCreated)
        case let .edit(response):
            currentProposal = response.data
            phase = .proposal
            invalidationCenter.record(.proposalEdited)
        case let .confirm(response):
            currentProposal = nil
            confirmedRegistration = response.data.registration
            phase = .confirmed
            invalidationCenter.record(.registrationConfirmed)
        case .cancel:
            currentProposal = nil
            confirmedRegistration = nil
            phase = .cancelled
            invalidationCenter.record(.proposalCancelled)
        }

        mutationState = .succeeded(receipt)
        captureError = nil
        accessibilityFocusTarget = .operationSummary
        clearActiveOperation(operation)
    }

    private func publishCaptureFailure(
        _ error: any Error,
        operation: ActiveMealOperation
    ) {
        guard claimPublication(operation) else { return }
        let capabilityError = Self.capabilityError(from: error)

        if case let .submitting(attempt) = mutationState {
            mutationState = Self.failureState(
                attempt: attempt,
                error: capabilityError
            )
        } else if capabilityError == .operationUnavailable {
            mutationState = .unavailable
        }
        captureError = capabilityError
        accessibilityFocusTarget = .operationSummary
        clearActiveOperation(operation)
    }

    private func publishMutationFailure(
        _ attempt: RegistrationMutationAttempt,
        error: any Error,
        operation: ActiveMealOperation
    ) {
        guard claimPublication(operation) else { return }
        let capabilityError = Self.capabilityError(from: error)

        captureError = capabilityError
        if Self.invalidatesPending(capabilityError) {
            currentProposal = nil
            phase = .capture
            mutationState = .idle
        } else {
            mutationState = Self.failureState(
                attempt: attempt,
                error: capabilityError
            )
        }
        accessibilityFocusTarget = .operationSummary
        clearActiveOperation(operation)
    }

    private func publishAttemptConstructionFailure(_ error: any Error) {
        let capabilityError = Self.capabilityError(from: error)
        captureError = capabilityError
        if capabilityError == .operationUnavailable {
            mutationState = .unavailable
        }
        accessibilityFocusTarget = .operationSummary
    }

    private func beginOperation(
        supersedingCurrent: Bool
    ) -> ActiveMealOperation {
        if supersedingCurrent {
            activeOwnership?.invalidate()
        }
        operationSequence += 1
        let ownership = FeatureLoadOwnership()
        activeOwnership = ownership
        return ActiveMealOperation(
            sequence: operationSequence,
            ownership: ownership
        )
    }

    private func mayContinue(_ operation: ActiveMealOperation) -> Bool {
        !Task.isCancelled
            && !operation.ownership.isInvalidated
            && operation.sequence == operationSequence
            && activeOwnership === operation.ownership
    }

    private func claimPublication(_ operation: ActiveMealOperation) -> Bool {
        mayContinue(operation) && operation.ownership.claimPublication()
    }

    private func clearActiveOperation(_ operation: ActiveMealOperation) {
        if activeOwnership === operation.ownership {
            activeOwnership = nil
            activeDetectionSource = nil
        }
    }

    private func finishCancelledOperationIfNeeded(
        _ operation: ActiveMealOperation
    ) {
        guard operation.sequence == operationSequence,
              activeOwnership === operation.ownership,
              operation.ownership.isInvalidated || Task.isCancelled
        else {
            return
        }
        activeOwnership = nil
        activeDetectionSource = nil
        if case .submitting = mutationState {
            mutationState = .idle
        }
    }

    private static func failureState(
        attempt: RegistrationMutationAttempt,
        error: BodyFlowCapabilityError
    ) -> RegistrationMutationState {
        error == .operationUnavailable
            ? .unavailable
            : .failed(attempt, error)
    }

    private static func capabilityError(
        from error: any Error
    ) -> BodyFlowCapabilityError {
        error as? BodyFlowCapabilityError ?? .serviceUnavailable
    }

    private static func invalidatesPending(
        _ error: BodyFlowCapabilityError
    ) -> Bool {
        error == .registrationExpired || error == .registrationNotPending
    }

    private func isValidDemonstrationInput(
        _ source: MealCaptureSource
    ) -> Bool {
        guard let demonstrationTextLimit,
              case let .text(text) = source else { return true }
        return demonstrationTextLimit.contains(text.count)
    }
}

struct RegistrationAttemptCoordinator {
    let timeProvider: any TimeProviding
    let keyProvider: any IdempotencyKeyProviding

    func propose(
        _ payload: RegistrationProposalRequest
    ) throws -> MutationAttempt<RegistrationProposalRequest> {
        MutationAttempt(
            operation: .proposalCreate,
            key: try keyProvider.nextKey(),
            payload: payload,
            createdAt: timeProvider.now
        )
    }

    func edit(
        registrationID: String,
        proposal: RegistrationProposalRequest
    ) throws -> MutationAttempt<RegistrationEditCommand> {
        MutationAttempt(
            operation: .proposalEdit,
            key: try keyProvider.nextKey(),
            payload: RegistrationEditCommand(
                registrationID: registrationID,
                proposal: proposal
            ),
            createdAt: timeProvider.now
        )
    }

    func confirm(
        registrationID: String
    ) throws -> MutationAttempt<RegistrationIDCommand> {
        try idAttempt(
            operation: .proposalConfirm,
            registrationID: registrationID
        )
    }

    func cancel(
        registrationID: String
    ) throws -> MutationAttempt<RegistrationIDCommand> {
        try idAttempt(
            operation: .proposalCancel,
            registrationID: registrationID
        )
    }

    private func idAttempt(
        operation: MutationOperation,
        registrationID: String
    ) throws -> MutationAttempt<RegistrationIDCommand> {
        MutationAttempt(
            operation: operation,
            key: try keyProvider.nextKey(),
            payload: RegistrationIDCommand(registrationID: registrationID),
            createdAt: timeProvider.now
        )
    }
}

@MainActor
struct RegistrationOperationCoordinator {
    let model: MealRegistrationModel

    func perform(_ action: RegistrationOperationAction?) async {
        switch action {
        case .retry:
            await model.retry()
        case .newProposal:
            await model.createNewProposalFromDraft()
        case nil:
            return
        }
    }
}

private struct ActiveMealOperation: Sendable {
    let sequence: Int
    let ownership: FeatureLoadOwnership
}
