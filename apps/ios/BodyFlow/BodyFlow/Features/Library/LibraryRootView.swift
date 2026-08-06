import Observation
import SwiftUI

enum LibraryCopy {
    static let description =
        "Explore conteúdos educativos publicados para apoiar sua jornada."
}

struct LibraryVisibilityRequest: Equatable, Hashable, Sendable {
    let publicationID: String
    let version: Int
}

enum LibraryCardVisibilityPolicy {
    static let threshold = 0.5

    static func request(
        isVisible: Bool,
        publicationID: String,
        version: Int
    ) -> LibraryVisibilityRequest? {
        guard isVisible else { return nil }
        return LibraryVisibilityRequest(
            publicationID: publicationID,
            version: version
        )
    }
}

enum LibraryAccessibilityFocusTarget: Hashable, Sendable, CaseIterable {
    case resultsHeading
    case firstPageResultSummary
    case reloadFirstPageAction
    case retryNextPageAction
}

enum LibraryAccessibilitySemanticRole: Equatable, Sendable {
    case heading
    case summary
    case action
}

extension LibraryAccessibilityFocusTarget {
    var semanticRole: LibraryAccessibilitySemanticRole {
        switch self {
        case .resultsHeading:
            .heading
        case .firstPageResultSummary:
            .summary
        case .reloadFirstPageAction, .retryNextPageAction:
            .action
        }
    }
}

enum LibraryFirstPageSummaryElement: Equatable, Sendable {
    case resultCount
    case staleDisclosure
}

enum LibraryFirstPageSummaryPolicy {
    static func element(
        showsStaleDisclosure: Bool
    ) -> LibraryFirstPageSummaryElement {
        showsStaleDisclosure ? .staleDisclosure : .resultCount
    }
}

enum LibraryActionKind: Equatable, Hashable, Sendable {
    case retryFirstPage
    case loadNextPage
    case retryNextPage
    case reloadFirstPage
}

struct LibraryActionRequest: Equatable, Hashable, Sendable {
    let kind: LibraryActionKind
    let key: FeedLoadKey
    let sequence: Int
}

enum LibraryActionRequestPolicy {
    static func next(
        kind: LibraryActionKind,
        key: FeedLoadKey,
        previousSequence: Int
    ) -> LibraryActionRequest {
        LibraryActionRequest(
            kind: kind,
            key: key,
            sequence: previousSequence + 1
        )
    }

    static func owns(
        _ request: LibraryActionRequest,
        activeRequest: LibraryActionRequest?,
        currentTaskKey: FeedLoadKey?
    ) -> Bool {
        activeRequest == request && currentTaskKey == request.key
    }
}

enum LibraryFocusOwnership {
    static func canPublish(
        capturedKey: FeedLoadKey?,
        currentKey: FeedLoadKey?
    ) -> Bool {
        guard let capturedKey else { return false }
        return capturedKey == currentKey
    }
}

enum LibraryRecoveryPolicy {
    static func action(
        allowsFirstPageRetry: Bool,
        nextPageState: PublishedContentNextPageState
    ) -> LibraryActionKind? {
        if nextPageState == .reloadFirstPageRequired {
            return .reloadFirstPage
        }
        return allowsFirstPageRetry ? .retryFirstPage : nil
    }
}

enum LibraryRefreshPolicy {
    static func allowsRefresh(for state: ScreenState) -> Bool {
        switch state {
        case .empty, .offline, .recoverableError:
            true
        case .loading, .unavailable:
            false
        }
    }
}

struct LibraryCoverLoadToken: Equatable, Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

struct LibraryCoverResponseCandidate: Equatable, Sendable {
    let token: LibraryCoverLoadToken
    let query: ContentFeedQuery
    let feed: PublishedContentFeed
}

enum LibraryCoverLoadContext {
    @TaskLocal static var token: LibraryCoverLoadToken?

    @MainActor
    static func withToken<Value: Sendable>(
        _ token: LibraryCoverLoadToken,
        operation: @MainActor () async throws -> Value
    ) async rethrows -> Value {
        try await $token.withValue(token, operation: operation)
    }
}

protocol LibraryCoverCandidateProviding: Sendable {
    func takeCandidate(
        for token: LibraryCoverLoadToken
    ) async -> LibraryCoverResponseCandidate?
}

