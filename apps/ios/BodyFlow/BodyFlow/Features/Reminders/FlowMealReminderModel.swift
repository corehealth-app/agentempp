import Foundation
import Observation

/// One notice in the currently authenticated Flow transcript.
@MainActor
@Observable
final class FlowMealReminderModel {
    private(set) var id: UUID?
    private(set) var reminder: FlowMealReminder?
    private(set) var isWorking = false
    private(set) var hasFailure = false
    private(set) var hasNoMatchingMeal = false
    private(set) var answerMeal: ConversationMealCommand.MealType?
    @ObservationIgnored private let repository: @Sendable () async throws -> any FlowMealReminderProviding
    @ObservationIgnored private var operation: UUID?

    init(repository: @escaping @Sendable () async throws -> any FlowMealReminderProviding) {
        self.repository = repository
    }

    func open(_ noticeID: UUID) {
        if id == noticeID { return }
        dismiss()
        id = noticeID
    }

    func beginAnswer() {
        guard reminder?.state == .pending, let meal = reminder?.mealType else { return }
        answerMeal = ConversationMealCommand.MealType(rawValue: meal.rawValue)
    }

    func dismiss() {
        id = nil
        reminder = nil
        operation = nil
        isWorking = false
        hasFailure = false
        hasNoMatchingMeal = false
        answerMeal = nil
    }

    func refresh(skip: Bool = false, alreadyLogged: Bool = false) async {
        guard let id, !isWorking else { return }
        let attempt = UUID()
        operation = attempt
        isWorking = true
        hasFailure = false
        hasNoMatchingMeal = false
        defer {
            if operation == attempt {
                isWorking = false
                operation = nil
            }
        }
        do {
            let provider = try await repository()
            let current = try await provider.reminder(id: id, skip: skip)
            try Task.checkCancellation()
            guard self.id == id, operation == attempt else { return }
            reminder = current
            hasNoMatchingMeal = alreadyLogged && current.state == .pending
            if current.state != .pending { answerMeal = nil }
        } catch is CancellationError {
            return
        } catch {
            guard self.id == id, operation == attempt else { return }
            hasFailure = true
        }
    }
}
