import Foundation
import Observation

enum WorkoutStrengthClarificationFailure: Equatable, Sendable {
    case capability(BodyFlowCapabilityError)
    case contextUnavailable
    case answerConflict
    case disabled
}

/// Owns one workout under the original authenticated context. A locally stopped
/// wait says nothing about server cancellation; its immutable intent survives.
@MainActor
@Observable
final class WorkoutStrengthClarificationModel {
    let workoutID: String
    private(set) var snapshot: WorkoutStrengthClarification?
    private(set) var failure: WorkoutStrengthClarificationFailure?
    private(set) var pendingAttempt: MutationAttempt<WorkoutStrengthAnswerCommand>?
    private(set) var isLoading = false
    private(set) var isSubmitting = false

    private let provider: any WorkoutStrengthClarificationProviding
    private let timeProvider: any TimeProviding
    private let keyProvider: any IdempotencyKeyProviding
    private let invalidationCenter: FeatureInvalidationCenter
    private let isSessionActive: @MainActor @Sendable () -> Bool
    private var mutationBlock: WorkoutStrengthClarificationFailure?
    private var sequence = 0
    private var activeOwnership: FeatureLoadOwnership?

    init(workoutID: String, provider: any WorkoutStrengthClarificationProviding,
         timeProvider: any TimeProviding, keyProvider: any IdempotencyKeyProviding,
         invalidationCenter: FeatureInvalidationCenter,
         isSessionActive: @escaping @MainActor @Sendable () -> Bool) throws {
        guard let workoutID = WorkoutStrengthWire.uuid(workoutID) else {
            throw BodyFlowCapabilityError.invalidInput
        }
        self.workoutID = workoutID
        self.provider = provider
        self.timeProvider = timeProvider
        self.keyProvider = keyProvider
        self.invalidationCenter = invalidationCenter
        self.isSessionActive = isSessionActive
    }

    var isBusy: Bool { isLoading || isSubmitting }
    var canAnswer: Bool {
        guard isSessionActive(), !isBusy, failure == nil, mutationBlock == nil,
              pendingAttempt == nil, case let .unanswered(question) = snapshot else { return false }
        return question.scope.workoutID == workoutID
    }
    var canRetryAnswer: Bool {
        isSessionActive() && !isBusy && pendingAttempt != nil && mutationBlock == nil
    }

    func load() async {
        guard snapshot == nil, !isBusy else { return }
        await reload()
    }

    /// Explicit reads may supersede old reads, but never an in-flight POST.
    /// They cannot rewrite or rebase the retained answer command.
    func reload() async {
        guard isSessionActive(), !Task.isCancelled, !isSubmitting else { return }
        let operation = beginOperation()
        isLoading = true
        failure = nil
        await withTaskCancellationHandler {
            do {
                let response = try await provider.load(workoutID: workoutID)
                guard response.data.workoutID == nil || response.data.workoutID == workoutID else {
                    throw BodyFlowCapabilityError.serviceUnavailable
                }
                guard claimPublication(operation) else { return }
                publishRead(response.data)
                finish(operation)
            } catch { publishFailure(error, operation: operation) }
        } onCancel: { operation.ownership.invalidate() }
        finishCancelled(operation)
    }

    func answer(_ answer: WorkoutStrengthAnswer) async {
        guard canAnswer, !Task.isCancelled, case let .unanswered(question) = snapshot else { return }
        do {
            let key = try keyProvider.nextKey()
            guard WorkoutStrengthWire.uuid(key.value) != nil else {
                throw BodyFlowCapabilityError.invalidIdempotencyKey
            }
            let attempt = MutationAttempt(operation: .workoutStrengthAnswer, key: key,
                payload: WorkoutStrengthAnswerCommand(question: question, answer: answer), createdAt: timeProvider.now)
            pendingAttempt = attempt
            await send(attempt)
        } catch {
            guard isSessionActive(), !Task.isCancelled else { return }
            failure = Self.failure(from: error)
        }
    }

    func retryAnswer() async {
        guard canRetryAnswer, !Task.isCancelled, let pendingAttempt else { return }
        await send(pendingAttempt)
    }