actor LibraryCoverCapturingListing:
    PublishedContentListing,
    LibraryCoverCandidateProviding {
    private let listing: any PublishedContentListing
    private var candidates: [
        LibraryCoverLoadToken: LibraryCoverResponseCandidate
    ] = [:]

    init(listing: any PublishedContentListing) {
        self.listing = listing
    }

    func content(
        _ query: ContentFeedQuery
    ) async throws -> PublishedContentFeedResponse {
        guard let token = LibraryCoverLoadContext.token else {
            return try await listing.content(query)
        }

        let response = try await listing.content(query)
        try Task.checkCancellation()
        candidates[token] = LibraryCoverResponseCandidate(
            token: token,
            query: query,
            feed: response.data
        )
        return response
    }

    func takeCandidate(
        for token: LibraryCoverLoadToken
    ) -> LibraryCoverResponseCandidate? {
        candidates.removeValue(forKey: token)
    }
}

@MainActor
enum LibraryCoverLoadCoordinator {
    @discardableResult
    static func perform(
        requestedKey: FeedLoadKey,
        relay: LibraryCoverAuthorizationRelay,
        candidateProvider: any LibraryCoverCandidateProviding,
        allowsSupersession: Bool = true,
        reusesCompletedAuthorization: Bool = false,
        currentKey: @escaping @MainActor () -> FeedLoadKey?,
        ownsOperation: @escaping @MainActor () -> Bool = { true },
        state: @escaping @MainActor ()
            -> FeatureReadState<PublishedContentFeed>,
        recoveryOperation: (@MainActor () async -> Void)? = nil,
        operation: @escaping @MainActor () async -> Void
    ) async -> Bool {
        if reusesCompletedAuthorization {
            await relay.waitForPendingLoadToFinish()
        }

        guard !Task.isCancelled,
              currentKey() == requestedKey,
              ownsOperation(),
              allowsSupersession || !relay.hasPendingLoad else {
            return false
        }

        if reusesCompletedAuthorization,
           currentKey() == requestedKey,
           ownsOperation(),
           relay.canReuseCompletedAuthorization(
               for: requestedKey,
               state: state()
           ) {
            return true
        }

        let recoversExistingRequest = reusesCompletedAuthorization
            && relay.requiresFirstPageRecovery(for: requestedKey)
        let token = relay.begin(requestedKey: requestedKey)
        await LibraryCoverLoadContext.withToken(token) {
            if recoversExistingRequest, let recoveryOperation {
                await recoveryOperation()
            } else {
                await operation()
            }
        }

        guard let candidate = await candidateProvider.takeCandidate(
            for: token
        ) else {
            relay.discard(token: token)
            return false
        }

        return relay.commit(
            candidate: candidate,
            capturedKey: requestedKey,
            currentKey: currentKey(),
            state: state(),
            isCancelled: Task.isCancelled || !ownsOperation()
        )
    }
}

@MainActor
enum LibraryCoverFirstPageRecovery {
    static func perform(
        model: PublishedContentFeedViewModel,
        key: FeedLoadKey
    ) async {
        if model.nextPageState == .reloadFirstPageRequired {
            await model.reloadFirstPageAfterInvalidCursor()
        } else {
            await model.retryFirstPage()
        }

        guard !Task.isCancelled else { return }
        await model.load(
            query: key.query,
            catalogRevision: key.catalogRevision
        )
    }
}

private struct LibraryCoverIdentity: Equatable, Hashable, Sendable {
    let publicationID: String
    let version: Int
}

private struct LibraryAuthorizedCover: Equatable, Sendable {
    let cover: PublishedContentCover?
}

struct LibraryCoverAuthorization: Equatable, Sendable {
    let revision: Int
    let cover: PublishedContentCover?
}

@MainActor
@Observable
final class LibraryCoverAuthorizationRelay {
    private(set) var requestedKey: FeedLoadKey?
    private(set) var authorizedKey: FeedLoadKey?
    private var latestToken: LibraryCoverLoadToken?
    private var invalidatedToken: LibraryCoverLoadToken?
    private var pendingLoadWaiters: [
        UUID: AsyncStream<Void>.Continuation
    ] = [:]
    private var covers: [LibraryCoverIdentity: LibraryAuthorizedCover] = [:]

    var requestedRevision: Int? { requestedKey?.catalogRevision }
    var authorizedRevision: Int? { authorizedKey?.catalogRevision }
    var hasPendingLoad: Bool { latestToken != nil }

