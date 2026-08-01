import Foundation

enum RegistrationSheetOperationIntent: Equatable, Sendable {
    case capture(MealCaptureSource)
    case operationAction(RegistrationOperationAction)
    case edit(MealProposalRequest)
    case confirm
    case cancel
    case workoutProposal(WorkoutProposalRequest)
    case workoutEdit(WorkoutProposalRequest)
    case hydration(amountML: Int?, customAmount: String, occurredAt: Date)
    case weight(value: Double?, recordedAt: Date)
}

@MainActor
final class RegistrationSheetTaskCoordinator {
    private struct PendingOperation {
        let intent: RegistrationSheetOperationIntent
        let operation: @MainActor () async -> Void
    }

    private var activeIntent: RegistrationSheetOperationIntent?
    private var activeTask: Task<Void, Never>?
    private var pendingOperation: PendingOperation?
    private var sequence = 0

    func perform(
        _ intent: RegistrationSheetOperationIntent,
        operation: @escaping @MainActor () async -> Void
    ) {
        guard activeIntent != intent else { return }

        if let activeTask {
            activeTask.cancel()
            pendingOperation = PendingOperation(intent: intent, operation: operation)
            activeIntent = intent
            return
        }

        start(intent, operation: operation)
    }

    func discard() {
        activeTask?.cancel()
        activeTask = nil
        activeIntent = nil
        pendingOperation = nil
        sequence += 1
    }

    private func start(
        _ intent: RegistrationSheetOperationIntent,
        operation: @escaping @MainActor () async -> Void
    ) {
        sequence += 1
        let currentSequence = sequence
        activeIntent = intent
        activeTask = Task { [weak self] in
            await operation()
            self?.finish(sequence: currentSequence)
        }
    }

    private func finish(sequence: Int) {
        guard self.sequence == sequence else { return }

        activeTask = nil
        if let pendingOperation {
            self.pendingOperation = nil
            start(pendingOperation.intent, operation: pendingOperation.operation)
        } else {
            activeIntent = nil
        }
    }
}
