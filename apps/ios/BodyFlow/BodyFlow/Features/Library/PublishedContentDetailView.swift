import Observation
import SwiftUI

struct ContentDetailCoverLoadToken: Equatable, Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

struct ContentDetailCoverIdentity: Equatable, Hashable, Sendable {
    let publicationID: String
    let version: Int
}

enum ContentDetailCoverCommitPolicy {
    static func canCommit(
        candidateIdentity: ContentDetailCoverIdentity,
        renderedIdentity: ContentDetailCoverIdentity,
        candidateToken: ContentDetailCoverLoadToken,
        latestToken: ContentDetailCoverLoadToken,
        capturedRevision: Int,
        currentRevision: Int,
        isCancelled: Bool
    ) -> Bool {
        !isCancelled
            && candidateIdentity == renderedIdentity
            && candidateToken == latestToken
            && capturedRevision == currentRevision
    }
}

struct ContentDetailCoverCandidate: Sendable {
    let identity: ContentDetailCoverIdentity
    let cover: PublishedContentCover?
    let token: ContentDetailCoverLoadToken
}

enum ContentDetailCoverLoadContext {
    @TaskLocal static var token: ContentDetailCoverLoadToken?

    @MainActor
    static func withToken<Value: Sendable>(
        _ token: ContentDetailCoverLoadToken,
        operation: @MainActor () async throws -> Value
    ) async rethrows -> Value {
        try await $token.withValue(token, operation: operation)
    }
}

protocol ContentDetailCoverCandidateProviding: Sendable {
    func takeCandidate(
        for token: ContentDetailCoverLoadToken
    ) async -> (ContentDetailCoverCandidate, ContentDetailCoverLoadToken)?
}

actor ContentDetailCoverCapturingProvider:
    PublishedContentDetailProviding,
    ContentDetailCoverCandidateProviding {
    private let provider: any PublishedContentDetailProviding
    private var latestToken: ContentDetailCoverLoadToken?
    private var candidates: [
        ContentDetailCoverLoadToken: ContentDetailCoverCandidate
    ] = [:]

    init(provider: any PublishedContentDetailProviding) {
        self.provider = provider
    }

    func contentDetail(
        publicationID: String
    ) async throws -> PublishedContentDetailResponse {
        guard let token = ContentDetailCoverLoadContext.token else {
            return try await provider.contentDetail(
                publicationID: publicationID
            )
        }

        latestToken = token
        candidates.removeAll(keepingCapacity: true)
        let response = try await provider.contentDetail(
            publicationID: publicationID
        )
        try Task.checkCancellation()
        guard latestToken == token else {
            throw CancellationError()
        }
        let summary = response.data.summary
        candidates[token] = ContentDetailCoverCandidate(
            identity: ContentDetailCoverIdentity(
                publicationID: summary.publicationID,
                version: summary.version
            ),
            cover: summary.cover,
            token: token
        )
        return response
    }

    func takeCandidate(
        for token: ContentDetailCoverLoadToken
    ) async -> (ContentDetailCoverCandidate, ContentDetailCoverLoadToken)? {
        guard let latestToken,
              latestToken == token,
              let candidate = candidates.removeValue(forKey: token)
        else {
            return nil
        }
        return (candidate, latestToken)
    }

    func isLatest(_ token: ContentDetailCoverLoadToken) -> Bool {
        latestToken == token
    }
}

struct ContentDetailCoverAuthorization: Equatable, Sendable {
    let identity: ContentDetailCoverIdentity
    let cover: PublishedContentCover?
    let revision: Int
}

enum ContentDetailCoverAuthorizationCoordinator {
    static func authorization(
        candidate: ContentDetailCoverCandidate,
        latestToken: ContentDetailCoverLoadToken,
        state: FeatureReadState<RenderablePublishedContentDetail>,
        capturedRevision: Int,
        currentRevision: Int,
        isCancelled: Bool
    ) -> ContentDetailCoverAuthorization? {
        guard case let .loaded(detail) = state else { return nil }
        let renderedIdentity = ContentDetailCoverIdentity(
            publicationID: detail.publicationID,
            version: detail.version
        )
        guard ContentDetailCoverCommitPolicy.canCommit(
            candidateIdentity: candidate.identity,
            renderedIdentity: renderedIdentity,
            candidateToken: candidate.token,
            latestToken: latestToken,
            capturedRevision: capturedRevision,
            currentRevision: currentRevision,
            isCancelled: isCancelled
        ) else {
            return nil
        }
        return ContentDetailCoverAuthorization(
            identity: candidate.identity,
            cover: candidate.cover,
            revision: capturedRevision
        )
    }
}

