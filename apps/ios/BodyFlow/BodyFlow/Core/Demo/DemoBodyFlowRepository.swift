#if DEBUG
import Foundation

actor DemoBodyFlowRepository:
    TodayProviding,
    MealDetectionProviding,
    RegistrationProviding,
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

    private enum OpenRegistration {
        case mealInitial
        case mealEdited
        case workoutInitial
        case workoutEdited

        var response: RegistrationProposalResponse {
            switch self {
            case .mealInitial:
                DemoBodyFlowFixtures.pendingMealRegistration
            case .mealEdited:
                DemoBodyFlowFixtures.editedMealRegistration
            case .workoutInitial:
                DemoBodyFlowFixtures.pendingWorkoutRegistration
            case .workoutEdited:
                DemoBodyFlowFixtures.editedWorkoutRegistration
            }
        }

        var edited: OpenRegistration {
            switch self {
            case .mealInitial, .mealEdited:
                .mealEdited
            case .workoutInitial, .workoutEdited:
                .workoutEdited
            }
        }

        var isMeal: Bool {
            switch self {
            case .mealInitial, .mealEdited:
                true
            case .workoutInitial, .workoutEdited:
                false
            }
        }

        var confirmation: RegistrationConfirmationResponse {
            switch self {
            case .mealInitial:
                DemoBodyFlowFixtures.confirmedMealRegistration
            case .mealEdited:
                DemoBodyFlowFixtures.confirmedEditedMealRegistration
            case .workoutInitial:
                DemoBodyFlowFixtures.confirmedWorkoutRegistration
            case .workoutEdited:
                DemoBodyFlowFixtures.confirmedEditedWorkoutRegistration
            }
        }

        var cancellation: RegistrationCancellationResponse {
            switch self {
            case .mealInitial:
                DemoBodyFlowFixtures.cancelledMealRegistration
            case .mealEdited:
                DemoBodyFlowFixtures.cancelledEditedMealRegistration
            case .workoutInitial:
                DemoBodyFlowFixtures.cancelledWorkoutRegistration
            case .workoutEdited:
                DemoBodyFlowFixtures.cancelledEditedWorkoutRegistration
            }
        }
    }

    private enum ConfirmationState {
        case none
        case mealInitial
        case mealEdited
        case workoutInitial
        case workoutEdited
        case mealInitialWorkoutInitial
        case mealEditedWorkoutInitial
        case mealInitialWorkoutEdited
        case mealEditedWorkoutEdited

        func confirming(_ registration: OpenRegistration) -> ConfirmationState {
            switch registration {
            case .mealInitial:
                switch self {
                case .workoutInitial,
                     .mealInitialWorkoutInitial,
                     .mealEditedWorkoutInitial:
                    .mealInitialWorkoutInitial
                case .workoutEdited,
                     .mealInitialWorkoutEdited,
                     .mealEditedWorkoutEdited:
                    .mealInitialWorkoutEdited
                case .none, .mealInitial, .mealEdited:
                    .mealInitial
                }
            case .mealEdited:
                switch self {
                case .workoutInitial,
                     .mealInitialWorkoutInitial,
                     .mealEditedWorkoutInitial:
                    .mealEditedWorkoutInitial
                case .workoutEdited,
                     .mealInitialWorkoutEdited,
                     .mealEditedWorkoutEdited:
                    .mealEditedWorkoutEdited
                case .none, .mealInitial, .mealEdited:
                    .mealEdited
                }
            case .workoutInitial:
                switch self {
                case .mealInitial,
                     .mealInitialWorkoutInitial,
                     .mealInitialWorkoutEdited:
                    .mealInitialWorkoutInitial
                case .mealEdited,
                     .mealEditedWorkoutInitial,
                     .mealEditedWorkoutEdited:
                    .mealEditedWorkoutInitial
                case .none, .workoutInitial, .workoutEdited:
                    .workoutInitial
                }
            case .workoutEdited:
                switch self {
                case .mealInitial,
                     .mealInitialWorkoutInitial,
                     .mealInitialWorkoutEdited:
                    .mealInitialWorkoutEdited
                case .mealEdited,
                     .mealEditedWorkoutInitial,
                     .mealEditedWorkoutEdited:
                    .mealEditedWorkoutEdited
                case .none, .workoutInitial, .workoutEdited:
                    .workoutEdited
                }
            }
        }

        var today: TodayResponse? {
            switch self {
            case .none:
                nil
            case .mealInitial:
                DemoBodyFlowFixtures.postMealConfirmationToday
            case .mealEdited:
                DemoBodyFlowFixtures.postEditedMealConfirmationToday
            case .workoutInitial:
                DemoBodyFlowFixtures.postWorkoutConfirmationToday
            case .workoutEdited:
                DemoBodyFlowFixtures.postEditedWorkoutConfirmationToday
            case .mealInitialWorkoutInitial:
                DemoBodyFlowFixtures.postInitialMealInitialWorkoutConfirmationToday
            case .mealEditedWorkoutInitial:
                DemoBodyFlowFixtures.postEditedMealInitialWorkoutConfirmationToday
            case .mealInitialWorkoutEdited:
                DemoBodyFlowFixtures.postInitialMealEditedWorkoutConfirmationToday
            case .mealEditedWorkoutEdited:
                DemoBodyFlowFixtures.postEditedMealEditedWorkoutConfirmationToday
            }
        }

        var history: HistoryResponse? {
            switch self {
            case .none:
                nil
            case .mealInitial:
                DemoBodyFlowFixtures.postMealConfirmationHistory
            case .mealEdited:
                DemoBodyFlowFixtures.postEditedMealConfirmationHistory
            case .workoutInitial:
                DemoBodyFlowFixtures.postWorkoutConfirmationHistory
            case .workoutEdited:
                DemoBodyFlowFixtures.postEditedWorkoutConfirmationHistory
            case .mealInitialWorkoutInitial:
                DemoBodyFlowFixtures.postInitialMealInitialWorkoutConfirmationHistory
            case .mealEditedWorkoutInitial:
                DemoBodyFlowFixtures.postEditedMealInitialWorkoutConfirmationHistory
            case .mealInitialWorkoutEdited:
                DemoBodyFlowFixtures.postInitialMealEditedWorkoutConfirmationHistory
            case .mealEditedWorkoutEdited:
                DemoBodyFlowFixtures.postEditedMealEditedWorkoutConfirmationHistory
            }
        }
    }

    private enum ReplayEntry {
        case propose(
            MutationAttempt<RegistrationProposalRequest>,
            RegistrationProposalResponse
        )
        case edit(
            MutationAttempt<RegistrationEditCommand>,
            RegistrationProposalResponse
        )
        case confirm(
            MutationAttempt<RegistrationIDCommand>,
            RegistrationConfirmationResponse
        )
        case cancel(
            MutationAttempt<RegistrationIDCommand>,
            RegistrationCancellationResponse
        )
    }

    private let scenario: DemoBodyFlowScenario
    private var readCounts: [ReadCapability: Int] = [:]
    private var openRegistrations: [String: OpenRegistration] = [:]
    private var confirmationState = ConfirmationState.none
    private var replayLedger: [IdempotencyKey: ReplayEntry] = [:]
    private var consumedRegistrationFailure = false

    init(scenario: DemoBodyFlowScenario) {
        self.scenario = scenario
    }

    func detect(
        _ input: MealDetectionInput
    ) async throws -> RegistrationProposalRequest {
        switch input {
        case .text:
            DemoBodyFlowFixtures.detectedTextMealRequest
        case .photoSample:
            DemoBodyFlowFixtures.detectedPhotoMealRequest
        case .audioSample:
            DemoBodyFlowFixtures.detectedAudioMealRequest
        }
    }

    func propose(
        _ attempt: MutationAttempt<RegistrationProposalRequest>
    ) async throws -> RegistrationProposalResponse {
        if let replay = replayLedger[attempt.key] {
            guard case let .propose(originalAttempt, result) = replay,
                  originalAttempt == attempt
            else {
                throw BodyFlowCapabilityError.idempotencyConflict
            }
            return result
        }
        guard attempt.operation == .proposalCreate else {
            throw BodyFlowCapabilityError.invalidInput
        }
        try prepareRegistrationMutation()

        let pending: OpenRegistration = switch attempt.payload {
        case .meal:
            .mealInitial
        case .workout:
            .workoutInitial
        }
        let result = pending.response
        openRegistrations[result.data.id] = pending
        replayLedger[attempt.key] = .propose(attempt, result)
        return result
    }

    func edit(
        _ attempt: MutationAttempt<RegistrationEditCommand>
    ) async throws -> RegistrationProposalResponse {
        if let replay = replayLedger[attempt.key] {
            guard case let .edit(originalAttempt, result) = replay,
                  originalAttempt == attempt
            else {
                throw BodyFlowCapabilityError.idempotencyConflict
            }
            return result
        }
        guard attempt.operation == .proposalEdit else {
            throw BodyFlowCapabilityError.invalidInput
        }
        try prepareRegistrationMutation()

        let pending = try requireOpenRegistration(
            id: attempt.payload.registrationID,
            at: attempt.createdAt
        )
        guard pending.isMeal == attempt.payload.proposal.isMeal else {
            throw BodyFlowCapabilityError.invalidInput
        }
        let edited = pending.edited
        openRegistrations[attempt.payload.registrationID] = edited
        let result = edited.response
        replayLedger[attempt.key] = .edit(attempt, result)
        return result
    }

    func confirm(
        _ attempt: MutationAttempt<RegistrationIDCommand>
    ) async throws -> RegistrationConfirmationResponse {
        if let replay = replayLedger[attempt.key] {
            guard case let .confirm(originalAttempt, result) = replay,
                  originalAttempt == attempt
            else {
                throw BodyFlowCapabilityError.idempotencyConflict
            }
            return result
        }
        guard attempt.operation == .proposalConfirm else {
            throw BodyFlowCapabilityError.invalidInput
        }
        try prepareRegistrationMutation()

        let pending = try requireOpenRegistration(
            id: attempt.payload.registrationID,
            at: attempt.createdAt
        )
        openRegistrations.removeValue(forKey: attempt.payload.registrationID)
        confirmationState = confirmationState.confirming(pending)
        let result = pending.confirmation
        replayLedger[attempt.key] = .confirm(attempt, result)
        return result
    }

    func cancel(
        _ attempt: MutationAttempt<RegistrationIDCommand>
    ) async throws -> RegistrationCancellationResponse {
        if let replay = replayLedger[attempt.key] {
            guard case let .cancel(originalAttempt, result) = replay,
                  originalAttempt == attempt
            else {
                throw BodyFlowCapabilityError.idempotencyConflict
            }
            return result
        }
        guard attempt.operation == .proposalCancel else {
            throw BodyFlowCapabilityError.invalidInput
        }
        try prepareRegistrationMutation()

        let pending = try requireOpenRegistration(
            id: attempt.payload.registrationID,
            at: attempt.createdAt
        )
        openRegistrations.removeValue(forKey: attempt.payload.registrationID)
        let result = pending.cancellation
        replayLedger[attempt.key] = .cancel(attempt, result)
        return result
    }

    func today() async throws -> TodayResponse {
        try await prepareRead(.today)
        if let confirmedToday = confirmationState.today {
            return confirmedToday
        }
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
        if let confirmedHistory = confirmationState.history {
            return confirmedHistory
        }
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

    private func prepareRegistrationMutation() throws {
        guard scenario == .registrationFailureOnce,
              !consumedRegistrationFailure
        else {
            return
        }
        consumedRegistrationFailure = true
        throw BodyFlowCapabilityError.serviceUnavailable
    }

    private func requireOpenRegistration(
        id: String,
        at attemptDate: Date
    ) throws -> OpenRegistration {
        guard let pending = openRegistrations[id] else {
            throw BodyFlowCapabilityError.registrationNotPending
        }
        guard attemptDate < pending.response.data.expiresAt.value else {
            openRegistrations.removeValue(forKey: id)
            throw BodyFlowCapabilityError.registrationExpired
        }
        return pending
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

private extension RegistrationProposalRequest {
    var isMeal: Bool {
        switch self {
        case .meal:
            true
        case .workout:
            false
        }
    }
}
#endif
