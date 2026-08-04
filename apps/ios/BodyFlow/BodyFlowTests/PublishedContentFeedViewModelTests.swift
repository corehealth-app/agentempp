import Foundation
import Testing

@testable import BodyFlow

@Suite("Published content feed view model")
@MainActor
struct PublishedContentFeedViewModelTests {
    @Test("pending first page is loading and forwards the exact query")
    func initialLoadingAndQuery() async throws {
        let provider = ControlledPublishedContentListing()
        let model = PublishedContentFeedViewModel(listing: provider)
        let query = try Self.query(
            surface: .library,
            category: .sleep
        )

        let load = Task { await model.load(query: query, catalogRevision: 7) }
        await provider.waitForCallCount(1)

        #expect(model.state == .loading)
        #expect(await provider.recordedQueries() == [query])

        await provider.succeed(call: 1, with: Self.response(items: [Self.item(1)]))
        await load.value
    }

    @Test("first page publishes the complete feed")
    func loaded() async throws {
        let feed = Self.feed(items: [Self.item(1), Self.item(2)], nextCursor: "next")
        let provider = QueuePublishedContentListing([.success(Self.response(feed))])
        let model = PublishedContentFeedViewModel(listing: provider)

        await model.load(query: try Self.query(), catalogRevision: 1)

        #expect(model.state == .loaded(feed))
        #expect(model.nextPageState == .idle)
    }

    @Test("empty first page publishes empty")
    func empty() async throws {
        let provider = QueuePublishedContentListing([
            .success(Self.response(items: [], nextCursor: nil)),
        ])
        let model = PublishedContentFeedViewModel(listing: provider)

        await model.load(query: try Self.query(), catalogRevision: 1)

        #expect(model.state == .empty)
    }

    @Test("initial offline has no invented content")
    func initialOffline() async throws {
        let provider = QueuePublishedContentListing([.failure(.offline)])
        let model = PublishedContentFeedViewModel(listing: provider)

        await model.load(query: try Self.query(), catalogRevision: 1)

        #expect(model.state == .offline(previousValue: nil))
    }