    @discardableResult
    func begin(requestedKey: FeedLoadKey) -> LibraryCoverLoadToken {
        let token = LibraryCoverLoadToken()
        latestToken = token
        invalidatedToken = nil
        self.requestedKey = requestedKey
        authorizedKey = nil
        covers.removeAll(keepingCapacity: true)
        return token
    }

    @discardableResult
    func commit(
        candidate: LibraryCoverResponseCandidate,
        capturedKey: FeedLoadKey,
        currentKey: FeedLoadKey?,
        state: FeatureReadState<PublishedContentFeed>,
        isCancelled: Bool
    ) -> Bool {
        guard latestToken == candidate.token else { return false }
        defer { finishPendingLoad(token: candidate.token) }

        guard invalidatedToken != candidate.token,
              !isCancelled,
              requestedKey == capturedKey,
              currentKey == capturedKey,
              candidate.query == capturedKey.query,
              didPublish(candidate.feed, in: state)
        else {
            return false
        }

        replaceCovers(with: candidate.feed.items)
        authorizedKey = capturedKey
        return true
    }

    func discard(token: LibraryCoverLoadToken) {
        finishPendingLoad(token: token)
    }

    func cancelPendingLoad() {
        invalidatedToken = latestToken
    }

    func waitForPendingLoadToFinish() async {
        while latestToken != nil, !Task.isCancelled {
            let waiterID = UUID()
            let channel = AsyncStream<Void>.makeStream()
            pendingLoadWaiters[waiterID] = channel.continuation

            await withTaskCancellationHandler {
                for await _ in channel.stream {
                    break
                }
            } onCancel: {
                channel.continuation.finish()
            }

            pendingLoadWaiters.removeValue(forKey: waiterID)?.finish()
        }
    }

    func canReuseCompletedAuthorization(
        for key: FeedLoadKey,
        state: FeatureReadState<PublishedContentFeed>
    ) -> Bool {
        guard latestToken == nil,
              requestedKey == key,
              authorizedKey == key,
              let items = successfulItems(in: state)
        else {
            return false
        }
        var publishedCovers: [
            LibraryCoverIdentity: LibraryAuthorizedCover
        ] = [:]
        for summary in items {
            let identity = LibraryCoverIdentity(
                publicationID: summary.publicationID,
                version: summary.version
            )
            guard publishedCovers.updateValue(
                LibraryAuthorizedCover(cover: summary.cover),
                forKey: identity
            ) == nil else {
                return false
            }
        }
        return publishedCovers == covers
    }

    func requiresFirstPageRecovery(for key: FeedLoadKey) -> Bool {
        latestToken == nil && requestedKey == key
    }

    func reconcilePublishedState(
        for key: FeedLoadKey,
        state: FeatureReadState<PublishedContentFeed>,
        isCancelled: Bool
    ) {
        guard !isCancelled,
              requestedKey == key,
              authorizedKey == key,
              let items = successfulItems(in: state)
        else {
            return
        }
        replaceCovers(with: items)
    }

    func authorization(
        for summary: PublishedContentSummary,
        requestedKey: FeedLoadKey?
    ) -> LibraryCoverAuthorization? {
        guard let requestedKey,
              self.requestedKey == requestedKey,
              authorizedKey == requestedKey,
              let authorized = covers[LibraryCoverIdentity(
                  publicationID: summary.publicationID,
                  version: summary.version
              )]
        else {
            return nil
        }
        return LibraryCoverAuthorization(
            revision: requestedKey.catalogRevision,
            cover: authorized.cover
        )
    }

    func cover(
        for summary: PublishedContentSummary,
        requestedKey: FeedLoadKey?
    ) -> PublishedContentCover? {
        authorization(for: summary, requestedKey: requestedKey)?.cover
    }

    func invalidate() {
        latestToken = nil
        invalidatedToken = nil
        finishPendingLoadWaiters()
        requestedKey = nil
        authorizedKey = nil
        covers.removeAll(keepingCapacity: false)
    }

    private func successfulItems(
        in state: FeatureReadState<PublishedContentFeed>
    ) -> [PublishedContentSummary]? {
        switch state {
        case let .loaded(feed):
            feed.items
        case .empty:
            []
        case .idle, .loading, .offline, .failed, .unavailable:
            nil
        }
    }

    private func didPublish(
        _ candidate: PublishedContentFeed,
        in state: FeatureReadState<PublishedContentFeed>
    ) -> Bool {
        switch state {
        case let .loaded(feed):
            feed == candidate
        case .empty:
            candidate.items.isEmpty
        case .idle, .loading, .offline, .failed, .unavailable:
            false
        }
    }

