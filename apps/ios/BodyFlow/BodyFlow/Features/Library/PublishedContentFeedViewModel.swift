import Observation

enum PublishedContentNextPageState: Equatable, Sendable {
    case idle
    case loading
    case failed(BodyFlowCapabilityError)
    case reloadFirstPageRequired
}

@MainActor
@Observable
final class PublishedContentFeedViewModel {
    private struct FirstPageLoadIdentity: Equatable {
        let key: FeedLoadKey
        let sequence: Int
    }

    private struct PageLoadIdentity {
        let key: FeedLoadKey
        let expectedCursor: String
        let sequence: Int
        let query: ContentFeedQuery
        let cancellationState: PublishedContentNextPageState
    }

    private struct ActivePageLoad {
        let identity: PageLoadIdentity
        let task: Task<FeatureLoadCompletion<PublishedContentFeedResponse>?, Never>
    }

    private let listing: any PublishedContentListing
    private let firstPageController = FeatureKeyedLoadController<
        FeedLoadKey,
        PublishedContentFeedResponse
    >()

    private var activeKey: FeedLoadKey?
    private var firstPageQuery: ContentFeedQuery?
    private var currentFeed: PublishedContentFeed?
    private var nextPageCursor: String?
    private var nextPageAttempt: ContentFeedQuery?
    private var activeFirstPageLoad: FirstPageLoadIdentity?
    private var activePageLoad: ActivePageLoad?
    private var firstPageSequence = 0
    private var pageSequence = 0

    private(set) var state: FeatureReadState<PublishedContentFeed> = .idle
    private(set) var nextPageState: PublishedContentNextPageState = .idle

    init(listing: any PublishedContentListing) {
        self.listing = listing
    }

    func load(query: ContentFeedQuery, catalogRevision: Int) async {
        guard !Task.isCancelled else { return }
        let key = FeedLoadKey(query: query, catalogRevision: catalogRevision)
        guard activeFirstPageLoad?.key != key else { return }

        if activeKey != key {
            let keepsCurrentFeed = activeKey?.query == query
            invalidatePaging(preservingCurrentFeed: keepsCurrentFeed)
            activeKey = key
            firstPageQuery = query
            publishFirstPageLoading()
        }

        let identity = beginFirstPageLoad(for: key)
        await firstPageController.load(
            key: key,
            operation: firstPageOperation(query: query),
            publish: { [weak self] completion in
                self?.publishFirstPage(completion, identity: identity)
            }
        )
        finishFirstPageLoad(identity)
    }

    func retryFirstPage() async {
        guard !Task.isCancelled,
              nextPageState != .reloadFirstPageRequired,
              activeFirstPageLoad == nil,
              let key = activeKey,
              let query = firstPageQuery else {
            return
        }

        invalidatePaging(preservingCurrentFeed: true)
        publishFirstPageLoading()
        let identity = beginFirstPageLoad(for: key)
        await firstPageController.retry(
            key: key,
            operation: firstPageOperation(query: query),
            publish: { [weak self] completion in
                self?.publishFirstPage(completion, identity: identity)
            }
        )
        finishFirstPageLoad(identity)
    }

    func loadNextPage() async {
        guard !Task.isCancelled,
              nextPageState == .idle,
              activeFirstPageLoad == nil,
              let key = activeKey,
              let firstPageQuery,
              let expectedCursor = nextPageCursor,
              let query = try? ContentFeedQuery(
                  surface: firstPageQuery.surface,
                  category: firstPageQuery.category,
                  limit: firstPageQuery.limit,
                  cursor: expectedCursor
              ) else {
            return
        }

        let cancellationState = nextPageState
        nextPageAttempt = query
        nextPageState = .loading
        await startPageLoad(
            key: key,
            expectedCursor: expectedCursor,
            query: query,
            cancellationState: cancellationState
        )
    }

    func retryNextPage() async {
        guard !Task.isCancelled,
              case .failed = nextPageState,
              activeFirstPageLoad == nil,
              let key = activeKey,
              let expectedCursor = nextPageCursor,
              let query = nextPageAttempt,
              query.cursor == expectedCursor else {
            return
        }

        let cancellationState = nextPageState
        nextPageState = .loading
        await startPageLoad(
            key: key,
            expectedCursor: expectedCursor,
            query: query,
            cancellationState: cancellationState
        )
    }

