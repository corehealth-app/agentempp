import Observation

struct RenderablePublishedContentDetail: Equatable, Sendable {
    let publicationID: String
    let version: Int
    let title: String
    let categoryLabel: String
    let readingTimeLabel: String
    let saved: Bool
    let completed: Bool
    let document: BodyFlowMarkdownDocument

    func reconciling(_ state: PublishedContentState) -> Self {
        Self(
            publicationID: publicationID,
            version: version,
            title: title,
            categoryLabel: categoryLabel,
            readingTimeLabel: readingTimeLabel,
            saved: state.saved,
            completed: state.completed,
            document: document
        )
    }
}

enum ContentOpenedEventState: Equatable, Sendable {
    case idle
    case submitting
    case succeeded
    case failed(BodyFlowCapabilityError)
}

struct ContentDetailLoadInvocationToken: Equatable, Hashable, Sendable {
    let sequence: UInt64
}

struct ContentDetailOpenedDispatchOwnership: Equatable, Sendable {
    private(set) var pendingOwner: ContentDetailLoadInvocationToken?

    mutating func registerPending(owner: ContentDetailLoadInvocationToken) {
        pendingOwner = owner
    }

    mutating func claimPending(
        for invocation: ContentDetailLoadInvocationToken
    ) -> Bool {
        guard pendingOwner == invocation else { return false }
        pendingOwner = nil
        return true
    }

    mutating func discardPending(
        for invocation: ContentDetailLoadInvocationToken
    ) {
        guard pendingOwner == invocation else { return }
        pendingOwner = nil
    }
}

enum ContentDetailBoundedAction: Equatable, Hashable, Sendable {
    case back
    case library
}

struct ContentDetailBoundedPresentation: Equatable, Sendable {
    let message: String
    let actions: [ContentDetailBoundedAction]
}

enum ContentDetailMutationAttempt: Equatable, Sendable {
    case save(MutationAttempt<ContentSaveCommand>)
    case completion(MutationAttempt<ContentReadCommand>)

    var publicationID: String {
        switch self {
        case let .save(attempt): attempt.payload.publicationID
        case let .completion(attempt): attempt.payload.publicationID
        }
    }

    var version: Int {
        switch self {
        case let .save(attempt): attempt.payload.body.version
        case let .completion(attempt): attempt.payload.body.version
        }
    }
}

typealias ContentDetailMutationState = FeatureMutationState<
    ContentDetailMutationAttempt,
    PublishedContentStateResponse
>

enum ContentDetailAccessibilityFocusTarget: Hashable, Sendable {
    case mutationSummary
    case articleHeading
}

struct ContentDetailAccessibilityFocusEvent: Equatable, Sendable {
    let sequence: UInt64
    let target: ContentDetailAccessibilityFocusTarget
}

struct ContentMutationPresentation: Equatable, Sendable {
    let message: String
    let systemImage: String
    let allowsRetry: Bool
}

private enum ContentDetailMutationIntent: Equatable, Sendable {
    case save(Bool)
    case completion
}

@MainActor
@Observable
final class ContentDetailViewModel {
    private struct PendingOpenedDispatch {
        let owner: ContentDetailLoadInvocationToken
        let detail: RenderablePublishedContentDetail
        let attempt: MutationAttempt<ContentReadCommand>
        let canonicalMutationGeneration: UInt64
    }

    private let publicationID: String
    private let origin: ContentOrigin
    private let detailProvider: any PublishedContentDetailProviding
    private let stateRecorder: any PublishedContentStateRecording
    private let markdownParser: any BodyFlowMarkdownParsing
    private let keyProvider: any IdempotencyKeyProviding
    private let timeProvider: any TimeProviding
    private let invalidationCenter: FeatureInvalidationCenter
    private let coverLoader: any ContentCoverLoading
    private let loadController = FeatureRevisionLoadController<
        RenderablePublishedContentDetail
    >()

