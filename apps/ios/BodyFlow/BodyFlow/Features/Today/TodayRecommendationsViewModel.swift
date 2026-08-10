import Observation

@MainActor
@Observable
final class TodayRecommendationsViewModel {
    private let composition: LibraryCoverFeedComposition
    private var activeKey: FeedLoadKey?

    private var feed: PublishedContentFeedViewModel { composition.model }

    var state: FeatureReadState<PublishedContentFeed> {
        feed.state
    }

    var items: [PublishedContentSummary] {
        Array(feed.state.presentation.value?.items.prefix(3) ?? [])
    }

    var requestedCoverRevision: Int? {
        composition.authorizationRelay.requestedRevision
    }

    init(
        listing: any PublishedContentListing,
        stateRecorder: any PublishedContentStateRecording,
        keyProvider: any IdempotencyKeyProviding,
        timeProvider: any TimeProviding,
        invalidationCenter: FeatureInvalidationCenter,
        coverLoader: any ContentCoverLoading
    ) {
        composition = LibraryCoverFeedComposition(
            listing: listing,
            stateRecorder: stateRecorder,
            keyProvider: keyProvider,
            timeProvider: timeProvider,
            invalidationCenter: invalidationCenter,
            coverLoader: coverLoader
        )
    }

    func load(catalogRevision: Int) async {
        guard let query = try? ContentFeedQuery(
            surface: .today,
            category: nil,
            limit: 3,
            cursor: nil
        ) else {
            return
        }
        let key = FeedLoadKey(query: query, catalogRevision: catalogRevision)
        activeKey = key
        _ = await LibraryCoverLoadCoordinator.perform(
            requestedKey: key,
            relay: composition.authorizationRelay,
            candidateProvider: composition.candidateProvider,
            reusesCompletedAuthorization: true,
            currentKey: { self.activeKey },
            state: { self.feed.state },
            recoveryOperation: {
                await LibraryCoverFirstPageRecovery.perform(
                    model: self.feed,
                    key: key
                )
            },
            operation: { await self.feed.load(query: query, catalogRevision: catalogRevision) }
        )
    }

    func retry() async {
        guard let activeKey else { return }
        _ = await LibraryCoverLoadCoordinator.perform(
            requestedKey: activeKey,
            relay: composition.authorizationRelay,
            candidateProvider: composition.candidateProvider,
            allowsSupersession: false,
            currentKey: { self.activeKey },
            state: { self.feed.state },
            operation: { await self.feed.retryFirstPage() }
        )
    }

    func recordImpression(for summary: PublishedContentSummary) async {
        await feed.recordImpression(for: summary, origin: .today)
    }

    func coverAuthorization(
        for summary: PublishedContentSummary,
        catalogRevision: Int
    ) -> LibraryCoverAuthorization? {
        guard let query = try? ContentFeedQuery(
            surface: .today, category: nil, limit: 3, cursor: nil
        ) else { return nil }
        return composition.authorizationRelay.authorization(
            for: summary,
            requestedKey: FeedLoadKey(
                query: query,
                catalogRevision: catalogRevision
            )
        )
    }
}