@MainActor
@Observable
final class ContentDetailCoverRelay {
    private var storedAuthorization: ContentDetailCoverAuthorization?

    func commit(
        _ candidate: ContentDetailCoverCandidate,
        latestToken: ContentDetailCoverLoadToken,
        state: FeatureReadState<RenderablePublishedContentDetail>,
        capturedRevision: Int,
        currentRevision: Int,
        isCancelled: Bool
    ) -> Bool {
        guard let authorization =
                ContentDetailCoverAuthorizationCoordinator.authorization(
            candidate: candidate,
            latestToken: latestToken,
            state: state,
            capturedRevision: capturedRevision,
            currentRevision: currentRevision,
            isCancelled: isCancelled
        ) else { return false }
        storedAuthorization = authorization
        return true
    }

    func authorization(
        for renderedIdentity: ContentDetailCoverIdentity
    ) -> ContentDetailCoverAuthorization? {
        guard storedAuthorization?.identity == renderedIdentity else {
            return nil
        }
        return storedAuthorization
    }

    func cover(for renderedIdentity: ContentDetailCoverIdentity)
        -> PublishedContentCover? {
        authorization(for: renderedIdentity)?.cover
    }

    func clear() {
        storedAuthorization = nil
    }

    func hasAuthorization(
        for renderedIdentity: ContentDetailCoverIdentity
    ) -> Bool {
        authorization(for: renderedIdentity) != nil
    }
}

@MainActor
enum ContentDetailCoverResolution: Equatable {
    case missing
    case discarded
    case committed
}

struct ContentDetailCoverCommitContext: Equatable, Sendable {
    let activeToken: ContentDetailCoverLoadToken?
    let currentRevision: Int
    let state: FeatureReadState<RenderablePublishedContentDetail>
    let isCancelled: Bool
}

@MainActor
enum ContentDetailCoverObservationCoordinator {
    @discardableResult
    static func resolve(
        token: ContentDetailCoverLoadToken,
        capturedRevision: Int,
        provider: any ContentDetailCoverCandidateProviding,
        relay: ContentDetailCoverRelay,
        currentContext: @escaping @MainActor ()
            -> ContentDetailCoverCommitContext
    ) async -> ContentDetailCoverResolution {
        guard let (candidate, latestToken) =
                await provider.takeCandidate(for: token)
        else {
            return .missing
        }
        let context = currentContext()
        return relay.commit(
            candidate,
            latestToken: latestToken,
            state: context.state,
            capturedRevision: capturedRevision,
            currentRevision: context.currentRevision,
            isCancelled: context.isCancelled
                || context.activeToken != token
        ) ? .committed : .discarded
    }
}

@MainActor
struct ContentDetailCoverCompositionIdentity: Equatable {
    let model: ObjectIdentifier
    let provider: ObjectIdentifier
    let relay: ObjectIdentifier
}

@MainActor
struct ContentDetailCoverTaskIdentity: Equatable {
    let composition: ContentDetailCoverCompositionIdentity
    let revision: Int
}

@MainActor
@Observable
final class ContentDetailCoverComposition {
    let model: ContentDetailViewModel
    let coverProvider: ContentDetailCoverCapturingProvider
    private let coverRelay: ContentDetailCoverRelay

    private var activeToken: ContentDetailCoverLoadToken?
    private var activeRevision: Int?
    private var completedAuthorizedRevision: Int?
    private var stateObservationContinuations: [
        ContentDetailCoverLoadToken: AsyncStream<Void>.Continuation
    ] = [:]

    var identity: ContentDetailCoverCompositionIdentity {
        ContentDetailCoverCompositionIdentity(
            model: ObjectIdentifier(model),
            provider: ObjectIdentifier(coverProvider),
            relay: ObjectIdentifier(coverRelay)
        )
    }

    var taskOwnerIdentity: ContentDetailCoverCompositionIdentity { identity }
    var coverRelayIdentity: ObjectIdentifier { ObjectIdentifier(coverRelay) }