    private var currentDetail: RenderablePublishedContentDetail?
    private var openedAttempted = false
    private var invocationSequence: UInt64 = 0
    private var openedDispatchOwnership = ContentDetailOpenedDispatchOwnership()
    private var pendingOpenedDispatch: PendingOpenedDispatch?
    private var conflictAwaitingReload = false
    private var contentMutationClaimed = false
    private var canonicalMutationGeneration: UInt64 = 0
    private var contentMutationIntent: ContentDetailMutationIntent?
    private var accessibilityFocusSequence: UInt64 = 0

    private(set) var state: FeatureReadState<RenderablePublishedContentDetail> = .idle
    private(set) var openedEventState: ContentOpenedEventState = .idle
    private(set) var contentMutationState = ContentDetailMutationState.idle
    private(set) var accessibilityFocusEvent: ContentDetailAccessibilityFocusEvent?

    init(
        publicationID: String,
        origin: ContentOrigin,
        detailProvider: any PublishedContentDetailProviding,
        stateRecorder: any PublishedContentStateRecording,
        markdownParser: any BodyFlowMarkdownParsing,
        keyProvider: any IdempotencyKeyProviding,
        timeProvider: any TimeProviding,
        invalidationCenter: FeatureInvalidationCenter,
        coverLoader: any ContentCoverLoading
    ) {
        self.publicationID = publicationID
        self.origin = origin
        self.detailProvider = detailProvider
        self.stateRecorder = stateRecorder
        self.markdownParser = markdownParser
        self.keyProvider = keyProvider
        self.timeProvider = timeProvider
        self.invalidationCenter = invalidationCenter
        self.coverLoader = coverLoader
    }

    var boundedPresentation: ContentDetailBoundedPresentation? {
        guard case let .failed(_, error) = state else { return nil }
        return switch error {
        case .contentNotFound:
            ContentDetailBoundedPresentation(
                message: "Este conteúdo não está mais disponível",
                actions: [.back, .library]
            )
        case .subscriptionRequired:
            ContentDetailBoundedPresentation(
                message: "Conteúdo indisponível para sua assinatura atual",
                actions: [.back]
            )
        default:
            nil
        }
    }

    var isContentMutationSubmitting: Bool {
        contentMutationClaimed || conflictAwaitingReload
    }

    var accessibilityFocusTarget: ContentDetailAccessibilityFocusTarget? {
        accessibilityFocusEvent?.target
    }

    var canToggleSaved: Bool {
        currentDetail != nil && !isContentMutationSubmitting
    }

    var showsCompletionAction: Bool {
        currentDetail?.completed == false
    }

    var canComplete: Bool {
        showsCompletionAction && !isContentMutationSubmitting
    }

    var canRetryContentMutation: Bool {
        guard !conflictAwaitingReload,
              case .failed = contentMutationState else { return false }
        return true
    }

    var contentMutationPresentation: ContentMutationPresentation? {
        switch contentMutationState {
        case .idle:
            nil
        case .submitting:
            ContentMutationPresentation(
                message: "Atualizando conteúdo…",
                systemImage: "arrow.triangle.2.circlepath",
                allowsRetry: false
            )
        case let .succeeded(response):
            switch contentMutationIntent {
            case .save:
                ContentMutationPresentation(
                    message: response.data.saved
                        ? "Conteúdo salvo"
                        : "Conteúdo removido dos salvos",
                    systemImage: response.data.saved
                        ? "bookmark.fill"
                        : "bookmark.slash",
                    allowsRetry: false
                )
            case .completion:
                ContentMutationPresentation(
                    message: "Conteúdo concluído",
                    systemImage: "checkmark.circle.fill",
                    allowsRetry: false
                )
            case nil:
                nil
            }
        case let .failed(_, error):
            if error == .contentVersionChanged {
                ContentMutationPresentation(
                    message: "O conteúdo foi atualizado. Recarregando…",
                    systemImage: "arrow.clockwise",
                    allowsRetry: false
                )
            } else {
                ContentMutationPresentation(
                    message: "Não foi possível atualizar. Tente novamente.",
                    systemImage: "exclamationmark.triangle",
                    allowsRetry: canRetryContentMutation
                )
            }
        case .unavailable:
            ContentMutationPresentation(
                message: "Ação indisponível nesta versão",
                systemImage: "exclamationmark.circle",
                allowsRetry: false
            )
        }
    }

