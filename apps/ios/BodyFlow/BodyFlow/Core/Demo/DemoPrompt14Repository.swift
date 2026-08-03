#if DEBUG
import Foundation

actor DemoPrompt14Repository:
    PublishedContentListing,
    PublishedContentDetailProviding,
    PublishedContentStateRecording,
    PublishedContentSessionLifetime
{
    private enum ReadKey: Hashable {
        case feed(ContentFeedQuery)
        case detail(String)
    }

    private let scenario: DemoPrompt14Scenario
    private var generation: UInt64 = 0
    private var ended = false
    private var readCounts: [ReadKey: Int] = [:]
    private var nextPendingReadID: UInt64 = 0
    private var pendingReads: [UInt64: CheckedContinuation<Void, any Error>] = [:]

    init(scenario: DemoPrompt14Scenario) {
        self.scenario = scenario
    }

    func content(
        _ query: ContentFeedQuery
    ) async throws -> PublishedContentFeedResponse {
        let operationGeneration = try await prepareRead(.feed(query))
        let response = try DemoPrompt14Fixtures.feed(
            for: query,
            empty: scenario == .empty
        )
        try PublishedContentContractValidator.validate(response.data)
        try requireCurrent(operationGeneration)
        return response
    }

    func contentDetail(
        publicationID: String
    ) async throws -> PublishedContentDetailResponse {
        let operationGeneration = try await prepareRead(.detail(publicationID))
        guard publicationID == DemoPrompt14Fixtures.firstSummary.publicationID else {
            throw BodyFlowCapabilityError.contentNotFound
        }

        switch scenario {
        case .contentNotFound:
            throw BodyFlowCapabilityError.contentNotFound
        case .subscriptionRequired:
            throw BodyFlowCapabilityError.subscriptionRequired
        default:
            break
        }

        let response = scenario == .markdownInvalid
            ? DemoPrompt14Fixtures.invalidMarkdownDetailResponse
            : DemoPrompt14Fixtures.validDetailResponse
        try PublishedContentContractValidator.validate(response.data)
        _ = try BodyFlowMarkdownParser().parse(response.data.bodyMarkdown)
        try requireCurrent(operationGeneration)
        return response
    }

    func recordRead(
        _ attempt: MutationAttempt<ContentReadCommand>
    ) async throws -> PublishedContentStateResponse {
        _ = attempt
        guard !ended else { throw CancellationError() }
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func setSaved(
        _ attempt: MutationAttempt<ContentSaveCommand>
    ) async throws -> PublishedContentStateResponse {
        _ = attempt
        guard !ended else { throw CancellationError() }
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func endSession() async {
        guard !ended else { return }
        ended = true
        generation &+= 1
        readCounts.removeAll(keepingCapacity: false)
        let continuations = Array(pendingReads.values)
        pendingReads.removeAll(keepingCapacity: false)
        for continuation in continuations {
            continuation.resume(throwing: CancellationError())
        }
    }

    private func prepareRead(_ key: ReadKey) async throws -> UInt64 {
        guard !ended else { throw CancellationError() }
        let operationGeneration = generation

        switch scenario {
        case .loading:
            try await waitUntilSessionEnds()
        case .offline:
            throw BodyFlowCapabilityError.offline
        case .error:
            throw BodyFlowCapabilityError.serviceUnavailable
        case .unavailable:
            throw BodyFlowCapabilityError.operationUnavailable
        case .stale:
            let count = readCounts[key, default: 0]
            readCounts[key] = count + 1
            if count > 0 {
                throw BodyFlowCapabilityError.offline
            }
        case .loaded,
             .empty,
             .openedError,
             .contentNotFound,
             .subscriptionRequired,
             .markdownInvalid,
             .coverInvalid,
             .mascotVariants,
             .progressEmpty,
             .progressMinimum,
             .streakZero,
             .conflict,
             .reduceMotion,
             .differentiateWithoutColor:
            break
        }

        try requireCurrent(operationGeneration)
        return operationGeneration
    }

    private func waitUntilSessionEnds() async throws {
        nextPendingReadID &+= 1
        let pendingReadID = nextPendingReadID
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                guard !ended else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                pendingReads[pendingReadID] = continuation
            }
        }, onCancel: {
            Task {
                await self.cancelPendingRead(pendingReadID)
            }
        })
    }

    private func cancelPendingRead(_ pendingReadID: UInt64) {
        pendingReads.removeValue(forKey: pendingReadID)?
            .resume(throwing: CancellationError())
    }

    private func requireCurrent(_ operationGeneration: UInt64) throws {
        guard !ended, generation == operationGeneration else {
            throw CancellationError()
        }
        try Task.checkCancellation()
    }
}

struct DemoPrompt14PublishedContentSessionFactory:
    PublishedContentSessionCreating
{
    let scenario: DemoPrompt14Scenario

    func makeSession(userID: String) -> PublishedContentSession {
        _ = userID
        let repository = DemoPrompt14Repository(scenario: scenario)
        return PublishedContentSession(
            listing: repository,
            detail: repository,
            state: repository,
            lifetime: repository
        )
    }
}

actor DemoPrompt14CoachProvider: CoachExperienceProviding {
    private let scenario: DemoPrompt14Scenario
    private var nextMascotVariantIndex = 0

    init(scenario: DemoPrompt14Scenario) {
        self.scenario = scenario
    }

    func coachExperience() async throws -> CoachExperienceResponse {
        switch scenario {
        case .loading:
            try await Task.sleep(for: .milliseconds(100))
        case .offline:
            throw BodyFlowCapabilityError.offline
        case .error:
            throw BodyFlowCapabilityError.serviceUnavailable
        case .unavailable:
            throw BodyFlowCapabilityError.operationUnavailable
        default:
            break
        }

        let response: CoachExperienceResponse
        if scenario == .mascotVariants {
            if nextMascotVariantIndex == DemoPrompt14Fixtures.coachResponses.count {
                nextMascotVariantIndex = 0
            }
            response = DemoPrompt14Fixtures.coachResponses[nextMascotVariantIndex]
            nextMascotVariantIndex += 1
        } else {
            response = DemoPrompt14Fixtures.balancedCoachResponse
        }
        guard CoachExperienceV1PresentationContract.validatedSnapshot(
            from: response
        ) != nil else {
            throw BodyFlowCapabilityError.unsupportedCoachContract
        }
        return response
    }
}

struct DemoPrompt14CoachExperienceSessionFactory:
    CoachExperienceSessionCreating
{
    let scenario: DemoPrompt14Scenario

    func makeCoachExperience(
        userID: String
    ) -> any CoachExperienceProviding {
        _ = userID
        return DemoPrompt14CoachProvider(scenario: scenario)
    }
}

struct DemoPrompt14ProgressProvider: ProgressProviding {
    let response: ProgressResponse

    func progress() async throws -> ProgressResponse {
        response
    }
}

struct DemoPrompt14ContentCoverSessionFactory: ContentCoverSessionCreating {
    let scenario: DemoPrompt14Scenario
    let timeProvider: any TimeProviding

    func makeLoader(userID: String) -> any ContentCoverLoading {
        _ = userID
        let origin = URL(string: "https://prompt14-fixture.invalid")
            .flatMap { try? ContentCoverTrustedOrigin(validating: $0) }
        return ContentCoverLoader(
            stream: DemoContentCoverByteStream(scenario: scenario),
            origin: origin,
            decoder: ContentCoverDecoder(),
            cache: SessionCoverCache(),
            timeProvider: timeProvider
        )
    }
}
#endif
