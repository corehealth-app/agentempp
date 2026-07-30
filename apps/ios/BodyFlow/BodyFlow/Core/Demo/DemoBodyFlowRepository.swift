#if DEBUG
import Foundation

actor DemoBodyFlowRepository:
    TodayProviding,
    PlanProviding,
    ProgressProviding,
    HistoryProviding,
    RoutineProviding
{
    private enum ReadCapability: Hashable {
        case today
        case plan
        case progress
        case history
        case routineList(RoutineItemKind)
        case routineHistory(RoutineItemKind)
    }

    private let scenario: DemoBodyFlowScenario
    private var readCounts: [ReadCapability: Int] = [:]

    init(scenario: DemoBodyFlowScenario) {
        self.scenario = scenario
    }

    func today() async throws -> TodayResponse {
        try await prepareRead(.today)
        return scenario == .empty
            ? DemoBodyFlowFixtures.emptyToday
            : scenario == .incompleteDay
                ? DemoBodyFlowFixtures.incompleteToday
                : DemoBodyFlowFixtures.loadedToday
    }

    func plan() async throws -> PlanResponse {
        try await prepareRead(.plan)
        return scenario == .empty
            ? DemoBodyFlowFixtures.emptyPlan
            : DemoBodyFlowFixtures.loadedPlan
    }

    func progress() async throws -> ProgressResponse {
        try await prepareRead(.progress)
        return scenario == .empty
            ? DemoBodyFlowFixtures.emptyProgress
            : DemoBodyFlowFixtures.loadedProgress
    }

    func history(_ query: HistoryQuery) async throws -> HistoryResponse {
        _ = query
        try await prepareRead(.history)
        return scenario == .empty
            ? DemoBodyFlowFixtures.emptyHistory
            : DemoBodyFlowFixtures.loadedHistory
    }

    func list(
        kind: RoutineItemKind,
        includeArchived: Bool
    ) async throws -> RoutineListResponse {
        _ = includeArchived
        try await prepareRead(.routineList(kind))
        guard scenario != .empty else {
            return DemoBodyFlowFixtures.emptyRoutineList
        }
        return switch kind {
        case .supplement:
            DemoBodyFlowFixtures.loadedSupplementList
        case .medication:
            DemoBodyFlowFixtures.loadedMedicationList
        }
    }

    func record(
        _ attempt: MutationAttempt<RoutineActionCommand>
    ) async throws -> RoutineActionResponse {
        _ = attempt
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func history(
        kind: RoutineItemKind,
        itemID: String,
        cursor: String?,
        limit: Int
    ) async throws -> RoutineHistoryPage {
        _ = itemID
        _ = cursor
        _ = limit
        try await prepareRead(.routineHistory(kind))
        guard scenario != .empty else {
            return DemoBodyFlowFixtures.emptyRoutineHistory
        }
        return switch kind {
        case .supplement:
            DemoBodyFlowFixtures.loadedSupplementHistory
        case .medication:
            DemoBodyFlowFixtures.loadedMedicationHistory
        }
    }

    private func prepareRead(_ capability: ReadCapability) async throws {
        switch scenario {
        case .loadingDelay:
            try await Task.sleep(for: .milliseconds(100))
        case .initialOffline:
            throw BodyFlowCapabilityError.offline
        case .initialError:
            throw BodyFlowCapabilityError.serviceUnavailable
        case .unavailablePresentation:
            throw BodyFlowCapabilityError.operationUnavailable
        case .staleOffline:
            try consumeFirstRead(
                of: capability,
                thenThrow: .offline
            )
        case .staleError:
            try consumeFirstRead(
                of: capability,
                thenThrow: .serviceUnavailable
            )
        case .loaded,
             .empty,
             .incompleteDay,
             .registrationFailureOnce,
             .routineConflictOnce,
             .reduceMotionVerification:
            break
        }
    }

    private func consumeFirstRead(
        of capability: ReadCapability,
        thenThrow error: BodyFlowCapabilityError
    ) throws {
        let count = readCounts[capability, default: 0]
        readCounts[capability] = count + 1
        if count > 0 {
            throw error
        }
    }
}
#endif