    @Test("initial service failure has no invented content")
    func initialFailure() async throws {
        let provider = QueuePublishedContentListing([.failure(.serviceUnavailable)])
        let model = PublishedContentFeedViewModel(listing: provider)

        await model.load(query: try Self.query(), catalogRevision: 1)

        #expect(model.state == .failed(
            previousValue: nil,
            error: .serviceUnavailable
        ))
    }

    @Test("unavailable listing publishes unavailable")
    func unavailable() async throws {
        let provider = QueuePublishedContentListing([.failure(.operationUnavailable)])
        let model = PublishedContentFeedViewModel(listing: provider)

        await model.load(query: try Self.query(), catalogRevision: 1)

        #expect(model.state == .unavailable)
    }

    @Test("first-page retries preserve stale rows for offline and service errors")
    func staleFirstPageErrors() async throws {
        for error in [BodyFlowCapabilityError.offline, .serviceUnavailable] {
            let original = Self.feed(items: [Self.item(1)], nextCursor: "cursor-1")
            let stale = Self.feed(items: [Self.item(1)], nextCursor: nil)
            let provider = QueuePublishedContentListing([
                .success(Self.response(original)),
                .failure(error),
            ])
            let model = PublishedContentFeedViewModel(listing: provider)

            await model.load(query: try Self.query(), catalogRevision: 2)
            await model.retryFirstPage()

            switch error {
            case .offline:
                #expect(model.state == .offline(previousValue: stale))
            default:
                #expect(model.state == .failed(
                    previousValue: stale,
                    error: .serviceUnavailable
                ))
            }
        }
    }

    @Test("stale first-page failure blocks old cursor until successful retry")
    func staleFirstPageFailureBlocksOldCursorUntilSuccessfulRetry() async throws {
        let initial = Self.feed(items: [Self.item(1)], nextCursor: "old.cursor")
        let replacement = Self.feed(items: [Self.item(2)], nextCursor: "new.cursor")
        let next = Self.feed(items: [Self.item(3)], nextCursor: nil)
        let provider = QueuePublishedContentListing([
            .success(Self.response(initial)),
            .failure(.offline),
            .success(Self.response(replacement)),
            .success(Self.response(next)),
        ])
        let model = PublishedContentFeedViewModel(listing: provider)

        await model.load(query: try Self.query(), catalogRevision: 1)
        await model.retryFirstPage()

        #expect(model.state == .offline(previousValue: Self.feed(
            items: [Self.item(1)],
            nextCursor: nil
        )))

        await model.loadNextPage()
        #expect(await provider.recordedQueries().count == 2)
        guard await provider.recordedQueries().count == 2 else { return }

        await model.retryFirstPage()
        await model.loadNextPage()

        #expect(await provider.recordedQueries().map(\.cursor) == [
            nil,
            nil,
            nil,
            "new.cursor",
        ])
        #expect(model.state == .loaded(Self.feed(
            items: [Self.item(2), Self.item(3)],
            nextCursor: nil
        )))
    }

    @Test("library saved and category dimensions use the exact initial limit")
    func queryDimensions() async throws {
        let queries = [
            try Self.query(surface: .library, category: nil),
            try Self.query(surface: .saved, category: nil),
            try Self.query(surface: .library, category: .nutrition),
            try Self.query(surface: .library, category: .sleep),
        ]
        let provider = QueuePublishedContentListing(
            queries.map { _ in .success(Self.response(items: [Self.item(1)])) }
        )
        let model = PublishedContentFeedViewModel(listing: provider)

        for (revision, query) in queries.enumerated() {
            await model.load(query: query, catalogRevision: revision)
        }

        #expect(await provider.recordedQueries() == queries)
        #expect(queries.allSatisfy { $0.limit == 20 && $0.cursor == nil })
    }

    @Test("next page preserves every query dimension and opaque cursor")
    func opaquePagination() async throws {
        let cursor = "  opaque/+== next_🙂  "
        let first = Self.feed(items: [Self.item(1)], nextCursor: cursor)
        let second = Self.feed(items: [Self.item(2)], nextCursor: "following")
        let provider = QueuePublishedContentListing([
            .success(Self.response(first)),
            .success(Self.response(second)),
        ])
        let model = PublishedContentFeedViewModel(listing: provider)
        let initial = try Self.query(surface: .library, category: .sleep)
        let expectedNext = try ContentFeedQuery(
            surface: .library,
            category: .sleep,
            limit: 20,
            cursor: cursor
        )

        await model.load(query: initial, catalogRevision: 7)
        await model.loadNextPage()

        #expect(await provider.recordedQueries() == [initial, expectedNext])
        #expect(model.state == .loaded(Self.feed(
            items: [Self.item(1), Self.item(2)],
            nextCursor: "following"
        )))
        #expect(model.nextPageState == .idle)
    }

    @Test("nil next cursor disables load more")
    func nilNextCursor() async throws {
        let first = Self.feed(items: [Self.item(1)], nextCursor: nil)
        let provider = QueuePublishedContentListing([.success(Self.response(first))])
        let model = PublishedContentFeedViewModel(listing: provider)

        await model.load(query: try Self.query(), catalogRevision: 1)
        await model.loadNextPage()
        await model.retryNextPage()

        #expect(await provider.recordedQueries().count == 1)
        #expect(model.state == .loaded(first))
    }

    @Test("next-page errors preserve rows and retry the immutable attempt")
    func nextPageRetry() async throws {
        for error in [BodyFlowCapabilityError.offline, .serviceUnavailable] {
            let first = Self.feed(items: [Self.item(1)], nextCursor: "opaque.retry")
            let next = Self.feed(items: [Self.item(2)], nextCursor: nil)
            let provider = QueuePublishedContentListing([
                .success(Self.response(first)),
                .failure(error),
                .success(Self.response(next)),
            ])
            let model = PublishedContentFeedViewModel(listing: provider)
            let initial = try Self.query(surface: .saved, category: .nutrition)
            let attempt = try ContentFeedQuery(
                surface: .saved,
                category: .nutrition,
                limit: 20,
                cursor: "opaque.retry"
            )

            await model.load(query: initial, catalogRevision: 3)
            await model.loadNextPage()

            #expect(model.state == .loaded(first))
            #expect(model.nextPageState == .failed(error))

            await model.retryNextPage()

            #expect(await provider.recordedQueries() == [initial, attempt, attempt])
            #expect(model.state == .loaded(Self.feed(
                items: [Self.item(1), Self.item(2)],
                nextCursor: nil
            )))
            #expect(model.nextPageState == .idle)
        }
    }

    @Test("invalid cursor clears only paging and allows only nil-cursor reload")
    func invalidCursorRecovery() async throws {
        let first = Self.feed(items: [Self.item(1)], nextCursor: "invalid.opaque")
        let cleared = Self.feed(items: [Self.item(1)], nextCursor: nil)
        let replacement = Self.feed(items: [Self.item(2)], nextCursor: nil)
        let provider = QueuePublishedContentListing([
            .success(Self.response(first)),
            .failure(.invalidContentCursor),
            .success(Self.response(replacement)),
        ])
        let model = PublishedContentFeedViewModel(listing: provider)
        let initial = try Self.query(surface: .library, category: .sleep)
        let invalidAttempt = try ContentFeedQuery(
            surface: .library,
            category: .sleep,
            limit: 20,
            cursor: "invalid.opaque"
        )

        await model.load(query: initial, catalogRevision: 9)
        await model.loadNextPage()

        #expect(model.state == .loaded(cleared))
        #expect(model.nextPageState == .reloadFirstPageRequired)

        await model.loadNextPage()
        await model.retryNextPage()
        await model.retryFirstPage()
        #expect(await provider.recordedQueries() == [initial, invalidAttempt])
        #expect(model.state == .loaded(cleared))

        await model.reloadFirstPageAfterInvalidCursor()

        #expect(await provider.recordedQueries() == [initial, invalidAttempt, initial])
        #expect(model.state == .loaded(replacement))
        #expect(model.nextPageState == .idle)
    }

    @Test("malformed first-page next cursor is cleared before paging recovery")
    func malformedFirstPageCursor() async throws {
        let malformedCursor = try Self.taskOneRejectedCursorFixture()
        let item = Self.item(1)
        let visible = Self.feed(items: [item], nextCursor: nil)
        let replacement = Self.feed(items: [Self.item(10)], nextCursor: nil)
        let provider = QueuePublishedContentListing([
            .success(Self.response(items: [item], nextCursor: malformedCursor)),
            .success(Self.response(replacement)),
        ])
        let model = PublishedContentFeedViewModel(listing: provider)
        let initial = try Self.query(surface: .library, category: .sleep)

        await model.load(query: initial, catalogRevision: 1)

        #expect(model.state == .loaded(visible))
        #expect(model.nextPageState == .reloadFirstPageRequired)

        await model.loadNextPage()
        await model.retryNextPage()
        await model.retryFirstPage()
        #expect(await provider.recordedQueries() == [initial])
        #expect(model.state == .loaded(visible))

        await model.reloadFirstPageAfterInvalidCursor()

        #expect(await provider.recordedQueries() == [initial, initial])
        #expect(model.state == .loaded(replacement))
        #expect(model.nextPageState == .idle)
    }

    @Test("malformed appended next cursor keeps appended rows and enters recovery")
    func malformedAppendedCursor() async throws {
        let malformedCursor = try Self.taskOneRejectedCursorFixture()
        let cursor = "valid.next"
        let first = Self.feed(items: [Self.item(1)], nextCursor: cursor)
        let appended = Self.feed(
            items: [Self.item(1), Self.item(2)],
            nextCursor: nil
        )
        let replacement = Self.feed(items: [Self.item(3)], nextCursor: nil)
        let provider = QueuePublishedContentListing([
            .success(Self.response(first)),
            .success(Self.response(items: [Self.item(2)], nextCursor: malformedCursor)),
            .success(Self.response(replacement)),
        ])
        let model = PublishedContentFeedViewModel(listing: provider)
        let initial = try Self.query(surface: .saved, category: .nutrition)
        let next = try ContentFeedQuery(
            surface: .saved,
            category: .nutrition,
            limit: 20,
            cursor: cursor
        )

        await model.load(query: initial, catalogRevision: 20)
        await model.loadNextPage()

        #expect(model.state == .loaded(appended))
        #expect(model.nextPageState == .reloadFirstPageRequired)

        await model.loadNextPage()
        await model.retryNextPage()
        await model.retryFirstPage()
        #expect(await provider.recordedQueries() == [initial, next])
        #expect(model.state == .loaded(appended))

        await model.reloadFirstPageAfterInvalidCursor()

        #expect(await provider.recordedQueries() == [initial, next, initial])
        #expect(model.state == .loaded(replacement))
        #expect(model.nextPageState == .idle)
    }

    @Test("cancelled invalid-cursor reload keeps recovery available")
    func cancelledInvalidCursorReload() async throws {
        for lateOutcome in LatePageOutcome.allCases {
            let provider = ControlledPublishedContentListing()
            let model = PublishedContentFeedViewModel(listing: provider)
            let query = try Self.query(surface: .saved, category: .sleep)
            let first = Self.feed(items: [Self.item(1)], nextCursor: "rejected.next")
            let cleared = Self.feed(items: [Self.item(1)], nextCursor: nil)
            let replacement = Self.feed(items: [Self.item(2)], nextCursor: nil)

            let firstLoad = Task { await model.load(query: query, catalogRevision: 8) }
            await provider.waitForCallCount(1)
            await provider.succeed(call: 1, with: Self.response(first))
            await firstLoad.value

            let rejectedPage = Task { await model.loadNextPage() }
            await provider.waitForCallCount(2)
            await provider.fail(call: 2, with: .invalidContentCursor)
            await rejectedPage.value
            #expect(model.state == .loaded(cleared))
            #expect(model.nextPageState == .reloadFirstPageRequired)

            let cancelledReload = Task {
                await model.reloadFirstPageAfterInvalidCursor()
            }
            await provider.waitForCallCount(3)
            cancelledReload.cancel()
            switch lateOutcome {
            case .value:
                await provider.succeed(call: 3, with: Self.response(replacement))
            case .error:
                await provider.fail(call: 3, with: .offline)
            }
            await cancelledReload.value

            #expect(model.state == .loaded(cleared))
            #expect(model.nextPageState == .reloadFirstPageRequired)
            guard model.nextPageState == .reloadFirstPageRequired else { continue }

            await provider.setImmediateResult(
                call: 4,
                result: .success(Self.response(replacement))
            )
            await model.loadNextPage()
            await model.retryNextPage()
            await model.retryFirstPage()
            #expect(await provider.observedCallCount() == 3)

            await model.reloadFirstPageAfterInvalidCursor()

            let nilCursorReload = try ContentFeedQuery(
                surface: .saved,
                category: .sleep,
                limit: 20,
                cursor: nil
            )
            #expect(await provider.recordedQueries() == [
                query,
                try ContentFeedQuery(
                    surface: .saved,
                    category: .sleep,
                    limit: 20,
                    cursor: "rejected.next"
                ),
                nilCursorReload,
                nilCursorReload,
            ])
            #expect(model.state == .loaded(replacement))
            #expect(model.nextPageState == .idle)
        }
    }

    @Test("direct next-page cancellation restores idle and permits the exact cursor")
    func directNextPageCancellation() async throws {
        for lateOutcome in LatePageOutcome.allCases {
            let provider = ControlledPublishedContentListing()
            let model = PublishedContentFeedViewModel(listing: provider)
            let first = Self.feed(items: [Self.item(1)], nextCursor: "cancel.next")
            let next = Self.feed(items: [Self.item(2)], nextCursor: nil)
            let query = try Self.query()

            let firstLoad = Task { await model.load(query: query, catalogRevision: 1) }
            await provider.waitForCallCount(1)
            await provider.succeed(call: 1, with: Self.response(first))
            await firstLoad.value

            let cancelledPage = Task { await model.loadNextPage() }
            await provider.waitForCallCount(2)
            cancelledPage.cancel()
            switch lateOutcome {
            case .value:
                await provider.succeed(call: 2, with: Self.response(next))
            case .error:
                await provider.fail(call: 2, with: .offline)
            }
            await cancelledPage.value

            #expect(model.state == .loaded(first))
            #expect(model.nextPageState == .idle)
            guard model.nextPageState == .idle else { continue }

            let replacementPage = Task { await model.loadNextPage() }
            await provider.waitForCallCount(3)
            await provider.succeed(call: 3, with: Self.response(next))
            await replacementPage.value

            #expect(await provider.recordedQueries().map(\.cursor) == [
                nil,
                "cancel.next",
                "cancel.next",
            ])
            #expect(model.state == .loaded(Self.feed(
                items: [Self.item(1), Self.item(2)],
                nextCursor: nil
            )))
        }
    }

    @Test("direct retry cancellation restores failure and permits the exact attempt")
    func directNextPageRetryCancellation() async throws {
        for lateOutcome in LatePageOutcome.allCases {
            let provider = ControlledPublishedContentListing()
            let model = PublishedContentFeedViewModel(listing: provider)
            let first = Self.feed(items: [Self.item(1)], nextCursor: "cancel.retry")
            let next = Self.feed(items: [Self.item(2)], nextCursor: nil)
            let query = try Self.query()

            let firstLoad = Task { await model.load(query: query, catalogRevision: 1) }
            await provider.waitForCallCount(1)
            await provider.succeed(call: 1, with: Self.response(first))
            await firstLoad.value

            let failedPage = Task { await model.loadNextPage() }
            await provider.waitForCallCount(2)
            await provider.fail(call: 2, with: .serviceUnavailable)
            await failedPage.value
            #expect(model.nextPageState == .failed(.serviceUnavailable))

            let cancelledRetry = Task { await model.retryNextPage() }
            await provider.waitForCallCount(3)
            cancelledRetry.cancel()
            switch lateOutcome {
            case .value:
                await provider.succeed(call: 3, with: Self.response(next))
            case .error:
                await provider.fail(call: 3, with: .offline)
            }
            await cancelledRetry.value

            #expect(model.state == .loaded(first))
            #expect(model.nextPageState == .failed(.serviceUnavailable))
            guard model.nextPageState == .failed(.serviceUnavailable) else { continue }

            let replacementRetry = Task { await model.retryNextPage() }
            await provider.waitForCallCount(4)
            await provider.succeed(call: 4, with: Self.response(next))
            await replacementRetry.value

            #expect(await provider.recordedQueries().map(\.cursor) == [
                nil,
                "cancel.retry",
                "cancel.retry",
                "cancel.retry",
            ])
            #expect(model.state == .loaded(Self.feed(
                items: [Self.item(1), Self.item(2)],
                nextCursor: nil
            )))
        }
    }

    @Test("active first-page retry blocks paging and owns stale failure")
    func firstPageRetryBlocksPaging() async throws {
        let provider = ControlledPublishedContentListing()
        let model = PublishedContentFeedViewModel(listing: provider)
        let query = try Self.query()
        let first = Self.feed(items: [Self.item(1)], nextCursor: "stale.next")
        let stale = Self.feed(items: [Self.item(1)], nextCursor: nil)
        let forbidden = Self.feed(items: [Self.item(2)], nextCursor: nil)

        let firstLoad = Task { await model.load(query: query, catalogRevision: 1) }
        await provider.waitForCallCount(1)
        await provider.succeed(call: 1, with: Self.response(first))
        await firstLoad.value

        let oldPage = Task { await model.loadNextPage() }
        await provider.waitForCallCount(2)

        let firstPageRetry = Task { await model.retryFirstPage() }
        await provider.waitForCallCount(3)
        await provider.setImmediateResult(call: 4, result: .success(Self.response(forbidden)))

        await model.loadNextPage()
        #expect(await provider.observedCallCount() == 3)

        await provider.fail(call: 3, with: .offline)
        await firstPageRetry.value
        await provider.succeed(call: 2, with: Self.response(forbidden))
        await oldPage.value

        #expect(model.state == .offline(previousValue: stale))
        #expect(model.nextPageState == .idle)
        #expect(await provider.observedCallCount() == 3)
    }

    @Test("revision-only supersession suppresses late next-page value and error")
    func revisionOnlyNextPageSupersession() async throws {
        for lateOutcome in LatePageOutcome.allCases {
            let provider = ControlledPublishedContentListing()
            let model = PublishedContentFeedViewModel(listing: provider)
            let query = try Self.query(surface: .library, category: .sleep)
            let first = Self.feed(items: [Self.item(1)], nextCursor: "shared.next")
            let fresh = Self.feed(items: [Self.item(3)], nextCursor: "shared.next")

            let firstLoad = Task { await model.load(query: query, catalogRevision: 1) }
            await provider.waitForCallCount(1)
            await provider.succeed(call: 1, with: Self.response(first))
            await firstLoad.value

            let oldPage = Task { await model.loadNextPage() }
            await provider.waitForCallCount(2)
            let revisionLoad = Task { await model.load(query: query, catalogRevision: 2) }
            await provider.waitForCallCount(3)
            await provider.succeed(call: 3, with: Self.response(fresh))
            await revisionLoad.value

            switch lateOutcome {
            case .value:
                await provider.succeed(
                    call: 2,
                    with: Self.response(items: [Self.item(2)])
                )
            case .error:
                await provider.fail(call: 2, with: .serviceUnavailable)
            }
            await oldPage.value

            #expect(await provider.cancellationObserved(call: 2) == true)
            #expect(model.state == .loaded(fresh))
            #expect(model.nextPageState == .idle)
        }
    }

    @Test("new query suppresses an older late first-page value")
    func querySupersessionSuppressesLateValue() async throws {
        let provider = ControlledPublishedContentListing()
        let model = PublishedContentFeedViewModel(listing: provider)
        let oldQuery = try Self.query(surface: .library, category: nil)
        let newQuery = try Self.query(surface: .saved, category: .sleep)
        let fresh = Self.feed(items: [Self.item(2)], nextCursor: nil)

        let oldLoad = Task { await model.load(query: oldQuery, catalogRevision: 4) }
        await provider.waitForCallCount(1)
        let newLoad = Task { await model.load(query: newQuery, catalogRevision: 4) }
        await provider.waitForCallCount(2)

        await provider.succeed(call: 2, with: Self.response(fresh))
        await newLoad.value
        await provider.succeed(
            call: 1,
            with: Self.response(items: [Self.item(1)], nextCursor: "late")
        )
        await oldLoad.value

        #expect(await provider.cancellationObserved(call: 1) == true)
        #expect(model.state == .loaded(fresh))
    }

    @Test("new revision suppresses an older late first-page error")
    func revisionSupersessionSuppressesLateError() async throws {
        let provider = ControlledPublishedContentListing()
        let model = PublishedContentFeedViewModel(listing: provider)
        let query = try Self.query()
        let fresh = Self.feed(items: [Self.item(2)], nextCursor: nil)

        let oldLoad = Task { await model.load(query: query, catalogRevision: 4) }
        await provider.waitForCallCount(1)
        let newLoad = Task { await model.load(query: query, catalogRevision: 5) }
        await provider.waitForCallCount(2)

        await provider.succeed(call: 2, with: Self.response(fresh))
        await newLoad.value
        await provider.fail(call: 1, with: .offline)
        await oldLoad.value

        #expect(await provider.cancellationObserved(call: 1) == true)
        #expect(model.state == .loaded(fresh))
    }

    @Test("new full identity cancels and suppresses late next-page value and error")
    func nextPageSupersession() async throws {
        for lateOutcome in LatePageOutcome.allCases {
            let provider = ControlledPublishedContentListing()
            let model = PublishedContentFeedViewModel(listing: provider)
            let oldQuery = try Self.query(surface: .library, category: nil)
            let newQuery = try Self.query(surface: .saved, category: nil)
            let oldFirst = Self.feed(items: [Self.item(1)], nextCursor: "old.next")
            let fresh = Self.feed(items: [Self.item(3)], nextCursor: nil)

            let firstLoad = Task { await model.load(query: oldQuery, catalogRevision: 1) }
            await provider.waitForCallCount(1)
            await provider.succeed(call: 1, with: Self.response(oldFirst))
            await firstLoad.value

            let pageLoad = Task { await model.loadNextPage() }
            await provider.waitForCallCount(2)
            let replacement = Task { await model.load(query: newQuery, catalogRevision: 2) }
            await provider.waitForCallCount(3)
            await provider.succeed(call: 3, with: Self.response(fresh))
            await replacement.value

            switch lateOutcome {
            case .value:
                await provider.succeed(
                    call: 2,
                    with: Self.response(items: [Self.item(2)])
                )
            case .error:
                await provider.fail(call: 2, with: .serviceUnavailable)
            }
            await pageLoad.value

            #expect(await provider.cancellationObserved(call: 2) == true)
            #expect(model.state == .loaded(fresh))
            #expect(model.nextPageState == .idle)
        }
    }

    @Test("duplicate publication IDs reject first and next pages")
    func rejectsDuplicatePublicationIDs() async throws {
        let duplicated = Self.item(1)
        let initialProvider = QueuePublishedContentListing([
            .success(Self.response(items: [duplicated, duplicated])),
        ])
        let initialModel = PublishedContentFeedViewModel(listing: initialProvider)

        await initialModel.load(query: try Self.query(), catalogRevision: 1)

        #expect(initialModel.state == .failed(
            previousValue: nil,
            error: .invalidContentContract
        ))

        let first = Self.feed(items: [duplicated], nextCursor: "next")
        let nextProvider = QueuePublishedContentListing([
            .success(Self.response(first)),
            .success(Self.response(items: [duplicated])),
        ])
        let nextModel = PublishedContentFeedViewModel(listing: nextProvider)

        await nextModel.load(query: try Self.query(), catalogRevision: 1)
        await nextModel.loadNextPage()

        #expect(nextModel.state == .loaded(first))
        #expect(nextModel.nextPageState == .failed(.invalidContentContract))
    }

    @Test("contract validation rejects malformed first and next pages")
    func validatesEveryPage() async throws {
        let invalid = Self.item(1, title: "no")
        let initialProvider = QueuePublishedContentListing([
            .success(Self.response(items: [invalid])),
        ])
        let initialModel = PublishedContentFeedViewModel(listing: initialProvider)

        await initialModel.load(query: try Self.query(), catalogRevision: 1)

        #expect(initialModel.state == .failed(
            previousValue: nil,
            error: .invalidContentContract
        ))

        let first = Self.feed(items: [Self.item(1)], nextCursor: "next")
        let nextProvider = QueuePublishedContentListing([
            .success(Self.response(first)),
            .success(Self.response(items: [invalid])),
        ])
        let nextModel = PublishedContentFeedViewModel(listing: nextProvider)

        await nextModel.load(query: try Self.query(), catalogRevision: 1)
        await nextModel.loadNextPage()

        #expect(nextModel.state == .loaded(first))
        #expect(nextModel.nextPageState == .failed(.invalidContentContract))
    }

    @Test("a completed query and catalog revision load only once")
    func completedKeyLoadsOnlyOnce() async throws {
        let response = Self.response(items: [Self.item(1)])
        let provider = QueuePublishedContentListing([.success(response)])
        let model = PublishedContentFeedViewModel(listing: provider)
        let query = try Self.query(surface: .library, category: .nutrition)

        await model.load(query: query, catalogRevision: 11)
        await model.load(query: query, catalogRevision: 11)

        #expect(await provider.recordedQueries() == [query])
        #expect(model.state == .loaded(response.data))
    }
}