    private func replaceCovers(with items: [PublishedContentSummary]) {
        covers = Dictionary(
            uniqueKeysWithValues: items.map { summary in
                (
                    LibraryCoverIdentity(
                        publicationID: summary.publicationID,
                        version: summary.version
                    ),
                    LibraryAuthorizedCover(cover: summary.cover)
                )
            }
        )
    }

    private func finishPendingLoad(token: LibraryCoverLoadToken) {
        guard latestToken == token else { return }
        latestToken = nil
        invalidatedToken = nil
        finishPendingLoadWaiters()
    }

    private func finishPendingLoadWaiters() {
        let waiters = Array(pendingLoadWaiters.values)
        pendingLoadWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            waiter.finish()
        }
    }
}

enum LibraryAccessibilityFocusEvent: Hashable, Sendable, CaseIterable {
    case initialLoadCompleted
    case filterLoadCompleted
    case firstPageRetryCompleted
    case invalidCursorDetected
    case nextPageFailed
}

enum LibraryAccessibilityFocusReducer {
    static func target(
        after event: LibraryAccessibilityFocusEvent
    ) -> LibraryAccessibilityFocusTarget {
        switch event {
        case .initialLoadCompleted, .filterLoadCompleted:
            .resultsHeading
        case .firstPageRetryCompleted:
            .firstPageResultSummary
        case .invalidCursorDetected:
            .reloadFirstPageAction
        case .nextPageFailed:
            .retryNextPageAction
        }
    }

    static func target(
        afterFirstPageEvent event: LibraryAccessibilityFocusEvent,
        nextPageState: PublishedContentNextPageState
    ) -> LibraryAccessibilityFocusTarget {
        if nextPageState == .reloadFirstPageRequired {
            return .reloadFirstPageAction
        }
        return target(after: event)
    }
}

@MainActor
@Observable
final class LibraryCoverFeedComposition {
    let model: PublishedContentFeedViewModel
    let candidateProvider: LibraryCoverCapturingListing
    let authorizationRelay: LibraryCoverAuthorizationRelay

    init(
        listing: any PublishedContentListing,
        stateRecorder: any PublishedContentStateRecording,
        keyProvider: any IdempotencyKeyProviding,
        timeProvider: any TimeProviding,
        invalidationCenter: FeatureInvalidationCenter,
        coverLoader: any ContentCoverLoading
    ) {
        let candidateProvider = LibraryCoverCapturingListing(
            listing: listing
        )
        self.candidateProvider = candidateProvider
        authorizationRelay = LibraryCoverAuthorizationRelay()
        model = PublishedContentFeedViewModel(
            listing: candidateProvider,
            stateRecorder: stateRecorder,
            keyProvider: keyProvider,
            timeProvider: timeProvider,
            invalidationCenter: invalidationCenter,
            coverLoader: coverLoader
        )
    }
}

@MainActor
struct LibraryRootView: View {
    @State private var selection: LibrarySelection
    @State private var category: ContentCategory?
    @State private var composition: LibraryCoverFeedComposition
    @State private var nextTaskFocusEvent: LibraryAccessibilityFocusEvent?
    @State private var actionRequest: LibraryActionRequest?
    @State private var actionSequence: Int
    @AccessibilityFocusState private var accessibilityFocus:
        LibraryAccessibilityFocusTarget?

    private let invalidationCenter: FeatureInvalidationCenter

    init(
        initialSelection: LibrarySelection,
        sessionOwner: Prompt14SessionOwner,
        dependencies: AppDependencies,
        invalidationCenter: FeatureInvalidationCenter
    ) {
        _selection = State(initialValue: initialSelection)
        _category = State(initialValue: nil)
        _composition = State(initialValue: LibraryCoverFeedComposition(
            listing: sessionOwner.contentListing,
            stateRecorder: sessionOwner.contentState,
            keyProvider: dependencies.idempotencyKeyProvider,
            timeProvider: dependencies.timeProvider,
            invalidationCenter: invalidationCenter,
            coverLoader: sessionOwner.coverLoader
        ))
        _nextTaskFocusEvent = State(initialValue: .initialLoadCompleted)
        _actionRequest = State(initialValue: nil)
        _actionSequence = State(initialValue: 0)
        self.invalidationCenter = invalidationCenter
    }

