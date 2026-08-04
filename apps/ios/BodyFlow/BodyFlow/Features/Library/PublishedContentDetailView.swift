import SwiftUI

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

@MainActor
struct PublishedContentDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @State private var model: ContentDetailViewModel
    @State private var retryRequest: ContentDetailRetryRequest?
    @State private var retrySequence = 0

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
        _model = State(initialValue: ContentDetailViewModel(
            publicationID: publicationID,
            origin: origin,
            detailProvider: detailProvider,
            stateRecorder: stateRecorder,
            markdownParser: BodyFlowMarkdownParser(),
            keyProvider: keyProvider,
            timeProvider: timeProvider,
            invalidationCenter: invalidationCenter,
            coverLoader: coverLoader
        ))
    }

    var body: some View {
        Group {
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
        .accessibilityIdentifier("screen.content-detail.\(publicationID)")
        .task(id: detailRevision) {
            await model.load(revision: detailRevision)
        }
        .task(id: retryRequest) {
            guard let retryRequest else { return }
            await model.retry(revision: retryRequest.revision)
        }
    }

    private var detailRevision: Int {
        invalidationCenter.revision(for: .contentDetail(publicationID))
    }

    private func retry() {
        let request = ContentDetailRetryRequestPolicy.next(
            revision: detailRevision,
            previousSequence: retrySequence
        )
        retrySequence = request.sequence
        retryRequest = request
    }

    private func article(
        _ detail: RenderablePublishedContentDetail
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                Text(detail.title)
                    .font(BodyFlowTypography.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(BodyFlowColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

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

                Divider()

                BodyFlowMarkdownView(document: detail.document)
            }
            .padding(.horizontal, BodyFlowSpacing.lg)
            .padding(.vertical, BodyFlowSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