    /// Ends this local wait only. In particular, never enables an opposite
    /// answer after a POST whose persisted outcome is still unknown.
    func cancel() {
        activeOwnership?.invalidate()
        sequence += 1
        activeOwnership = nil
        isLoading = false
        isSubmitting = false
    }

    private func send(_ attempt: MutationAttempt<WorkoutStrengthAnswerCommand>) async {
        let operation = beginOperation()
        isSubmitting = true
        failure = nil
        await withTaskCancellationHandler {
            do {
                let response = try await provider.answer(attempt)
                guard case let .answered(receipt) = response.data, Self.matches(receipt, attempt: attempt) else {
                    throw BodyFlowCapabilityError.serviceUnavailable
                }
                guard claimPublication(operation) else { return }
                snapshot = response.data
                resolveAttempt()
                finish(operation)
            } catch { publishFailure(error, operation: operation) }
        } onCancel: { operation.ownership.invalidate() }
        finishCancelled(operation)
    }

    private func publishRead(_ value: WorkoutStrengthClarification) {
        snapshot = value
        guard let attempt = pendingAttempt else {
            mutationBlock = nil
            failure = nil
            return
        }
        switch value {
        case let .answered(receipt) where Self.matches(receipt, attempt: attempt):
            resolveAttempt()
        case let .unanswered(question) where question == attempt.payload.question:
            // Even a definitive failure cannot be erased by reading revision0.
            failure = mutationBlock
        default:
            mutationBlock = if case .answered = value { .answerConflict } else { .contextUnavailable }
            failure = mutationBlock
        }
    }

    private func resolveAttempt() {
        pendingAttempt = nil
        mutationBlock = nil
        failure = nil
        invalidationCenter.record(keys: [.today, .history])
    }

    private static func matches(_ receipt: WorkoutStrengthAnswerReceipt,
                                attempt: MutationAttempt<WorkoutStrengthAnswerCommand>) -> Bool {
        receipt.scope == attempt.payload.question.scope
            && receipt.questionKey == attempt.payload.question.questionKey
            && receipt.answer == attempt.payload.answer
    }

    private func publishFailure(_ error: any Error, operation: StrengthQuestionOperation) {
        if error is CancellationError {
            operation.ownership.invalidate()
            return
        }
        guard claimPublication(operation) else { return }
        let result = Self.failure(from: error)
        failure = result
        switch result {
        case .contextUnavailable, .answerConflict, .disabled: mutationBlock = result
        case .capability: break
        }
        finish(operation)
    }

    private static func failure(from error: any Error) -> WorkoutStrengthClarificationFailure {
        switch error {
        case WorkoutStrengthClarificationError.contextUnavailable: .contextUnavailable
        case WorkoutStrengthClarificationError.answerConflict: .answerConflict
        case WorkoutStrengthClarificationError.disabled: .disabled
        default: .capability(error as? BodyFlowCapabilityError ?? .serviceUnavailable)
        }
    }

    private func beginOperation() -> StrengthQuestionOperation {
        activeOwnership?.invalidate()
        sequence += 1
        let ownership = FeatureLoadOwnership()
        activeOwnership = ownership
        return StrengthQuestionOperation(sequence: sequence, ownership: ownership)
    }
    private func owns(_ operation: StrengthQuestionOperation) -> Bool {
        operation.sequence == sequence && activeOwnership === operation.ownership
    }
    private func claimPublication(_ operation: StrengthQuestionOperation) -> Bool {
        isSessionActive() && !Task.isCancelled && owns(operation) && operation.ownership.claimPublication()
    }
    private func finish(_ operation: StrengthQuestionOperation) {
        guard owns(operation) else { return }
        activeOwnership = nil
        isLoading = false
        isSubmitting = false
    }
    private func finishCancelled(_ operation: StrengthQuestionOperation) {
        guard owns(operation), operation.ownership.isInvalidated || Task.isCancelled || !isSessionActive() else { return }
        finish(operation)
    }
}

private struct StrengthQuestionOperation: Sendable {
    let sequence: Int
    let ownership: FeatureLoadOwnership
}