    private var model: PublishedContentFeedViewModel { composition.model }

    private var coverAuthorizationRelay: LibraryCoverAuthorizationRelay {
        composition.authorizationRelay
    }

    var body: some View {
        VStack(spacing: 0) {
            filters
            Divider()
            readStateContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BodyFlowColor.background)
        .navigationTitle("Biblioteca")
        .accessibilityIdentifier("screen.library")
        .task(id: taskKey) {
            guard !Task.isCancelled,
                  let capturedKey = taskKey else { return }
            let focusEvent = nextTaskFocusEvent
            _ = await LibraryCoverLoadCoordinator.perform(
                requestedKey: capturedKey,
                relay: coverAuthorizationRelay,
                candidateProvider: composition.candidateProvider,
                reusesCompletedAuthorization: true,
                currentKey: { taskKey },
                state: { model.state },
                recoveryOperation: {
                    await LibraryCoverFirstPageRecovery.perform(
                        model: model,
                        key: capturedKey
                    )
                },
                operation: {
                    await model.load(
                        query: capturedKey.query,
                        catalogRevision: capturedKey.catalogRevision
                    )
                }
            )
            guard !Task.isCancelled,
                  LibraryFocusOwnership.canPublish(
                      capturedKey: capturedKey,
                      currentKey: taskKey
                  ) else {
                return
            }
            if let focusEvent {
                applyFirstPageFocus(after: focusEvent)
                if nextTaskFocusEvent == focusEvent {
                    nextTaskFocusEvent = nil
                }
            }
        }
        .task(id: actionRequest) {
            guard let actionRequest else { return }
            await perform(actionRequest)
        }
        .onDisappear {
            cancelPendingAction()
            coverAuthorizationRelay.cancelPendingLoad()
            accessibilityFocus = nil
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Text(LibraryCopy.description)
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Conteúdo", selection: selectionBinding) {
                Text(LibrarySelection.all.title)
                    .tag(LibrarySelection.all)
                    .accessibilityIdentifier(
                        LibrarySelection.all.accessibilityIdentifier
                    )
                Text(LibrarySelection.saved.title)
                    .tag(LibrarySelection.saved)
                    .accessibilityIdentifier(
                        LibrarySelection.saved.accessibilityIdentifier
                    )
            }
            .pickerStyle(.segmented)
            .frame(minHeight: BodyFlowSpacing.minimumTapTarget)

            Menu {
                Button {
                    select(category: nil)
                } label: {
                    categoryMenuLabel(
                        title: "Todas as categorias",
                        isSelected: category == nil
                    )
                }

                ForEach(ContentCategory.allCases, id: \.self) { option in
                    Button {
                        select(category: option)
                    } label: {
                        categoryMenuLabel(
                            title: option.libraryDisplayName,
                            isSelected: category == option
                        )
                    }
                }
            } label: {
                Label(
                    category?.libraryDisplayName ?? "Todas as categorias",
                    systemImage: "line.3.horizontal.decrease.circle"
                )
                .font(BodyFlowTypography.headline)
                .frame(
                    maxWidth: .infinity,
                    minHeight: BodyFlowSpacing.minimumTapTarget,
                    alignment: .leading
                )
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("library.category")
        }
        .padding(.horizontal, BodyFlowSpacing.md)
        .padding(.vertical, BodyFlowSpacing.sm)
    }

    @ViewBuilder
    private var readStateContent: some View {
        let presentation = model.state.presentation

        if let fullScreenState = presentation.fullScreenState {
            fullScreenContent(fullScreenState)
        } else if let feed = presentation.value {
            feedContent(
                feed,
                showsStaleBanner: presentation.showsStaleBanner
            )
        } else {
            fullScreenContent(.loading)
        }
    }

