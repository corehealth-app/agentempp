#if DEBUG
import Foundation

actor DemoBodyFlowRepository:
    TodayProviding,
    MealDetectionProviding,
    RegistrationProviding,
    HydrationRecording,
    WeightRecording,
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

        var fixtureVariant: DemoConfirmationVariant {
            switch self {
            case .none:
                .none
            case .mealInitial:
                .mealInitial
            case .mealEdited:
                .mealEdited
            case .workoutInitial:
                .workoutInitial
            case .workoutEdited:
                .workoutEdited
            case .mealInitialWorkoutInitial:
                .mealInitialWorkoutInitial
            case .mealEditedWorkoutInitial:
                .mealEditedWorkoutInitial
            case .mealInitialWorkoutEdited:
                .mealInitialWorkoutEdited
            case .mealEditedWorkoutEdited:
                .mealEditedWorkoutEdited
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
        case hydration(
            MutationAttempt<HydrationCommand>,
            HydrationReceipt
        )
        case weight(
            MutationAttempt<WeightCommand>,
            WeightDemoReceipt
        )
        case routine(
            MutationAttempt<RoutineActionCommand>,
            RoutineActionResponse
        )
    }

    private let scenario: DemoBodyFlowScenario
    private var readCounts: [ReadCapability: Int] = [:]
    private var openRegistrations: [String: OpenRegistration] = [:]
    private var confirmationState = ConfirmationState.none
    private var hydrationRecorded = false
    private var supplementRoutineVariant = DemoRoutineVariant.baseline
    private var medicationRoutineVariant = DemoRoutineVariant.baseline
    private var replayLedger: [IdempotencyKey: ReplayEntry] = [:]
    private var consumedRegistrationFailure = false
    private var consumedRoutineConflict = false

    init(scenario: DemoBodyFlowScenario) {
        self.scenario = scenario
    }

    private func replayResult<Payload, Result>(
        for attempt: MutationAttempt<Payload>,
        extracting: (ReplayEntry) -> (MutationAttempt<Payload>, Result)?
    ) throws -> Result? where Payload: Hashable & Sendable {
        guard let entry = replayLedger[attempt.key] else {
            return nil
        }
        guard let (originalAttempt, result) = extracting(entry),
              originalAttempt == attempt else {
            throw BodyFlowCapabilityError.idempotencyConflict
        }
        return result
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
        if let result: RegistrationProposalResponse = try replayResult(
            for: attempt,
            extracting: { entry in
                guard case let .propose(originalAttempt, result) = entry else {
                    return nil
                }
                return (originalAttempt, result)
            }
        ) {
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
        if let result: RegistrationProposalResponse = try replayResult(
            for: attempt,
            extracting: { entry in
                guard case let .edit(originalAttempt, result) = entry else {
                    return nil
                }
                return (originalAttempt, result)
            }
        ) {
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
        if let result: RegistrationConfirmationResponse = try replayResult(
            for: attempt,
            extracting: { entry in
                guard case let .confirm(originalAttempt, result) = entry else {
                    return nil
                }
                return (originalAttempt, result)
            }
        ) {
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
        if let result: RegistrationCancellationResponse = try replayResult(
            for: attempt,
            extracting: { entry in
                guard case let .cancel(originalAttempt, result) = entry else {
                    return nil
                }
                return (originalAttempt, result)
            }
        ) {
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

    func record(
        _ attempt: MutationAttempt<HydrationCommand>
    ) async throws -> HydrationReceipt {
        try prepareTask11Mutation(requiresRoutineOccurrence: false)
        if let result: HydrationReceipt = try replayResult(
            for: attempt,
            extracting: { entry in
                guard case let .hydration(originalAttempt, result) = entry else {
                    return nil
                }
                return (originalAttempt, result)
            }
        ) {
            return result
        }
        guard attempt.operation == .hydration else {
            throw BodyFlowCapabilityError.invalidInput
        }

        let result = DemoBodyFlowFixtures.hydrationReceipt
        hydrationRecorded = true
        replayLedger[attempt.key] = .hydration(attempt, result)
        return result
    }

    func record(
        _ attempt: MutationAttempt<WeightCommand>
    ) async throws -> WeightDemoReceipt {
        try prepareTask11Mutation(requiresRoutineOccurrence: false)
        if let result: WeightDemoReceipt = try replayResult(
            for: attempt,
            extracting: { entry in
                guard case let .weight(originalAttempt, result) = entry else {
                    return nil
                }
                return (originalAttempt, result)
            }
        ) {
            return result
        }
        guard attempt.operation == .weight else {
            throw BodyFlowCapabilityError.invalidInput
        }

        let result = WeightDemoReceipt(
            weightKG: attempt.payload.weightKG,
            recordedAt: attempt.payload.recordedAt,
            label: "Demonstração local; não sincronizado"
        )
        replayLedger[attempt.key] = .weight(attempt, result)
        return result
    }

    func today() async throws -> TodayResponse {
        try await prepareRead(.today)
        if hydrationRecorded,
           confirmationState.fixtureVariant == .none,
           supplementRoutineVariant == .baseline,
           medicationRoutineVariant == .baseline {
            if scenario == .empty {
                return DemoBodyFlowFixtures.postEmptyHydrationToday
            }
            if scenario == .incompleteDay {
                return DemoBodyFlowFixtures.postIncompleteHydrationToday
            }
        }
        if confirmationState.fixtureVariant != .none
            || hydrationRecorded
            || supplementRoutineVariant != .baseline
            || medicationRoutineVariant != .baseline {
            return DemoBodyFlowFixtures.today(
                confirmation: confirmationState.fixtureVariant,
                hydrationRecorded: hydrationRecorded,
                routine: supplementRoutineVariant,
                medication: medicationRoutineVariant
            )
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
            switch supplementRoutineVariant {
            case .baseline:
                DemoBodyFlowFixtures.loadedSupplementList
            case .conflictReloaded:
                DemoBodyFlowFixtures.routineConflictSupplementList
            case .taken, .snoozedThenTaken:
                DemoBodyFlowFixtures.postRoutineTakenSupplementList
            case .skipped, .snoozedThenSkipped:
                DemoBodyFlowFixtures.postRoutineSkippedSupplementList
            case .snoozed, .snoozedThenSnoozed:
                DemoBodyFlowFixtures.postRoutineSnoozedSupplementList
            }
        case .medication:
            switch medicationRoutineVariant {
            case .baseline, .conflictReloaded:
                DemoBodyFlowFixtures.loadedMedicationList
            case .taken, .snoozedThenTaken:
                DemoBodyFlowFixtures.postMedicationTakenList
            case .skipped, .snoozedThenSkipped:
                DemoBodyFlowFixtures.postMedicationSkippedList
            case .snoozed, .snoozedThenSnoozed:
                DemoBodyFlowFixtures.postMedicationSnoozedList
            }
        }
    }

    func record(
        _ attempt: MutationAttempt<RoutineActionCommand>
    ) async throws -> RoutineActionResponse {
        try prepareTask11Mutation(requiresRoutineOccurrence: true)
        if let result: RoutineActionResponse = try replayResult(
            for: attempt,
            extracting: { entry in
                guard case let .routine(originalAttempt, result) = entry else {
                    return nil
                }
                return (originalAttempt, result)
            }
        ) {
            return result
        }
        guard attempt.operation == .routineAction else {
            throw BodyFlowCapabilityError.invalidInput
        }
        try validateRoutineCommand(attempt.payload)

        if scenario == .routineConflictOnce,
           attempt.payload.kind == .supplement,
           !consumedRoutineConflict {
            consumedRoutineConflict = true
            supplementRoutineVariant = .conflictReloaded
            throw BodyFlowCapabilityError.routineTransitionInvalid
        }
        let currentVariant = attempt.payload.kind == .supplement
            ? supplementRoutineVariant
            : medicationRoutineVariant
        let transition = try routineTransition(
            from: currentVariant,
            kind: attempt.payload.kind,
            status: attempt.payload.status
        )
        if attempt.payload.kind == .supplement {
            supplementRoutineVariant = transition.variant
        } else {
            medicationRoutineVariant = transition.variant
        }
        let result = transition.receipt
        replayLedger[attempt.key] = .routine(attempt, result)
        return result
    }

    func history(
        kind: RoutineItemKind,
        itemID: String,
        cursor: String?,
        limit: Int
    ) async throws -> RoutineHistoryPage {
        try await prepareRead(.routineHistory(kind))
        guard (1...50).contains(limit) else {
            throw BodyFlowCapabilityError.invalidInput
        }
        guard scenario != .empty else {
            return DemoBodyFlowFixtures.emptyRoutineHistory
        }
        return switch kind {
        case .supplement:
            try supplementHistory(itemID: itemID, cursor: cursor)
        case .medication:
            try medicationHistory(itemID: itemID, cursor: cursor)
        }
    }

    private func routineTransition(
        from variant: DemoRoutineVariant,
        kind: RoutineItemKind,
        status: RoutineActionStatus
    ) throws -> (variant: DemoRoutineVariant, receipt: RoutineActionResponse) {
        switch variant {
        case .baseline, .conflictReloaded:
            let nextVariant: DemoRoutineVariant = switch status {
            case .taken: .taken
            case .skipped: .skipped
            case .snoozed: .snoozed
            }
            let receipt: RoutineActionResponse = switch (kind, status) {
            case (.supplement, .taken):
                DemoBodyFlowFixtures.routineTakenReceipt
            case (.supplement, .skipped):
                DemoBodyFlowFixtures.routineSkippedReceipt
            case (.supplement, .snoozed):
                DemoBodyFlowFixtures.routineSnoozedReceipt
            case (.medication, .taken):
                DemoBodyFlowFixtures.medicationTakenReceipt
            case (.medication, .skipped):
                DemoBodyFlowFixtures.medicationSkippedReceipt
            case (.medication, .snoozed):
                DemoBodyFlowFixtures.medicationSnoozedReceipt
            }
            return (nextVariant, receipt)
        case .snoozed:
            let nextVariant: DemoRoutineVariant = switch status {
            case .taken: .snoozedThenTaken
            case .skipped: .snoozedThenSkipped
            case .snoozed: .snoozedThenSnoozed
            }
            let receipt: RoutineActionResponse = switch (kind, status) {
            case (.supplement, .taken):
                DemoBodyFlowFixtures.routineSnoozedThenTakenReceipt
            case (.supplement, .skipped):
                DemoBodyFlowFixtures.routineSnoozedThenSkippedReceipt
            case (.supplement, .snoozed):
                DemoBodyFlowFixtures.routineSnoozedThenSnoozedReceipt
            case (.medication, .taken):
                DemoBodyFlowFixtures.medicationSnoozedThenTakenReceipt
            case (.medication, .skipped):
                DemoBodyFlowFixtures.medicationSnoozedThenSkippedReceipt
            case (.medication, .snoozed):
                DemoBodyFlowFixtures.medicationSnoozedThenSnoozedReceipt
            }
            return (nextVariant, receipt)
        case .taken,
             .skipped,
             .snoozedThenTaken,
             .snoozedThenSkipped,
             .snoozedThenSnoozed:
            throw BodyFlowCapabilityError.routineTransitionInvalid
        }
    }

    private func validateRoutineCommand(
        _ command: RoutineActionCommand
    ) throws {
        let targetScheduledFor = Date(timeIntervalSince1970: 1_784_545_200)
        let targetOccurredAt = Date(timeIntervalSince1970: 1_784_589_300)
        let targetsAuthoredOccurrence: Bool = switch command.kind {
        case .supplement:
            command.itemID == "supplement-1"
                && command.reminderRuleID == "rule-08"
                && command.scheduledFor.value == targetScheduledFor
        case .medication:
            command.itemID == "medication-1"
                && command.reminderRuleID == "medication-rule-09"
                && command.scheduledFor.value
                    == Date(timeIntervalSince1970: 1_784_548_800)
        }
        guard targetsAuthoredOccurrence,
              command.occurredAt.value == targetOccurredAt else {
            throw BodyFlowCapabilityError.routineTransitionInvalid
        }

        guard command.status == .snoozed else {
            return
        }
        guard let snoozedUntil = command.snoozedUntil?.value,
              let timeZone = TimeZone(identifier: "America/Sao_Paulo")
        else {
            throw BodyFlowCapabilityError.routineSnoozeInvalid
        }
        let policy = RoutineSnoozePolicy(timeZone: timeZone)
        guard policy.date(
            for: .custom(snoozedUntil),
            scheduledFor: command.scheduledFor.value,
            occurredAt: command.occurredAt.value
        ) != nil else {
            throw BodyFlowCapabilityError.routineSnoozeInvalid
        }
        guard snoozedUntil == Date(timeIntervalSince1970: 1_784_591_100) else {
            throw BodyFlowCapabilityError.routineTransitionInvalid
        }
    }

    private func supplementHistory(
        itemID: String,
        cursor: String?
    ) throws -> RoutineHistoryPage {
        guard itemID == "supplement-1" else {
            throw BodyFlowCapabilityError.invalidInput
        }
        if let cursor {
            guard cursor == DemoBodyFlowFixtures.documentedRoutineHistoryCursor else {
                throw BodyFlowCapabilityError.invalidInput
            }
            return DemoBodyFlowFixtures.secondSupplementHistoryPage
        }

        return switch supplementRoutineVariant {
        case .baseline:
            DemoBodyFlowFixtures.loadedSupplementHistory
        case .conflictReloaded:
            DemoBodyFlowFixtures.routineConflictSupplementHistory
        case .taken:
            DemoBodyFlowFixtures.postRoutineTakenSupplementHistory
        case .skipped:
            DemoBodyFlowFixtures.postRoutineSkippedSupplementHistory
        case .snoozed:
            DemoBodyFlowFixtures.postRoutineSnoozedSupplementHistory
        case .snoozedThenTaken:
            DemoBodyFlowFixtures.postRoutineSnoozedThenTakenSupplementHistory
        case .snoozedThenSkipped:
            DemoBodyFlowFixtures.postRoutineSnoozedThenSkippedSupplementHistory
        case .snoozedThenSnoozed:
            DemoBodyFlowFixtures.postRoutineSnoozedThenSnoozedSupplementHistory
        }
    }

    private func medicationHistory(
        itemID: String,
        cursor: String?
    ) throws -> RoutineHistoryPage {
        guard itemID == "medication-1", cursor == nil else {
            throw BodyFlowCapabilityError.invalidInput
        }
        return switch medicationRoutineVariant {
        case .baseline, .conflictReloaded:
            DemoBodyFlowFixtures.loadedMedicationHistory
        case .taken:
            DemoBodyFlowFixtures.postMedicationTakenHistory
        case .skipped:
            DemoBodyFlowFixtures.postMedicationSkippedHistory
        case .snoozed:
            DemoBodyFlowFixtures.postMedicationSnoozedHistory
        case .snoozedThenTaken:
            DemoBodyFlowFixtures.postMedicationSnoozedThenTakenHistory
        case .snoozedThenSkipped:
            DemoBodyFlowFixtures.postMedicationSnoozedThenSkippedHistory
        case .snoozedThenSnoozed:
            DemoBodyFlowFixtures.postMedicationSnoozedThenSnoozedHistory
        }
    }

    private func prepareRead(_ capability: ReadCapability) async throws {
        switch scenario {
        case .loadingDelay:
            try await Task.sleep(for: .milliseconds(100))
        case .initialOffline:
            try await preparePersistentFailure(
                of: capability,
                error: .offline
            )
        case .initialError:
            try await preparePersistentFailure(
                of: capability,
                error: .serviceUnavailable
            )
        case .unavailablePresentation:
            throw BodyFlowCapabilityError.operationUnavailable
        case .staleOffline:
            try await delayRepeatedRead(of: capability)
            try consumeFirstRead(
                of: capability,
                thenThrow: .offline
            )
        case .staleError:
            try await delayRepeatedRead(of: capability)
            try consumeFirstRead(
                of: capability,
                thenThrow: .serviceUnavailable
            )
        case .loaded,
             .empty,
             .incompleteDay,
             .registrationFailureOnce,
             .routineConflictOnce,
             .routineActionUnavailable,
             .reduceMotionVerification:
            break
        }
    }

    private func preparePersistentFailure(
        of capability: ReadCapability,
        error: BodyFlowCapabilityError
    ) async throws {
        let count = readCounts[capability, default: 0]
        readCounts[capability] = count + 1
        if count > 0 {
            try await Task.sleep(for: .milliseconds(1_500))
        }
        throw error
    }

    private func delayRepeatedRead(
        of capability: ReadCapability
    ) async throws {
        if readCounts[capability, default: 0] > 0 {
            try await Task.sleep(for: .milliseconds(1_500))
        }
    }

    private func prepareRegistrationMutation() throws {
        if scenario == .unavailablePresentation {
            throw BodyFlowCapabilityError.operationUnavailable
        }
        guard scenario == .registrationFailureOnce,
              !consumedRegistrationFailure
        else {
            return
        }
        consumedRegistrationFailure = true
        throw BodyFlowCapabilityError.serviceUnavailable
    }

    private func prepareTask11Mutation(
        requiresRoutineOccurrence: Bool
    ) throws {
        if scenario == .unavailablePresentation {
            throw BodyFlowCapabilityError.operationUnavailable
        }
        if !requiresRoutineOccurrence {
            try prepareRegistrationMutation()
        }
        if requiresRoutineOccurrence,
           scenario == .routineActionUnavailable {
            throw BodyFlowCapabilityError.operationUnavailable
        }
        if requiresRoutineOccurrence,
           scenario == .empty || scenario == .incompleteDay {
            throw BodyFlowCapabilityError.routineTransitionInvalid
        }
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
