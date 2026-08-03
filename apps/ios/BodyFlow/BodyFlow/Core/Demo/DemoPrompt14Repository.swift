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

    private struct MutableContentState: Equatable {
        var saved: Bool
        var completed: Bool
    }

    private enum LedgerIdentity: Hashable {
        case read(
            operation: MutationOperation,
            command: ContentReadCommand,
            createdAt: Date
        )
        case save(
            operation: MutationOperation,
            command: ContentSaveCommand,
            createdAt: Date
        )
    }

    private enum LedgerEntry {
        case inProgress(LedgerIdentity)
        case completed(LedgerIdentity, PublishedContentStateResponse)

        var identity: LedgerIdentity {
            switch self {
            case let .inProgress(identity), let .completed(identity, _):
                identity
            }
        }
    }

    private enum MutationStart {
        case started(UInt64)
        case replayed(PublishedContentStateResponse)
    }

    private let scenario: DemoPrompt14Scenario
    private let mutationGate: DemoPrompt14MutationGate?
    private let mutationCommitGate: DemoPrompt14MutationGate?
    private var generation: UInt64 = 0
    private var ended = false
    private var readCounts: [ReadKey: Int] = [:]
    private var nextPendingReadID: UInt64 = 0
    private var pendingReads: [UInt64: CheckedContinuation<Void, any Error>] = [:]
    private var nextPendingReadObserverID: UInt64 = 0
    private var pendingReadObservers: [
        UInt64: (
            minimumCount: Int,
            continuation: CheckedContinuation<Void, Never>
        )
    ] = [:]
    private var mutableContentStates: [String: MutableContentState] = [:]
    private var idempotencyLedger: [IdempotencyKey: LedgerEntry] = [:]
    private var didFailOpened = false
    private var didFailStateMutation = false

    init(
        scenario: DemoPrompt14Scenario,
        mutationGate: DemoPrompt14MutationGate? = nil,
        mutationCommitGate: DemoPrompt14MutationGate? = nil
    ) {
        self.scenario = scenario
        self.mutationGate = mutationGate
        self.mutationCommitGate = mutationCommitGate
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
        return overlay(response, for: query)
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
        return overlay(response)
    }

    func recordRead(
        _ attempt: MutationAttempt<ContentReadCommand>
    ) async throws -> PublishedContentStateResponse {
        let identity = LedgerIdentity.read(
            operation: attempt.operation,
            command: attempt.payload,
            createdAt: attempt.createdAt
        )
        if let replay = try existingMutationResponse(
            key: attempt.key,
            identity: identity
        ) {
            return replay
        }
        guard attempt.operation == .contentRead else {
            throw BodyFlowCapabilityError.invalidInput
        }
        let summary = try authoredSummary(
            publicationID: attempt.payload.publicationID,
            version: attempt.payload.body.version
        )
        let mutationStart = try beginMutation(
            key: attempt.key,
            identity: identity
        )
        if case let .replayed(response) = mutationStart {
            return replayedResponse(response)
        }
        guard case let .started(operationGeneration) = mutationStart else {
            preconditionFailure("Mutation start must be started or replayed")
        }

        do {
            try requireCurrent(operationGeneration)
            try applyReadScenarioFailure(for: attempt.payload.body.event)
            try await waitForControlledMutation()
            try requireCurrent(operationGeneration)
            if let mutationCommitGate {
                try await mutationCommitGate.wait()
            }
            try requireCurrent(operationGeneration)

            var state = mutableState(for: summary)
            let changed: Bool
            let stateToPublish: MutableContentState?
            switch attempt.payload.body.event {
            case .impression, .opened:
                changed = true
                stateToPublish = nil
            case .completed:
                changed = !state.completed
                state.completed = true
                stateToPublish = state
            }

            let response = contentStateResponse(
                publicationID: summary.publicationID,
                version: summary.version,
                state: state,
                changed: changed,
                replayed: false
            )
            completeMutation(
                key: attempt.key,
                identity: identity,
                response: response,
                publicationID: summary.publicationID,
                state: stateToPublish
            )
            return response
        } catch {
            abandonMutation(key: attempt.key, identity: identity)
            throw error
        }
    }

    func setSaved(
        _ attempt: MutationAttempt<ContentSaveCommand>
    ) async throws -> PublishedContentStateResponse {
        let identity = LedgerIdentity.save(
            operation: attempt.operation,
            command: attempt.payload,
            createdAt: attempt.createdAt
        )
        if let replay = try existingMutationResponse(
            key: attempt.key,
            identity: identity
        ) {
            return replay
        }
        guard attempt.operation == .contentSave else {
            throw BodyFlowCapabilityError.invalidInput
        }
        let summary = try authoredSummary(
            publicationID: attempt.payload.publicationID,
            version: attempt.payload.body.version
        )
        let mutationStart = try beginMutation(
            key: attempt.key,
            identity: identity
        )
        if case let .replayed(response) = mutationStart {
            return replayedResponse(response)
        }
        guard case let .started(operationGeneration) = mutationStart else {
            preconditionFailure("Mutation start must be started or replayed")
        }

        do {
            try requireCurrent(operationGeneration)
            try applySaveScenarioFailure()
            try await waitForControlledMutation()
            try requireCurrent(operationGeneration)
            if let mutationCommitGate {
                try await mutationCommitGate.wait()
            }
            try requireCurrent(operationGeneration)

            var state = mutableState(for: summary)
            let changed = state.saved != attempt.payload.body.saved
            state.saved = attempt.payload.body.saved
            let response = contentStateResponse(
                publicationID: summary.publicationID,
                version: summary.version,
                state: state,
                changed: changed,
                replayed: false
            )
            completeMutation(
                key: attempt.key,
                identity: identity,
                response: response,
                publicationID: summary.publicationID,
                state: state
            )
            return response
        } catch {
            abandonMutation(key: attempt.key, identity: identity)
            throw error
        }
    }

    func endSession() async {
        guard !ended else { return }
        ended = true
        generation &+= 1
        readCounts.removeAll(keepingCapacity: false)
        mutableContentStates.removeAll(keepingCapacity: false)
        idempotencyLedger.removeAll(keepingCapacity: false)
        await mutationGate?.cancelAll()
        await mutationCommitGate?.cancelAll()
        let continuations = Array(pendingReads.values)
        pendingReads.removeAll(keepingCapacity: false)
        for continuation in continuations {
            continuation.resume(throwing: CancellationError())
        }
        let observers = pendingReadObservers.values.map(\.continuation)
        pendingReadObservers.removeAll(keepingCapacity: false)
        for observer in observers {
            observer.resume()
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
                resumeSatisfiedPendingReadObservers()
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

    private func authoredSummary(
        publicationID: String,
        version: Int
    ) throws -> PublishedContentSummary {
        guard let summary = DemoPrompt14Fixtures.summary(publicationID: publicationID) else {
            throw BodyFlowCapabilityError.contentNotFound
        }
        guard summary.version == version else {
            throw BodyFlowCapabilityError.contentVersionChanged
        }
        return summary
    }

    private func applyReadScenarioFailure(
        for event: ContentReadEvent
    ) throws {
        if scenario == .openedError, event == .opened, !didFailOpened {
            didFailOpened = true
            throw BodyFlowCapabilityError.serviceUnavailable
        }
        if scenario == .conflict, event == .completed, !didFailStateMutation {
            didFailStateMutation = true
            throw BodyFlowCapabilityError.contentVersionChanged
        }
    }

    private func applySaveScenarioFailure() throws {
        guard scenario == .conflict, !didFailStateMutation else { return }
        didFailStateMutation = true
        throw BodyFlowCapabilityError.contentVersionChanged
    }

    private func beginMutation(
        key: IdempotencyKey,
        identity: LedgerIdentity
    ) throws -> MutationStart {
        guard !ended else { throw CancellationError() }
        if let entry = idempotencyLedger[key] {
            guard entry.identity == identity else {
                throw BodyFlowCapabilityError.idempotencyConflict
            }
            switch entry {
            case .inProgress:
                throw BodyFlowCapabilityError.idempotencyRequestInProgress
            case let .completed(_, response):
                return .replayed(response)
            }
        }

        let operationGeneration = generation
        idempotencyLedger[key] = .inProgress(identity)
        return .started(operationGeneration)
    }

    private func existingMutationResponse(
        key: IdempotencyKey,
        identity: LedgerIdentity
    ) throws -> PublishedContentStateResponse? {
        guard !ended else { throw CancellationError() }
        guard let entry = idempotencyLedger[key] else { return nil }
        guard entry.identity == identity else {
            throw BodyFlowCapabilityError.idempotencyConflict
        }
        switch entry {
        case .inProgress:
            throw BodyFlowCapabilityError.idempotencyRequestInProgress
        case let .completed(_, response):
            return replayedResponse(response)
        }
    }

    private func replayedResponse(
        _ response: PublishedContentStateResponse
    ) -> PublishedContentStateResponse {
        PublishedContentStateResponse(
            data: PublishedContentState(
                publicationID: response.data.publicationID,
                version: response.data.version,
                saved: response.data.saved,
                completed: response.data.completed,
                changed: false,
                replayed: true
            ),
            meta: response.meta
        )
    }

    private func waitForControlledMutation() async throws {
        if let mutationGate {
            try await mutationGate.wait()
        } else if scenario == .loading {
            try await waitUntilSessionEnds()
        }
    }

    private func mutableState(
        for summary: PublishedContentSummary
    ) -> MutableContentState {
        if let state = mutableContentStates[summary.publicationID] {
            return state
        }
        return MutableContentState(
            saved: summary.saved,
            completed: summary.completed
        )
    }

    private func contentStateResponse(
        publicationID: String,
        version: Int,
        state: MutableContentState,
        changed: Bool,
        replayed: Bool
    ) -> PublishedContentStateResponse {
        PublishedContentStateResponse(
            data: PublishedContentState(
                publicationID: publicationID,
                version: version,
                saved: state.saved,
                completed: state.completed,
                changed: changed,
                replayed: replayed
            ),
            meta: DemoPrompt14Fixtures.contentStateMetadata
        )
    }

    private func completeMutation(
        key: IdempotencyKey,
        identity: LedgerIdentity,
        response: PublishedContentStateResponse,
        publicationID: String,
        state: MutableContentState?
    ) {
        if let state {
            mutableContentStates[publicationID] = state
        }
        idempotencyLedger[key] = .completed(identity, response)
    }

    private func abandonMutation(
        key: IdempotencyKey,
        identity: LedgerIdentity
    ) {
        guard case let .inProgress(storedIdentity)? = idempotencyLedger[key],
              storedIdentity == identity
        else {
            return
        }
        idempotencyLedger.removeValue(forKey: key)
    }

    private func overlay(
        _ response: PublishedContentFeedResponse,
        for query: ContentFeedQuery
    ) -> PublishedContentFeedResponse {
        let items: [PublishedContentSummary]
        if query.surface == .saved, !response.data.items.isEmpty {
            items = DemoPrompt14Fixtures.authoredSummaries
                .map(overlay)
                .filter(\.saved)
        } else {
            items = response.data.items.map(overlay)
        }
        return PublishedContentFeedResponse(
            data: PublishedContentFeed(
                items: items,
                nextCursor: response.data.nextCursor
            ),
            meta: response.meta
        )
    }

    private func overlay(
        _ response: PublishedContentDetailResponse
    ) -> PublishedContentDetailResponse {
        PublishedContentDetailResponse(
            data: PublishedContentDetail(
                summary: overlay(response.data.summary),
                bodyMarkdown: response.data.bodyMarkdown
            ),
            meta: response.meta
        )
    }

    private func overlay(
        _ summary: PublishedContentSummary
    ) -> PublishedContentSummary {
        guard let state = mutableContentStates[summary.publicationID] else {
            return summary
        }
        return PublishedContentSummary(
            publicationID: summary.publicationID,
            slug: summary.slug,
            locale: summary.locale,
            title: summary.title,
            excerpt: summary.excerpt,
            category: summary.category,
            tags: summary.tags,
            readingTimeMinutes: summary.readingTimeMinutes,
            publishAt: summary.publishAt,
            featuredToday: summary.featuredToday,
            version: summary.version,
            saved: state.saved,
            completed: state.completed,
            cover: summary.cover
        )
    }

    func mutationLedgerCountForTesting() -> Int {
        idempotencyLedger.count
    }

    func waitUntilPendingReadCountForTesting(_ count: Int) async {
        precondition(count > 0)
        guard pendingReads.count < count else { return }
        nextPendingReadObserverID &+= 1
        let observerID = nextPendingReadObserverID
        await withCheckedContinuation { continuation in
            pendingReadObservers[observerID] = (count, continuation)
        }
    }

    private func resumeSatisfiedPendingReadObservers() {
        let observerIDs = pendingReadObservers.compactMap { observerID, observer in
            pendingReads.count >= observer.minimumCount ? observerID : nil
        }
        for observerID in observerIDs {
            pendingReadObservers.removeValue(forKey: observerID)?
                .continuation.resume()
        }
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
