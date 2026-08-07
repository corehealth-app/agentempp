import SwiftUI

enum TodayRecommendationsSectionState: Equatable, Sendable {
    case loading, cards, empty, offline, failed, unavailable
}

struct TodayRecommendationsLibraryAction: Equatable, Sendable {
    let title = "Ver biblioteca"
    let route: ContentRoute = .library(initialSelection: .all)
}

struct TodayRecommendationsPresentation: Equatable, Sendable {
    static let heading = "Conteúdos para hoje"
    static let emptyCopy = "Nenhum conteúdo selecionado para hoje"
    static let unavailableCopy = "Indisponível nesta versão"
    let sectionState: TodayRecommendationsSectionState
    let cards: [PublishedContentSummary]
    let showsStaleDisclosure: Bool
    let showsRetry: Bool
    let libraryAction = TodayRecommendationsLibraryAction()

    init(state: FeatureReadState<PublishedContentFeed>) {
        cards = Array(state.presentation.value?.items.prefix(3) ?? [])
        showsStaleDisclosure = cards.isEmpty == false && state.presentation.showsStaleBanner
        showsRetry = showsStaleDisclosure || cards.isEmpty && state != .unavailable
        sectionState = switch state {
        case .idle, .loading: .loading
        case .empty: .empty
        case .loaded: .cards
        case .offline(previousValue: .some), .failed(previousValue: .some, error: _): .cards
        case .offline(previousValue: nil): .offline
        case .failed(previousValue: nil, error: _): .failed
        case .unavailable: .unavailable
        }
    }
}

struct TodayRecommendationsCardPresentation: Equatable, Sendable {
    let summary: PublishedContentSummary

    var route: ContentRoute {
        .detail(publicationID: summary.publicationID, origin: .today)
    }
}

enum TodayRecommendationInteraction {
    static func visibilityRequest(
        isVisible: Bool,
        summary: PublishedContentSummary
    ) -> LibraryVisibilityRequest? {
        LibraryCardVisibilityPolicy.request(
            isVisible: isVisible,
            publicationID: summary.publicationID,
            version: summary.version
        )
    }
}

@MainActor
struct TodayRecommendationsSection: View {
    let model: TodayRecommendationsViewModel
    let catalogRevision: Int

    var body: some View {
        let presentation = TodayRecommendationsPresentation(state: model.state)
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            Text(TodayRecommendationsPresentation.heading)
                .font(BodyFlowTypography.title)
                .foregroundStyle(BodyFlowColor.primaryText)

            sectionContent(presentation)

            NavigationLink(value: AppRoute.content(presentation.libraryAction.route)) {
                Label(presentation.libraryAction.title, systemImage: "books.vertical")
                    .font(BodyFlowTypography.headline)
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today.recommendations.library")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.recommendations")
    }

    @ViewBuilder
    private func sectionContent(_ presentation: TodayRecommendationsPresentation) -> some View {
        switch presentation.sectionState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: BodyFlowSpacing.minimumTapTarget)
                .accessibilityIdentifier("today.recommendations.loading")
        case .empty:
            Text(TodayRecommendationsPresentation.emptyCopy)
        case .cards:
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                if presentation.showsStaleDisclosure { StaleDataBanner() }
                recommendationCards(presentation.cards)
                if presentation.showsRetry { retryButton }
            }
        case .offline:
            recoverableState("Sem conexão para carregar conteúdos.")
        case .failed:
            recoverableState("Não foi possível carregar conteúdos agora.")
        case .unavailable:
            Text(TodayRecommendationsPresentation.unavailableCopy)
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.secondaryText)
                .accessibilityIdentifier("today.recommendations.unavailable")
        }
    }

    private func recommendationCards(_ cards: [PublishedContentSummary]) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            ForEach(cards) { summary in
                TodayRecommendationCard(
                    presentation: TodayRecommendationsCardPresentation(
                        summary: summary
                    ),
                    model: model,
                    catalogRevision: catalogRevision
                )
            }
        }
    }

    private func recoverableState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Text(message)
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.secondaryText)
            retryButton
        }
    }

    private var retryButton: some View {
        Button {
            Task { await model.retry() }
        } label: {
            Text("Tentar novamente")
                .font(BodyFlowTypography.headline)
                .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("today.recommendations.retry")
    }
}

@MainActor
private struct TodayRecommendationCard: View {
    let presentation: TodayRecommendationsCardPresentation
    let model: TodayRecommendationsViewModel
    let catalogRevision: Int

    @State private var isVisible = false

    var body: some View {
        NavigationLink(value: AppRoute.content(presentation.route)) {
            BodyFlowCard {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                    ContentCoverView(
                        publicationID: presentation.summary.publicationID,
                        version: presentation.summary.version,
                        cover: model.coverAuthorization(
                            for: presentation.summary,
                            catalogRevision: catalogRevision
                        )?.cover,
                        parentRevision: catalogRevision,
                        authorizedParentRevision: model.coverAuthorization(
                            for: presentation.summary,
                            catalogRevision: catalogRevision
                        )?.revision,
                        onParentRevisionChanged: {},
                        onCapabilityInvalidated: {}
                    )

                    Text(presentation.summary.title)
                        .font(BodyFlowTypography.headline)
                        .foregroundStyle(BodyFlowColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(presentation.summary.excerpt)
                        .font(BodyFlowTypography.body)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(
                        "\(presentation.summary.readingTimeMinutes) min de leitura",
                        systemImage: "clock"
                    )
                    .font(BodyFlowTypography.callout)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(
            "today.recommendations.card.\(presentation.summary.publicationID)"
        )
        .onScrollVisibilityChange(threshold: LibraryCardVisibilityPolicy.threshold) {
            isVisible = $0
        }
        .task(id: visibilityRequest) {
            guard visibilityRequest != nil else { return }
            await model.recordImpression(for: presentation.summary)
        }
    }

    private var visibilityRequest: LibraryVisibilityRequest? {
        TodayRecommendationInteraction.visibilityRequest(
            isVisible: isVisible,
            summary: presentation.summary
        )
    }
}
