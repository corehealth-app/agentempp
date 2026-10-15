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
    private let registrationProtocol: WorkoutRegistrationProtocol?
    private let isSessionActive: @MainActor @Sendable () -> Bool
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
    private(set) var retainedFailedAttempt: RegistrationMutationAttempt?
    private(set) var requiresCurrentReview = false
    private(set) var isReviewingCurrent = false

    var isSubmitting: Bool {
        if case .submitting = mutationState { true } else { false }
    }

    var isBusy: Bool { isSubmitting || isReviewingCurrent }

    var allowsPendingActions: Bool {
        isSessionActive() && currentProposal?.status == "pending" && !isBusy && !requiresCurrentReview
    }

    init(
        registration: any RegistrationProviding,
        timeProvider: any TimeProviding,
        keyProvider: any IdempotencyKeyProviding,
        invalidationCenter: FeatureInvalidationCenter,
        registrationProtocol: WorkoutRegistrationProtocol? = nil,
        isSessionActive: @escaping @MainActor @Sendable () -> Bool = { true }
    ) {
        self.registration = registration
        self.invalidationCenter = invalidationCenter
        self.registrationProtocol = registrationProtocol
        self.isSessionActive = isSessionActive
        attemptCoordinator = RegistrationAttemptCoordinator(
            timeProvider: timeProvider,
            keyProvider: keyProvider
        )
        initialPerformedAt = timeProvider.now
    }

    func submit(_ proposal: WorkoutProposalRequest) async {
        guard isSessionActive(), !isBusy, !requiresCurrentReview else { return }
        if currentProposal?.workoutVersion != nil || registrationProtocol != nil && phase != .form { return }
        do {
            let attempt = try attemptCoordinator.propose(.workout(
                Self.input(proposal, protocol: registrationProtocol)
            ))
            pendingDraft = Self.input(proposal, protocol: nil)
            await runMutation(.propose(attempt))
        } catch {
            publishAttemptConstructionFailure(error)
        }
    }

    func saveEdit(_ proposal: WorkoutProposalRequest) async {
        guard allowsPendingActions, let currentProposal else { return }
        do {
            let attempt = try attemptCoordinator.edit(
                registrationID: currentProposal.id,
                proposal: .workout(Self.input(proposal, protocol: nil)),
                workoutVersion: currentProposal.workoutVersion
            )
            pendingDraft = Self.input(proposal, protocol: nil)
            await runMutation(.edit(attempt))
        } catch {
            publishAttemptConstructionFailure(error)
        }
    }

    func confirm() async {
        guard allowsPendingActions, let currentProposal else { return }
        do {
            await runMutation(.confirm(try attemptCoordinator.confirm(
                registrationID: currentProposal.id,
                workoutVersion: currentProposal.workoutVersion
            )))
        } catch {
            publishAttemptConstructionFailure(error)
        }
    }

    func cancel() async {
        guard allowsPendingActions, let currentProposal else { return }
        do {
            await runMutation(.cancel(try attemptCoordinator.cancel(
                registrationID: currentProposal.id,
                workoutVersion: currentProposal.workoutVersion
            )))
        } catch {
            publishAttemptConstructionFailure(error)
        }
    }

    func retry() async {
        guard isSessionActive(), !isBusy, captureError != .registrationAuthorityStale else { return }
        if requiresCurrentReview {
            await reviewCurrentVersion()
            return
        }
        guard case let .failed(attempt, _) = mutationState else { return }
        await runMutation(attempt)
    }

    /// This is only a read. It never repairs the expected revision or sends
    /// the failed mutation again; the next patient action is a new intent.
    func reviewCurrentVersion() async {
        guard isSessionActive(), !isBusy, requiresCurrentReview,
              captureError != .registrationAuthorityStale,
              let attempt = retainedFailedAttempt,
              let id = attempt.registrationID else { return }
        let operation = beginOperation()
        isReviewingCurrent = true
        accessibilityFocusTarget = nil
        await withTaskCancellationHandler {
            do {
                guard let reader = registration as? any WorkoutRegistrationReading else {
                    throw BodyFlowCapabilityError.serviceUnavailable
                }
                let response = try await reader.loadWorkoutRegistration(id: id)
                try Self.validate(response.data, id: id)
                publishSuccess(.workoutCurrent(response), operation: operation)
            } catch is CancellationError {
                return
            } catch {
                // Retain the mutation for diagnosis, but retry will remain a
                // GET until a current owned projection has been reviewed.
                publishFailure(attempt, error: error, operation: operation, reviewing: true)
            }
        } onCancel: {
            operation.ownership.invalidate()
        }
        finishCancelledOperationIfNeeded(operation)
    }

    /// An explicit new intention after a terminal/stale result. The form
    /// keeps the authored fields; preparing it performs no request.
    func prepareNewProposal() {
        guard isSessionActive(), !isBusy, phase != .confirmed else { return }
        guard !requiresCurrentReview || captureError == .registrationAuthorityStale
                || retainedFailedAttempt?.registrationID == nil else { return }
        guard registrationProtocol != nil || currentProposal?.workoutVersion != nil
                || retainedFailedAttempt?.isVersionedWorkout == true || requiresCurrentReview else {
            startNewProposal()
            return
        }
        invalidateActiveOperation()
        currentProposal = nil
        confirmedRegistration = nil
        retainedFailedAttempt = nil
        requiresCurrentReview = false
        mutationState = .idle
        captureError = nil
        phase = .form
        accessibilityFocusTarget = nil
    }

    func startNewProposal() {
        guard isSessionActive() else { return }
        invalidateActiveOperation()
        currentProposal = nil
        pendingDraft = nil
        confirmedRegistration = nil
        retainedFailedAttempt = nil
        requiresCurrentReview = false
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
        guard isSessionActive(), !isBusy else { return }
        let operation = beginOperation()
        if retainedFailedAttempt != attempt { retainedFailedAttempt = nil }
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
        case let .propose(value):
            let response = try await registration.propose(value)
            if attempt.isVersionedWorkout {
                try Self.validate(response.data)
                if response.data.status != "pending" || response.data.workoutVersion?.contentRevision != 0 {
                    return .workoutCurrent(response)
                }
            }
            return .propose(response)
        case let .edit(value):
            let response = try await registration.edit(value)
            if let version = value.payload.workoutVersion {
                try Self.validate(response.data, id: value.payload.registrationID)
                guard let receipt = response.data.editReceipt,
                      receipt.requestKey == "wue1:\(value.key.value)",
                      receipt.expectedRevision == version.contentRevision,
                      receipt.resultRevision == version.contentRevision + 1,
                      response.data.workoutVersion.map({ $0.contentRevision >= receipt.resultRevision }) == true else {
                    throw BodyFlowCapabilityError.serviceUnavailable
                }
                if response.data.status != "pending" || response.data.workoutVersion?.contentRevision != receipt.resultRevision {
                    return .workoutCurrent(response)
                }
            }
            return .edit(response)
        case let .confirm(value):
            let response = try await registration.confirm(value)
            if let version = value.payload.workoutVersion {
                try Self.validate(response.data.registration, id: value.payload.registrationID)
                guard response.data.registration.status == "confirmed",
                      response.data.registration.workoutVersion == version else {
                    throw BodyFlowCapabilityError.serviceUnavailable
                }
            }
            return .confirm(response)
        case let .cancel(value):
            let response = try await registration.cancel(value)
            if let version = value.payload.workoutVersion {
                try Self.validate(response.data, id: value.payload.registrationID)
                guard response.data.status == "cancelled", response.data.workoutVersion == version else {
                    throw BodyFlowCapabilityError.serviceUnavailable
                }
            }
            return .cancel(response)
        }
    }

    private static func validate(_ snapshot: RegistrationSnapshot, id: String? = nil) throws {
        let matchesID = id.map { snapshot.id.caseInsensitiveCompare($0) == .orderedSame } ?? true
        guard snapshot.workoutVersion != nil, case .workout = snapshot.proposal,
              ["pending", "confirmed", "cancelled", "expired"].contains(snapshot.status),
              matchesID else {
            throw BodyFlowCapabilityError.serviceUnavailable
        }
    }

    private static func input(_ request: WorkoutProposalRequest, protocol value: WorkoutRegistrationProtocol?) -> WorkoutProposalRequest {
        WorkoutProposalRequest(
            workoutType: request.workoutType, durationMin: request.durationMin,
            intensity: request.intensity, performedAt: request.performedAt,
            registrationProtocol: value
        )
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
        case .alreadyConfirmed:
            // The record is saved; the device holds no confirmed snapshot of
            // it and keeps no draft to send again.
            currentProposal = nil
            pendingDraft = nil
            confirmedRegistration = nil
            phase = .confirmed
            invalidationCenter.record(.registrationConfirmed)
        case let .workoutCurrent(response):
            let snapshot = response.data
            confirmedRegistration = snapshot.status == "confirmed" ? snapshot : nil
            currentProposal = snapshot.status == "confirmed" ? nil : snapshot
            phase = snapshot.status == "confirmed" ? .confirmed : .proposal
            invalidationCenter.record(keys: snapshot.status == "confirmed" ? [.today, .history] : [.today])
        }
        if case .workoutCurrent = receipt {} else { retainedFailedAttempt = nil }
        requiresCurrentReview = false
        mutationState = .succeeded(receipt)
        captureError = nil
        accessibilityFocusTarget = .operationSummary
        clearActiveOperation(operation)
    }

    private func publishFailure(_ attempt: RegistrationMutationAttempt, error: any Error, operation: ActiveWorkoutOperation, reviewing: Bool = false) {
        let receivedError = Self.capabilityError(from: error)
        let capabilityError: BodyFlowCapabilityError = attempt.isVersionedWorkout && receivedError == .registrationAlreadyConfirmed
            ? .registrationReviewRequired : receivedError
        // `409 registration_already_confirmed`: this proposal's record is
        // already saved. That is the confirmed outcome, not a failure.
        if capabilityError == .registrationAlreadyConfirmed,
           let registrationID = attempt.registrationID {
            publishSuccess(.alreadyConfirmed(registrationID: registrationID), operation: operation)
            return
        }
        guard claimPublication(operation) else { return }
        let needsReview = [
            BodyFlowCapabilityError.registrationRevisionConflict, .registrationReviewRequired, .registrationAuthorityStale,
        ].contains(capabilityError)
        // A legacy attempt can be refused because the server now requires
        // a version. Keep that original attempt untouched; only an owned GET
        // can supply authority for a later, explicit patient action.
        if attempt.isVersionedWorkout || needsReview || reviewing { retainedFailedAttempt = attempt }
        captureError = capabilityError
        if reviewing {
            requiresCurrentReview = true
            mutationState = .failed(attempt, capabilityError)
        } else if Self.invalidatesPending(capabilityError) {
            currentProposal = nil
            if !attempt.isVersionedWorkout { pendingDraft = nil }
            requiresCurrentReview = false
            phase = .form
            mutationState = .idle
        } else {
            if needsReview { requiresCurrentReview = true }
            mutationState = capabilityError == .operationUnavailable
                ? .unavailable
                : .failed(attempt, capabilityError)
        }
        accessibilityFocusTarget = .operationSummary
        clearActiveOperation(operation)
    }

    private func publishAttemptConstructionFailure(_ error: any Error) {
        guard isSessionActive() else { return }
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
        isReviewingCurrent = false
    }

    private func mayContinue(_ operation: ActiveWorkoutOperation) -> Bool {
        isSessionActive() && !Task.isCancelled && !operation.ownership.isInvalidated
            && operation.sequence == operationSequence
            && activeOwnership === operation.ownership
    }

    private func claimPublication(_ operation: ActiveWorkoutOperation) -> Bool {
        mayContinue(operation) && operation.ownership.claimPublication()
    }

    private func clearActiveOperation(_ operation: ActiveWorkoutOperation) {
        if activeOwnership === operation.ownership {
            activeOwnership = nil
            isReviewingCurrent = false
        }
    }

    private func finishCancelledOperationIfNeeded(_ operation: ActiveWorkoutOperation) {
        guard operation.sequence == operationSequence,
              activeOwnership === operation.ownership,
              operation.ownership.isInvalidated || Task.isCancelled || !isSessionActive() else { return }
        activeOwnership = nil
        isReviewingCurrent = false
        if case .submitting = mutationState { mutationState = .idle }
    }

    private static func capabilityError(from error: any Error) -> BodyFlowCapabilityError {
        error as? BodyFlowCapabilityError ?? .serviceUnavailable
    }

    private static func invalidatesPending(_ error: BodyFlowCapabilityError) -> Bool {
        error == .registrationExpired || error == .registrationNotPending
    }
}

private extension RegistrationMutationAttempt {
    var isVersionedWorkout: Bool {
        switch self {
        case let .propose(attempt):
            if case let .workout(request) = attempt.payload { return request.registrationProtocol == .uiV1 }
            return false
        case let .edit(attempt): return attempt.payload.workoutVersion != nil
        case let .confirm(attempt), let .cancel(attempt): return attempt.payload.workoutVersion != nil
        }
    }
}

private struct ActiveWorkoutOperation: Sendable {
    let sequence: Int
    let ownership: FeatureLoadOwnership
}
