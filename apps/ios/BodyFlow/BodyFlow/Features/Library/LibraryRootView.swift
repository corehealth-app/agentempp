import Observation
import SwiftUI

enum LibraryCopy {
    static let description = description(for: .portugueseBrazil)

    static func description(for language: SupportedAppLanguage) -> String {
        string("library.description", language: language)
    }

    static func string(
        _ key: String.LocalizationValue,
        language: SupportedAppLanguage
    ) -> String {
        (try? AppLocalization.string(key, for: language)) ?? String(localized: key)
    }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @State private var selection: LibrarySelection
    @State private var category: ContentCategory?
    @State private var composition: LibraryCoverFeedComposition
    @State private var nextTaskFocusEvent: LibraryAccessibilityFocusEvent?
    @State private var actionRequest: LibraryActionRequest?
    @State private var firstPageScrollRequest: LibraryActionRequest?
    @State private var actionSequence: Int
    @State private var isCategorySelectorPresented: Bool
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
        _firstPageScrollRequest = State(initialValue: nil)
        _actionSequence = State(initialValue: 0)
        _isCategorySelectorPresented = State(initialValue: false)
        self.invalidationCenter = invalidationCenter
    }

    private var model: PublishedContentFeedViewModel { composition.model }

    private var coverAuthorizationRelay: LibraryCoverAuthorizationRelay {
        composition.authorizationRelay
    }

    var body: some View {
        VStack(spacing: 0) {
            if !embedsFiltersInFeed {
                filters
                Divider()
            }
            readStateContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BodyFlowColor.background)
        .navigationTitle(copy("library.navigation.title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
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

    private var embedsFiltersInFeed: Bool {
        dynamicTypeSize.isAccessibilitySize
            && model.state.presentation.value != nil
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Text(LibraryCopy.description(for: language))
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if dynamicTypeSize.isAccessibilitySize {
                // Accessibility sizes stack every control (the XXXL
                // evidence test locks this order).
                VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                    selectionToggle
                    categoryControl
                }
            } else {
                // Regular sizes keep the toggle and the category on one row:
                // the toggle hugs its two labels and the category takes the
                // rest, wrapping its name when the width runs out. (Measured
                // by ideal width the pair never "fits" a 370 pt row —
                // "Todas as categorias" alone needs ~200 pt — so a
                // ViewThatFits would always stack them.)
                HStack(alignment: .center, spacing: BodyFlowSpacing.sm) {
                    selectionToggle
                    categoryControl
                }
            }
        }
        .padding(.horizontal, BodyFlowSpacing.md)
        .padding(.vertical, BodyFlowSpacing.sm)
    }

    /// Todos / Salvos as one segmented control: the selected segment is
    /// filled with the brand color and marked by its glyph and the
    /// selected trait, so the choice never depends on color alone.
    private var selectionToggle: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    selectionButton(.all)

                    Divider()

                    selectionButton(.saved)
                }
            } else {
                HStack(spacing: 0) {
                    selectionButton(.all)

                    Divider()

                    selectionButton(.saved)
                }
                // Hug the two labels so the category control beside the
                // toggle keeps the rest of the row.
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        // The vertical Divider() between the two buttons has no bounded
        // ideal height of its own, so it (and transitively this Group)
        // happily accepts whatever height an ambient flexible ancestor
        // proposes — competing with the feed's ScrollView for leftover
        // vertical space instead of staying compact. Pinning the whole
        // toggle to its own content-driven ideal height fixes that while
        // still growing naturally for larger Dynamic Type sizes (each
        // button's minHeight-44 floor is preserved).
        .fixedSize(horizontal: false, vertical: true)
        .background(BodyFlowColor.surface)
        .clipShape(
            RoundedRectangle(cornerRadius: BodyFlowRadius.small)
        )
        .overlay {
            RoundedRectangle(cornerRadius: BodyFlowRadius.small)
                .stroke(
                    BodyFlowColor.color(.borderSubtle),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .contain)
    }

    /// One button, one visible label (plus decorative glyphs): the
    /// accessibility evidence test locks 0 nested buttons / 1 text.
    private var categoryControl: some View {
        Button {
            isCategorySelectorPresented = true
        } label: {
            HStack(spacing: BodyFlowSpacing.xs) {
                Label(
                    verbatim: category?.libraryDisplayName(for: language)
                        ?? copy("library.category.all"),
                    symbol: .categoryFilter
                )
                .font(BodyFlowTypography.headline)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: BodyFlowSpacing.xs)
                Image(symbol: .picker)
                    .font(BodyFlowTypography.caption)
                    .accessibilityHidden(true)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: BodyFlowSpacing.minimumTapTarget,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.bodyFlowRow)
        .foregroundStyle(BodyFlowColor.accent)
        .accessibilityLabel(
            category?.libraryDisplayName(for: language)
                ?? copy("library.category.all")
        )
        .accessibilityIdentifier("library.category")
        .confirmationDialog(
            copy("library.category.select"),
            isPresented: $isCategorySelectorPresented,
            titleVisibility: .visible
        ) {
            categoryDialogButton(
                title: copy("library.category.all"),
                option: nil
            )

            ForEach(ContentCategory.allCases, id: \.self) { option in
                categoryDialogButton(
                    title: option.libraryDisplayName(for: language),
                    option: option
                )
            }

            Button(copy("library.action.cancel"), role: .cancel) {}
        }
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
        let descriptor = state.descriptor(for: language)
        let heading = state == .empty ? resultsHeading : descriptor.title
        let message = state == .empty
            ? LibraryEmptyMessage.message(
                selection: selection,
                category: category,
                language: language
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

                    if state == .loading {
                        loadingPlaceholders
                    }
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

    /// Two card-shaped placeholders under the first-page spinner: the feed's
    /// shape without any fabricated title, count or reading time. Hidden
    /// from assistive technologies; the loading state announces itself.
    private var loadingPlaceholders: some View {
        VStack(spacing: BodyFlowSpacing.md) {
            ForEach(0..<2, id: \.self) { _ in
                BodyFlowCard {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                        RoundedRectangle(cornerRadius: BodyFlowRadius.field, style: .continuous)
                            .fill(BodyFlowColor.color(.surfaceElevated))
                            .frame(height: BodyFlowSpacing.xl * 3)
                        RoundedRectangle(cornerRadius: BodyFlowRadius.small, style: .continuous)
                            .fill(BodyFlowColor.color(.surfaceElevated))
                            .frame(width: BodyFlowSpacing.xl * 5, height: BodyFlowSpacing.md)
                        RoundedRectangle(cornerRadius: BodyFlowRadius.small, style: .continuous)
                            .fill(BodyFlowColor.color(.surfaceElevated))
                            .frame(maxWidth: .infinity)
                            .frame(height: BodyFlowSpacing.sm)
                    }
                }
            }
        }
        .padding(.top, BodyFlowSpacing.md)
        .accessibilityHidden(true)
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
        let presentation = LibraryPresentation(feed: feed, language: language)

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if embedsFiltersInFeed {
                        filters
                        Divider()
                    }

                    VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                        if showsStaleBanner {
                            FeatureStaleRecovery(retry: firstPageStaleRetry) {
                                StaleDataBanner()
                                    .accessibilityFocused(
                                        $accessibilityFocus,
                                        equals: .firstPageResultSummary
                                    )
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
                            .id("library.results-heading.scroll-target")

                        resultCount(
                            presentation.cards.count,
                            showsStaleDisclosure: showsStaleBanner
                        )

                        cardRows(for: feed)

                        pagingControls(for: feed)
                    }
                    .padding(BodyFlowSpacing.md)
                }
            }
            .refreshable {
                await refreshFirstPage()
            }
            .onChange(of: firstPageScrollRequest) { _, request in
                guard let request,
                      request.kind == .reloadFirstPage,
                      request.key == taskKey,
                      LibraryActionRequestPolicy.owns(
                          request,
                          activeRequest: actionRequest,
                          currentTaskKey: taskKey
                      ) else {
                    return
                }
                proxy.scrollTo(
                    "library.results-heading.scroll-target",
                    anchor: .top
                )
            }
        }
    }

    @ViewBuilder
    private func cardRows(for feed: PublishedContentFeed) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: BodyFlowSpacing.md) {
                contentRows(for: feed)
            }
        } else {
            LazyVStack(spacing: BodyFlowSpacing.md) {
                contentRows(for: feed)
            }
        }
    }

    @ViewBuilder
    private func contentRows(for feed: PublishedContentFeed) -> some View {
        ForEach(feed.items) { summary in
            LibraryContentRow(
                summary: summary,
                model: model,
                coverAuthorizationRelay: coverAuthorizationRelay,
                requestedKey: taskKey,
                language: language
            )
        }
    }

    @ViewBuilder
    private func pagingControls(for feed: PublishedContentFeed) -> some View {
        let paging = LibraryPagingPresentation(
            feed: feed,
            state: model.nextPageState
        )

        if paging.showsProgress {
            ProgressView(copy("library.paging.loading"))
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
                    Text(copy("library.paging.load-more"))
                        .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                }
                .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                .accessibilityIdentifier("library.load-more")
            case .retryNextPage:
                VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                    BodyFlowStatusLine(
                        copy("library.paging.error"),
                        kind: .error,
                        font: BodyFlowTypography.callout
                    )

                    Button {
                        requestAction(.retryNextPage)
                    } label: {
                        Text(copy("state.retry"))
                            .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                    }
                    .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                    .accessibilityIdentifier("state.retry-next-page")
                    .accessibilityFocused(
                        $accessibilityFocus,
                        equals: .retryNextPageAction
                    )
                }
            case .reloadFirstPage:
                VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                    BodyFlowStatusLine(
                        copy("library.paging.expired"),
                        kind: .warning,
                        font: BodyFlowTypography.callout
                    )

                    Button {
                        requestAction(.reloadFirstPage)
                    } label: {
                        Text(copy("library.paging.reload"))
                            .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                    }
                    .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                    .accessibilityIdentifier("state.reload-first-page")
                    .accessibilityFocused(
                        $accessibilityFocus,
                        equals: .reloadFirstPageAction
                    )
                }
            }
        }
    }

    /// Retry for a stale first page, only while the recovery policy allows
    /// it; otherwise the stale banner stands alone.
    private var firstPageStaleRetry: (@MainActor () -> Void)? {
        guard LibraryRecoveryPolicy.action(
            allowsFirstPageRetry: true,
            nextPageState: model.nextPageState
        ) == .retryFirstPage else {
            return nil
        }
        return { requestAction(.retryFirstPage) }
    }

    @ViewBuilder
    private func recoveryControl(for action: LibraryActionKind?) -> some View {
        switch action {
        case .retryFirstPage:
            FeatureRetryButton {
                requestAction(.retryFirstPage)
            }
        case .reloadFirstPage:
            Button {
                requestAction(.reloadFirstPage)
            } label: {
                Text(copy("library.paging.reload"))
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
            }
            .buttonStyle(BodyFlowButtonStyle(role: .secondary))
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

    private func selectionButton(
        _ option: LibrarySelection
    ) -> some View {
        Button {
            guard selection != option else { return }
            cancelPendingAction()
            nextTaskFocusEvent = .filterLoadCompleted
            selection = option
        } label: {
            Label(
                verbatim: option.title(for: language),
                symbol: selection == option ? .selected : .unselected
            )
            .font(BodyFlowTypography.headline)
            .padding(.horizontal, BodyFlowSpacing.sm)
            .frame(
                maxWidth: .infinity,
                minHeight: BodyFlowSpacing.minimumTapTarget
            )
            // A frame with only minHeight (no maxHeight) accepts whatever
            // height an ambient flexible ancestor proposes, which let this
            // control balloon to consume leftover vertical space alongside
            // the feed's ScrollView. Pin it to its content-driven ideal
            // height (still never below the 44pt floor above) so it stays
            // compact instead of competing for layout space.
            .fixedSize(horizontal: false, vertical: true)
            .background(
                selection == option
                    ? BodyFlowColor.accent
                    : BodyFlowColor.surface
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.bodyFlowRow)
        .foregroundStyle(
            selection == option
                ? BodyFlowColor.color(.onPrimary)
                : BodyFlowColor.primaryText
        )
        .accessibilityIdentifier(option.accessibilityIdentifier)
        .accessibilityAddTraits(
            selection == option ? .isSelected : []
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
            return category.libraryDisplayName(for: language)
        }
        switch selection {
        case .all:
            return copy("library.results.published")
        case .saved:
            return copy("library.results.saved")
        }
    }

    private func select(category newCategory: ContentCategory?) {
        guard category != newCategory else { return }
        cancelPendingAction()
        nextTaskFocusEvent = .filterLoadCompleted
        category = newCategory
    }

    private func categoryDialogButton(
        title: String,
        option: ContentCategory?
    ) -> some View {
        let isSelected = category == option

        let label = isSelected
            ? String(
                format: copy("library.category.selected-format"),
                locale: language.formattingLocale,
                title
            )
            : title
        return Button(label) {
            select(category: option)
        }
    }

    private func resultSummary(for count: Int) -> String {
        let key: String.LocalizationValue = count == 1
            ? "library.results.count-one"
            : "library.results.count-many"
        return String(
            format: copy(key),
            locale: language.formattingLocale,
            count
        )
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        LibraryCopy.string(key, language: language)
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
        var didCommitReload = false
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
            didCommitReload = await LibraryCoverLoadCoordinator.perform(
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
            guard didCommitReload else { return }
            firstPageScrollRequest = request
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
    let language: SupportedAppLanguage

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
            presentation: LibraryCardPresentation(
                summary: summary,
                language: language
            ),
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