private extension PublishedContentFeedViewModelTests {
    enum LatePageOutcome: CaseIterable {
        case value
        case error
    }

    static func query(
        surface: ContentSurface = .library,
        category: ContentCategory? = nil
    ) throws -> ContentFeedQuery {
        try ContentFeedQuery(
            surface: surface,
            category: category,
            limit: 20,
            cursor: nil
        )
    }

    static func response(
        items: [PublishedContentSummary],
        nextCursor: String? = nil
    ) -> PublishedContentFeedResponse {
        response(feed(items: items, nextCursor: nextCursor))
    }

    static func response(
        _ feed: PublishedContentFeed
    ) -> PublishedContentFeedResponse {
        PublishedContentFeedResponse(
            data: feed,
            meta: MobileResponseMetadata(
                apiVersion: "1",
                requestID: "90000000-0000-4000-8000-000000000015"
            )
        )
    }

    static func feed(
        items: [PublishedContentSummary],
        nextCursor: String?
    ) -> PublishedContentFeed {
        PublishedContentFeed(items: items, nextCursor: nextCursor)
    }

    static func item(
        _ number: Int,
        title: String = "A complete article title"
    ) -> PublishedContentSummary {
        PublishedContentSummary(
            publicationID: String(
                format: "00000000-0000-4000-8000-%012d",
                number
            ),
            slug: "article-\(number)",
            locale: .ptBR,
            title: title,
            excerpt: "A complete educational excerpt used by the deterministic feed tests.",
            category: .sleep,
            tags: ["sleep"],
            readingTimeMinutes: 3,
            publishAt: APITimestamp(
                value: Date(timeIntervalSince1970: 1_784_070_900 + Double(number))
            ),
            featuredToday: false,
            version: number,
            saved: false,
            completed: false,
            cover: nil
        )
    }