    private func fullScreenContent(_ state: ScreenState) -> some View {
        let descriptor = state.descriptor
        let heading = state == .empty ? resultsHeading : descriptor.title
        let message = state == .empty
            ? LibraryEmptyMessage.message(
                selection: selection,
                category: category
            )
            : descriptor.message
        let recoveryAction = LibraryRecoveryPolicy.action(
            allowsFirstPageRetry: descriptor.showsRetry,
            nextPageState: model.nextPageState
        )

        return GeometryReader { geometry in
            fullScreenScroll(state: state) {
                VStack(spacing: BodyFlowSpacing.md) {
                    if state == .loading {
                        ProgressView()
                            .controlSize(.large)
                            .tint(BodyFlowColor.accent)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: descriptor.systemImage)
                            .font(BodyFlowTypography.largeTitle)
                            .foregroundStyle(
                                state == .recoverableError
                                    ? BodyFlowColor.warning
                                    : BodyFlowColor.accent
                            )
                            .accessibilityHidden(true)
                    }

                    Text(heading)
                        .font(BodyFlowTypography.title)
                        .fontWeight(.semibold)
                        .foregroundStyle(BodyFlowColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("library.results-heading")
                        .accessibilityFocused(
                            $accessibilityFocus,
                            equals: .resultsHeading
                        )

                    if !message.isEmpty {
                        Text(message)
                            .font(BodyFlowTypography.body)
                            .foregroundStyle(BodyFlowColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("library.results-summary")
                            .accessibilityFocused(
                                $accessibilityFocus,
                                equals: .firstPageResultSummary
                            )
                    }

                    recoveryControl(for: recoveryAction)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, BodyFlowSpacing.lg)
                .padding(.vertical, BodyFlowSpacing.xl)
                .frame(
                    maxWidth: .infinity,
                    minHeight: geometry.size.height
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BodyFlowColor.background)
        .accessibilityIdentifier(state.accessibilityIdentifier)
    }

    @ViewBuilder
    private func fullScreenScroll<Content: View>(
        state: ScreenState,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if LibraryRefreshPolicy.allowsRefresh(for: state) {
            ScrollView {
                content()
            }
            .scrollBounceBehavior(.basedOnSize)
            .refreshable {
                await refreshFirstPage()
            }
        } else {
            ScrollView {
                content()
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func feedContent(
        _ feed: PublishedContentFeed,
        showsStaleBanner: Bool
    ) -> some View {
        let presentation = LibraryPresentation(feed: feed)

        return ScrollView {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                if showsStaleBanner {
                    StaleDataBanner()
                        .accessibilityFocused(
                            $accessibilityFocus,
                            equals: .firstPageResultSummary
                        )

                    if LibraryRecoveryPolicy.action(
                        allowsFirstPageRetry: true,
                        nextPageState: model.nextPageState
                    ) == .retryFirstPage {
                        Button {
                            requestAction(.retryFirstPage)
                        } label: {
                            Text("Tentar novamente")
                                .font(BodyFlowTypography.headline)
                                .frame(
                                    minHeight: BodyFlowSpacing.minimumTapTarget
                                )
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("state.retry")
                    }
                }

                Text(resultsHeading)
                    .font(BodyFlowTypography.title)
                    .fontWeight(.semibold)
                    .foregroundStyle(BodyFlowColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("library.results-heading")
                    .accessibilityFocused(
                        $accessibilityFocus,
                        equals: .resultsHeading
                    )

                resultCount(
                    presentation.cards.count,
                    showsStaleDisclosure: showsStaleBanner
                )

                LazyVStack(spacing: BodyFlowSpacing.md) {
                    ForEach(feed.items) { summary in
                        LibraryContentRow(
                            summary: summary,
                            model: model,
                            coverAuthorizationRelay:
                                coverAuthorizationRelay,
                            requestedKey: taskKey
                        )
                    }
                }

                pagingControls(for: feed)
            }
            .padding(BodyFlowSpacing.md)
        }
        .refreshable {
            await refreshFirstPage()
        }
    }

    @ViewBuilder
    private func pagingControls(for feed: PublishedContentFeed) -> some View {
        let paging = LibraryPagingPresentation(
            feed: feed,
            state: model.nextPageState
        )

        if paging.showsProgress {
            ProgressView("Carregando mais conteúdos")
                .frame(
                    maxWidth: .infinity,
                    minHeight: BodyFlowSpacing.minimumTapTarget
                )
        } else {
            switch paging.action {
            case .none:
                EmptyView()
            case .loadMore:
                Button {
                    requestAction(.loadNextPage)
                } label: {
                    Text("Carregar mais")
                        .font(BodyFlowTypography.headline)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: BodyFlowSpacing.minimumTapTarget
                        )
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("library.load-more")
            case .retryNextPage:
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Label(
                        "Não foi possível carregar mais conteúdos.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(BodyFlowTypography.callout)
                    .foregroundStyle(BodyFlowColor.primaryText)

                    Button {
                        requestAction(.retryNextPage)
                    } label: {
                        Text("Tentar novamente")
                            .font(BodyFlowTypography.headline)
                            .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("state.retry-next-page")
                    .accessibilityFocused(
                        $accessibilityFocus,
                        equals: .retryNextPageAction
                    )
                }
            case .reloadFirstPage:
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text("A continuação da lista não está mais disponível.")
                        .font(BodyFlowTypography.callout)
                        .foregroundStyle(BodyFlowColor.primaryText)

                    Button {
                        requestAction(.reloadFirstPage)
                    } label: {
                        Text("Recarregar desde o início")
                            .font(BodyFlowTypography.headline)
                            .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("state.reload-first-page")
                    .accessibilityFocused(
                        $accessibilityFocus,
                        equals: .reloadFirstPageAction
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func recoveryControl(for action: LibraryActionKind?) -> some View {
        switch action {
        case .retryFirstPage:
            Button {
                requestAction(.retryFirstPage)
            } label: {
                Text("Tentar novamente")
                    .font(BodyFlowTypography.headline)
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("state.retry")
        case .reloadFirstPage:
            Button {
                requestAction(.reloadFirstPage)
            } label: {
                Text("Recarregar desde o início")
                    .font(BodyFlowTypography.headline)
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("state.reload-first-page")
            .accessibilityFocused(
                $accessibilityFocus,
                equals: .reloadFirstPageAction
            )
        case .loadNextPage, .retryNextPage, .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private func resultCount(
        _ count: Int,
        showsStaleDisclosure: Bool
    ) -> some View {
        let element = LibraryFirstPageSummaryPolicy.element(
            showsStaleDisclosure: showsStaleDisclosure
        )

        if element == .resultCount {
            resultCountText(count)
                .accessibilityFocused(
                    $accessibilityFocus,
                    equals: .firstPageResultSummary
                )
        } else {
            resultCountText(count)
        }
    }

    private func resultCountText(_ count: Int) -> some View {
        Text(resultSummary(for: count))
            .font(BodyFlowTypography.callout)
            .foregroundStyle(BodyFlowColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("library.results-summary")
    }

    private var selectionBinding: Binding<LibrarySelection> {
        Binding(
            get: { selection },
            set: { newSelection in
                guard selection != newSelection else { return }
                cancelPendingAction()
                nextTaskFocusEvent = .filterLoadCompleted
                selection = newSelection
            }
        )
    }

    private var taskKey: FeedLoadKey? {
        guard let query = try? ContentFeedQuery(
            surface: selection.contentSurface,
            category: category,
            limit: 20,
            cursor: nil
        ) else {
            return nil
        }

        return FeedLoadKey(
            query: query,
            catalogRevision: invalidationCenter.revision(for: .contentCatalog)
        )
    }

    private var resultsHeading: String {
        if let category {
            return category.libraryDisplayName
        }
        switch selection {
        case .all:
            return "Conteúdos publicados"
        case .saved:
            return "Conteúdos salvos"
        }
    }

    private func categoryMenuLabel(
        title: String,
        isSelected: Bool
    ) -> some View {
        Label(
            title,
            systemImage: isSelected ? "checkmark" : "circle"
        )
    }

    private func select(category newCategory: ContentCategory?) {
        guard category != newCategory else { return }
        cancelPendingAction()
        nextTaskFocusEvent = .filterLoadCompleted
        category = newCategory
    }

    private func resultSummary(for count: Int) -> String {
        count == 1 ? "1 conteúdo" : "\(count) conteúdos"
    }

    private func refreshFirstPage() async {
        guard !Task.isCancelled,
              let capturedKey = taskKey else { return }
        _ = await LibraryCoverLoadCoordinator.perform(
            requestedKey: capturedKey,
            relay: coverAuthorizationRelay,
            candidateProvider: composition.candidateProvider,
            allowsSupersession: false,
            reusesCompletedAuthorization: false,
            currentKey: { taskKey },
            state: { model.state },
            operation: { await model.retryFirstPage() }
        )
        guard !Task.isCancelled,
              LibraryFocusOwnership.canPublish(
                  capturedKey: capturedKey,
                  currentKey: taskKey
              ) else {
            return
        }
        applyFirstPageFocus(after: .firstPageRetryCompleted)
    }

    private func requestAction(_ kind: LibraryActionKind) {
        guard let taskKey else { return }
        let request = LibraryActionRequestPolicy.next(
            kind: kind,
            key: taskKey,
            previousSequence: actionSequence
        )
        actionSequence = request.sequence
        actionRequest = request
    }

    private func cancelPendingAction() {
        actionSequence += 1
        actionRequest = nil
    }

    private func perform(_ request: LibraryActionRequest) async {
        switch request.kind {
        case .retryFirstPage:
            _ = await LibraryCoverLoadCoordinator.perform(
                requestedKey: request.key,
                relay: coverAuthorizationRelay,
                candidateProvider: composition.candidateProvider,
                allowsSupersession: false,
                reusesCompletedAuthorization: false,
                currentKey: { taskKey },
                ownsOperation: {
                    LibraryActionRequestPolicy.owns(
                        request,
                        activeRequest: actionRequest,
                        currentTaskKey: taskKey
                    )
                },
                state: { model.state },
                operation: { await model.retryFirstPage() }
            )
        case .loadNextPage:
            await model.loadNextPage()
        case .retryNextPage:
            await model.retryNextPage()
        case .reloadFirstPage:
            _ = await LibraryCoverLoadCoordinator.perform(
                requestedKey: request.key,
                relay: coverAuthorizationRelay,
                candidateProvider: composition.candidateProvider,
                allowsSupersession: false,
                reusesCompletedAuthorization: false,
                currentKey: { taskKey },
                ownsOperation: {
                    LibraryActionRequestPolicy.owns(
                        request,
                        activeRequest: actionRequest,
                        currentTaskKey: taskKey
                    )
                },
                state: { model.state },
                operation: {
                    await model.reloadFirstPageAfterInvalidCursor()
                }
            )
        }

        guard !Task.isCancelled,
              LibraryActionRequestPolicy.owns(
                  request,
                  activeRequest: actionRequest,
                  currentTaskKey: taskKey
              ) else {
            return
        }

        switch request.kind {
        case .loadNextPage, .retryNextPage:
            coverAuthorizationRelay.reconcilePublishedState(
                for: request.key,
                state: model.state,
                isCancelled: Task.isCancelled
            )
        case .retryFirstPage, .reloadFirstPage:
            break
        }

        switch request.kind {
        case .retryFirstPage:
            applyFirstPageFocus(after: .firstPageRetryCompleted)
        case .loadNextPage, .retryNextPage:
            focusForNextPageState()
        case .reloadFirstPage:
            applyFirstPageFocus(after: .firstPageRetryCompleted)
        }
    }

    private func focusForNextPageState() {
        switch model.nextPageState {
        case .failed:
            applyFocus(after: .nextPageFailed)
        case .reloadFirstPageRequired:
            applyFocus(after: .invalidCursorDetected)
        case .idle, .loading:
            break
        }
    }

    private func applyFocus(after event: LibraryAccessibilityFocusEvent) {
        accessibilityFocus = LibraryAccessibilityFocusReducer.target(after: event)
    }

    private func applyFirstPageFocus(
        after event: LibraryAccessibilityFocusEvent
    ) {
        accessibilityFocus = LibraryAccessibilityFocusReducer.target(
            afterFirstPageEvent: event,
            nextPageState: model.nextPageState
        )
    }
}

@MainActor
private struct LibraryContentRow: View {
    let summary: PublishedContentSummary
    let model: PublishedContentFeedViewModel
    let coverAuthorizationRelay: LibraryCoverAuthorizationRelay
    let requestedKey: FeedLoadKey?

    @State private var isVisible = false

    private var visibilityRequest: LibraryVisibilityRequest? {
        LibraryCardVisibilityPolicy.request(
            isVisible: isVisible,
            publicationID: summary.publicationID,
            version: summary.version
        )
    }

    var body: some View {
        let coverAuthorization = coverAuthorizationRelay.authorization(
            for: summary,
            requestedKey: requestedKey
        )
        PublishedContentCard(
            presentation: LibraryCardPresentation(summary: summary),
            coverInput: LibraryCardCoverInput(
                summary: summary,
                authorizedCover: coverAuthorization?.cover
            ),
            requestedCoverRevision: requestedKey?.catalogRevision ?? 0,
            authorizedCoverRevision: coverAuthorization?.revision
        )
        .onScrollVisibilityChange(
            threshold: LibraryCardVisibilityPolicy.threshold
        ) { isVisible in
            self.isVisible = isVisible
        }
        .task(id: visibilityRequest) {
            guard visibilityRequest != nil else { return }
            await model.recordImpression(
                for: summary,
                origin: .library
            )
        }
    }
}
