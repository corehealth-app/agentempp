struct UnavailableBodyFlowCapabilities:
    TodayProviding,
    HistoryProviding,
    PlanProviding,
    ProgressProviding,
    MealDetectionProviding,
    RegistrationProviding,
    HydrationRecording,
    WeightRecording,
    RoutineProviding,
    PublishedContentListing,
    PublishedContentDetailProviding,
    PublishedContentStateRecording,
    PublishedContentSessionLifetime,
    CoachExperienceProviding
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

    func detect(
        _ input: MealDetectionInput
    ) async throws -> RegistrationProposalRequest {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func propose(
        _ attempt: MutationAttempt<RegistrationProposalRequest>
    ) async throws -> RegistrationProposalResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func edit(
        _ attempt: MutationAttempt<RegistrationEditCommand>
    ) async throws -> RegistrationProposalResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func confirm(
        _ attempt: MutationAttempt<RegistrationIDCommand>
    ) async throws -> RegistrationConfirmationResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func cancel(
        _ attempt: MutationAttempt<RegistrationIDCommand>
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

    func content(
        _ query: ContentFeedQuery
    ) async throws -> PublishedContentFeedResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func contentDetail(
        publicationID: String
    ) async throws -> PublishedContentDetailResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func recordRead(
        _ attempt: MutationAttempt<ContentReadCommand>
    ) async throws -> PublishedContentStateResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func setSaved(
        _ attempt: MutationAttempt<ContentSaveCommand>
    ) async throws -> PublishedContentStateResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func endSession() async {}

    func coachExperience() async throws -> CoachExperienceResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }
}

struct UnavailablePublishedContentSessionFactory:
    PublishedContentSessionCreating {
    func makeSession(userID: String) -> PublishedContentSession {
        let unavailable = UnavailableBodyFlowCapabilities()
        return PublishedContentSession(
            listing: unavailable,
            detail: unavailable,
            state: unavailable,
            lifetime: unavailable
        )
    }
}

struct UnavailableCoachExperienceSessionFactory:
    CoachExperienceSessionCreating {
    func makeCoachExperience(
        userID: String
    ) -> any CoachExperienceProviding {
        UnavailableBodyFlowCapabilities()
    }
}

struct UnavailableContentCoverSessionFactory: ContentCoverSessionCreating {
    private let stream: any ContentCoverByteStreaming

    init(
        stream: any ContentCoverByteStreaming =
            UnavailableContentCoverByteStream()
    ) {
        self.stream = stream
    }

    func makeLoader(userID: String) -> any ContentCoverLoading {
        ContentCoverLoader(
            stream: stream,
            origin: nil,
            decoder: ContentCoverDecoder(),
            cache: SessionCoverCache(),
            timeProvider: SystemTimeProvider()
        )
    }
}

struct UnavailableContentCoverByteStream: ContentCoverByteStreaming {
    func stream(
        _ request: ContentCoverTransportRequest
    ) async throws -> ContentCoverByteStream {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func cancelAll() async {}
}
