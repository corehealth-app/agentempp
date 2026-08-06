import Foundation
import Testing

@testable import BodyFlow

@Suite("Today recommendations")
@MainActor
struct TodayRecommendationsTests {
    @Test("recommendations use the fixed Today query and preserve server order")
    func fixedTodayQueryAndServerOrder() async throws {
        let items = [Self.item(1), Self.item(2), Self.item(3), Self.item(4)]
        let listing = RecommendationsListing([
            .success(Self.response(items: items, nextCursor: "not-used")),
        ])
        let recommendations = Self.model(listing: listing)

        await recommendations.load(catalogRevision: 7)

        #expect(await listing.queries() == [try ContentFeedQuery(
            surface: .today,
            category: nil,
            limit: 3,
            cursor: nil
        )])
        #expect(recommendations.items.map(\.publicationID) == items.prefix(3).map(\.publicationID))
    }

    @Test("recommendations do not paginate")
    func noPagination() async throws {
        let listing = RecommendationsListing([
            .success(Self.response(items: [Self.item(1)], nextCursor: "opaque")),
        ])
        let recommendations = Self.model(listing: listing)

        await recommendations.load(catalogRevision: 2)
        await recommendations.load(catalogRevision: 2)

        #expect(await listing.queries() == [try ContentFeedQuery(
            surface: .today,
            category: nil,
            limit: 3,
            cursor: nil
        )])
        #expect(recommendations.coverAuthorization(
            for: Self.item(1), catalogRevision: 2
        )?.revision == 2)
    }

    @Test("recommendation failure never replaces official Today state")
    func failureIsIsolated() async throws {
        let officialResponse = try BodyFlowTestFixtures.decodeInconsistentToday()
        let officialToday = TodayViewModel(
            provider: RecommendationsTodayProvider([.success(officialResponse)])
        )
        let recommendations = Self.model(listing: RecommendationsListing([
            .failure(.serviceUnavailable),
        ]))

        await officialToday.load(revision: 0)
        await recommendations.load(catalogRevision: 0)

        #expect(officialToday.state == .loaded(officialResponse.data))
        #expect(recommendations.state == .failed(
            previousValue: nil,
            error: .serviceUnavailable
        ))
    }

    @Test("offline error and unavailable capability stay within recommendations")
    func containedReadStates() async {
        for (outcome, expected) in [
            (
                Result<PublishedContentFeedResponse, BodyFlowCapabilityError>.failure(.offline),
                FeatureReadState<PublishedContentFeed>.offline(previousValue: nil)
            ),
            (
                .failure(.operationUnavailable),
                .unavailable
            ),
        ] {
            let recommendations = Self.model(
                listing: RecommendationsListing([outcome])
            )

            await recommendations.load(catalogRevision: 0)

            #expect(recommendations.state == expected)
        }
    }

    @Test("visible recommendations record only Today impressions")
    func todayImpression() async {
        let summary = Self.item(1)
        let recorder = RecommendationsStateRecorder()
        let recommendations = Self.model(
            listing: RecommendationsListing([
                .success(Self.response(items: [summary], nextCursor: nil)),
            ]),
            stateRecorder: recorder
        )

        await recommendations.load(catalogRevision: 0)
        await recommendations.recordImpression(for: summary)
        await recommendations.recordImpression(for: summary)

        let attempts = await recorder.readAttempts()
        #expect(attempts.map(\.payload.publicationID) == [summary.publicationID])
        #expect(attempts.map(\.payload.body) == [ContentReadBody(
            event: .impression,
            origin: .today,
            version: summary.version
        )])
    }

    @Test("Today recommendation cards navigate with their publication identity and Today origin")
    func todayCardRoute() {
        let summary = Self.item(1)

        #expect(TodayRecommendationsCardPresentation(summary: summary).route == .detail(
            publicationID: summary.publicationID,
            origin: .today
        ))
    }

    @Test("recommendations use the approved empty copy")
    func emptyCopy() {
        #expect(TodayRecommendationsPresentation.emptyCopy == "Nenhum conteúdo selecionado para hoje")
    }

    @Test("section presentation keeps exact copy CTA route and contained states")
    func sectionPresentation() {
        let cases: [(FeatureReadState<PublishedContentFeed>, TodayRecommendationsSectionState)] = [
            (.loading, .loading),
            (.empty, .empty),
            (.offline(previousValue: nil), .offline),
            (.failed(previousValue: nil, error: .serviceUnavailable), .failed),
            (.unavailable, .unavailable),
        ]

        for (state, expectedState) in cases {
            let presentation = TodayRecommendationsPresentation(state: state)
            #expect(TodayRecommendationsPresentation.heading == "Conteúdos para hoje")
            #expect(presentation.sectionState == expectedState)
            #expect(presentation.libraryAction.title == "Ver biblioteca")
            #expect(presentation.libraryAction.route == .library(initialSelection: .all))
        }
        #expect(TodayRecommendationsPresentation.unavailableCopy == "Indisponível nesta versão")
    }

    @Test("stale recommendations disclose freshness and retain retry inside the section")
    func stalePresentation() {
        let feed = PublishedContentFeed(items: [Self.item(1)], nextCursor: nil)

        for state in [
            FeatureReadState<PublishedContentFeed>.offline(previousValue: feed),
            .failed(previousValue: feed, error: .serviceUnavailable),
        ] {
            let presentation = TodayRecommendationsPresentation(state: state)
            #expect(presentation.cards.map(\.publicationID) == [Self.item(1).publicationID])
            #expect(presentation.showsStaleDisclosure)
            #expect(presentation.showsRetry)
        }
    }

    @Test("Today root keeps the normal Library entry for empty and unavailable official states")
    func rootNavigationPresentation() {
        for state in [
            FeatureReadState<TodaySnapshot>.empty,
            .unavailable,
        ] {
            #expect(TodayRootNavigationPresentation(state: state).toolbarRoutes == [
                .content(.library(initialSelection: .all)), .mainHistory,
            ])
        }
    }

    @Test("new observed catalog revision immediately blocks prior cover authorization")
    func safeCoverAuthorization() async {
        let first = Self.item(1)
        let second = Self.item(2)
        let listing = RecommendationsListing([
            .success(Self.response(items: [first], nextCursor: nil)),
            .success(Self.response(items: [second], nextCursor: nil)),
        ])
        let recommendations = Self.model(listing: listing)

        await recommendations.load(catalogRevision: 0)
        #expect(recommendations.coverAuthorization(for: first, catalogRevision: 0)?.revision == 0)
        #expect(recommendations.coverAuthorization(for: first, catalogRevision: 1) == nil)
        await recommendations.load(catalogRevision: 1)
        #expect(recommendations.coverAuthorization(for: second, catalogRevision: 1)?.revision == 1)
    }

    @Test("controlled retry authorizes only its newly published cover")
    func controlledRetryCoverAuthorization() async {
        let first = Self.item(1)
        let second = Self.item(2)
        let listing = ControlledRecommendationsListing()
        let recommendations = Self.model(listing: listing)
        let initial = Task { await recommendations.load(catalogRevision: 0) }
        await listing.waitForCallCount(1)
        await listing.succeed(call: 1, with: Self.response(items: [first], nextCursor: nil))
        await initial.value
        let retry = Task { await recommendations.retry() }
        await listing.waitForCallCount(2)
        #expect(recommendations.coverAuthorization(for: first, catalogRevision: 0) == nil)
        await listing.succeed(call: 2, with: Self.response(items: [second], nextCursor: nil))
        await retry.value
        #expect(recommendations.coverAuthorization(for: second, catalogRevision: 0)?.revision == 0)
    }

    @Test("concurrent retry rejects the second attempt while the first is pending")
    func concurrentRetry() async {
        let first = Self.item(1)
        let second = Self.item(2)
        let listing = ControlledRecommendationsListing(maximumSuspendedCalls: 2)
        let recommendations = Self.model(listing: listing)
        let initial = Task { await recommendations.load(catalogRevision: 0) }
        await listing.waitForCallCount(1)
        await listing.succeed(call: 1, with: Self.response(items: [first], nextCursor: nil))
        await initial.value
        let retryOne = Task { await recommendations.retry() }
        await listing.waitForCallCount(2)
        let retryTwo = Task { await recommendations.retry() }
        await retryTwo.value
        #expect(await listing.callCount() == 2)
        await listing.succeed(call: 2, with: Self.response(items: [second], nextCursor: nil))
        await retryOne.value
        #expect(await listing.callCount() == 2)
        #expect(recommendations.coverAuthorization(for: second, catalogRevision: 0)?.revision == 0)
    }

    @Test("visibility interaction only creates a Today impression when visible")
    func visibilityInteraction() async {
        let summary = Self.item(1)
        #expect(TodayRecommendationInteraction.visibilityRequest(isVisible: false, summary: summary) == nil)
        #expect(TodayRecommendationInteraction.visibilityRequest(isVisible: true, summary: summary) != nil)
        #expect(TodayRecommendationsCardPresentation(summary: summary).route == .detail(publicationID: summary.publicationID, origin: .today))
    }
}