    func load(revision: Int) async {
        guard !Task.isCancelled else { return }
        let invocation = nextInvocationToken()
        if currentDetail == nil {
            state = .loading
        }

        await loadController.load(
            revision: revision,
            operation: detailOperation(),
            publish: { [weak self] completion in
                self?.publish(completion, invocation: invocation)
            }
        )

        guard !Task.isCancelled else {
            discardPendingOpenedDispatch(ownedBy: invocation)
            return
        }
        await dispatchPendingOpenedIfOwned(by: invocation)
    }

    func retry(revision: Int) async {
        guard !Task.isCancelled else { return }
        let invocation = nextInvocationToken()
        if currentDetail == nil {
            state = .loading
        }

        await loadController.retry(
            revision: revision,
            operation: detailOperation(),
            publish: { [weak self] completion in
                self?.publish(completion, invocation: invocation)
            }
        )

        guard !Task.isCancelled else {
            discardPendingOpenedDispatch(ownedBy: invocation)
            return
        }
        await dispatchPendingOpenedIfOwned(by: invocation)
    }

    func toggleSaved() async {
        guard !Task.isCancelled,
              canToggleSaved,
              let detail = currentDetail,
              claimContentMutation() else { return }
        do {
            let attempt = MutationAttempt(
                operation: .contentSave,
                key: try keyProvider.nextKey(),
                payload: ContentSaveCommand(
                    publicationID: publicationID,
                    body: ContentSaveBody(
                        saved: !detail.saved,
                        version: detail.version
                    )
                ),
                createdAt: timeProvider.now
            )
            await runContentMutation(
                .save(attempt),
                intent: .save(attempt.payload.body.saved)
            )
        } catch {
            releaseContentMutationClaim()
            publishContentMutationConstructionFailure(error)
        }
    }

    func complete() async {
        guard !Task.isCancelled,
              canComplete,
              let detail = currentDetail,
              claimContentMutation() else { return }
        do {
            let attempt = MutationAttempt(
                operation: .contentRead,
                key: try keyProvider.nextKey(),
                payload: ContentReadCommand(
                    publicationID: publicationID,
                    body: ContentReadBody(
                        event: .completed,
                        origin: origin,
                        version: detail.version
                    )
                ),
                createdAt: timeProvider.now
            )
            await runContentMutation(.completion(attempt), intent: .completion)
        } catch {
            releaseContentMutationClaim()
            publishContentMutationConstructionFailure(error)
        }
    }

    func retryContentMutation() async {
        guard canRetryContentMutation,
              case let .failed(attempt, _) = contentMutationState,
              let contentMutationIntent,
              claimContentMutation() else { return }
        await runContentMutation(attempt, intent: contentMutationIntent)
    }

    func consumeAccessibilityFocus() {
        accessibilityFocusEvent = nil
    }

    func consumeAccessibilityFocus(
        _ event: ContentDetailAccessibilityFocusEvent
    ) {
        guard accessibilityFocusEvent == event else { return }
        accessibilityFocusEvent = nil
    }

    private func detailOperation() -> @Sendable () async throws
        -> RenderablePublishedContentDetail {
        let publicationID = publicationID
        let detailProvider = detailProvider
        let markdownParser = markdownParser

        return {
            let response = try await detailProvider.contentDetail(
                publicationID: publicationID
            )
            try PublishedContentContractValidator.validate(response.data)
            guard response.data.summary.publicationID == publicationID else {
                throw BodyFlowCapabilityError.invalidContentContract
            }
            let document = try markdownParser.parse(response.data.bodyMarkdown)
            let summary = response.data.summary
            return RenderablePublishedContentDetail(
                publicationID: summary.publicationID,
                version: summary.version,
                title: summary.title,
                categoryLabel: summary.category.libraryDisplayName,
                readingTimeLabel: "\(summary.readingTimeMinutes) min de leitura",
                saved: summary.saved,
                completed: summary.completed,
                document: document
            )
        }
    }