    static func make(
        publicationID: String,
        origin: ContentOrigin,
        detailProvider: any PublishedContentDetailProviding,
        stateRecorder: any PublishedContentStateRecording,
        keyProvider: any IdempotencyKeyProviding,
        timeProvider: any TimeProviding,
        invalidationCenter: FeatureInvalidationCenter,
        coverLoader: any ContentCoverLoading
    ) -> ContentDetailCoverComposition {
        let coverProvider = ContentDetailCoverCapturingProvider(
            provider: detailProvider
        )
        let relay = ContentDetailCoverRelay()
        let model = ContentDetailViewModel(
            publicationID: publicationID,
            origin: origin,
            detailProvider: coverProvider,
            stateRecorder: stateRecorder,
            markdownParser: BodyFlowMarkdownParser(),
            keyProvider: keyProvider,
            timeProvider: timeProvider,
            invalidationCenter: invalidationCenter,
            coverLoader: coverLoader
        )
        return ContentDetailCoverComposition(
            model: model,
            coverProvider: coverProvider,
            coverRelay: relay
        )
    }

    private init(
        model: ContentDetailViewModel,
        coverProvider: ContentDetailCoverCapturingProvider,
        coverRelay: ContentDetailCoverRelay
    ) {
        self.model = model
        self.coverProvider = coverProvider
        self.coverRelay = coverRelay
    }

    func cover(
        for renderedIdentity: ContentDetailCoverIdentity
    ) -> PublishedContentCover? {
        coverRelay.cover(for: renderedIdentity)
    }

    func coverAuthorization(
        for renderedIdentity: ContentDetailCoverIdentity
    ) -> ContentDetailCoverAuthorization? {
        coverRelay.authorization(for: renderedIdentity)
    }

    func hasCoverAuthorization(
        for renderedIdentity: ContentDetailCoverIdentity
    ) -> Bool {
        coverRelay.hasAuthorization(for: renderedIdentity)
    }

    func performLoad(
        revision: Int,
        isRetry: Bool,
        currentRevision: @escaping @MainActor () -> Int
    ) async {
        guard !Task.isCancelled else { return }

        if !isRetry,
           completedAuthorizedRevision == revision,
           case let .loaded(detail) = model.state,
           coverRelay.hasAuthorization(for: ContentDetailCoverIdentity(
               publicationID: detail.publicationID,
               version: detail.version
           )) {
            return
        }

        let token = ContentDetailCoverLoadToken()
        activeToken = token
        activeRevision = revision
        completedAuthorizedRevision = nil
        coverRelay.clear()

        let observer = Task { @MainActor [weak self] in
            await self?.observeLoad(
                token: token,
                revision: revision,
                currentRevision: currentRevision
            )
        }

        await withTaskCancellationHandler {
            await ContentDetailCoverLoadContext.withToken(token) {
                if isRetry {
                    await model.retry(revision: revision)
                } else {
                    await model.load(revision: revision)
                }
            }

            finishStateObservation(for: token)
            observer.cancel()
            await observer.value
            _ = await resolve(
                token: token,
                revision: revision,
                currentRevision: currentRevision,
                isCancelled: { Task.isCancelled }
            )
        } onCancel: {
            observer.cancel()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.finishStateObservation(for: token)
                _ = await self.resolve(
                    token: token,
                    revision: revision,
                    currentRevision: currentRevision,
                    isCancelled: { true }
                )
            }
        }
    }

    func cancelActiveLoad() {
        guard let activeToken,
              let activeRevision else { return }
        self.activeToken = nil
        self.activeRevision = nil
        completedAuthorizedRevision = nil
        finishStateObservation(for: activeToken)
        coverRelay.clear()
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.resolve(
                token: activeToken,
                revision: activeRevision,
                currentRevision: { activeRevision },
                isCancelled: { true }
            )
        }
    }

    private func observeLoad(
        token: ContentDetailCoverLoadToken,
        revision: Int,
        currentRevision: @escaping @MainActor () -> Int
    ) async {
        while !Task.isCancelled,
              activeToken == token,
              activeRevision == revision {
            if await resolveIfTerminal(
                token: token,
                revision: revision,
                currentRevision: currentRevision
            ) {
                return
            }
            let changes = nextModelStateMutation(for: token)
            for await _ in changes {
                break
            }
        }
        if Task.isCancelled {
            _ = await resolve(
                token: token,
                revision: revision,
                currentRevision: currentRevision,
                isCancelled: { true }
            )
        }
    }

    private func resolveIfTerminal(
        token: ContentDetailCoverLoadToken,
        revision: Int,
        currentRevision: @escaping @MainActor () -> Int
    ) async -> Bool {
        switch model.state {
        case .idle, .loading:
            return false
        case .loaded, .empty, .offline, .failed, .unavailable:
            let resolution = await resolve(
                token: token,
                revision: revision,
                currentRevision: currentRevision,
                isCancelled: { Task.isCancelled }
            )
            return resolution != .missing
        }
    }

    private func resolve(
        token: ContentDetailCoverLoadToken,
        revision: Int,
        currentRevision: @escaping @MainActor () -> Int,
        isCancelled: @escaping @MainActor () -> Bool
    ) async -> ContentDetailCoverResolution {
        let resolution = await ContentDetailCoverObservationCoordinator.resolve(
            token: token,
            capturedRevision: revision,
            provider: coverProvider,
            relay: coverRelay,
            currentContext: { [weak self] in
                guard let self else {
                    return ContentDetailCoverCommitContext(
                        activeToken: nil,
                        currentRevision: currentRevision(),
                        state: .idle,
                        isCancelled: true
                    )
                }
                return ContentDetailCoverCommitContext(
                    activeToken: self.activeToken,
                    currentRevision: currentRevision(),
                    state: self.model.state,
                    isCancelled: isCancelled()
                )
            }
        )
        if resolution == .committed,
           activeToken == token,
           activeRevision == revision {
            activeToken = nil
            activeRevision = nil
            completedAuthorizedRevision = revision
            finishStateObservation(for: token)
        }
        return resolution
    }

    private func nextModelStateMutation(
        for token: ContentDetailCoverLoadToken
    ) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            finishStateObservation(for: token)
            stateObservationContinuations[token] = continuation
            withObservationTracking {
                _ = model.state
            } onChange: {
                continuation.yield()
                continuation.finish()
            }
        }
    }

    private func finishStateObservation(
        for token: ContentDetailCoverLoadToken
    ) {
        stateObservationContinuations.removeValue(forKey: token)?.finish()
    }
}

