import Foundation

enum RegistrationSheetOperationIntent: Equatable, Sendable {
    case capture(MealCaptureSource)
    case operationAction(RegistrationOperationAction)
    case edit(MealProposalRequest)
    case confirm
    case cancel
    case workoutProposal(WorkoutProposalRequest)
    case workoutEdit(WorkoutProposalRequest)
}

@MainActor
final class RegistrationSheetTaskCoordinator {
    private var activeIntent: RegistrationSheetOperationIntent?
    private var activeTask: Task<Void, Never>?
    private var sequence = 0

    func perform(
        _ intent: RegistrationSheetOperationIntent,
        operation: @escaping @MainActor () async -> Void
    ) {
        guard activeIntent != intent else { return }

        activeTask?.cancel()
        sequence += 1
        let currentSequence = sequence
        activeIntent = intent
        activeTask = Task { [weak self] in
            await operation()
            guard !Task.isCancelled,
                  self?.sequence == currentSequence
            else {
                return
            }
            self?.activeIntent = nil
            self?.activeTask = nil
        }
    }

    func discard() {
        activeTask?.cancel()
        activeTask = nil
        activeIntent = nil
        sequence += 1
    }
}
