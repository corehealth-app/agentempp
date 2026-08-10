import Foundation
import Testing

@testable import BodyFlow

@Suite("Library presentation")
struct LibraryPresentationTests {
    @Test("library description is concise and pinned in pt-BR")
    func libraryDescription() {
        #expect(LibraryCopy.description ==
            "Explore conteúdos educativos publicados para apoiar sua jornada.")
    }

    @Test("all fixed categories have localized labels in contract order")
    func localizedCategoryLabels() {
        #expect(ContentCategory.allCases == [
            .weightLoss,
            .hypertrophy,
            .nutrition,
            .training,
            .neuroscience,
            .habitFormation,
            .cardiovascularHealth,
            .hydration,
            .supplementation,
            .sleep,
            .usingBodyFlow,
        ])
        #expect(ContentCategory.allCases.map(\.libraryDisplayName) == [
            "Emagrecimento",
            "Hipertrofia",
            "Nutrição",
            "Treino",
            "Neurociência",
            "Formação de hábitos",
            "Saúde cardiovascular",
            "Hidratação",
            "Suplementação",
            "Sono",
            "Uso do BodyFlow",
        ])
    }

    @Test("selection labels and surfaces stay aligned")
    func selectionPresentation() {
        #expect(LibrarySelection.all.title == "Todos")
        #expect(LibrarySelection.saved.title == "Salvos")
        #expect(LibrarySelection.all.accessibilityIdentifier == "library.selection.all")
        #expect(LibrarySelection.saved.accessibilityIdentifier == "library.selection.saved")
        #expect(LibrarySelection.all.contentSurface == .library)
        #expect(LibrarySelection.saved.contentSurface == .saved)
    }

    @Test("empty messages are exact and category takes precedence")
    func exactEmptyMessages() {
        #expect(LibraryEmptyMessage.message(
            selection: .all,
            category: nil
        ) == "Nenhum conteúdo publicado está disponível para você agora.")
        #expect(LibraryEmptyMessage.message(
            selection: .saved,
            category: nil
        ) == "Você ainda não tem conteúdos salvos disponíveis.")
        #expect(LibraryEmptyMessage.message(
            selection: .all,
            category: .sleep
        ) == "Nenhum conteúdo disponível nesta categoria.")
        #expect(LibraryEmptyMessage.message(
            selection: .saved,
            category: .nutrition
        ) == "Nenhum conteúdo disponível nesta categoria.")
    }

    @Test("cards preserve server order and approved summary fields")
    func cardsPreserveServerOrder() {
        let summaries = [
            Self.summary(3, category: .sleep),
            Self.summary(1, category: .nutrition),
            Self.summary(2, category: .training),
        ]
        let presentation = LibraryPresentation(feed: PublishedContentFeed(
            items: summaries,
            nextCursor: "opaque / cursor"
        ))

        #expect(presentation.cards.map(\.publicationID) == summaries.map(\.publicationID))
        #expect(presentation.cards.map(\.title) == summaries.map(\.title))
        #expect(presentation.cards.map(\.excerpt) == summaries.map(\.excerpt))
        #expect(presentation.nextCursor == "opaque / cursor")
    }

    @Test("card presentation stores only approved display fields and identity")
    func cardsUseOnlyApprovedContractFields() {
        let summary = Self.summary(
            7,
            category: .habitFormation,
            saved: true,
            completed: true,
            includesCover: true
        )
        let card = LibraryCardPresentation(summary: summary)

        #expect(Set(Mirror(reflecting: card).children.compactMap(\.label)) == [
            "publicationID",
            "cover",
            "title",
            "excerpt",
            "categoryLabel",
            "readingTimeLabel",
            "saved",
            "completed",
        ])
        #expect(card.publicationID == summary.publicationID)
        #expect(card.cover == summary.cover)
        #expect(card.title == summary.title)
        #expect(card.excerpt == summary.excerpt)
        #expect(card.categoryLabel == "Formação de hábitos")
        #expect(card.readingTimeLabel == "7 min de leitura")
        #expect(card.saved)
        #expect(card.completed)
        #expect(card.accessibilityIdentifier == "library.card.\(summary.publicationID)")
    }

    @Test("card route contains only publication identity and library origin")
    func cardRouteCarriesNoVersionOrSnapshot() throws {
        let summary = Self.summary(9, category: .hydration)
        let route = LibraryCardPresentation(summary: summary).route

        guard case let .detail(publicationID, origin) = route else {
            Issue.record("Expected a typed content detail route")
            return
        }

        #expect(publicationID == summary.publicationID)
        #expect(origin == .library)
        let payload = try #require(Mirror(reflecting: route).children.first?.value)
        #expect(Mirror(reflecting: payload).children.map(\.label) == [
            "publicationID", "origin",
        ])
    }

    @Test("paging presentation keeps next-page retry separate")
    func separateNextPageRetry() {
        let feedWithCursor = PublishedContentFeed(
            items: [Self.summary(1)],
            nextCursor: "opaque.next"
        )
        let feedWithoutCursor = PublishedContentFeed(
            items: [Self.summary(1)],
            nextCursor: nil
        )

        #expect(LibraryPagingPresentation(
            feed: feedWithCursor,
            state: .idle
        ).action == .loadMore)
        #expect(LibraryPagingPresentation(
            feed: feedWithoutCursor,
            state: .idle
        ).action == .none)
        #expect(LibraryPagingPresentation(
            feed: feedWithCursor,
            state: .loading
        ).action == .none)
        #expect(LibraryPagingPresentation(
            feed: feedWithCursor,
            state: .failed(.offline)
        ).action == .retryNextPage)
        #expect(LibraryPagingPresentation(
            feed: feedWithCursor,
            state: .reloadFirstPageRequired
        ).action == .reloadFirstPage)
        #expect(LibraryPagingPresentation(
            feed: feedWithCursor,
            state: .failed(.offline)
        ).accessibilityIdentifier == "state.retry-next-page")
    }

    @Test("the exact query and catalog revision form the task key")
    func taskKeyOwnsExactQueryAndRevision() throws {
        let query = try ContentFeedQuery(
            surface: .saved,
            category: .neuroscience,
            limit: 20,
            cursor: nil
        )

        let key = FeedLoadKey(query: query, catalogRevision: 13)

        #expect(key.query == query)
        #expect(key.catalogRevision == 13)
    }

    @Test("first completed load focuses the results heading")
    func initialLoadFocus() {
        #expect(LibraryAccessibilityFocusReducer.target(
            after: .initialLoadCompleted
        ) == .resultsHeading)
    }

    @Test("filter change focuses the updated results heading")
    func filterChangeFocus() {
        #expect(LibraryAccessibilityFocusReducer.target(
            after: .filterLoadCompleted
        ) == .resultsHeading)
    }

    @Test("first-page retry focuses its result or error summary")
    func firstPageRetryFocus() {
        #expect(LibraryAccessibilityFocusReducer.target(
            after: .firstPageRetryCompleted
        ) == .firstPageResultSummary)
    }

    @Test("invalid cursor focuses only the first-page reload action")
    func invalidCursorFocus() {
        #expect(LibraryAccessibilityFocusReducer.target(
            after: .invalidCursorDetected
        ) == .reloadFirstPageAction)
        #expect(LibraryAccessibilityFocusReducer.target(
            afterFirstPageEvent: .initialLoadCompleted,
            nextPageState: .reloadFirstPageRequired
        ) == .reloadFirstPageAction)
        #expect(LibraryAccessibilityFocusReducer.target(
            afterFirstPageEvent: .firstPageRetryCompleted,
            nextPageState: .reloadFirstPageRequired
        ) == .reloadFirstPageAction)
    }

    @Test("next-page failure focuses its bounded retry, never an old card")
    func nextPageFailureFocus() {
        #expect(LibraryAccessibilityFocusReducer.target(
            after: .nextPageFailed
        ) == .retryNextPageAction)
        let allEventTargets = LibraryAccessibilityFocusEvent.allCases.map {
            LibraryAccessibilityFocusReducer.target(after: $0)
        }
        #expect(Set(allEventTargets) == [
            .resultsHeading,
            .firstPageResultSummary,
            .reloadFirstPageAction,
            .retryNextPageAction,
        ])
    }

    @Test("visibility policy requests impressions only for actually visible cards")
    func visibleImpressionBoundary() {
        let summary = Self.summary(21)

        #expect(LibraryCardVisibilityPolicy.request(
            isVisible: false,
            publicationID: summary.publicationID,
            version: summary.version
        ) == nil)

        let request = LibraryCardVisibilityPolicy.request(
            isVisible: true,
            publicationID: summary.publicationID,
            version: summary.version
        )
        #expect(request?.publicationID == summary.publicationID)
        #expect(request?.version == summary.version)
    }

    @Test("focus targets map to distinct semantic elements")
    func distinctFocusSemantics() {
        #expect(LibraryAccessibilityFocusTarget.resultsHeading.semanticRole == .heading)
        #expect(LibraryAccessibilityFocusTarget.firstPageResultSummary.semanticRole == .summary)
        #expect(LibraryAccessibilityFocusTarget.reloadFirstPageAction.semanticRole == .action)
        #expect(LibraryAccessibilityFocusTarget.retryNextPageAction.semanticRole == .action)
        #expect(LibraryFirstPageSummaryPolicy.element(
            showsStaleDisclosure: false
        ) == .resultCount)
        #expect(LibraryFirstPageSummaryPolicy.element(
            showsStaleDisclosure: true
        ) == .staleDisclosure)
    }

    @Test("action ownership rejects superseded requests and changed task keys")
    func actionOwnership() throws {
        let originalKey = FeedLoadKey(
            query: try ContentFeedQuery(
                surface: .library,
                category: nil,
                limit: 20,
                cursor: nil
            ),
            catalogRevision: 4
        )
        let filteredKey = FeedLoadKey(
            query: try ContentFeedQuery(
                surface: .library,
                category: .sleep,
                limit: 20,
                cursor: nil
            ),
            catalogRevision: 4
        )
        let first = LibraryActionRequestPolicy.next(
            kind: .retryFirstPage,
            key: originalKey,
            previousSequence: 0
        )
        let replacement = LibraryActionRequestPolicy.next(
            kind: .loadNextPage,
            key: originalKey,
            previousSequence: first.sequence
        )

        #expect(first.sequence == 1)
        #expect(replacement.sequence == 2)
        #expect(LibraryActionRequestPolicy.owns(
            first,
            activeRequest: first,
            currentTaskKey: originalKey
        ))
        #expect(LibraryActionRequestPolicy.owns(
            first,
            activeRequest: replacement,
            currentTaskKey: originalKey
        ) == false)
        #expect(LibraryActionRequestPolicy.owns(
            first,
            activeRequest: first,
            currentTaskKey: filteredKey
        ) == false)
        #expect(LibraryFocusOwnership.canPublish(
            capturedKey: originalKey,
            currentKey: filteredKey
        ) == false)
    }

    @Test("invalid cursor exposes only working first-page reload recovery")
    func invalidCursorRecoveryPolicy() {
        #expect(LibraryRecoveryPolicy.action(
            allowsFirstPageRetry: true,
            nextPageState: .reloadFirstPageRequired
        ) == .reloadFirstPage)
        #expect(LibraryRecoveryPolicy.action(
            allowsFirstPageRetry: false,
            nextPageState: .reloadFirstPageRequired
        ) == .reloadFirstPage)
        #expect(LibraryRecoveryPolicy.action(
            allowsFirstPageRetry: true,
            nextPageState: .idle
        ) == .retryFirstPage)
        #expect(LibraryRecoveryPolicy.action(
            allowsFirstPageRetry: false,
            nextPageState: .idle
        ) == nil)
    }

    @Test("full-screen refresh is available only for recoverable read states")
    func fullScreenRefreshPolicy() {
        #expect(LibraryRefreshPolicy.allowsRefresh(for: .loading) == false)
        #expect(LibraryRefreshPolicy.allowsRefresh(for: .unavailable) == false)
        #expect(LibraryRefreshPolicy.allowsRefresh(for: .empty))
        #expect(LibraryRefreshPolicy.allowsRefresh(for: .offline))
        #expect(LibraryRefreshPolicy.allowsRefresh(for: .recoverableError))
    }
}

private extension LibraryPresentationTests {
    static func summary(
        _ number: Int,
        category: ContentCategory = .sleep,
        saved: Bool = false,
        completed: Bool = false,
        includesCover: Bool = false
    ) -> PublishedContentSummary {
        PublishedContentSummary(
            publicationID: String(
                format: "00000000-0000-4000-8000-%012d",
                number
            ),
            slug: "not-presented-\(number)",
            locale: .ptBR,
            title: "Título \(number)",
            excerpt: "Resumo educacional \(number)",
            category: category,
            tags: ["not-presented"],
            readingTimeMinutes: 7,
            publishAt: APITimestamp(
                value: Date(timeIntervalSince1970: 1_784_070_900 + Double(number))
            ),
            featuredToday: number.isMultiple(of: 2),
            version: 90 + number,
            saved: saved,
            completed: completed,
            cover: includesCover
                ? PublishedContentCover(
                    url: "/api/mobile/v1/content/covers/fixture-\(number)",
                    expiresAt: APITimestamp(
                        value: Date(timeIntervalSince1970: 1_784_157_300)
                    )
                )
                : nil
        )
    }
}
