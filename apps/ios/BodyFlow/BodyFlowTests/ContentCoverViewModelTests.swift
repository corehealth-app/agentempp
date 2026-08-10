import CoreGraphics
import Foundation
import Observation
import Testing

@testable import BodyFlow

@MainActor
@Suite("Content cover presentation owner")
struct ContentCoverViewModelTests {
    private let publicationID = "10000000-0000-4000-8000-000000000001"
    private let baseDate = Date(timeIntervalSince1970: 2_000_000_000)

    // Mutation caught: rounding point dimensions before applying the real
    // display scale, truncating fractional pixels, or accepting zero/nonfinite
    // geometry and invoking the loader with a fabricated target.
    @Test("target pixels come from actual displayed points times display scale")
    func targetUsesDisplayedPointsAndScale() {
        #expect(ContentCoverTargetSizing.target(
            widthPoints: 120.25,
            heightPoints: 80,
            displayScale: 3
        ) == ContentCoverTargetSize(widthPixels: 361, heightPixels: 240))
        #expect(ContentCoverTargetSizing.target(
            widthPoints: 0,
            heightPoints: 80,
            displayScale: 3
        ) == nil)
        #expect(ContentCoverTargetSizing.target(
            widthPoints: 120,
            heightPoints: .infinity,
            displayScale: 3
        ) == nil)
        #expect(ContentCoverTargetSizing.target(
            widthPoints: .leastNonzeroMagnitude,
            heightPoints: 80,
            displayScale: .leastNonzeroMagnitude
        ) == nil)
    }

    // Mutation caught: invoking the loader for a missing capability or using a
    // distinct empty/error visual instead of the one neutral placeholder.
    @Test("nil cover stays on the neutral placeholder without loading")
    func nilCoverDoesNotLoad() async {
        let loader = ScriptedPresentationCoverLoader([])
        let model = ContentCoverViewModel()

        await loadCover(
            model,
            request: nil,
            loader: loader,
            onCapabilityInvalidated: {}
        )

        #expect(model.presentation.isPlaceholder)
        #expect(await loader.calls.isEmpty)
    }

    // Mutation caught: changing the card-to-cover adapter to omit either the
    // authorized summary version or its exact optional capability.
    @Test("card cover input preserves the summary version and exact cover")
    func cardForwardsSummaryCoverIdentity() throws {
        let cover = self.cover(url: "/api/mobile/v1/content/covers/card")
        let summary = summary(version: 27, cover: cover)

        let input = LibraryCardCoverInput(
            summary: summary,
            authorizedCover: cover
        )
        let request = ContentCoverPresentationRequest(
            publicationID: input.publicationID,
            version: input.version,
            cover: try #require(input.cover),
            target: ContentCoverTargetSize(
                widthPixels: 240,
                heightPixels: 160
            ),
            session: ContentCoverSessionToken()
        )

        #expect(request.publicationID == publicationID)
        #expect(request.version == 27)
        #expect(request.cover == cover)
    }

    // RED: the catalog revision requested by invalidation must close the
    // capability gate until that exact response has actually been published.
    // A newly materialized row cannot inherit the previous response's token.
    @Test("library separates requested and authorized cover revisions")
    func librarySeparatesRequestedAndAuthorizedCoverRevisions() async throws {
        let relay = LibraryCoverAuthorizationRelay()
        let revisionZero = try feedKey(revision: 0)
        let revisionOne = try feedKey(revision: 1)
        let unchangedCover = cover(
            url: "/api/mobile/v1/content/covers/same-capability"
        )
        let unchangedSummary = summary(version: 4, cover: unchangedCover)

        let initialToken = relay.begin(requestedKey: revisionZero)
        let initialFeed = PublishedContentFeed(
            items: [unchangedSummary],
            nextCursor: nil
        )
        #expect(relay.commit(
            candidate: libraryCandidate(
                token: initialToken,
                key: revisionZero,
                feed: initialFeed
            ),
            capturedKey: revisionZero,
            currentKey: revisionZero,
            state: .loaded(initialFeed),
            isCancelled: false
        ))
        #expect(relay.cover(
            for: unchangedSummary,
            requestedKey: revisionZero
        ) == unchangedCover)

        let refreshToken = relay.begin(requestedKey: revisionOne)
        #expect(relay.requestedRevision == 1)
        #expect(relay.authorizedRevision == nil)
        #expect(relay.cover(
            for: unchangedSummary,
            requestedKey: revisionOne
        ) == nil)

        let loader = ScriptedPresentationCoverLoader([])
        let cardModel = ContentCoverViewModel()
        let cardAuthorization = relay.authorization(
            for: unchangedSummary,
            requestedKey: revisionOne
        )
        await cardModel.load(
            descriptor: ContentCoverViewDescriptor(
                request: cardAuthorization?.cover.map { authorizedCover in
                    ContentCoverPresentationRequest(
                        publicationID: unchangedSummary.publicationID,
                        version: unchangedSummary.version,
                        cover: authorizedCover,
                        target: ContentCoverTargetSize(
                            widthPixels: 240,
                            heightPixels: 160
                        ),
                        session: ContentCoverSessionToken()
                    )
                },
                parentRevision: revisionOne.catalogRevision,
                authorizedParentRevision: cardAuthorization?.revision
            ),
            loader: loader,
            refreshBudget: ContentCoverRefreshBudget(
                session: ContentCoverSessionToken()
            ),
            onParentRevisionChanged: {},
            onCapabilityInvalidated: {}
        )
        #expect(cardModel.presentation.isPlaceholder)
        #expect(await loader.calls.isEmpty)

        let refreshedFeed = PublishedContentFeed(
            items: [unchangedSummary],
            nextCursor: nil
        )
        #expect(relay.commit(
            candidate: libraryCandidate(
                token: refreshToken,
                key: revisionOne,
                feed: refreshedFeed
            ),
            capturedKey: revisionOne,
            currentKey: revisionOne,
            state: .loaded(refreshedFeed),
            isCancelled: false
        ))
        #expect(relay.authorizedRevision == 1)
        #expect(relay.cover(
            for: unchangedSummary,
            requestedKey: revisionOne
        ) == unchangedCover)
    }

    // RED: stale, superseded and cancelled first-page completions must not
    // authorize a capability after their provider suspension has ended.
    @Test("library relay rejects stale token revision and cancellation")
    func libraryRelayRejectsStaleTokenRevisionAndCancellation() throws {
        let relay = LibraryCoverAuthorizationRelay()
        let revisionOne = try feedKey(revision: 1)
        let revisionTwo = try feedKey(revision: 2)
        let feed = PublishedContentFeed(
            items: [summary(version: 4, cover: cover())],
            nextCursor: nil
        )
        let state: FeatureReadState<PublishedContentFeed> = .loaded(feed)

        let staleToken = relay.begin(requestedKey: revisionOne)
        let currentToken = relay.begin(requestedKey: revisionTwo)
        #expect(!relay.commit(
            candidate: libraryCandidate(
                token: staleToken,
                key: revisionOne,
                feed: feed
            ),
            capturedKey: revisionOne,
            currentKey: revisionTwo,
            state: state,
            isCancelled: false
        ))
        #expect(!relay.commit(
            candidate: libraryCandidate(
                token: currentToken,
                key: revisionTwo,
                feed: feed
            ),
            capturedKey: revisionTwo,
            currentKey: revisionOne,
            state: state,
            isCancelled: false
        ))
        let cancelledToken = relay.begin(requestedKey: revisionTwo)
        #expect(!relay.commit(
            candidate: libraryCandidate(
                token: cancelledToken,
                key: revisionTwo,
                feed: feed
            ),
            capturedKey: revisionTwo,
            currentKey: revisionTwo,
            state: state,
            isCancelled: true
        ))
        #expect(relay.authorizedRevision == nil)
    }

    // RED: the coordinator itself must await the provider/model operation and
    // only then sample token ownership, current revision and cancellation.
    @Test("library revalidates ownership after the feed operation suspends")
    func libraryRevalidatesAfterFeedAwait() async throws {
        enum Mutation: CaseIterable {
            case token
            case revision
            case cancellation
        }

        let revisionOne = try feedKey(revision: 1)
        let revisionTwo = try feedKey(revision: 2)
        let feed = PublishedContentFeed(
            items: [summary(version: 4, cover: cover())],
            nextCursor: nil
        )
        let state: FeatureReadState<PublishedContentFeed> = .loaded(feed)

        for mutation in Mutation.allCases {
            let relay = LibraryCoverAuthorizationRelay()
            let operation = ControlledParentRefresh()
            let candidateProvider = SuspendedLibraryCoverCandidateProvider(
                query: revisionOne.query,
                feed: feed
            )
            var currentKey: FeedLoadKey? = revisionOne
            let load = Task { @MainActor in
                await LibraryCoverLoadCoordinator.perform(
                    requestedKey: revisionOne,
                    relay: relay,
                    candidateProvider: candidateProvider,
                    currentKey: { currentKey },
                    state: { state },
                    operation: { await operation.run() }
                )
            }
            await operation.waitUntilStarted()
            await operation.finish()
            await candidateProvider.waitUntilStarted()

            switch mutation {
            case .token:
                _ = relay.begin(requestedKey: revisionTwo)
            case .revision:
                currentKey = revisionTwo
            case .cancellation:
                load.cancel()
            }
            await candidateProvider.resume()

            #expect(await load.value == false)
            #expect(relay.authorizedRevision == nil)
        }
    }

    @Test("user first-page action cannot supersede an active feed load")
    func userFirstPageActionDoesNotSupersedeActiveLoad() async throws {
        let key = try feedKey(revision: 1)
        let relay = LibraryCoverAuthorizationRelay()
        _ = relay.begin(requestedKey: key)
        var operationWasCalled = false

        let didCommit = await LibraryCoverLoadCoordinator.perform(
            requestedKey: key,
            relay: relay,
            candidateProvider: MissingLibraryCoverCandidateProvider(),
            allowsSupersession: false,
            currentKey: { key },
            state: { .empty },
            operation: { operationWasCalled = true }
        )

        #expect(!didCommit)
        #expect(!operationWasCalled)
        #expect(relay.hasPendingLoad)
    }

    @Test("library authorizes only the response captured by the completed load")
    func libraryAuthorizesCapturedPublishedResponse() async throws {
        let key = try feedKey(revision: 8)
        let feed = PublishedContentFeed(
            items: [summary(version: 12, cover: cover())],
            nextCursor: nil
        )
        let relay = LibraryCoverAuthorizationRelay()
        let provider = ImmediateLibraryCoverCandidateProvider(
            query: key.query,
            feed: feed
        )
        var operationFinished = false

        let didCommit = await LibraryCoverLoadCoordinator.perform(
            requestedKey: key,
            relay: relay,
            candidateProvider: provider,
            currentKey: { key },
            state: { operationFinished ? .loaded(feed) : .loading },
            operation: { operationFinished = true }
        )

        #expect(didCommit)
        #expect(relay.authorizedRevision == 8)
    }

    @Test("library never authorizes when a feed operation publishes no response")
    func libraryDoesNotAuthorizeNoOpFeedOperation() async throws {
        let key = try feedKey(revision: 9)
        let oldFeed = PublishedContentFeed(
            items: [summary(version: 3, cover: cover())],
            nextCursor: nil
        )
        let relay = LibraryCoverAuthorizationRelay()
        var operationWasCalled = false

        let didCommit = await LibraryCoverLoadCoordinator.perform(
            requestedKey: key,
            relay: relay,
            candidateProvider: MissingLibraryCoverCandidateProvider(),
            currentKey: { key },
            state: { .loaded(oldFeed) },
            operation: { operationWasCalled = true }
        )

        #expect(operationWasCalled)
        #expect(!didCommit)
        #expect(!relay.hasPendingLoad)
        #expect(relay.authorizedRevision == nil)
    }

    @Test("library stages only the exact response returned inside its load token")
    func libraryCapturesExactProviderResponseForToken() async throws {
        let key = try feedKey(revision: 10)
        let feed = PublishedContentFeed(
            items: [summary(version: 14, cover: cover())],
            nextCursor: "opaque-next"
        )
        let response = PublishedContentFeedResponse(
            data: feed,
            meta: MobileResponseMetadata(
                apiVersion: "1",
                requestID: "90000000-0000-4000-8000-000000000099"
            )
        )
        let downstream = OneShotLibraryContentListing(response: response)
        let capturing = LibraryCoverCapturingListing(listing: downstream)
        let token = LibraryCoverLoadToken()

        let returned = try await LibraryCoverLoadContext.withToken(token) {
            try await capturing.content(key.query)
        }
        let candidate = await capturing.takeCandidate(for: token)

        #expect(returned == response)
        #expect(candidate == libraryCandidate(
            token: token,
            key: key,
            feed: feed
        ))
        #expect(await capturing.takeCandidate(for: token) == nil)
    }

    @Test("library disappearance preserves only completed authorization")
    func libraryDisappearancePreservesCompletedAuthorization() throws {
        let revision = try feedKey(revision: 11)
        let feed = PublishedContentFeed(
            items: [summary(version: 15, cover: cover())],
            nextCursor: nil
        )
        let relay = LibraryCoverAuthorizationRelay()
        let completedToken = relay.begin(requestedKey: revision)
        #expect(relay.commit(
            candidate: libraryCandidate(
                token: completedToken,
                key: revision,
                feed: feed
            ),
            capturedKey: revision,
            currentKey: revision,
            state: .loaded(feed),
            isCancelled: false
        ))

        relay.cancelPendingLoad()
        #expect(relay.authorization(
            for: feed.items[0],
            requestedKey: revision
        )?.revision == 11)

        let pendingToken = relay.begin(requestedKey: revision)
        relay.cancelPendingLoad()
        #expect(!relay.commit(
            candidate: libraryCandidate(
                token: pendingToken,
                key: revision,
                feed: feed
            ),
            capturedKey: revision,
            currentKey: revision,
            state: .loaded(feed),
            isCancelled: false
        ))
        #expect(relay.authorizedRevision == nil)
    }

    // RED: a replacement SwiftUI task must not start a second ownership while
    // the cancelled, non-cooperative first-page operation is still tearing
    // down. The relay keeps that teardown observable until its exact token
    // finishes, then permits one replacement attempt.
    @Test("library reentry waits for cancelled ownership teardown")
    func libraryReentryWaitsForCancelledOwnershipTeardown() async throws {
        let key = try feedKey(revision: 12)
        let relay = LibraryCoverAuthorizationRelay()
        let cancelledToken = relay.begin(requestedKey: key)
        relay.cancelPendingLoad()
        let probe = LibraryCoverCoordinatorProbe()

        let cancelledReplacement = Task { @MainActor in
            probe.markEntered()
            return await LibraryCoverLoadCoordinator.perform(
                requestedKey: key,
                relay: relay,
                candidateProvider: MissingLibraryCoverCandidateProvider(),
                reusesCompletedAuthorization: true,
                currentKey: { key },
                state: { .loading },
                operation: { probe.recordOperationStart() }
            )
        }

        await probe.waitUntilEntered()
        #expect(probe.operationStartCount == 0)
        cancelledReplacement.cancel()
        #expect(await cancelledReplacement.value == false)
        #expect(relay.hasPendingLoad)

        let replacementProbe = LibraryCoverCoordinatorProbe()
        let replacement = Task { @MainActor in
            replacementProbe.markEntered()
            return await LibraryCoverLoadCoordinator.perform(
                requestedKey: key,
                relay: relay,
                candidateProvider: MissingLibraryCoverCandidateProvider(),
                reusesCompletedAuthorization: true,
                currentKey: { key },
                state: { .loading },
                operation: { replacementProbe.recordOperationStart() }
            )
        }
        await replacementProbe.waitUntilEntered()
        #expect(replacementProbe.operationStartCount == 0)

        relay.discard(token: cancelledToken)
        #expect(await replacement.value == false)
        #expect(replacementProbe.operationStartCount == 1)
    }

    // Mutation caught: clearing the relay token on disappearance lets a new
    // same-key task be consumed by PublishedContentFeedViewModel while its
    // cancelled, non-cooperative provider is still active. When teardown
    // finally ends, no task remains to publish or authorize the cover.
    @Test("library reentry reloads once after a non-cooperative cancellation")
    func libraryReentryReloadsAfterNonCooperativeCancellation() async throws {
        let key = try feedKey(revision: 13)
        let item = summary(version: 17, cover: cover())
        let feed = PublishedContentFeed(items: [item], nextCursor: nil)
        let response = PublishedContentFeedResponse(
            data: feed,
            meta: MobileResponseMetadata(
                apiVersion: "1",
                requestID: "90000000-0000-4000-8000-000000000098"
            )
        )
        let listing = NonCooperativeLibraryContentListing()
        let capturing = LibraryCoverCapturingListing(listing: listing)
        let relay = LibraryCoverAuthorizationRelay()
        let model = PublishedContentFeedViewModel(
            listing: capturing,
            stateRecorder: UnavailableBodyFlowCapabilities(),
            keyProvider: DeterministicIdempotencyKeyProvider(
                prefix: "cover-reentry"
            ),
            timeProvider: FixedTimeProvider(value: baseDate),
            invalidationCenter: FeatureInvalidationCenter(),
            coverLoader: ScriptedPresentationCoverLoader([])
        )

        let firstLoad = Task { @MainActor in
            await LibraryCoverLoadCoordinator.perform(
                requestedKey: key,
                relay: relay,
                candidateProvider: capturing,
                reusesCompletedAuthorization: true,
                currentKey: { key },
                state: { model.state },
                operation: {
                    await model.load(
                        query: key.query,
                        catalogRevision: key.catalogRevision
                    )
                }
            )
        }
        await listing.waitForCallCount(1)

        firstLoad.cancel()
        relay.cancelPendingLoad()
        let replacementProbe = LibraryCoverCoordinatorProbe()
        let replacement = Task { @MainActor in
            replacementProbe.markEntered()
            return await LibraryCoverLoadCoordinator.perform(
                requestedKey: key,
                relay: relay,
                candidateProvider: capturing,
                reusesCompletedAuthorization: true,
                currentKey: { key },
                state: { model.state },
                operation: {
                    replacementProbe.recordOperationStart()
                    await model.load(
                        query: key.query,
                        catalogRevision: key.catalogRevision
                    )
                }
            )
        }
        await replacementProbe.waitUntilEntered()

        #expect(replacementProbe.operationStartCount == 0)
        #expect(await listing.callCount == 1)

        await listing.succeed(call: 1, response: response)
        #expect(await firstLoad.value == false)
        await replacementProbe.waitForOperationStartCount(1)
        await listing.waitForCallCount(2)
        #expect(await listing.queries == [key.query, key.query])

        await listing.succeed(call: 2, response: response)
        #expect(await replacement.value)
        #expect(relay.authorization(
            for: item,
            requestedKey: key
        )?.cover == item.cover)
    }

    // RED: cancellation may arrive after the feed controller published the
    // response but before the relay committed its capability. Reentry cannot
    // reuse that denied authorization, and a regular same-key load is already
    // complete, so it must issue one explicit first-page recovery attempt.
    @Test("library reentry recovers when cancellation follows feed publication")
    func libraryReentryRecoversAfterPublishedFeedCancellation() async throws {
        let key = try feedKey(revision: 14)
        let item = summary(version: 18, cover: cover())
        let feed = PublishedContentFeed(items: [item], nextCursor: nil)
        let response = PublishedContentFeedResponse(
            data: feed,
            meta: MobileResponseMetadata(
                apiVersion: "1",
                requestID: "90000000-0000-4000-8000-000000000097"
            )
        )
        let listing = OneShotLibraryContentListing(response: response)
        let capturing = LibraryCoverCapturingListing(listing: listing)
        let candidates = SuspendedFirstLibraryCoverCandidateProvider(
            upstream: capturing
        )
        let relay = LibraryCoverAuthorizationRelay()
        let model = PublishedContentFeedViewModel(
            listing: capturing,
            stateRecorder: UnavailableBodyFlowCapabilities(),
            keyProvider: DeterministicIdempotencyKeyProvider(
                prefix: "cover-published-reentry"
            ),
            timeProvider: FixedTimeProvider(value: baseDate),
            invalidationCenter: FeatureInvalidationCenter(),
            coverLoader: ScriptedPresentationCoverLoader([])
        )

        let firstLoad = Task { @MainActor in
            await LibraryCoverLoadCoordinator.perform(
                requestedKey: key,
                relay: relay,
                candidateProvider: candidates,
                reusesCompletedAuthorization: true,
                currentKey: { key },
                state: { model.state },
                operation: {
                    await model.load(
                        query: key.query,
                        catalogRevision: key.catalogRevision
                    )
                }
            )
        }
        await candidates.waitUntilFirstTakeStarted()
        #expect(model.state == .loaded(feed))

        firstLoad.cancel()
        relay.cancelPendingLoad()
        let replacement = Task { @MainActor in
            await LibraryCoverLoadCoordinator.perform(
                requestedKey: key,
                relay: relay,
                candidateProvider: candidates,
                reusesCompletedAuthorization: true,
                currentKey: { key },
                state: { model.state },
                recoveryOperation: {
                    await LibraryCoverFirstPageRecovery.perform(
                        model: model,
                        key: key
                    )
                },
                operation: {
                    await model.load(
                        query: key.query,
                        catalogRevision: key.catalogRevision
                    )
                }
            )
        }

        await candidates.resumeFirstTake()
        #expect(await firstLoad.value == false)
        #expect(await replacement.value)
        #expect(await listing.callCount == 2)
        #expect(await candidates.takeCount == 2)
        #expect(relay.authorization(
            for: item,
            requestedKey: key
        )?.cover == item.cover)
    }

    // RED: an invalid first-page cursor disables ordinary retry. Cover
    // recovery must use the model's explicit cursor-reload path and still
    // perform exactly one replacement request before authorizing the response.
    @Test("library cover recovery honors invalid cursor reload ownership")
    func libraryCoverRecoveryUsesInvalidCursorReload() async throws {
        let key = try feedKey(revision: 15)
        let item = summary(version: 19, cover: cover())
        let malformedFeed = PublishedContentFeed(
            items: [item],
            nextCursor: String(repeating: "x", count: 513)
        )
        let publishedFirstFeed = PublishedContentFeed(
            items: [item],
            nextCursor: nil
        )
        let recoveredFeed = PublishedContentFeed(
            items: [item],
            nextCursor: nil
        )
        let listing = QueuedLibraryContentListing(responses: [
            PublishedContentFeedResponse(
                data: malformedFeed,
                meta: MobileResponseMetadata(
                    apiVersion: "1",
                    requestID: "90000000-0000-4000-8000-000000000096"
                )
            ),
            PublishedContentFeedResponse(
                data: recoveredFeed,
                meta: MobileResponseMetadata(
                    apiVersion: "1",
                    requestID: "90000000-0000-4000-8000-000000000095"
                )
            ),
        ])
        let capturing = LibraryCoverCapturingListing(listing: listing)
        let candidates = SuspendedFirstLibraryCoverCandidateProvider(
            upstream: capturing
        )
        let relay = LibraryCoverAuthorizationRelay()
        let model = PublishedContentFeedViewModel(
            listing: capturing,
            stateRecorder: UnavailableBodyFlowCapabilities(),
            keyProvider: DeterministicIdempotencyKeyProvider(
                prefix: "cover-cursor-reentry"
            ),
            timeProvider: FixedTimeProvider(value: baseDate),
            invalidationCenter: FeatureInvalidationCenter(),
            coverLoader: ScriptedPresentationCoverLoader([])
        )

        let firstLoad = Task { @MainActor in
            await LibraryCoverLoadCoordinator.perform(
                requestedKey: key,
                relay: relay,
                candidateProvider: candidates,
                reusesCompletedAuthorization: true,
                currentKey: { key },
                state: { model.state },
                operation: {
                    await model.load(
                        query: key.query,
                        catalogRevision: key.catalogRevision
                    )
                }
            )
        }
        await candidates.waitUntilFirstTakeStarted()
        #expect(model.state == .loaded(publishedFirstFeed))
        #expect(model.nextPageState == .reloadFirstPageRequired)

        firstLoad.cancel()
        relay.cancelPendingLoad()
        let replacement = Task { @MainActor in
            await LibraryCoverLoadCoordinator.perform(
                requestedKey: key,
                relay: relay,
                candidateProvider: candidates,
                reusesCompletedAuthorization: true,
                currentKey: { key },
                state: { model.state },
                recoveryOperation: {
                    await LibraryCoverFirstPageRecovery.perform(
                        model: model,
                        key: key
                    )
                },
                operation: {
                    await model.load(
                        query: key.query,
                        catalogRevision: key.catalogRevision
                    )
                }
            )
        }

        await candidates.resumeFirstTake()
        #expect(await firstLoad.value == false)
        #expect(await replacement.value)
        #expect(await listing.queries == [key.query, key.query])
        #expect(relay.authorization(
            for: item,
            requestedKey: key
        )?.cover == item.cover)
    }

    // RED: SwiftUI may restart the automatic task for an already completed
    // key after navigation. The feed controller intentionally performs no
    // second request, so that reentry must not erase the published capability.
    @Test("library reentry reuses completed authorization for the same key")
    func libraryReentryReusesCompletedAuthorization() async throws {
        let key = try feedKey(revision: 12)
        let item = summary(version: 16, cover: cover())
        let feed = PublishedContentFeed(items: [item], nextCursor: nil)
        let relay = LibraryCoverAuthorizationRelay()
        let initialToken = relay.begin(requestedKey: key)
        #expect(relay.commit(
            candidate: libraryCandidate(
                token: initialToken,
                key: key,
                feed: feed
            ),
            capturedKey: key,
            currentKey: key,
            state: .loaded(feed),
            isCancelled: false
        ))
        var operationWasCalled = false

        let didReuse = await LibraryCoverLoadCoordinator.perform(
            requestedKey: key,
            relay: relay,
            candidateProvider: MissingLibraryCoverCandidateProvider(),
            reusesCompletedAuthorization: true,
            currentKey: { key },
            state: { .loaded(feed) },
            operation: { operationWasCalled = true }
        )

        #expect(didReuse)
        #expect(!operationWasCalled)
        #expect(relay.authorization(
            for: item,
            requestedKey: key
        )?.cover == item.cover)
    }

    // Mutation caught: constructing a fresh/global loader below the shell or
    // losing the authenticated shell's stable session token in Environment.
    @Test("shell cover environment preserves loader and stable session token")
    func shellEnvironmentPreservesSessionComposition() async throws {
        let image = Self.image(width: 2, height: 2)
        let loader = ScriptedPresentationCoverLoader([.success(image)])
        let session = ContentCoverSessionToken(
            rawValue: UUID(uuidString: "EEEEEEEE-EEEE-4EEE-8EEE-EEEEEEEEEEEE")!
        )

        let environment = ContentCoverEnvironment.make(
            loader: loader,
            session: session,
            invalidationCenter: FeatureInvalidationCenter()
        )

        #expect(environment.session == session)
        _ = try await environment.loader.image(
            publicationID: publicationID,
            version: 3,
            cover: cover(),
            target: ContentCoverTargetSize(widthPixels: 20, heightPixels: 10)
        )
        #expect(await loader.calls.count == 1)
    }

    // Mutation caught: wiring SwiftUI task identity to only part of the
    // request, failing to cancel on disappearance, or exposing the decorative
    // neutral placeholder as meaningful accessibility content.
    @Test("view descriptor wires full task identity and decorative placeholder")
    func viewWiringAndPlaceholderSemantics() {
        let request = request(version: 8)
        let descriptor = ContentCoverViewDescriptor(
            request: request,
            parentRevision: 0
        )

        #expect(descriptor.taskIdentity.request == request)
        #expect(descriptor.cancelsOnDisappear)
        #expect(descriptor.placeholder == .neutral)
        #expect(descriptor.isAccessibilityHidden)
    }

    // Mutation caught: bypassing ContentCoverLoading, forwarding point sizes
    // instead of pixel sizes, or failing to publish the loader's decoded image.
    @Test("valid decoded image publishes through the loader-only path")
    func validImagePublishes() async throws {
        let image = Self.image(width: 7, height: 5)
        let loader = ScriptedPresentationCoverLoader([.success(image)])
        let model = ContentCoverViewModel()
        let request = request(version: 4, widthPixels: 361, heightPixels: 240)

        await loadCover(
            model,
            request: request,
            loader: loader,
            onCapabilityInvalidated: {}
        )

        let published = try #require(model.presentation.image)
        #expect(published.cgImage.width == 7)
        #expect(published.cgImage.height == 5)
        let call = try #require(await loader.calls.first)
        #expect(call.publicationID == publicationID)
        #expect(call.version == 4)
        #expect(call.target == ContentCoverTargetSize(
            widthPixels: 361,
            heightPixels: 240
        ))
    }

    // RED: an invalidation closes the gate even when the newly authorized
    // response returns the exact same capability. Authorization, not a token
    // or target change, is what reopens loading.
    @Test("same capability reloads only after its response is authorized")
    func sameCapabilityReloadsAfterAuthorization() async throws {
        let request = request(version: 4)
        let loader = ScriptedPresentationCoverLoader([
            .success(Self.image(width: 4, height: 3)),
            .success(Self.image(width: 8, height: 6)),
        ])
        let model = ContentCoverViewModel()
        let budget = ContentCoverRefreshBudget(session: request.session)

        await model.load(
            descriptor: ContentCoverViewDescriptor(
                request: request,
                parentRevision: 0,
                authorizedParentRevision: 0
            ),
            loader: loader,
            refreshBudget: budget,
            onParentRevisionChanged: {},
            onCapabilityInvalidated: {}
        )
        #expect(try #require(model.presentation.image).cgImage.width == 4)

        await model.load(
            descriptor: ContentCoverViewDescriptor(
                request: request,
                parentRevision: 1,
                authorizedParentRevision: nil
            ),
            loader: loader,
            refreshBudget: budget,
            onParentRevisionChanged: {},
            onCapabilityInvalidated: {}
        )
        #expect(model.presentation.isPlaceholder)
        #expect(await loader.calls.count == 1)

        await model.load(
            descriptor: ContentCoverViewDescriptor(
                request: request,
                parentRevision: 1,
                authorizedParentRevision: 1
            ),
            loader: loader,
            refreshBudget: budget,
            onParentRevisionChanged: {},
            onCapabilityInvalidated: {}
        )
        #expect(try #require(model.presentation.image).cgImage.width == 8)
        #expect(await loader.calls.count == 2)
    }

    // RED: target geometry is part of request cancellation, but it cannot
    // itself authorize a capability while the parent response is pending.
    @Test("target-only replacement cannot reopen a closed revision gate")
    func targetOnlyReplacementCannotAuthorize() async {
        let original = request(version: 4)
        let resized = request(
            version: 4,
            widthPixels: 480,
            heightPixels: 320
        )
        let loader = ScriptedPresentationCoverLoader([])
        let model = ContentCoverViewModel()
        let budget = ContentCoverRefreshBudget(session: original.session)

        await model.load(
            descriptor: ContentCoverViewDescriptor(
                request: original,
                parentRevision: 1,
                authorizedParentRevision: nil
            ),
            loader: loader,
            refreshBudget: budget,
            onParentRevisionChanged: {},
            onCapabilityInvalidated: {}
        )
        await model.load(
            descriptor: ContentCoverViewDescriptor(
                request: resized,
                parentRevision: 1,
                authorizedParentRevision: nil
            ),
            loader: loader,
            refreshBudget: budget,
            onParentRevisionChanged: {},
            onCapabilityInvalidated: {}
        )

        #expect(model.presentation.isPlaceholder)
        #expect(await loader.calls.isEmpty)
    }

    // RED: a task that arrives already cancelled cannot mutate ownership,
    // clear the current image, invoke callbacks or start a replacement load.
    @Test("pre-cancelled load leaves current presentation and ownership intact")
    func preCancelledLoadDoesNotMutate() async throws {
        let image = Self.image(width: 7, height: 5)
        let loader = ScriptedPresentationCoverLoader([.success(image)])
        let model = ContentCoverViewModel()
        let initial = request(version: 4)
        let budget = ContentCoverRefreshBudget(session: initial.session)
        let callbacks = CoverRefreshRecorder()

        await model.load(
            descriptor: ContentCoverViewDescriptor(
                request: initial,
                parentRevision: 0,
                authorizedParentRevision: 0
            ),
            loader: loader,
            refreshBudget: budget,
            onParentRevisionChanged: {},
            onCapabilityInvalidated: {}
        )

        let cancelled = Task { @MainActor in
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            await model.load(
                descriptor: ContentCoverViewDescriptor(
                    request: request(version: 5),
                    parentRevision: 1,
                    authorizedParentRevision: nil
                ),
                loader: loader,
                refreshBudget: budget,
                onParentRevisionChanged: { await callbacks.record() },
                onCapabilityInvalidated: { await callbacks.record() }
            )
        }
        await cancelled.value

        #expect(try #require(model.presentation.image).cgImage.width == 7)
        #expect(await loader.calls.count == 1)
        #expect(await callbacks.count == 0)
    }

    // Mutation caught: refreshing for arbitrary cover failures, refreshing once
    // per rotating raw token/target, or suppressing refresh for a new version.
    @Test("expiry and 404 refresh once per session publication version lineage")
    func notFoundRefreshIsBoundedByLineage() async {
        let loader = ScriptedPresentationCoverLoader([
            .failure(.contentCoverNotFound), // expired capability
            .failure(.contentCoverNotFound), // 404 after token rotation
            .failure(.contentCoverNotFound), // a new version is a new lineage
            .failure(.contentCoverNotFound), // a new publication is a lineage
            .failure(.contentCoverNotFound), // a new session is a lineage
        ])
        let refreshes = CoverRefreshRecorder()
        let model = ContentCoverViewModel()
        let session = ContentCoverSessionToken(
            rawValue: UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
        )
        let budget = ContentCoverRefreshBudget(session: session)

        await loadCover(
            model,
            request: request(
                version: 4,
                url: "/api/mobile/v1/content/covers/expired",
                session: session,
                widthPixels: 240
            ),
            loader: loader,
            refreshBudget: budget,
            onCapabilityInvalidated: { await refreshes.record() }
        )
        await loadCover(
            model,
            request: request(
                version: 4,
                url: "/api/mobile/v1/content/covers/rotated-after-404",
                session: session,
                widthPixels: 480
            ),
            loader: loader,
            refreshBudget: budget,
            onCapabilityInvalidated: { await refreshes.record() }
        )
        #expect(model.presentation.isPlaceholder)
        #expect(await refreshes.count == 1)

        await loadCover(
            model,
            request: request(
                version: 5,
                url: "/api/mobile/v1/content/covers/new-version",
                session: session,
                widthPixels: 480
            ),
            loader: loader,
            refreshBudget: budget,
            onCapabilityInvalidated: { await refreshes.record() }
        )
        #expect(model.presentation.isPlaceholder)
        #expect(await refreshes.count == 2)

        await loadCover(
            model,
            request: request(
                publicationID: "20000000-0000-4000-8000-000000000002",
                version: 5,
                url: "/api/mobile/v1/content/covers/new-publication",
                session: session,
                widthPixels: 480
            ),
            loader: loader,
            refreshBudget: budget,
            onCapabilityInvalidated: { await refreshes.record() }
        )
        #expect(await refreshes.count == 3)

        let nextSession = ContentCoverSessionToken(
            rawValue: UUID(
                uuidString: "FFFFFFFF-FFFF-4FFF-8FFF-FFFFFFFFFFFF"
            )!
        )
        await loadCover(
            model,
            request: request(
                publicationID: "20000000-0000-4000-8000-000000000002",
                version: 5,
                url: "/api/mobile/v1/content/covers/new-session",
                session: nextSession,
                widthPixels: 480
            ),
            loader: loader,
            refreshBudget: ContentCoverRefreshBudget(session: nextSession),
            onCapabilityInvalidated: { await refreshes.record() }
        )
        #expect(await refreshes.count == 4)
    }

    // Mutation caught: letting presentation code classify expiry itself or
    // crossing transport for a capability already expired at the real loader.
    @Test("real loader expiry uses placeholder one refresh and zero transport")
    func realExpiredCapabilityIsBounded() async {
        let stream = CoverLoaderStreamSpy()
        let clock = LockedCoverTimeProvider(now: baseDate)
        let loader = ContentCoverLoader(
            stream: stream,
            origin: try! ContentCoverTrustedOrigin(
                validating: URL(string: "https://mobile.bodyflow.test")!
            ),
            decoder: ContentCoverDecoder(),
            cache: SessionCoverCache(),
            timeProvider: clock
        )
        let refreshes = CoverRefreshRecorder()
        let model = ContentCoverViewModel()
        let expired = ContentCoverPresentationRequest(
            publicationID: publicationID,
            version: 6,
            cover: cover(expiresAt: baseDate),
            target: ContentCoverTargetSize(widthPixels: 240, heightPixels: 160),
            session: ContentCoverSessionToken()
        )

        await loadCover(
            model,
            request: expired,
            loader: loader,
            onCapabilityInvalidated: { await refreshes.record() }
        )

        #expect(model.presentation.isPlaceholder)
        #expect(await refreshes.count == 1)
        #expect(await stream.streamCallCount == 0)
    }

    // Mutation caught: resolving/opening an external capability outside the
    // real loader's raw-path validator.
    @Test("external capability reaches zero real transport calls")
    func externalCapabilityPerformsNoTransport() async {
        let stream = CoverLoaderStreamSpy()
        let loader = ContentCoverLoader(
            stream: stream,
            origin: try! ContentCoverTrustedOrigin(
                validating: URL(string: "https://mobile.bodyflow.test")!
            ),
            decoder: ContentCoverDecoder(),
            cache: SessionCoverCache(),
            timeProvider: LockedCoverTimeProvider(now: baseDate)
        )
        let model = ContentCoverViewModel()

        await loadCover(
            model,
            request: request(
                version: 7,
                url: "https://external.example/private-cover"
            ),
            loader: loader,
            onCapabilityInvalidated: {}
        )

        #expect(model.presentation.isPlaceholder)
        #expect(await stream.streamCallCount == 0)
    }

    // Mutation caught: surfacing different visuals for security/decode errors,
    // treating invalid MIME/dimensions as not-found, or requesting an external
    // URL through anything other than the injected loader boundary.
    @Test("external invalid oversized MIME and dimension failures are identical")
    func boundedFailuresUseOnePlaceholder() async throws {
        let cases: [(String, BodyFlowCapabilityError)] = [
            ("https://external.example/private-cover", .invalidContentCover),
            ("/api/mobile/v1/content/covers/too-large", .contentCoverTooLarge),
            ("/api/mobile/v1/content/covers/invalid-mime", .invalidContentCover),
            ("/api/mobile/v1/content/covers/invalid-dimensions", .invalidContentCover),
        ]
        let loader = ScriptedPresentationCoverLoader(
            cases.map { .failure($0.1) }
        )
        let refreshes = CoverRefreshRecorder()
        let model = ContentCoverViewModel()

        for (index, testCase) in cases.enumerated() {
            await loadCover(
                model,
                request: request(version: index + 1, url: testCase.0),
                loader: loader,
                onCapabilityInvalidated: { await refreshes.record() }
            )
            #expect(model.presentation.isPlaceholder)
        }

        #expect(await refreshes.count == 0)
        #expect(await loader.calls.map(\.coverURL) == cases.map(\.0))
    }

    // Mutation caught: canceling only SwiftUI publication state while leaving
    // the owner operation live, or accepting its non-cooperative late result.
    @Test("view disappearance cancels work and suppresses a late image")
    func disappearanceCancelsAndSuppressesLateImage() async {
        let loader = ControlledPresentationCoverLoader()
        let model = ContentCoverViewModel()
        let load = Task { @MainActor in
            await loadCover(
                model,
                request: request(version: 4),
                loader: loader,
                onCapabilityInvalidated: {}
            )
        }
        await loader.waitForCallCount(1)

        model.cancel()
        await loader.waitUntilCancelled(call: 1)
        await loader.succeed(call: 1, image: Self.image(width: 3, height: 2))
        await load.value

        #expect(model.presentation.isPlaceholder)
    }

    // Mutation caught: omitting version from task ownership, failing to cancel
    // the superseded version, or letting version N publish after N+1.
    @Test("version replacement cancels and suppresses the older late image")
    func versionReplacementSuppressesOldImage() async throws {
        let loader = ControlledPresentationCoverLoader()
        let model = ContentCoverViewModel()
        let oldLoad = Task { @MainActor in
            await loadCover(
                model,
                request: request(version: 4),
                loader: loader,
                onCapabilityInvalidated: {}
            )
        }
        await loader.waitForCallCount(1)

        let newLoad = Task { @MainActor in
            await loadCover(
                model,
                request: request(version: 5),
                loader: loader,
                onCapabilityInvalidated: {}
            )
        }
        await loader.waitForCallCount(2)
        await loader.waitUntilCancelled(call: 1)
        await loader.succeed(call: 2, image: Self.image(width: 5, height: 4))
        await newLoad.value
        await loader.succeed(call: 1, image: Self.image(width: 1, height: 1))
        await oldLoad.value

        let image = try #require(model.presentation.image)
        #expect(image.cgImage.width == 5)
        #expect(image.cgImage.height == 4)
    }

    // Mutation caught: omitting authenticated-session identity from task
    // ownership or allowing an old session's non-cooperative image to publish.
    @Test("old session late result cannot replace the current session image")
    func oldSessionLateResultIsSuppressed() async throws {
        let loader = ControlledPresentationCoverLoader()
        let model = ContentCoverViewModel()
        let sessionA = ContentCoverSessionToken(
            rawValue: UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
        )
        let sessionB = ContentCoverSessionToken(
            rawValue: UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!
        )
        let oldLoad = Task { @MainActor in
            await loadCover(
                model,
                request: request(version: 4, session: sessionA),
                loader: loader,
                onCapabilityInvalidated: {}
            )
        }
        await loader.waitForCallCount(1)

        let newLoad = Task { @MainActor in
            await loadCover(
                model,
                request: request(version: 4, session: sessionB),
                loader: loader,
                onCapabilityInvalidated: {}
            )
        }
        await loader.waitForCallCount(2)
        await loader.waitUntilCancelled(call: 1)
        await loader.succeed(call: 2, image: Self.image(width: 6, height: 4))
        await newLoad.value
        await loader.succeed(call: 1, image: Self.image(width: 2, height: 1))
        await oldLoad.value

        let image = try #require(model.presentation.image)
        #expect(image.cgImage.width == 6)
    }

    // Mutation caught: allowing a superseded version/session not-found to
    // invoke its parent callback after the current image has published.
    @Test("late old version and old session not-found cannot refresh")
    func lateSupersededNotFoundCannotRefresh() async throws {
        for replacement in [
            request(version: 5),
            request(
                version: 4,
                session: ContentCoverSessionToken(
                    rawValue: UUID(
                        uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"
                    )!
                )
            ),
        ] {
            let loader = ControlledPresentationCoverLoader()
            let refreshes = CoverRefreshRecorder()
            let model = ContentCoverViewModel()
            let old = Task { @MainActor in
                await loadCover(
                    model,
                    request: request(version: 4),
                    loader: loader,
                    onCapabilityInvalidated: { await refreshes.record() }
                )
            }
            await loader.waitForCallCount(1)
            let current = Task { @MainActor in
                await loadCover(
                    model,
                    request: replacement,
                    loader: loader,
                    onCapabilityInvalidated: { await refreshes.record() }
                )
            }
            await loader.waitForCallCount(2)
            await loader.succeed(
                call: 2,
                image: Self.image(width: 9, height: 6)
            )
            await current.value
            await loader.fail(call: 1, error: .contentCoverNotFound)
            await old.value

            #expect(await refreshes.count == 0)
            #expect(try #require(model.presentation.image).cgImage.width == 9)
        }
    }

    // Mutation caught: omitting publication, raw capability/expiry, target or
    // nil replacement from cancellation ownership.
    @Test("every request identity dimension cancels the prior operation")
    func everyIdentityDimensionCancelsOldLoad() async {
        let base = request(version: 4)
        let replacements: [ContentCoverPresentationRequest?] = [
            request(
                publicationID: "20000000-0000-4000-8000-000000000002",
                version: 4
            ),
            request(version: 4, url: "/api/mobile/v1/content/covers/replaced"),
            request(
                version: 4,
                expiresAt: baseDate.addingTimeInterval(1_200)
            ),
            request(version: 4, widthPixels: 480, heightPixels: 320),
            nil,
        ]

        for replacement in replacements {
            let loader = ControlledPresentationCoverLoader()
            let model = ContentCoverViewModel()
            let old = Task { @MainActor in
                await loadCover(
                    model,
                    request: base,
                    loader: loader,
                    onCapabilityInvalidated: {}
                )
            }
            await loader.waitForCallCount(1)

            if let replacement {
                let current = Task { @MainActor in
                    await loadCover(
                        model,
                        request: replacement,
                        loader: loader,
                        onCapabilityInvalidated: {}
                    )
                }
                await loader.waitForCallCount(2)
                await loader.waitUntilCancelled(call: 1)
                await loader.succeed(
                    call: 2,
                    image: Self.image(width: 4, height: 3)
                )
                await current.value
            } else {
                await loadCover(
                    model,
                    request: nil,
                    loader: loader,
                    onCapabilityInvalidated: {}
                )
                await loader.waitUntilCancelled(call: 1)
            }
            await loader.succeed(
                call: 1,
                image: Self.image(width: 1, height: 1)
            )
            await old.value
        }
    }

    // Mutation caught: committing a detail cover directly from the provider,
    // or omitting any authorization, revision, latest-token or cancellation
    // gate from the second-phase commit.
    @Test("detail cover commit requires the exact latest authorized load")
    func detailCoverCommitIsTwoPhaseAndExact() {
        let token = ContentDetailCoverLoadToken(
            rawValue: UUID(uuidString: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC")!
        )
        let otherToken = ContentDetailCoverLoadToken(
            rawValue: UUID(uuidString: "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD")!
        )
        let identity = ContentDetailCoverIdentity(
            publicationID: publicationID,
            version: 9
        )

        #expect(ContentDetailCoverCommitPolicy.canCommit(
            candidateIdentity: identity,
            renderedIdentity: identity,
            candidateToken: token,
            latestToken: token,
            capturedRevision: 3,
            currentRevision: 3,
            isCancelled: false
        ))
        #expect(!ContentDetailCoverCommitPolicy.canCommit(
            candidateIdentity: identity,
            renderedIdentity: identity,
            candidateToken: token,
            latestToken: otherToken,
            capturedRevision: 3,
            currentRevision: 3,
            isCancelled: false
        ))
        #expect(!ContentDetailCoverCommitPolicy.canCommit(
            candidateIdentity: identity,
            renderedIdentity: ContentDetailCoverIdentity(
                publicationID: publicationID,
                version: 10
            ),
            candidateToken: token,
            latestToken: token,
            capturedRevision: 3,
            currentRevision: 3,
            isCancelled: false
        ))
        #expect(!ContentDetailCoverCommitPolicy.canCommit(
            candidateIdentity: identity,
            renderedIdentity: identity,
            candidateToken: token,
            latestToken: token,
            capturedRevision: 3,
            currentRevision: 4,
            isCancelled: false
        ))
        #expect(!ContentDetailCoverCommitPolicy.canCommit(
            candidateIdentity: identity,
            renderedIdentity: identity,
            candidateToken: token,
            latestToken: token,
            capturedRevision: 3,
            currentRevision: 3,
            isCancelled: true
        ))
    }

    // RED: commit inputs must be sampled after the candidate-provider await.
    // Token supersession, revision advance or cancellation during that await
    // must all discard the candidate before it reaches the relay.
    @Test("detail revalidates ownership after candidate provider suspension")
    func detailRevalidatesAfterCandidateAwait() async {
        enum Mutation: CaseIterable {
            case token
            case revision
            case cancellation
        }

        for mutation in Mutation.allCases {
            let token = ContentDetailCoverLoadToken()
            let otherToken = ContentDetailCoverLoadToken()
            let candidate = ContentDetailCoverCandidate(
                identity: ContentDetailCoverIdentity(
                    publicationID: publicationID,
                    version: 9
                ),
                cover: cover(url: "/api/mobile/v1/content/covers/detail"),
                token: token
            )
            let provider = SuspendedContentDetailCoverCandidateProvider(
                candidate: candidate,
                latestToken: token
            )
            let relay = ContentDetailCoverRelay()
            var activeToken: ContentDetailCoverLoadToken? = token
            var currentRevision = 3
            var isCancelled = false

            let resolution = Task { @MainActor in
                await ContentDetailCoverObservationCoordinator.resolve(
                    token: token,
                    capturedRevision: 3,
                    provider: provider,
                    relay: relay,
                    currentContext: {
                        ContentDetailCoverCommitContext(
                            activeToken: activeToken,
                            currentRevision: currentRevision,
                            state: .loaded(Self.renderable(
                                publicationID: self.publicationID,
                                version: 9
                            )),
                            isCancelled: isCancelled
                        )
                    }
                )
            }
            await provider.waitUntilStarted()

            switch mutation {
            case .token:
                activeToken = otherToken
            case .revision:
                currentRevision = 4
            case .cancellation:
                isCancelled = true
            }
            await provider.resume()

            #expect(await resolution.value == .discarded)
            #expect(relay.cover(for: candidate.identity) == nil)
        }
    }

    // Mutation caught: exposing a staged GET cover when contract or Markdown
    // authorization fails, rather than requiring the model's exact loaded AST.
    @Test("detail staged cover commits only for an exact authorized loaded state")
    func detailAuthorizationGatesStagedCover() {
        let token = ContentDetailCoverLoadToken()
        let stagedCover = cover(url: "/api/mobile/v1/content/covers/detail")
        let candidate = ContentDetailCoverCandidate(
            identity: ContentDetailCoverIdentity(
                publicationID: publicationID,
                version: 9
            ),
            cover: stagedCover,
            token: token
        )
        let renderable = Self.renderable(publicationID: publicationID, version: 9)
        let invalidContract: FeatureReadState<RenderablePublishedContentDetail> =
            .failed(previousValue: nil, error: .invalidContentContract)
        let invalidMarkdown: FeatureReadState<RenderablePublishedContentDetail> =
            .failed(previousValue: nil, error: .unsupportedMarkdown)

        #expect(ContentDetailCoverAuthorizationCoordinator.authorization(
            candidate: candidate,
            latestToken: token,
            state: invalidContract,
            capturedRevision: 2,
            currentRevision: 2,
            isCancelled: false
        ) == nil)
        #expect(ContentDetailCoverAuthorizationCoordinator.authorization(
            candidate: candidate,
            latestToken: token,
            state: invalidMarkdown,
            capturedRevision: 2,
            currentRevision: 2,
            isCancelled: false
        ) == nil)
        let authorization = ContentDetailCoverAuthorizationCoordinator.authorization(
            candidate: candidate,
            latestToken: token,
            state: .loaded(renderable),
            capturedRevision: 2,
            currentRevision: 2,
            isCancelled: false
        )
        #expect(authorization?.cover == stagedCover)
        #expect(authorization?.revision == 2)
    }

    // RED: an authorization produced by revision N must not be promoted to
    // revision N+1 merely because the rendered detail identity is unchanged.
    @Test("detail cover authorization preserves its published revision")
    func detailAuthorizationDoesNotAdvanceWithCurrentRevision() {
        let token = ContentDetailCoverLoadToken()
        let identity = ContentDetailCoverIdentity(
            publicationID: publicationID,
            version: 9
        )
        let stagedCover = cover(
            url: "/api/mobile/v1/content/covers/detail"
        )
        let candidate = ContentDetailCoverCandidate(
            identity: identity,
            cover: stagedCover,
            token: token
        )
        let relay = ContentDetailCoverRelay()

        #expect(relay.commit(
            candidate,
            latestToken: token,
            state: .loaded(Self.renderable(
                publicationID: publicationID,
                version: 9
            )),
            capturedRevision: 6,
            currentRevision: 6,
            isCancelled: false
        ))
        #expect(relay.authorization(for: identity)?.revision == 6)

        let descriptor = ContentCoverViewDescriptor(
            request: ContentCoverPresentationRequest(
                publicationID: publicationID,
                version: 9,
                cover: stagedCover,
                target: ContentCoverTargetSize(
                    widthPixels: 240,
                    heightPixels: 160
                ),
                session: ContentCoverSessionToken()
            ),
            parentRevision: 7,
            authorizedParentRevision: relay.authorization(
                for: identity
            )?.revision
        )
        #expect(descriptor.taskIdentity.authorizedParentRevision == 6)
        #expect(descriptor.taskIdentity.parentRevision == 7)
    }

    // Mutation caught: staging from a second detail fetch, or allowing the
    // response for N to survive a same-owner N+1 supersession.
    @Test("detail staging uses the same GET and keeps only the latest token")
    func detailStagingSuppressesSupersededResponse() async throws {
        let provider = ControlledPresentationDetailProvider()
        let staging = ContentDetailCoverCapturingProvider(provider: provider)
        let tokenN = ContentDetailCoverLoadToken()
        let tokenNext = ContentDetailCoverLoadToken()
        let old = Task {
            try await ContentDetailCoverLoadContext.withToken(tokenN) {
                try await staging.contentDetail(publicationID: publicationID)
            }
        }
        await provider.waitForCallCount(1)
        let current = Task {
            try await ContentDetailCoverLoadContext.withToken(tokenNext) {
                try await staging.contentDetail(publicationID: publicationID)
            }
        }
        await provider.waitForCallCount(2)

        await provider.succeed(
            call: 2,
            response: detailResponse(version: 10)
        )
        _ = try await current.value
        await provider.succeed(
            call: 1,
            response: detailResponse(version: 9)
        )
        await #expect(throws: CancellationError.self) {
            _ = try await old.value
        }

        #expect(await provider.publicationIDs == [publicationID, publicationID])
        #expect(await staging.takeCandidate(for: tokenN) == nil)
        let latest = try #require(
            await staging.takeCandidate(for: tokenNext)?.0
        )
        #expect(latest.identity == ContentDetailCoverIdentity(
            publicationID: publicationID,
            version: 10
        ))
        #expect(latest.cover == cover(url: "/api/mobile/v1/content/covers/v10"))
    }

    @Test("detail synchronous cancellation closes authorization before return")
    func detailCancellationClosesAuthorizationSynchronously() async {
        let provider = ControlledPresentationDetailProvider()
        let composition = makeDetailComposition(
            provider: provider,
            recorder: UnavailableBodyFlowCapabilities()
        )
        let load = Task { @MainActor in
            await composition.performLoad(
                revision: 3,
                isRetry: false,
                currentRevision: { 3 }
            )
        }
        await provider.waitForCallCount(1)

        composition.cancelActiveLoad()
        await provider.succeed(
            call: 1,
            response: detailResponse(version: 9)
        )
        await load.value

        #expect(composition.cover(for: ContentDetailCoverIdentity(
            publicationID: publicationID,
            version: 9
        )) == nil)
    }

    // Mutation caught: retaining an already-decoded image when the owning
    // catalog revision changes, or fetching that stale request before the
    // nearest parent refresh has completed and published a new request.
    @Test("parent revision clears the image and gates the stale request")
    func parentRevisionClearsAndGatesStaleRequest() async throws {
        let oldRequest = request(version: 4)
        let newRequest = request(
            version: 5,
            url: "/api/mobile/v1/content/covers/canonical-v5"
        )
        let loader = ScriptedPresentationCoverLoader([
            .success(Self.image(width: 4, height: 3)),
            .success(Self.image(width: 8, height: 6)),
        ])
        let budget = ContentCoverRefreshBudget(session: oldRequest.session)
        let model = ContentCoverViewModel()

        await model.load(
            descriptor: ContentCoverViewDescriptor(
                request: oldRequest,
                parentRevision: 0
            ),
            loader: loader,
            refreshBudget: budget,
            onParentRevisionChanged: {},
            onCapabilityInvalidated: {}
        )
        #expect(try #require(model.presentation.image).cgImage.width == 4)

        let refresh = ControlledParentRefresh()
        let invalidated = Task { @MainActor in
            await model.load(
                descriptor: ContentCoverViewDescriptor(
                    request: oldRequest,
                    parentRevision: 1,
                    authorizedParentRevision: nil
                ),
                loader: loader,
                refreshBudget: budget,
                onParentRevisionChanged: { await refresh.run() },
                onCapabilityInvalidated: {}
            )
        }
        await refresh.waitUntilStarted()

        #expect(model.presentation.isPlaceholder)
        #expect(await loader.calls.count == 1)

        await refresh.finish()
        await invalidated.value
        #expect(model.presentation.isPlaceholder)
        #expect(await loader.calls.count == 1)

        await model.load(
            descriptor: ContentCoverViewDescriptor(
                request: newRequest,
                parentRevision: 1,
                authorizedParentRevision: 1
            ),
            loader: loader,
            refreshBudget: budget,
            onParentRevisionChanged: {},
            onCapabilityInvalidated: {}
        )
        #expect(try #require(model.presentation.image).cgImage.width == 8)
        #expect(await loader.calls.count == 2)
    }

    // Mutation caught: keeping a not-found budget in an ephemeral view model,
    // keying it by rotating token/target, or never rearming it after success.
    @Test("session budget is shared bounded and rearmed by success")
    func sessionBudgetIsSharedBoundedAndRearmed() async {
        let session = ContentCoverSessionToken(
            rawValue: UUID(uuidString: "ABABABAB-ABAB-4BAB-8BAB-ABABABABABAB")!
        )
        let budget = ContentCoverRefreshBudget(session: session)
        let refreshes = CoverRefreshRecorder()
        let loader = ScriptedPresentationCoverLoader([
            .failure(.contentCoverNotFound),
            .failure(.contentCoverNotFound),
            .success(Self.image(width: 3, height: 2)),
            .failure(.contentCoverNotFound),
            .failure(.contentCoverNotFound),
            .failure(.contentCoverNotFound),
        ])

        func load(
            _ request: ContentCoverPresentationRequest,
            model: ContentCoverViewModel
        ) async {
            await model.load(
                descriptor: ContentCoverViewDescriptor(
                    request: request,
                    parentRevision: 0
                ),
                loader: loader,
                refreshBudget: budget,
                onParentRevisionChanged: {},
                onCapabilityInvalidated: { await refreshes.record() }
            )
        }

        await load(request(version: 4, session: session), model: .init())
        await load(request(
            version: 4,
            url: "/api/mobile/v1/content/covers/rotated",
            session: session,
            widthPixels: 480
        ), model: .init())
        #expect(await refreshes.count == 1)

        await load(request(
            version: 4,
            url: "/api/mobile/v1/content/covers/success",
            session: session
        ), model: .init())
        await load(request(
            version: 4,
            url: "/api/mobile/v1/content/covers/later-expiry",
            session: session
        ), model: .init())
        #expect(await refreshes.count == 2)

        await load(request(version: 5, session: session), model: .init())
        await load(request(
            publicationID: "20000000-0000-4000-8000-000000000002",
            version: 5,
            session: session
        ), model: .init())
        #expect(await refreshes.count == 4)

        let nextEnvironment = ContentCoverEnvironment.make(
            loader: loader,
            session: ContentCoverSessionToken(
                rawValue: UUID(
                    uuidString: "CDCDCDCD-CDCD-4DCD-8DCD-CDCDCDCDCDCD"
                )!
            ),
            invalidationCenter: FeatureInvalidationCenter()
        )
        #expect(nextEnvironment.refreshBudget !== budget)
    }

    // Mutation caught: allowing a late older-version success/failure from a
    // different view model to roll the shared budget back after the newer
    // version has already claimed its one consecutive not-found refresh.
    @Test("late older completion cannot roll session budget backward")
    func lateOlderCompletionCannotRollBudgetBackward() async {
        let session = ContentCoverSessionToken(
            rawValue: UUID(uuidString: "EFEFEFEF-EFEF-4FEF-8FEF-EFEFEFEFEFEF")!
        )
        let budget = ContentCoverRefreshBudget(session: session)
        let loader = ControlledPresentationCoverLoader()
        let refreshes = CoverRefreshRecorder()
        let oldModel = ContentCoverViewModel()
        let newModel = ContentCoverViewModel()

        let old = Task { @MainActor in
            await loadCover(
                oldModel,
                request: request(version: 4, session: session),
                loader: loader,
                refreshBudget: budget,
                onCapabilityInvalidated: { await refreshes.record() }
            )
        }
        await loader.waitForCallCount(1)
        let current = Task { @MainActor in
            await loadCover(
                newModel,
                request: request(version: 5, session: session),
                loader: loader,
                refreshBudget: budget,
                onCapabilityInvalidated: { await refreshes.record() }
            )
        }
        await loader.waitForCallCount(2)
        await loader.fail(call: 2, error: .contentCoverNotFound)
        await current.value
        #expect(await refreshes.count == 1)

        await loader.succeed(call: 1, image: Self.image(width: 2, height: 2))
        await old.value

        let repeated = Task { @MainActor in
            await loadCover(
                ContentCoverViewModel(),
                request: request(
                    version: 5,
                    url: "/api/mobile/v1/content/covers/v5-rotated",
                    session: session
                ),
                loader: loader,
                refreshBudget: budget,
                onCapabilityInvalidated: { await refreshes.record() }
            )
        }
        await loader.waitForCallCount(3)
        await loader.fail(call: 3, error: .contentCoverNotFound)
        await repeated.value

        #expect(await refreshes.count == 1)
    }

    // Mutation caught: making the provider a plain View value while SwiftUI
    // retains a different model/relay State graph after static reinitialization.
    @Test("detail composition owns one persistent model provider and relay")
    func detailCompositionOwnsOnePersistentGraph() {
        let provider = ControlledPresentationDetailProvider()
        let composition = makeDetailComposition(
            provider: provider,
            recorder: SuspendedOpenedRecorder()
        )

        #expect(composition.identity == ContentDetailCoverCompositionIdentity(
            model: ObjectIdentifier(composition.model),
            provider: ObjectIdentifier(composition.coverProvider),
            relay: composition.coverRelayIdentity
        ))
        #expect(composition.identity == composition.taskOwnerIdentity)
        #expect(ContentDetailCoverTaskIdentity(
            composition: composition.taskOwnerIdentity,
            revision: 7
        ).composition == composition.identity)
    }

    // Mutation caught: waiting for the non-blocking opened POST to complete
    // before authorizing the already validated and rendered detail cover, or
    // clearing it when the completed revision reappears without a second GET.
    @Test("loaded detail authorizes cover before opened completes")
    func loadedDetailAuthorizesBeforeOpenedCompletes() async throws {
        let response = detailResponse(version: 9)
        try PublishedContentContractValidator.validate(response.data)
        _ = try BodyFlowMarkdownParser().parse(response.data.bodyMarkdown)
        let provider = ControlledPresentationDetailProvider()
        let recorder = SuspendedOpenedRecorder()
        let composition = makeDetailComposition(
            provider: provider,
            recorder: recorder
        )
        let load = Task { @MainActor in
            await composition.performLoad(
                revision: 0,
                isRetry: false,
                currentRevision: { 0 }
            )
        }
        await provider.waitForCallCount(1)
        await provider.succeed(call: 1, response: response)
        await recorder.waitUntilStarted()

        let identity = ContentDetailCoverIdentity(
            publicationID: publicationID,
            version: 9
        )
        #expect(await waitForAuthorizedCover(
            composition: composition,
            identity: identity
        ) == cover(url: "/api/mobile/v1/content/covers/v9"))
        #expect(await recorder.hasPendingRead)
        #expect(await provider.publicationIDs.count == 1)

        await recorder.succeed(response: stateResponse(version: 9))
        await load.value
        await composition.performLoad(
            revision: 0,
            isRetry: false,
            currentRevision: { 0 }
        )
        #expect(await provider.publicationIDs.count == 1)
        #expect(composition.cover(for: ContentDetailCoverIdentity(
            publicationID: publicationID,
            version: 9
        )) != nil)
    }

    // RED: leaving and returning after a completed detail load must not turn a
    // same-revision controller no-op into a permanent neutral placeholder.
    @Test("detail reentry preserves completed same-revision authorization")
    func detailReentryPreservesCompletedAuthorization() async throws {
        let response = detailResponse(version: 9)
        let provider = ControlledPresentationDetailProvider()
        let recorder = SuspendedOpenedRecorder()
        let composition = makeDetailComposition(
            provider: provider,
            recorder: recorder
        )
        let load = Task { @MainActor in
            await composition.performLoad(
                revision: 4,
                isRetry: false,
                currentRevision: { 4 }
            )
        }
        await provider.waitForCallCount(1)
        await provider.succeed(call: 1, response: response)
        await recorder.waitUntilStarted()
        let identity = ContentDetailCoverIdentity(
            publicationID: publicationID,
            version: 9
        )
        #expect(await waitForAuthorizedCover(
            composition: composition,
            identity: identity
        ) != nil)
        await recorder.succeed(response: stateResponse(version: 9))
        await load.value

        composition.cancelActiveLoad()
        #expect(composition.hasCoverAuthorization(for: identity))
        await composition.performLoad(
            revision: 4,
            isRetry: false,
            currentRevision: { 4 }
        )

        #expect(await provider.publicationIDs.count == 1)
        #expect(composition.hasCoverAuthorization(for: identity))
    }

    // Mutation caught: leaving a raw capability staged after any terminal
    // negative authorization path instead of destructively discarding it.
    @Test("detail coordinator discards every unauthorized staged candidate")
    func detailCoordinatorDiscardsUnauthorizedCandidates() async throws {
        let states: [(
            FeatureReadState<RenderablePublishedContentDetail>,
            Int,
            Bool
        )] = [
            (.failed(previousValue: nil, error: .invalidContentContract), 3, false),
            (.failed(previousValue: nil, error: .unsupportedMarkdown), 3, false),
            (.loaded(Self.renderable(publicationID: publicationID, version: 9)), 4, false),
            (.loaded(Self.renderable(publicationID: publicationID, version: 9)), 3, true),
        ]

        for (index, item) in states.enumerated() {
            let provider = ControlledPresentationDetailProvider()
            let staging = ContentDetailCoverCapturingProvider(provider: provider)
            let token = ContentDetailCoverLoadToken()
            let staged = Task {
                try await ContentDetailCoverLoadContext.withToken(token) {
                    try await staging.contentDetail(publicationID: publicationID)
                }
            }
            await provider.waitForCallCount(1)
            await provider.succeed(
                call: 1,
                response: detailResponse(version: 9)
            )
            _ = try await staged.value

            let relay = ContentDetailCoverRelay()
            let resolution = await ContentDetailCoverObservationCoordinator.resolve(
                token: token,
                capturedRevision: 3,
                provider: staging,
                relay: relay,
                currentContext: {
                    ContentDetailCoverCommitContext(
                        activeToken: token,
                        currentRevision: item.1,
                        state: item.0,
                        isCancelled: item.2
                    )
                }
            )

            #expect(resolution == .discarded)
            #expect(
                await staging.takeCandidate(for: token) == nil,
                "Unauthorized case \(index) retained a staged capability"
            )
        }
    }

    // Mutation caught: retaining hard-coded descriptor fields that tests can
    // inspect while ContentCoverView ignores them for task/render/lifecycle.
    @Test("production descriptor drives task placeholder and accessibility")
    func productionDescriptorDrivesViewSemantics() {
        let request = request(version: 12)
        let descriptor = ContentCoverViewDescriptor(
            request: request,
            parentRevision: 7
        )

        #expect(descriptor.taskIdentity == ContentCoverTaskIdentity(
            request: request,
            parentRevision: 7,
            authorizedParentRevision: 7
        ))
        #expect(descriptor.rendering(for: .placeholder) == .neutralPlaceholder)
        #expect(descriptor.cancelsOnDisappear)
        #expect(descriptor.isAccessibilityHidden)
    }

    private func loadCover(
        _ model: ContentCoverViewModel,
        request: ContentCoverPresentationRequest?,
        loader: any ContentCoverLoading,
        refreshBudget: ContentCoverRefreshBudget? = nil,
        parentRevision: Int = 0,
        onParentRevisionChanged: @escaping
            ContentCoverViewModel.InvalidationAction = {},
        onCapabilityInvalidated: @escaping
            ContentCoverViewModel.InvalidationAction
    ) async {
        let session = request?.session ?? ContentCoverSessionToken(
            rawValue: UUID(
                uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
            )!
        )
        await model.load(
            descriptor: ContentCoverViewDescriptor(
                request: request,
                parentRevision: parentRevision
            ),
            loader: loader,
            refreshBudget: refreshBudget
                ?? ContentCoverRefreshBudget(session: session),
            onParentRevisionChanged: onParentRevisionChanged,
            onCapabilityInvalidated: onCapabilityInvalidated
        )
    }

    private func request(
        publicationID: String? = nil,
        version: Int,
        url: String = "/api/mobile/v1/content/covers/AbC_123-xyz",
        expiresAt: Date? = nil,
        session: ContentCoverSessionToken = ContentCoverSessionToken(
            rawValue: UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
        ),
        widthPixels: Int = 240,
        heightPixels: Int = 160
    ) -> ContentCoverPresentationRequest {
        ContentCoverPresentationRequest(
            publicationID: publicationID ?? self.publicationID,
            version: version,
            cover: cover(url: url, expiresAt: expiresAt),
            target: ContentCoverTargetSize(
                widthPixels: widthPixels,
                heightPixels: heightPixels
            ),
            session: session
        )
    }

    private func feedKey(revision: Int) throws -> FeedLoadKey {
        FeedLoadKey(
            query: try ContentFeedQuery(
                surface: .library,
                category: nil,
                limit: 20,
                cursor: nil
            ),
            catalogRevision: revision
        )
    }

    private func libraryCandidate(
        token: LibraryCoverLoadToken,
        key: FeedLoadKey,
        feed: PublishedContentFeed
    ) -> LibraryCoverResponseCandidate {
        LibraryCoverResponseCandidate(
            token: token,
            query: key.query,
            feed: feed
        )
    }

    private func cover(
        url: String = "/api/mobile/v1/content/covers/AbC_123-xyz",
        expiresAt: Date? = nil
    ) -> PublishedContentCover {
        PublishedContentCover(
            url: url,
            expiresAt: APITimestamp(
                value: expiresAt ?? baseDate.addingTimeInterval(600)
            )
        )
    }

    private func summary(
        version: Int,
        cover: PublishedContentCover?
    ) -> PublishedContentSummary {
        PublishedContentSummary(
            publicationID: publicationID,
            slug: "conteudo-seguro",
            locale: .ptBR,
            title: "Conteúdo seguro",
            excerpt: "Resumo seguro longo o suficiente para o contrato móvel.",
            category: .nutrition,
            tags: ["seguro"],
            readingTimeMinutes: 4,
            publishAt: APITimestamp(value: baseDate),
            featuredToday: false,
            version: version,
            saved: false,
            completed: false,
            cover: cover
        )
    }

    private func detailResponse(
        version: Int
    ) -> PublishedContentDetailResponse {
        PublishedContentDetailResponse(
            data: PublishedContentDetail(
                summary: summary(
                    version: version,
                    cover: cover(
                        url: "/api/mobile/v1/content/covers/v\(version)"
                    )
                ),
                bodyMarkdown: "## Conteúdo seguro\n\nTexto autorizado suficientemente longo para o contrato do detalhe móvel, com contexto adicional validado antes da apresentação.\n"
            ),
            meta: MobileResponseMetadata(
                apiVersion: "1",
                requestID: "90000000-0000-4000-8000-000000000021"
            )
        )
    }

    private static func renderable(
        publicationID: String,
        version: Int
    ) -> RenderablePublishedContentDetail {
        RenderablePublishedContentDetail(
            publicationID: publicationID,
            version: version,
            title: "Conteúdo seguro",
            categoryLabel: "Nutrição",
            readingTimeLabel: "4 min de leitura",
            saved: false,
            completed: false,
            document: BodyFlowMarkdownDocument(blocks: [
                .paragraph(children: [.text("Conteúdo autorizado")]),
            ])
        )
    }

    private static func image(width: Int, height: Int) -> ContentCoverImage {
        let bytesPerRow = width * 4
        let data = Data(repeating: 0x7F, count: bytesPerRow * height)
        let provider = CGDataProvider(data: data as CFData)!
        let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.noneSkipLast.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        return ContentCoverImage(cgImage: cgImage)
    }

    private func makeDetailComposition(
        provider: any PublishedContentDetailProviding,
        recorder: any PublishedContentStateRecording
    ) -> ContentDetailCoverComposition {
        ContentDetailCoverComposition.make(
            publicationID: publicationID,
            origin: .library,
            detailProvider: provider,
            stateRecorder: recorder,
            keyProvider: DeterministicIdempotencyKeyProvider(
                prefix: "cover-composition"
            ),
            timeProvider: FixedTimeProvider(value: baseDate),
            invalidationCenter: FeatureInvalidationCenter(),
            coverLoader: ScriptedPresentationCoverLoader([])
        )
    }

    private func waitForAuthorizedCover(
        composition: ContentDetailCoverComposition,
        identity: ContentDetailCoverIdentity
    ) async -> PublishedContentCover? {
        while true {
            if let cover = composition.cover(for: identity) {
                return cover
            }
            await withCheckedContinuation { continuation in
                withObservationTracking {
                    _ = composition.cover(for: identity)
                } onChange: {
                    continuation.resume()
                }
            }
        }
    }

    private func stateResponse(version: Int) -> PublishedContentStateResponse {
        PublishedContentStateResponse(
            data: PublishedContentState(
                publicationID: publicationID,
                version: version,
                saved: false,
                completed: false,
                changed: false,
                replayed: false
            ),
            meta: MobileResponseMetadata(
                apiVersion: "1",
                requestID: "90000000-0000-4000-8000-000000000022"
            )
        )
    }
}

