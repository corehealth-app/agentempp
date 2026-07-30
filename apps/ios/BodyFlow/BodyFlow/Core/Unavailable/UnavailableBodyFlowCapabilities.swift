struct UnavailableBodyFlowCapabilities:
    TodayProviding,
    HistoryProviding,
    PlanProviding,
    ProgressProviding,
    MealDetectionProviding,
    RegistrationProviding,
    HydrationRecording,
    WeightRecording,
    RoutineProviding
{
    func today() async throws -> TodayResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func history(_ query: HistoryQuery) async throws -> HistoryResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func plan() async throws -> PlanResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func progress() async throws -> ProgressResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func detectMeal(
        from input: MealDetectionInput
    ) async throws -> RegistrationProposalRequest {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func propose(
        _ request: RegistrationProposalRequest
    ) async throws -> RegistrationProposalResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func edit(
        _ command: RegistrationEditCommand
    ) async throws -> RegistrationProposalResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func confirm(
        _ command: RegistrationIDCommand
    ) async throws -> RegistrationConfirmationResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func cancel(
        _ command: RegistrationIDCommand
    ) async throws -> RegistrationCancellationResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func record(
        _ attempt: MutationAttempt<HydrationCommand>
    ) async throws -> HydrationReceipt {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func record(
        _ attempt: MutationAttempt<WeightCommand>
    ) async throws -> WeightDemoReceipt {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func list(
        kind: RoutineItemKind,
        includeArchived: Bool
    ) async throws -> RoutineListResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func record(
        _ attempt: MutationAttempt<RoutineActionCommand>
    ) async throws -> RoutineActionResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func history(
        kind: RoutineItemKind,
        itemID: String,
        cursor: String?,
        limit: Int
    ) async throws -> RoutineHistoryPage {
        throw BodyFlowCapabilityError.operationUnavailable
    }
}
