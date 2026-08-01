import Foundation
import Observation

enum WorkoutRegistrationPhase: Equatable, Sendable {
    case form
    case proposal
    case confirmed
    case cancelled
}

@MainActor
@Observable
final class WorkoutRegistrationModel {
    private let registration: any RegistrationProviding
    private let invalidationCenter: FeatureInvalidationCenter
    private let attemptCoordinator: RegistrationAttemptCoordinator
    private var activeOwnership: FeatureLoadOwnership?
    private var operationSequence = 0

    let initialPerformedAt: Date
    private(set) var currentProposal: RegistrationSnapshot?
    private(set) var pendingDraft: WorkoutProposalRequest?
    private(set) var confirmedRegistration: RegistrationSnapshot?
    private(set) var mutationState = RegistrationMutationState.idle
    private(set) var captureError: BodyFlowCapabilityError?
    private(set) var phase = WorkoutRegistrationPhase.form
    private(set) var accessibilityFocusTarget: RegistrationAccessibilityFocusTarget?

    var isSubmitting: Bool {
        if case .submitting = mutationState { true } else { false }
    }

    init(
        registration: any RegistrationProviding,
        timeProvider: any TimeProviding,
        keyProvider: any IdempotencyKeyProviding,
        invalidationCenter: FeatureInvalidationCenter
    ) {
        self.registration = registration
        self.invalidationCenter = invalidationCenter
        attemptCoordinator = RegistrationAttemptCoordinator(
            timeProvider: timeProvider,
            keyProvider: keyProvider
        )
        initialPerformedAt = timeProvider.now
    }

    func submit(_ proposal: WorkoutProposalRequest) async {
        guard !isSubmitting else { return }
        do {
            let attempt = try attemptCoordinator.propose(.workout(proposal))
            pendingDraft = proposal
            await runMutation(.propose(attempt))
        } catch {
            publishAttemptConstructionFailure(error)
        }
    }

    func saveEdit(_ proposal: WorkoutProposalRequest) async {
        guard !isSubmitting, let currentProposal,
              currentProposal.status == "pending" else { return }
        do {
            let attempt = try attemptCoordinator.edit(
                registrationID: currentProposal.id,
                proposal: .workout(proposal)
            )
            pendingDraft = proposal
            await runMutation(.edit(attempt))
        } catch {
            publishAttemptConstructionFailure(error)
        }
    }

    func confirm() async {
        guard !isSubmitting, let currentProposal,
              currentProposal.status == "pending" else { return }
        do {
            await runMutation(.confirm(try attemptCoordinator.confirm(
                registrationID: currentProposal.id
            )))
        } catch {
            publishAttemptConstructionFailure(error)
        }
    }

    func cancel() async {
        guard !isSubmitting, let currentProposal,
              currentProposal.status == "pending" else { return }
        do {
            await runMutation(.cancel(try attemptCoordinator.cancel(
                registrationID: currentProposal.id
            )))
        } catch {
            publishAttemptConstructionFailure(error)
        }
    }

    func retry() async {
        guard case let .failed(attempt, _) = mutationState else { return }
        await runMutation(attempt)
    }

    func startNewProposal() {
        invalidateActiveOperation()
        currentProposal = nil
        pendingDraft = nil
        confirmedRegistration = nil
        mutationState = .idle
        captureError = nil
        phase = .form
        accessibilityFocusTarget = nil
    }

    func discardSheet() {
        invalidateActiveOperation()
        accessibilityFocusTarget = nil
        if case .submitting = mutationState { mutationState = .idle }
    }

    func consumeAccessibilityFocus() {
        accessibilityFocusTarget = nil
    }

    private func runMutation(_ attempt: RegistrationMutationAttempt) async {
        guard !isSubmitting else { return }
        let operation = beginOperation()
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
                publishFailure(attempt, error: error, operation: operation)
            }
        } onCancel: {
            operation.ownership.invalidate()
        }
        finishCancelledOperationIfNeeded(operation)
    }

    private func perform(_ attempt: RegistrationMutationAttempt) async throws -> RegistrationMutationReceipt {
        switch attempt {
        case let .propose(attempt): .propose(try await registration.propose(attempt))
        case let .edit(attempt): .edit(try await registration.edit(attempt))
        case let .confirm(attempt): .confirm(try await registration.confirm(attempt))
        case let .cancel(attempt): .cancel(try await registration.cancel(attempt))
        }
    }

    private func publishSuccess(_ receipt: RegistrationMutationReceipt, operation: ActiveWorkoutOperation) {
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
            pendingDraft = nil
            confirmedRegistration = response.data.registration
            phase = .confirmed
            invalidationCenter.record(.registrationConfirmed)
        case .cancel:
            currentProposal = nil
            pendingDraft = nil
            confirmedRegistration = nil
            phase = .cancelled
            invalidationCenter.record(.proposalCancelled)
        }
        mutationState = .succeeded(receipt)
        captureError = nil
        accessibilityFocusTarget = .operationSummary
        clearActiveOperation(operation)
    }

    private func publishFailure(_ attempt: RegistrationMutationAttempt, error: any Error, operation: ActiveWorkoutOperation) {
        guard claimPublication(operation) else { return }
        let capabilityError = Self.capabilityError(from: error)
        captureError = capabilityError
        if Self.invalidatesPending(capabilityError) {
            currentProposal = nil
            pendingDraft = nil
            phase = .form
            mutationState = .idle
        } else {
            mutationState = capabilityError == .operationUnavailable
                ? .unavailable
                : .failed(attempt, capabilityError)
        }
        accessibilityFocusTarget = .operationSummary
        clearActiveOperation(operation)
    }

    private func publishAttemptConstructionFailure(_ error: any Error) {
        let capabilityError = Self.capabilityError(from: error)
        captureError = capabilityError
        if capabilityError == .operationUnavailable { mutationState = .unavailable }
        accessibilityFocusTarget = .operationSummary
    }

    private func beginOperation() -> ActiveWorkoutOperation {
        activeOwnership?.invalidate()
        operationSequence += 1
        let ownership = FeatureLoadOwnership()
        activeOwnership = ownership
        return ActiveWorkoutOperation(sequence: operationSequence, ownership: ownership)
    }

    private func invalidateActiveOperation() {
        activeOwnership?.invalidate()
        operationSequence += 1
        activeOwnership = nil
    }

    private func mayContinue(_ operation: ActiveWorkoutOperation) -> Bool {
        !Task.isCancelled && !operation.ownership.isInvalidated
            && operation.sequence == operationSequence
            && activeOwnership === operation.ownership
    }

    private func claimPublication(_ operation: ActiveWorkoutOperation) -> Bool {
        mayContinue(operation) && operation.ownership.claimPublication()
    }

    private func clearActiveOperation(_ operation: ActiveWorkoutOperation) {
        if activeOwnership === operation.ownership { activeOwnership = nil }
    }

    private func finishCancelledOperationIfNeeded(_ operation: ActiveWorkoutOperation) {
        guard operation.sequence == operationSequence,
              activeOwnership === operation.ownership,
              operation.ownership.isInvalidated || Task.isCancelled else { return }
        activeOwnership = nil
        if case .submitting = mutationState { mutationState = .idle }
    }

    private static func capabilityError(from error: any Error) -> BodyFlowCapabilityError {
        error as? BodyFlowCapabilityError ?? .serviceUnavailable
    }

    private static func invalidatesPending(_ error: BodyFlowCapabilityError) -> Bool {
        error == .registrationExpired || error == .registrationNotPending
    }
}

private struct ActiveWorkoutOperation: Sendable {
    let sequence: Int
    let ownership: FeatureLoadOwnership
}