private extension TodayRecommendationsTests {
    static func model(
        listing: any PublishedContentListing,
        stateRecorder: any PublishedContentStateRecording = RecommendationsStateRecorder()
    ) -> TodayRecommendationsViewModel {
        TodayRecommendationsViewModel(
            listing: listing,
            stateRecorder: stateRecorder,
            keyProvider: RecommendationsKeyProvider(),
            timeProvider: FixedTimeProvider(
                value: Date(timeIntervalSince1970: 1_784_070_800)
            ),
            invalidationCenter: FeatureInvalidationCenter(),
            coverLoader: RecommendationsCoverLoader()
        )
    }

    static func response(
        items: [PublishedContentSummary],
        nextCursor: String?
    ) -> PublishedContentFeedResponse {
        PublishedContentFeedResponse(
            data: PublishedContentFeed(items: items, nextCursor: nextCursor),
            meta: MobileResponseMetadata(
                apiVersion: "1",
                requestID: "90000000-0000-4000-8000-000000000022"
            )
        )
    }

    static func item(_ number: Int) -> PublishedContentSummary {
        PublishedContentSummary(
            publicationID: String(
                format: "00000000-0000-4000-8000-%012d",
                number
            ),
            slug: "today-content-\(number)",
            locale: .ptBR,
            title: "Conteúdo educativo \(number)",
            excerpt: "Um resumo educativo suficiente para validar recomendações do Today.",
            category: .sleep,
            tags: ["sleep"],
            readingTimeMinutes: 3,
            publishAt: APITimestamp(
                value: Date(timeIntervalSince1970: 1_784_070_900 + Double(number))
            ),
            featuredToday: true,
            version: number,
            saved: false,
            completed: false,
            cover: nil
        )
    }
}

