import Foundation

@MainActor
final class HistoryFeatureCoordinator {
    private let model: HistoryViewModel

    init(model: HistoryViewModel) {
        self.model = model
    }

    func mealLogRow(for route: AppRoute) -> HistoryMealLogRow? {
        guard case let .historyMealLog(rowID) = route else { return nil }
        return model.mealLogRow(id: rowID)
    }

    func workoutLogRow(for route: AppRoute) -> HistoryWorkoutLogRow? {
        guard case let .historyWorkout(logID) = route else { return nil }
        return model.workoutLogRow(id: logID)
    }
}