    func reloadFirstPageAfterInvalidCursor() async {
        guard !Task.isCancelled,
              nextPageState == .reloadFirstPageRequired,
              activeFirstPageLoad == nil,
              let key = activeKey,
              let firstPageQuery,
              let query = try? ContentFeedQuery(
                  surface: firstPageQuery.surface,
                  category: firstPageQuery.category,
                  limit: firstPageQuery.limit,
                  cursor: nil
              ) else {
            return
        }

        publishFirstPageLoading()
        let identity = beginFirstPageLoad(for: key)
        await firstPageController.retry(
            key: key,
            operation: firstPageOperation(query: query),
            publish: { [weak self] completion in
                self?.publishFirstPage(completion, identity: identity)
            }
        )
        finishFirstPageLoad(identity)
    }

    private func firstPageOperation(
        query: ContentFeedQuery
    ) -> @Sendable () async throws -> PublishedContentFeedResponse {
        { [listing] in
            let response = try await listing.content(query)
            try Self.validate(response.data, existingPublicationIDs: [])
            return response
        }
    }

    private func publishFirstPageLoading() {
        if let currentFeed {
            state = currentFeed.items.isEmpty ? .empty : .loaded(currentFeed)
        } else {
            state = .loading
        }
    }

    private func publishFirstPage(
        _ completion: FeatureLoadCompletion<PublishedContentFeedResponse>,
        identity: FirstPageLoadIdentity
    ) {
        guard activeKey == identity.key,
              activeFirstPageLoad == identity else {
            return
        }

        defer {
            finishFirstPageLoad(identity)
        }

        switch completion {
        case let .value(response):
            let hasMalformedCursor = Self.hasMalformedNextCursor(
                response.data,
                query: identity.key.query
            )
            let feed = hasMalformedCursor
                ? Self.clearingNextCursor(in: response.data)
                : response.data
            currentFeed = feed
            nextPageCursor = feed.nextCursor
            nextPageAttempt = nil
            nextPageState = hasMalformedCursor ? .reloadFirstPageRequired : .idle
            state = feed.items.isEmpty ? .empty : .loaded(feed)
        case let .failure(error):
            state = Self.readState(for: error, previousValue: currentFeed)
        }
    }

    private func startPageLoad(
        key: FeedLoadKey,
        expectedCursor: String,
        query: ContentFeedQuery,
        cancellationState: PublishedContentNextPageState
    ) async {
        pageSequence += 1
        let identity = PageLoadIdentity(
            key: key,
            expectedCursor: expectedCursor,
            sequence: pageSequence,
            query: query,
            cancellationState: cancellationState
        )
        let existingPublicationIDs = Set(currentFeed?.items.map(\.publicationID) ?? [])
        let operationTask = Task { [listing] () -> FeatureLoadCompletion<
            PublishedContentFeedResponse
        >? in
            do {
                let response = try await listing.content(query)
                try Task.checkCancellation()
                try Self.validate(
                    response.data,
                    existingPublicationIDs: existingPublicationIDs
                )
                return FeatureLoadCompletion.value(response)
            } catch is CancellationError {
                return nil
            } catch {
                guard !Task.isCancelled else { return nil }
                return FeatureLoadCompletion.failure(error)
            }
        }

        cancelActivePageLoad()
        activePageLoad = ActivePageLoad(
            identity: identity,
            task: operationTask
        )

        let completion = await withTaskCancellationHandler {
            await operationTask.value
        } onCancel: {
            operationTask.cancel()
        }

        publishPage(completion, identity: identity)
    }

    private func publishPage(
        _ completion: FeatureLoadCompletion<PublishedContentFeedResponse>?,
        identity: PageLoadIdentity
    ) {
        defer {
            if activePageLoad?.identity.sequence == identity.sequence {
                activePageLoad = nil
            }
        }

        guard let completion else {
            restoreCancelledPage(identity)
            return
        }

        if Task.isCancelled {
            restoreCancelledPage(identity)
            return
        }

        guard activePageLoad?.identity.sequence == identity.sequence,
              activeKey == identity.key,
              nextPageCursor == identity.expectedCursor,
              nextPageAttempt == identity.query else {
            return
        }

        switch completion {
        case let .value(response):
            let items = (currentFeed?.items ?? []) + response.data.items
            let hasMalformedCursor = Self.hasMalformedNextCursor(
                response.data,
                query: identity.query
            )
            let feed = PublishedContentFeed(
                items: items,
                nextCursor: hasMalformedCursor ? nil : response.data.nextCursor
            )
            currentFeed = feed
            nextPageCursor = feed.nextCursor
            nextPageAttempt = nil
            nextPageState = hasMalformedCursor ? .reloadFirstPageRequired : .idle
            state = items.isEmpty ? .empty : .loaded(feed)
        case let .failure(error):
            let capabilityError = Self.capabilityError(from: error)
            if capabilityError == .invalidContentCursor {
                if let currentFeed {
                    let feed = Self.clearingNextCursor(in: currentFeed)
                    self.currentFeed = feed
                    replaceVisibleFeed(with: feed)
                }
                nextPageCursor = nil
                nextPageAttempt = nil
                nextPageState = .reloadFirstPageRequired
            } else {
                nextPageState = .failed(capabilityError)
            }
        }
    }