private actor RecommendationsListing: PublishedContentListing {
    private var results: [Result<PublishedContentFeedResponse, BodyFlowCapabilityError>]
    private var recordedQueries: [ContentFeedQuery] = []

    init(_ results: [Result<PublishedContentFeedResponse, BodyFlowCapabilityError>]) {
        self.results = results
    }

    func content(_ query: ContentFeedQuery) async throws -> PublishedContentFeedResponse {
        recordedQueries.append(query)
        guard !results.isEmpty else {
            throw BodyFlowCapabilityError.serviceUnavailable
        }
        return try results.removeFirst().get()
    }

    func queries() -> [ContentFeedQuery] {
        recordedQueries
    }
}

private actor ControlledRecommendationsListing: PublishedContentListing {
    private let maximumSuspendedCalls: Int?
    private var calls = 0
    private var continuations: [Int: CheckedContinuation<PublishedContentFeedResponse, any Error>] = [:]
    private var waiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    init(maximumSuspendedCalls: Int? = nil) {
        self.maximumSuspendedCalls = maximumSuspendedCalls
    }

    func content(_: ContentFeedQuery) async throws -> PublishedContentFeedResponse {
        calls += 1
        let call = calls
        for (expected, continuations) in waiters where expected <= calls {
            waiters[expected] = nil
            continuations.forEach { $0.resume() }
        }
        if let maximumSuspendedCalls, call > maximumSuspendedCalls {
            throw BodyFlowCapabilityError.serviceUnavailable
        }
        return try await withCheckedThrowingContinuation { continuations[call] = $0 }
    }

    func waitForCallCount(_ expected: Int) async {
        guard calls < expected else { return }
        await withCheckedContinuation { waiters[expected, default: []].append($0) }
    }

    func succeed(call: Int, with response: PublishedContentFeedResponse) {
        continuations.removeValue(forKey: call)?.resume(returning: response)
    }

    func callCount() -> Int { calls }
}

private actor RecommendationsStateRecorder: PublishedContentStateRecording {
    private var attempts: [MutationAttempt<ContentReadCommand>] = []

    func recordRead(
        _ attempt: MutationAttempt<ContentReadCommand>
    ) async throws -> PublishedContentStateResponse {
        attempts.append(attempt)
        return PublishedContentStateResponse(
            data: PublishedContentState(
                publicationID: attempt.payload.publicationID,
                version: attempt.payload.body.version,
                saved: false,
                completed: false,
                changed: false,
                replayed: false
            ),
            meta: MobileResponseMetadata(
                apiVersion: "1",
                requestID: "90000000-0000-4000-8000-000000000023"
            )
        )
    }

    func setSaved(
        _: MutationAttempt<ContentSaveCommand>
    ) async throws -> PublishedContentStateResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func readAttempts() -> [MutationAttempt<ContentReadCommand>] {
        attempts
    }
}

private struct RecommendationsKeyProvider: IdempotencyKeyProviding {
    func nextKey() throws -> IdempotencyKey {
        try IdempotencyKey(validating: "today-recommendations-key")
    }
}

private actor RecommendationsCoverLoader: ContentCoverLoading {
    func image(
        publicationID _: String,
        version _: Int,
        cover _: PublishedContentCover,
        target _: ContentCoverTargetSize
    ) async throws -> ContentCoverImage {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func remove(publicationID _: String, version _: Int) async {}

    func endSession() async {}
}

private actor RecommendationsTodayProvider: TodayProviding {
    private var results: [Result<TodayResponse, BodyFlowCapabilityError>]

    init(_ results: [Result<TodayResponse, BodyFlowCapabilityError>]) {
        self.results = results
    }

    func today() async throws -> TodayResponse {
        guard !results.isEmpty else {
            throw BodyFlowCapabilityError.serviceUnavailable
        }
        return try results.removeFirst().get()
    }
}
