import Foundation
import Observation

@MainActor
@Observable
final class HydrationRegistrationModel {
    private let recording: any HydrationRecording
    private let timeProvider: any TimeProviding
    private let keyProvider: any IdempotencyKeyProviding
    private let invalidationCenter: FeatureInvalidationCenter
    private var activeOwnership: FeatureLoadOwnership?
    private var operationSequence = 0

    let initialOccurredAt: Date
    private(set) var mutationState = HydrationMutationState.idle
    private(set) var captureError: BodyFlowCapabilityError?
    private(set) var accessibilityFocusTarget: RegistrationAccessibilityFocusTarget?

    var receipt: HydrationReceipt? { mutationState.receipt }

    var isSubmitting: Bool {
        if case .submitting = mutationState { true } else { false }
    }

    init(
        recording: any HydrationRecording,
        timeProvider: any TimeProviding,
        keyProvider: any IdempotencyKeyProviding,
        invalidationCenter: FeatureInvalidationCenter
    ) {
        self.recording = recording
        self.timeProvider = timeProvider
        self.keyProvider = keyProvider
        self.invalidationCenter = invalidationCenter
        initialOccurredAt = timeProvider.now
    }

    func submitQuick(_ amountML: Int, occurredAt: Date? = nil) async {
        guard [250, 500, 750].contains(amountML) else {
            publishValidationFailure()
            return
        }
        await submit(amountML: amountML, occurredAt: occurredAt ?? initialOccurredAt)
    }

    func submitCustom(_ input: String, occurredAt: Date? = nil) async {
        guard let amountML = Int(input), String(amountML) == input else {
            publishValidationFailure()
            return
        }
        await submit(amountML: amountML, occurredAt: occurredAt ?? initialOccurredAt)
    }

    func submit(amountML: Int, occurredAt: Date? = nil) async {
        guard !isSubmitting else { return }
        do {
            let command = try HydrationCommand(
                amountML: amountML,
                occurredAt: APITimestamp(value: occurredAt ?? initialOccurredAt)
            )
            let attempt = try MutationAttempt(
                operation: .hydration,
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

    private func run(_ attempt: MutationAttempt<HydrationCommand>) async {
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
        _ receipt: HydrationReceipt,
        operation: ActiveHydrationOperation
    ) {
        guard claimPublication(operation) else { return }
        mutationState = .succeeded(receipt)
        captureError = nil
        invalidationCenter.record(.hydrationRecorded)
        accessibilityFocusTarget = .operationSummary
        clearActiveOperation(operation)
    }

    private func publishFailure(
        _ attempt: MutationAttempt<HydrationCommand>,
        error: any Error,
        operation: ActiveHydrationOperation
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
        captureError = .invalidInput
        accessibilityFocusTarget = .operationSummary
    }

    private func publishConstructionFailure(_ error: any Error) {
        let capabilityError = Self.capabilityError(from: error)
        captureError = capabilityError
        if capabilityError == .operationUnavailable { mutationState = .unavailable }
        accessibilityFocusTarget = .operationSummary
    }

    private func beginOperation() -> ActiveHydrationOperation {
        activeOwnership?.invalidate()
        operationSequence += 1
        let ownership = FeatureLoadOwnership()
        activeOwnership = ownership
        return ActiveHydrationOperation(sequence: operationSequence, ownership: ownership)
    }

    private func invalidateActiveOperation() {
        activeOwnership?.invalidate()
        operationSequence += 1
        activeOwnership = nil
    }

    private func mayContinue(_ operation: ActiveHydrationOperation) -> Bool {
        !Task.isCancelled && !operation.ownership.isInvalidated
            && operation.sequence == operationSequence
            && activeOwnership === operation.ownership
    }

    private func claimPublication(_ operation: ActiveHydrationOperation) -> Bool {
        mayContinue(operation) && operation.ownership.claimPublication()
    }

    private func clearActiveOperation(_ operation: ActiveHydrationOperation) {
        if activeOwnership === operation.ownership { activeOwnership = nil }
    }

    private func finishCancelledOperationIfNeeded(_ operation: ActiveHydrationOperation) {
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

private struct ActiveHydrationOperation: Sendable {
    let sequence: Int
    let ownership: FeatureLoadOwnership
}