    private func restoreCancelledPage(_ identity: PageLoadIdentity) {
        guard activePageLoad?.identity.sequence == identity.sequence,
              activeKey == identity.key,
              nextPageCursor == identity.expectedCursor,
              nextPageAttempt == identity.query else {
            return
        }

        nextPageState = identity.cancellationState
        if identity.cancellationState == .idle {
            nextPageAttempt = nil
        }
    }

    private func replaceVisibleFeed(with feed: PublishedContentFeed) {
        switch state {
        case .loaded:
            state = feed.items.isEmpty ? .empty : .loaded(feed)
        case .empty:
            state = feed.items.isEmpty ? .empty : .loaded(feed)
        case .offline(previousValue: .some):
            state = .offline(previousValue: feed)
        case let .failed(previousValue: .some, error: error):
            state = .failed(previousValue: feed, error: error)
        case .idle,
             .loading,
             .offline(previousValue: nil),
             .failed(previousValue: nil, error: _),
             .unavailable:
            break
        }
    }

    private func beginFirstPageLoad(
        for key: FeedLoadKey
    ) -> FirstPageLoadIdentity {
        firstPageSequence += 1
        let identity = FirstPageLoadIdentity(
            key: key,
            sequence: firstPageSequence
        )
        activeFirstPageLoad = identity
        return identity
    }

    private func finishFirstPageLoad(_ identity: FirstPageLoadIdentity) {
        if activeFirstPageLoad == identity {
            activeFirstPageLoad = nil
        }
    }

    private func cancelActivePageLoad() {
        activePageLoad?.task.cancel()
        activePageLoad = nil
    }

    private func invalidatePaging(preservingCurrentFeed: Bool) {
        cancelActivePageLoad()
        nextPageAttempt = nil
        nextPageCursor = nil
        nextPageState = .idle

        guard preservingCurrentFeed, let currentFeed else {
            if !preservingCurrentFeed {
                self.currentFeed = nil
            }
            return
        }

        let feed = Self.clearingNextCursor(in: currentFeed)
        self.currentFeed = feed
        replaceVisibleFeed(with: feed)
    }

    nonisolated private static func validate(
        _ feed: PublishedContentFeed,
        existingPublicationIDs: Set<String>
    ) throws {
        try PublishedContentContractValidator.validate(feed)
        var publicationIDs = existingPublicationIDs
        for item in feed.items {
            guard publicationIDs.insert(item.publicationID).inserted else {
                throw BodyFlowCapabilityError.invalidContentContract
            }
        }
    }

    nonisolated private static func hasMalformedNextCursor(
        _ feed: PublishedContentFeed,
        query: ContentFeedQuery
    ) -> Bool {
        guard let cursor = feed.nextCursor else { return false }
        return (try? ContentFeedQuery(
            surface: query.surface,
            category: query.category,
            limit: query.limit,
            cursor: cursor
        )) == nil
    }

    nonisolated private static func clearingNextCursor(
        in feed: PublishedContentFeed
    ) -> PublishedContentFeed {
        PublishedContentFeed(items: feed.items, nextCursor: nil)
    }

    nonisolated private static func readState(
        for error: any Error,
        previousValue: PublishedContentFeed?
    ) -> FeatureReadState<PublishedContentFeed> {
        switch capabilityError(from: error) {
        case .operationUnavailable:
            .unavailable
        case .offline:
            .offline(previousValue: previousValue)
        case let capabilityError:
            .failed(previousValue: previousValue, error: capabilityError)
        }
    }

    nonisolated private static func capabilityError(
        from error: any Error
    ) -> BodyFlowCapabilityError {
        error as? BodyFlowCapabilityError ?? .serviceUnavailable
    }
}