    private func publish(
        _ completion: FeatureLoadCompletion<RenderablePublishedContentDetail>,
        invocation: ContentDetailLoadInvocationToken
    ) {
        switch completion {
        case let .value(detail):
            currentDetail = detail
            state = .loaded(detail)
            prepareOpenedDispatch(for: detail, ownedBy: invocation)
            if conflictAwaitingReload {
                conflictAwaitingReload = false
                contentMutationState = .idle
                contentMutationIntent = nil
                publishAccessibilityFocus(.articleHeading)
            }
        case let .failure(error):
            state = Self.readState(for: error, previousValue: currentDetail)
        }
    }

    private func prepareOpenedDispatch(
        for detail: RenderablePublishedContentDetail,
        ownedBy invocation: ContentDetailLoadInvocationToken
    ) {
        guard !openedAttempted,
              openedDispatchOwnership.pendingOwner == nil else { return }
        let attempt: MutationAttempt<ContentReadCommand>
        do {
            attempt = MutationAttempt(
                operation: .contentRead,
                key: try keyProvider.nextKey(),
                payload: ContentReadCommand(
                    publicationID: publicationID,
                    body: ContentReadBody(
                        event: .opened,
                        origin: origin,
                        version: detail.version
                    )
                ),
                createdAt: timeProvider.now
            )
        } catch {
            openedAttempted = true
            openedEventState = .failed(Self.capabilityError(from: error))
            return
        }

        pendingOpenedDispatch = PendingOpenedDispatch(
            owner: invocation,
            detail: detail,
            attempt: attempt,
            canonicalMutationGeneration: canonicalMutationGeneration
        )
        openedDispatchOwnership.registerPending(owner: invocation)
    }

    private func dispatchPendingOpenedIfOwned(
        by invocation: ContentDetailLoadInvocationToken
    ) async {
        guard !Task.isCancelled,
              let pendingOpenedDispatch,
              pendingOpenedDispatch.owner == invocation,
              openedDispatchOwnership.claimPending(for: invocation) else {
            return
        }
        self.pendingOpenedDispatch = nil
        openedAttempted = true
        openedEventState = .submitting
        do {
            let response = try await stateRecorder.recordRead(
                pendingOpenedDispatch.attempt
            )
            guard !Task.isCancelled else { return }
            guard response.data.publicationID ==
                    pendingOpenedDispatch.detail.publicationID,
                  response.data.version == pendingOpenedDispatch.detail.version
            else {
                openedEventState = .failed(.invalidContentContract)
                return
            }
            if canonicalMutationGeneration ==
                pendingOpenedDispatch.canonicalMutationGeneration {
                reconcile(
                    response.data,
                    openedDetail: pendingOpenedDispatch.detail
                )
            }
            openedEventState = .succeeded
        } catch is CancellationError {
            return
        } catch BodyFlowCapabilityError.contentVersionChanged {
            openedEventState = .failed(.contentVersionChanged)
            await coverLoader.remove(
                publicationID: publicationID,
                version: pendingOpenedDispatch.detail.version
            )
            invalidationCenter.record(.contentVersionConflict(
                publicationID: publicationID
            ))
        } catch {
            openedEventState = .failed(Self.capabilityError(from: error))
        }
    }

    private func discardPendingOpenedDispatch(
        ownedBy invocation: ContentDetailLoadInvocationToken
    ) {
        openedDispatchOwnership.discardPending(for: invocation)
        guard pendingOpenedDispatch?.owner == invocation else { return }
        pendingOpenedDispatch = nil
    }

    private func nextInvocationToken() -> ContentDetailLoadInvocationToken {
        invocationSequence &+= 1
        return ContentDetailLoadInvocationToken(sequence: invocationSequence)
    }

    private func reconcile(
        _ canonicalState: PublishedContentState,
        openedDetail: RenderablePublishedContentDetail
    ) {
        guard canonicalState.publicationID == openedDetail.publicationID,
              canonicalState.version == openedDetail.version,
              currentDetail?.publicationID == openedDetail.publicationID,
              currentDetail?.version == openedDetail.version else {
            return
        }

        let reconciled = openedDetail.reconciling(canonicalState)
        currentDetail = reconciled
        state = .loaded(reconciled)
    }

