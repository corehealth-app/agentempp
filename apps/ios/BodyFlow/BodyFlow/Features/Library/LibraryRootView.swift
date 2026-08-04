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
struct LibraryRootView: View {
    @State private var selection: LibrarySelection
    @State private var category: ContentCategory?
    @State private var model: PublishedContentFeedViewModel
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
        _model = State(initialValue: PublishedContentFeedViewModel(
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
            guard let capturedKey = taskKey else { return }
            let focusEvent = nextTaskFocusEvent
            await model.load(
                query: capturedKey.query,
                catalogRevision: capturedKey.catalogRevision
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
                            model: model
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
        let capturedKey = taskKey
        await model.retryFirstPage()
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
            await model.retryFirstPage()
        case .loadNextPage:
            await model.loadNextPage()
        case .retryNextPage:
            await model.retryNextPage()
        case .reloadFirstPage:
            await model.reloadFirstPageAfterInvalidCursor()
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

    @State private var isVisible = false

    private var visibilityRequest: LibraryVisibilityRequest? {
        LibraryCardVisibilityPolicy.request(
            isVisible: isVisible,
            publicationID: summary.publicationID,
            version: summary.version
        )
    }

    var body: some View {
        PublishedContentCard(
            presentation: LibraryCardPresentation(summary: summary)
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