private extension ContentCoverPresentation {
    var isPlaceholder: Bool {
        if case .placeholder = self { return true }
        return false
    }

    var image: ContentCoverImage? {
        if case let .image(image) = self { return image }
        return nil
    }
}

private struct PresentationCoverCall: Equatable, Sendable {
    let publicationID: String
    let version: Int
    let coverURL: String
    let target: ContentCoverTargetSize
}

private actor ScriptedPresentationCoverLoader: ContentCoverLoading {
    private var results: [Result<ContentCoverImage, BodyFlowCapabilityError>]
    private(set) var calls: [PresentationCoverCall] = []

    init(_ results: [Result<ContentCoverImage, BodyFlowCapabilityError>]) {
        self.results = results
    }

    func image(
        publicationID: String,
        version: Int,
        cover: PublishedContentCover,
        target: ContentCoverTargetSize
    ) async throws -> ContentCoverImage {
        calls.append(PresentationCoverCall(
            publicationID: publicationID,
            version: version,
            coverURL: cover.url,
            target: target
        ))
        guard !results.isEmpty else {
            throw BodyFlowCapabilityError.operationUnavailable
        }
        return try results.removeFirst().get()
    }

    func remove(publicationID: String, version: Int) async {}
    func endSession() async {}
}

private actor ControlledPresentationCoverLoader: ContentCoverLoading {
    private var callCount = 0
    private var continuations: [
        Int: CheckedContinuation<ContentCoverImage, any Error>
    ] = [:]
    private var callCountWaiters: [
        (count: Int, continuation: CheckedContinuation<Void, Never>)
    ] = []
    private var cancelledCalls: Set<Int> = []
    private var cancellationWaiters: [
        Int: [CheckedContinuation<Void, Never>]
    ] = [:]

    func image(
        publicationID: String,
        version: Int,
        cover: PublishedContentCover,
        target: ContentCoverTargetSize
    ) async throws -> ContentCoverImage {
        callCount += 1
        let call = callCount
        let ready = callCountWaiters.filter { callCount >= $0.count }
        callCountWaiters.removeAll { callCount >= $0.count }
        for waiter in ready {
            waiter.continuation.resume()
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                continuations[call] = continuation
            }
        } onCancel: {
            Task { await self.recordCancellation(call: call) }
        }
    }

    func remove(publicationID: String, version: Int) async {}
    func endSession() async {}

    func waitForCallCount(_ expectedCount: Int) async {
        guard callCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            callCountWaiters.append((expectedCount, continuation))
        }
    }

    func waitUntilCancelled(call: Int) async {
        guard !cancelledCalls.contains(call) else { return }
        await withCheckedContinuation { continuation in
            cancellationWaiters[call, default: []].append(continuation)
        }
    }

    func succeed(call: Int, image: ContentCoverImage) {
        continuations.removeValue(forKey: call)?.resume(returning: image)
    }

    func fail(call: Int, error: BodyFlowCapabilityError) {
        continuations.removeValue(forKey: call)?.resume(throwing: error)
    }

    private func recordCancellation(call: Int) {
        cancelledCalls.insert(call)
        let waiters = cancellationWaiters.removeValue(forKey: call) ?? []
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private actor ControlledPresentationDetailProvider:
    PublishedContentDetailProviding {
    private var continuations: [
        Int: CheckedContinuation<PublishedContentDetailResponse, any Error>
    ] = [:]
    private var callCountWaiters: [
        (count: Int, continuation: CheckedContinuation<Void, Never>)
    ] = []
    private(set) var publicationIDs: [String] = []

    func contentDetail(
        publicationID: String
    ) async throws -> PublishedContentDetailResponse {
        publicationIDs.append(publicationID)
        let call = publicationIDs.count
        let ready = callCountWaiters.filter {
            publicationIDs.count >= $0.count
        }
        callCountWaiters.removeAll {
            publicationIDs.count >= $0.count
        }
        for waiter in ready {
            waiter.continuation.resume()
        }
        return try await withCheckedThrowingContinuation { continuation in
            continuations[call] = continuation
        }
    }

    func waitForCallCount(_ count: Int) async {
        guard publicationIDs.count < count else { return }
        await withCheckedContinuation { continuation in
            callCountWaiters.append((count, continuation))
        }
    }

    func succeed(
        call: Int,
        response: PublishedContentDetailResponse
    ) {
        continuations.removeValue(forKey: call)?.resume(returning: response)
    }
}

private actor SuspendedContentDetailCoverCandidateProvider:
    ContentDetailCoverCandidateProviding {
    private let candidate: ContentDetailCoverCandidate
    private let latestToken: ContentDetailCoverLoadToken
    private var didStart = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    init(
        candidate: ContentDetailCoverCandidate,
        latestToken: ContentDetailCoverLoadToken
    ) {
        self.candidate = candidate
        self.latestToken = latestToken
    }

    func takeCandidate(
        for token: ContentDetailCoverLoadToken
    ) async -> (ContentDetailCoverCandidate, ContentDetailCoverLoadToken)? {
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }
        guard token == candidate.token else { return nil }
        return (candidate, latestToken)
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}

private actor CoverRefreshRecorder {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

@MainActor
private final class LibraryCoverCoordinatorProbe {
    private var didEnter = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var operationWaiters: [
        (count: Int, continuation: CheckedContinuation<Void, Never>)
    ] = []
    private(set) var operationStartCount = 0

    func markEntered() {
        didEnter = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilEntered() async {
        guard !didEnter else { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func recordOperationStart() {
        operationStartCount += 1
        let ready = operationWaiters.filter {
            operationStartCount >= $0.count
        }
        operationWaiters.removeAll {
            operationStartCount >= $0.count
        }
        for waiter in ready {
            waiter.continuation.resume()
        }
    }

    func waitForOperationStartCount(_ count: Int) async {
        guard operationStartCount < count else { return }
        await withCheckedContinuation { continuation in
            operationWaiters.append((count, continuation))
        }
    }
}

private actor NonCooperativeLibraryContentListing:
    PublishedContentListing {
    private var continuations: [
        Int: CheckedContinuation<PublishedContentFeedResponse, any Error>
    ] = [:]
    private var callCountWaiters: [
        (count: Int, continuation: CheckedContinuation<Void, Never>)
    ] = []
    private(set) var queries: [ContentFeedQuery] = []

    var callCount: Int { queries.count }

    func content(
        _ query: ContentFeedQuery
    ) async throws -> PublishedContentFeedResponse {
        queries.append(query)
        let call = queries.count
        let ready = callCountWaiters.filter { queries.count >= $0.count }
        callCountWaiters.removeAll { queries.count >= $0.count }
        for waiter in ready {
            waiter.continuation.resume()
        }

        return try await withCheckedThrowingContinuation { continuation in
            continuations[call] = continuation
        }
    }

    func waitForCallCount(_ count: Int) async {
        guard queries.count < count else { return }
        await withCheckedContinuation { continuation in
            callCountWaiters.append((count, continuation))
        }
    }

    func succeed(
        call: Int,
        response: PublishedContentFeedResponse
    ) {
        continuations.removeValue(forKey: call)?.resume(returning: response)
    }
}

private actor ControlledParentRefresh {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var finishContinuation: CheckedContinuation<Void, Never>?

    func run() async {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            finishContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func finish() {
        finishContinuation?.resume()
        finishContinuation = nil
    }
}

private actor ImmediateLibraryCoverCandidateProvider:
    LibraryCoverCandidateProviding {
    private let query: ContentFeedQuery
    private let feed: PublishedContentFeed

    init(query: ContentFeedQuery, feed: PublishedContentFeed) {
        self.query = query
        self.feed = feed
    }

    func takeCandidate(
        for token: LibraryCoverLoadToken
    ) -> LibraryCoverResponseCandidate? {
        LibraryCoverResponseCandidate(
            token: token,
            query: query,
            feed: feed
        )
    }
}

private actor OneShotLibraryContentListing: PublishedContentListing {
    private let response: PublishedContentFeedResponse
    private(set) var callCount = 0

    init(response: PublishedContentFeedResponse) {
        self.response = response
    }

    func content(
        _ query: ContentFeedQuery
    ) async throws -> PublishedContentFeedResponse {
        callCount += 1
        return response
    }
}

private actor QueuedLibraryContentListing: PublishedContentListing {
    private var responses: [PublishedContentFeedResponse]
    private(set) var queries: [ContentFeedQuery] = []

    init(responses: [PublishedContentFeedResponse]) {
        self.responses = responses
    }

    func content(
        _ query: ContentFeedQuery
    ) async throws -> PublishedContentFeedResponse {
        guard !responses.isEmpty else {
            throw BodyFlowCapabilityError.operationUnavailable
        }
        queries.append(query)
        return responses.removeFirst()
    }
}

private actor MissingLibraryCoverCandidateProvider:
    LibraryCoverCandidateProviding {
    func takeCandidate(
        for token: LibraryCoverLoadToken
    ) -> LibraryCoverResponseCandidate? {
        nil
    }
}

private actor SuspendedFirstLibraryCoverCandidateProvider:
    LibraryCoverCandidateProviding {
    private let upstream: any LibraryCoverCandidateProviding
    private var firstTakeStarted = false
    private var firstTakeWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstTakeContinuation: CheckedContinuation<Void, Never>?
    private(set) var takeCount = 0

    init(upstream: any LibraryCoverCandidateProviding) {
        self.upstream = upstream
    }

    func takeCandidate(
        for token: LibraryCoverLoadToken
    ) async -> LibraryCoverResponseCandidate? {
        takeCount += 1
        if takeCount == 1 {
            firstTakeStarted = true
            let waiters = firstTakeWaiters
            firstTakeWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
            await withCheckedContinuation { continuation in
                firstTakeContinuation = continuation
            }
        }
        return await upstream.takeCandidate(for: token)
    }

    func waitUntilFirstTakeStarted() async {
        guard !firstTakeStarted else { return }
        await withCheckedContinuation { continuation in
            firstTakeWaiters.append(continuation)
        }
    }

    func resumeFirstTake() {
        firstTakeContinuation?.resume()
        firstTakeContinuation = nil
    }
}

private actor SuspendedLibraryCoverCandidateProvider:
    LibraryCoverCandidateProviding {
    private let query: ContentFeedQuery
    private let feed: PublishedContentFeed
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    init(query: ContentFeedQuery, feed: PublishedContentFeed) {
        self.query = query
        self.feed = feed
    }

    func takeCandidate(
        for token: LibraryCoverLoadToken
    ) async -> LibraryCoverResponseCandidate? {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }
        return LibraryCoverResponseCandidate(
            token: token,
            query: query,
            feed: feed
        )
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}

private actor SuspendedOpenedRecorder: PublishedContentStateRecording {
    private var readContinuation: CheckedContinuation<
        PublishedContentStateResponse,
        any Error
    >?
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func recordRead(
        _ attempt: MutationAttempt<ContentReadCommand>
    ) async throws -> PublishedContentStateResponse {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        return try await withCheckedThrowingContinuation { continuation in
            readContinuation = continuation
        }
    }

    func setSaved(
        _ attempt: MutationAttempt<ContentSaveCommand>
    ) async throws -> PublishedContentStateResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func succeed(response: PublishedContentStateResponse) {
        readContinuation?.resume(returning: response)
        readContinuation = nil
    }

    var hasPendingRead: Bool { readContinuation != nil }
}
