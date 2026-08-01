import Foundation
import Observation

@MainActor
@Observable
final class WeightRegistrationModel {
    private let recording: any WeightRecording
    private let timeProvider: any TimeProviding
    private let keyProvider: any IdempotencyKeyProviding
    private var activeOwnership: FeatureLoadOwnership?
    private var operationSequence = 0

    let initialRecordedAt: Date
    private(set) var mutationState = WeightMutationState.idle
    private(set) var captureError: BodyFlowCapabilityError?
    private(set) var accessibilityFocusTarget: RegistrationAccessibilityFocusTarget?

    var receipt: WeightDemoReceipt? { mutationState.receipt }

    var isSubmitting: Bool {
        if case .submitting = mutationState { true } else { false }
    }

    init(
        recording: any WeightRecording,
        timeProvider: any TimeProviding,
        keyProvider: any IdempotencyKeyProviding,
        invalidationCenter: FeatureInvalidationCenter
    ) {
        self.recording = recording
        self.timeProvider = timeProvider
        self.keyProvider = keyProvider
        initialRecordedAt = timeProvider.now
        _ = invalidationCenter
    }

    func submit(weightKG: Double, recordedAt: Date? = nil) async {
        guard !isSubmitting else { return }
        do {
            let command = try WeightCommand(
                weightKG: weightKG,
                recordedAt: recordedAt ?? initialRecordedAt
            )
            let attempt = try MutationAttempt(
                operation: .weight,
                key: keyProvider.nextKey(),
                payload: command,
                createdAt: timeProvider.now
            )
            await run(attempt)
        } catch is RoutineCommandValidationError {
            publishValidationFailure()
        } catch {
            publishConstructionFailure(error)
        }
    }

    func retry() async {
        guard case let .failed(attempt, _) = mutationState else { return }
        await run(attempt)
    }

    func startNewEntry() {
        invalidateActiveOperation()
        mutationState = .idle
        captureError = nil
        accessibilityFocusTarget = nil
    }

    func discardSheet() {
        invalidateActiveOperation()
        accessibilityFocusTarget = nil
        if case .submitting = mutationState { mutationState = .idle }
    }

    func consumeAccessibilityFocus() { accessibilityFocusTarget = nil }

    private func run(_ attempt: MutationAttempt<WeightCommand>) async {
        guard !isSubmitting else { return }
        let operation = beginOperation()
        mutationState = .submitting(attempt)
        captureError = nil
        accessibilityFocusTarget = nil

        await withTaskCancellationHandler {
            do {
                let receipt = try await recording.record(attempt)
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

    private func publishSuccess(
        _ receipt: WeightDemoReceipt,
        operation: ActiveWeightOperation
    ) {
        guard claimPublication(operation) else { return }
        mutationState = .succeeded(receipt)
        captureError = nil
        accessibilityFocusTarget = .operationSummary
        clearActiveOperation(operation)
    }

    private func publishFailure(
        _ attempt: MutationAttempt<WeightCommand>,
        error: any Error,
        operation: ActiveWeightOperation
    ) {
        guard claimPublication(operation) else { return }
        let capabilityError = Self.capabilityError(from: error)
        captureError = capabilityError
        mutationState = capabilityError == .operationUnavailable
            ? .unavailable
            : .failed(attempt, capabilityError)
        accessibilityFocusTarget = .operationSummary
        clearActiveOperation(operation)
    }

    private func publishValidationFailure() {
        guard !isSubmitting else { return }
        mutationState = .idle
        captureError = .invalidInput
        accessibilityFocusTarget = .operationSummary
    }

    private func publishConstructionFailure(_ error: any Error) {
        let capabilityError = Self.capabilityError(from: error)
        captureError = capabilityError
        if capabilityError == .operationUnavailable { mutationState = .unavailable }
        accessibilityFocusTarget = .operationSummary
    }

    private func beginOperation() -> ActiveWeightOperation {
        activeOwnership?.invalidate()
        operationSequence += 1
        let ownership = FeatureLoadOwnership()
        activeOwnership = ownership
        return ActiveWeightOperation(sequence: operationSequence, ownership: ownership)
    }

    private func invalidateActiveOperation() {
        activeOwnership?.invalidate()
        operationSequence += 1
        activeOwnership = nil
    }

    private func mayContinue(_ operation: ActiveWeightOperation) -> Bool {
        !Task.isCancelled && !operation.ownership.isInvalidated
            && operation.sequence == operationSequence
            && activeOwnership === operation.ownership
    }

    private func claimPublication(_ operation: ActiveWeightOperation) -> Bool {
        mayContinue(operation) && operation.ownership.claimPublication()
    }

    private func clearActiveOperation(_ operation: ActiveWeightOperation) {
        if activeOwnership === operation.ownership { activeOwnership = nil }
    }

    private func finishCancelledOperationIfNeeded(_ operation: ActiveWeightOperation) {
        guard operation.sequence == operationSequence,
              activeOwnership === operation.ownership,
              operation.ownership.isInvalidated || Task.isCancelled
        else { return }
        activeOwnership = nil
        if case .submitting = mutationState { mutationState = .idle }
    }

    private static func capabilityError(from error: any Error) -> BodyFlowCapabilityError {
        error as? BodyFlowCapabilityError ?? .serviceUnavailable
    }
}

private struct ActiveWeightOperation: Sendable {
    let sequence: Int
    let ownership: FeatureLoadOwnership
}
