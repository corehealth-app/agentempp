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

@MainActor
@Observable
final class ContentDetailViewModel {
    private struct PendingOpenedDispatch {
        let owner: ContentDetailLoadInvocationToken
        let detail: RenderablePublishedContentDetail
        let attempt: MutationAttempt<ContentReadCommand>
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

    private(set) var state: FeatureReadState<RenderablePublishedContentDetail> = .idle
    private(set) var openedEventState: ContentOpenedEventState = .idle

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
            attempt: attempt
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
            reconcile(
                response.data,
                openedDetail: pendingOpenedDispatch.detail
            )
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