    private func runContentMutation(
        _ attempt: ContentDetailMutationAttempt,
        intent: ContentDetailMutationIntent
    ) async {
        defer { releaseContentMutationClaim() }
        contentMutationIntent = intent
        contentMutationState = .submitting(attempt)
        accessibilityFocusEvent = nil

        do {
            let response: PublishedContentStateResponse
            switch attempt {
            case let .save(saveAttempt):
                response = try await stateRecorder.setSaved(saveAttempt)
            case let .completion(readAttempt):
                response = try await stateRecorder.recordRead(readAttempt)
            }
            guard !Task.isCancelled else {
                discardCancelledContentMutation()
                return
            }
            guard response.data.publicationID == attempt.publicationID,
                  response.data.version == attempt.version,
                  currentDetail?.publicationID == attempt.publicationID,
                  currentDetail?.version == attempt.version else {
                throw BodyFlowCapabilityError.invalidContentContract
            }
            if case .completion = attempt,
               !response.data.completed {
                throw BodyFlowCapabilityError.invalidContentContract
            }

            reconcileContentMutation(response.data)
            canonicalMutationGeneration &+= 1
            contentMutationState = .succeeded(response)
            switch intent {
            case .save:
                invalidationCenter.record(.contentSaved(
                    publicationID: attempt.publicationID
                ))
            case .completion:
                invalidationCenter.record(.contentCompleted(
                    publicationID: attempt.publicationID
                ))
            }
            publishAccessibilityFocus(.mutationSummary)
        } catch is CancellationError {
            discardCancelledContentMutation()
        } catch BodyFlowCapabilityError.contentVersionChanged {
            guard canPublishContentMutationOutcome else {
                discardCancelledContentMutation()
                return
            }
            contentMutationState = .failed(attempt, .contentVersionChanged)
            conflictAwaitingReload = true
            await coverLoader.remove(
                publicationID: attempt.publicationID,
                version: attempt.version
            )
            guard canPublishContentMutationOutcome else {
                discardCancelledContentMutation()
                return
            }
            invalidationCenter.record(.contentVersionConflict(
                publicationID: attempt.publicationID
            ))
            publishAccessibilityFocus(.mutationSummary)
        } catch {
            guard canPublishContentMutationOutcome else {
                discardCancelledContentMutation()
                return
            }
            let capabilityError = Self.capabilityError(from: error)
            contentMutationState = capabilityError == .operationUnavailable
                ? .unavailable
                : .failed(attempt, capabilityError)
            publishAccessibilityFocus(.mutationSummary)
        }
    }

    private func claimContentMutation() -> Bool {
        guard !contentMutationClaimed,
              !conflictAwaitingReload else { return false }
        contentMutationClaimed = true
        return true
    }

    private func releaseContentMutationClaim() {
        contentMutationClaimed = false
    }

    private var canPublishContentMutationOutcome: Bool {
        !Task.isCancelled && contentMutationClaimed
    }

    private func discardCancelledContentMutation() {
        guard contentMutationClaimed else { return }
        contentMutationState = .idle
        contentMutationIntent = nil
        conflictAwaitingReload = false
        accessibilityFocusEvent = nil
    }

    private func reconcileContentMutation(_ canonicalState: PublishedContentState) {
        guard let currentDetail,
              currentDetail.publicationID == canonicalState.publicationID,
              currentDetail.version == canonicalState.version else { return }
        let reconciled = currentDetail.reconciling(canonicalState)
        self.currentDetail = reconciled
        state = .loaded(reconciled)
    }

    private func publishContentMutationConstructionFailure(_ error: any Error) {
        contentMutationState = .unavailable
        publishAccessibilityFocus(.mutationSummary)
    }

    private func publishAccessibilityFocus(
        _ target: ContentDetailAccessibilityFocusTarget
    ) {
        accessibilityFocusSequence &+= 1
        accessibilityFocusEvent = ContentDetailAccessibilityFocusEvent(
            sequence: accessibilityFocusSequence,
            target: target
        )
    }

    nonisolated private static func readState(
        for error: any Error,
        previousValue: RenderablePublishedContentDetail?
    ) -> FeatureReadState<RenderablePublishedContentDetail> {
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