struct ContentDetailRetryRequest: Equatable, Hashable, Sendable {
    let revision: Int
    let sequence: Int
}

enum ContentDetailRetryRequestPolicy {
    static func next(
        revision: Int,
        previousSequence: Int
    ) -> ContentDetailRetryRequest {
        ContentDetailRetryRequest(
            revision: revision,
            sequence: previousSequence + 1
        )
    }
}

enum ContentDetailAccessibilityFocusCommand: Equatable, Sendable {
    case clear
    case focus(ContentDetailAccessibilityFocusEvent)
}

struct ContentDetailAccessibilityFocusCoordinator: Equatable, Sendable {
    private var latestSequence: UInt64?
    private var pendingEvent: ContentDetailAccessibilityFocusEvent?

    mutating func receive(
        _ event: ContentDetailAccessibilityFocusEvent,
        currentFocus: ContentDetailAccessibilityFocusTarget?
    ) -> ContentDetailAccessibilityFocusCommand? {
        if let latestSequence,
           event.sequence <= latestSequence {
            return nil
        }
        latestSequence = event.sequence

        guard currentFocus == event.target else {
            pendingEvent = nil
            return .focus(event)
        }
        pendingEvent = event
        return .clear
    }

    mutating func focusDidChange(
        to focus: ContentDetailAccessibilityFocusTarget?
    ) -> ContentDetailAccessibilityFocusCommand? {
        guard focus == nil,
              let pendingEvent else { return nil }
        self.pendingEvent = nil
        return .focus(pendingEvent)
    }
}