    static func taskOneRejectedCursorFixture() throws -> String {
        let cursor = String(repeating: "a", count: 513)
        do {
            _ = try ContentFeedQuery(
                surface: .library,
                category: nil,
                limit: 20,
                cursor: cursor
            )
        } catch BodyFlowCapabilityError.invalidContentCursor {
            return cursor
        }
        throw PublishedContentFeedFixtureError.expectedRejectedCursor
    }
}

private enum PublishedContentFeedFixtureError: Error {
    case expectedRejectedCursor
}

private actor QueuePublishedContentListing: PublishedContentListing {
    private var results: [Result<PublishedContentFeedResponse, BodyFlowCapabilityError>]
    private var queries: [ContentFeedQuery] = []

    init(_ results: [Result<PublishedContentFeedResponse, BodyFlowCapabilityError>]) {
        self.results = results
    }

    func content(_ query: ContentFeedQuery) async throws -> PublishedContentFeedResponse {
        queries.append(query)
        guard !results.isEmpty else {
            throw BodyFlowCapabilityError.serviceUnavailable
        }
        return try results.removeFirst().get()
    }

    func recordedQueries() -> [ContentFeedQuery] {
        queries
    }
}

private actor ControlledPublishedContentListing: PublishedContentListing {
    private var callCount = 0
    private var queries: [ContentFeedQuery] = []
    private var continuations: [
        Int: CheckedContinuation<PublishedContentFeedResponse, any Error>
    ] = [:]
    private var callCountWaiters: [
        Int: [CheckedContinuation<Void, Never>]
    ] = [:]
    private var cancellationObservations: [Int: Bool] = [:]
    private var immediateResults: [
        Int: Result<PublishedContentFeedResponse, BodyFlowCapabilityError>
    ] = [:]

    func content(_ query: ContentFeedQuery) async throws -> PublishedContentFeedResponse {
        callCount += 1
        let call = callCount
        queries.append(query)
        resumeCallCountWaiters()
        defer {
            cancellationObservations[call] = Task.isCancelled
        }

        if let result = immediateResults.removeValue(forKey: call) {
            return try result.get()
        }

        return try await withCheckedThrowingContinuation { continuation in
            continuations[call] = continuation
        }
    }

    func waitForCallCount(_ expectedCount: Int) async {
        guard callCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            callCountWaiters[expectedCount, default: []].append(continuation)
        }
    }

    func recordedQueries() -> [ContentFeedQuery] {
        queries
    }

    func cancellationObserved(call: Int) -> Bool? {
        cancellationObservations[call]
    }

    func observedCallCount() -> Int {
        callCount
    }

    func setImmediateResult(
        call: Int,
        result: Result<PublishedContentFeedResponse, BodyFlowCapabilityError>
    ) {
        immediateResults[call] = result
    }

    func succeed(call: Int, with response: PublishedContentFeedResponse) {
        continuations.removeValue(forKey: call)?.resume(returning: response)
    }

    func fail(call: Int, with error: BodyFlowCapabilityError) {
        continuations.removeValue(forKey: call)?.resume(throwing: error)
    }

    private func resumeCallCountWaiters() {
        let readyCounts = callCountWaiters.keys.filter { $0 <= callCount }
        for count in readyCounts {
            let waiters = callCountWaiters.removeValue(forKey: count) ?? []
            for waiter in waiters {
                waiter.resume()
            }
        }
    }
}