@MainActor
struct PublishedContentDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @State private var composition: ContentDetailCoverComposition
    @State private var retryRequest: ContentDetailRetryRequest?
    @State private var retrySequence = 0
    @State private var accessibilityFocusCoordinator =
        ContentDetailAccessibilityFocusCoordinator()
    @AccessibilityFocusState private var accessibilityFocus:
        ContentDetailAccessibilityFocusTarget?

    private let publicationID: String
    private let invalidationCenter: FeatureInvalidationCenter

    init(
        publicationID: String,
        origin: ContentOrigin,
        detailProvider: any PublishedContentDetailProviding,
        stateRecorder: any PublishedContentStateRecording,
        keyProvider: any IdempotencyKeyProviding,
        timeProvider: any TimeProviding,
        invalidationCenter: FeatureInvalidationCenter,
        coverLoader: any ContentCoverLoading
    ) {
        self.publicationID = publicationID
        self.invalidationCenter = invalidationCenter
        _composition = State(initialValue: ContentDetailCoverComposition.make(
            publicationID: publicationID,
            origin: origin,
            detailProvider: detailProvider,
            stateRecorder: stateRecorder,
            keyProvider: keyProvider,
            timeProvider: timeProvider,
            invalidationCenter: invalidationCenter,
            coverLoader: coverLoader
        ))
    }

    var body: some View {
        ZStack {
            BodyFlowColor.background
                .ignoresSafeArea()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(
                    "screen.content-detail.\(publicationID)"
                )

            if let boundedPresentation = model.boundedPresentation {
                boundedState(boundedPresentation)
            } else {
                FeatureReadStateView(
                    state: model.state,
                    retryAction: retry
                ) { detail in
                    article(detail)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BodyFlowColor.background)
        .navigationTitle("Conteúdo")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: detailLoadIdentity) {
            let revision = detailRevision
            await performDetailLoad(revision: revision, isRetry: false)
        }
        .task(id: retryRequest) {
            guard let retryRequest else { return }
            await performDetailLoad(
                revision: retryRequest.revision,
                isRetry: true
            )
        }
        .onChange(of: model.accessibilityFocusEvent) { _, event in
            guard let event else { return }
            applyAccessibilityFocus(
                accessibilityFocusCoordinator.receive(
                    event,
                    currentFocus: accessibilityFocus
                )
            )
        }
        .onChange(of: accessibilityFocus) { _, focus in
            applyAccessibilityFocus(
                accessibilityFocusCoordinator.focusDidChange(to: focus)
            )
        }
        .onDisappear {
            composition.cancelActiveLoad()
        }
    }

    private var model: ContentDetailViewModel { composition.model }

    private var detailRevision: Int {
        invalidationCenter.revision(for: .contentDetail(publicationID))
    }

    private var detailLoadIdentity: ContentDetailCoverTaskIdentity {
        ContentDetailCoverTaskIdentity(
            composition: composition.taskOwnerIdentity,
            revision: detailRevision
        )
    }

    private func retry() {
        let request = ContentDetailRetryRequestPolicy.next(
            revision: detailRevision,
            previousSequence: retrySequence
        )
        retrySequence = request.sequence
        retryRequest = request
    }

    private func performDetailLoad(
        revision: Int,
        isRetry: Bool
    ) async {
        await composition.performLoad(
            revision: revision,
            isRetry: isRetry,
            currentRevision: { detailRevision }
        )
    }

    private func applyAccessibilityFocus(
        _ command: ContentDetailAccessibilityFocusCommand?
    ) {
        guard let command else { return }
        switch command {
        case .clear:
            accessibilityFocus = nil
        case let .focus(event):
            guard model.accessibilityFocusEvent == event else { return }
            accessibilityFocus = event.target
            model.consumeAccessibilityFocus(event)
        }
    }

    private func article(
        _ detail: RenderablePublishedContentDetail
    ) -> some View {
        let coverIdentity = ContentDetailCoverIdentity(
            publicationID: detail.publicationID,
            version: detail.version
        )
        let coverAuthorization = composition.coverAuthorization(
            for: coverIdentity
        )

        return ScrollView {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                Text(detail.title)
                    .font(BodyFlowTypography.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(BodyFlowColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused(
                        $accessibilityFocus,
                        equals: .articleHeading
                    )

                ContentCoverView(
                    publicationID: detail.publicationID,
                    version: detail.version,
                    cover: coverAuthorization?.cover,
                    parentRevision: detailRevision,
                    authorizedParentRevision: coverAuthorization?.revision,
                    onParentRevisionChanged: {},
                    onCapabilityInvalidated: { retry() }
                )

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        categoryMetadata(detail)
                        Spacer(minLength: BodyFlowSpacing.sm)
                        readingTimeMetadata(detail)
                    }
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                        categoryMetadata(detail)
                        readingTimeMetadata(detail)
                    }
                }

                if detail.saved || detail.completed {
                    status(detail)
                }

                contentActions(detail)

                if case let .failed(error) = model.openedEventState,
                   error != .contentVersionChanged {
                    Label(
                        "Não foi possível atualizar. Tente novamente.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(BodyFlowTypography.callout)
                    .foregroundStyle(BodyFlowColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if let presentation = model.contentMutationPresentation {
                    mutationSummary(presentation)
                }

                Divider()

                BodyFlowMarkdownView(document: detail.document)
            }
            .padding(.horizontal, BodyFlowSpacing.lg)
            .padding(.vertical, BodyFlowSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func contentActions(
        _ detail: RenderablePublishedContentDetail
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: BodyFlowSpacing.sm) {
                saveButton(detail)
                if model.showsCompletionAction {
                    completionButton
                }
            }
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                saveButton(detail)
                if model.showsCompletionAction {
                    completionButton
                }
            }
        }
    }

    private func saveButton(
        _ detail: RenderablePublishedContentDetail
    ) -> some View {
        Button {
            Task { await model.toggleSaved() }
        } label: {
            Label(
                detail.saved ? "Remover dos salvos" : "Salvar",
                systemImage: detail.saved ? "bookmark.slash" : "bookmark"
            )
            .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .disabled(!model.canToggleSaved)
        .accessibilityIdentifier("content-detail.save")
    }

    private var completionButton: some View {
        Button {
            Task { await model.complete() }
        } label: {
            Label("Concluir", systemImage: "checkmark.circle")
                .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderedProminent)
        .disabled(!model.canComplete)
        .accessibilityIdentifier("content-detail.complete")
    }

    private func mutationSummary(
        _ presentation: ContentMutationPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
            Label(presentation.message, systemImage: presentation.systemImage)
            if presentation.allowsRetry {
                Button {
                    Task { await model.retryContentMutation() }
                } label: {
                    Text("Tentar novamente")
                        .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("content-detail.mutation.retry")
            }
        }
        .font(BodyFlowTypography.callout)
        .foregroundStyle(BodyFlowColor.primaryText)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("content-detail.mutation.summary")
        .accessibilityFocused(
            $accessibilityFocus,
            equals: .mutationSummary
        )
    }

    private func categoryMetadata(
        _ detail: RenderablePublishedContentDetail
    ) -> some View {
        Label(detail.categoryLabel, systemImage: "books.vertical")
            .font(BodyFlowTypography.callout)
            .foregroundStyle(BodyFlowColor.secondaryText)
    }

    private func readingTimeMetadata(
        _ detail: RenderablePublishedContentDetail
    ) -> some View {
        Label(detail.readingTimeLabel, systemImage: "clock")
            .font(BodyFlowTypography.callout)
            .foregroundStyle(BodyFlowColor.secondaryText)
    }

    private func status(
        _ detail: RenderablePublishedContentDetail
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: BodyFlowSpacing.md) {
                statusLabels(detail)
            }
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                statusLabels(detail)
            }
        }
        .font(BodyFlowTypography.callout)
        .foregroundStyle(BodyFlowColor.primaryText)
    }

    @ViewBuilder
    private func statusLabels(
        _ detail: RenderablePublishedContentDetail
    ) -> some View {
        if detail.saved {
            Label("Salvo", systemImage: "bookmark.fill")
        }
        if detail.completed {
            Label("Concluído", systemImage: "checkmark.circle.fill")
        }
    }

    private func boundedState(
        _ presentation: ContentDetailBoundedPresentation
    ) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: BodyFlowSpacing.lg) {
                    Image(systemName: "book.closed")
                        .font(BodyFlowTypography.largeTitle)
                        .foregroundStyle(BodyFlowColor.accent)
                        .accessibilityHidden(true)

                    Text(presentation.message)
                        .font(BodyFlowTypography.title)
                        .fontWeight(.semibold)
                        .foregroundStyle(BodyFlowColor.primaryText)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

                    VStack(spacing: BodyFlowSpacing.sm) {
                        ForEach(presentation.actions, id: \.self) { action in
                            boundedAction(action)
                        }
                    }
                }
                .padding(.horizontal, BodyFlowSpacing.lg)
                .padding(.vertical, BodyFlowSpacing.xl)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func boundedAction(
        _ action: ContentDetailBoundedAction
    ) -> some View {
        Button(action == .back ? "Voltar" : "Biblioteca") {
            switch action {
            case .back:
                dismiss()
            case .library:
                router.popToRoot(in: .today)
                router.navigate(
                    to: .content(.library(initialSelection: .all)),
                    in: .today
                )
            }
        }
        .font(BodyFlowTypography.headline)
        .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
        .contentShape(Rectangle())
    }
}
