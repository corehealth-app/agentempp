import SwiftUI

enum TodayRecommendationsSectionState: Equatable, Sendable {
    case loading, cards, empty, offline, failed, unavailable
}

struct TodayRecommendationsLibraryAction: Equatable, Sendable {
    let title: String
    let route: ContentRoute = .library(initialSelection: .all)

    init(language: SupportedAppLanguage = .portugueseBrazil) {
        title = TodayCopy.string(
            "today.recommendations.library",
            language: language
        )
    }
}

struct TodayRecommendationsPresentation: Equatable, Sendable {
    static var heading: String { heading(for: .portugueseBrazil) }
    static var emptyCopy: String { emptyCopy(for: .portugueseBrazil) }
    static var unavailableCopy: String {
        unavailableCopy(for: .portugueseBrazil)
    }
    let sectionState: TodayRecommendationsSectionState
    let cards: [PublishedContentSummary]
    let showsStaleDisclosure: Bool
    let showsRetry: Bool
    let libraryAction: TodayRecommendationsLibraryAction

    init(
        state: FeatureReadState<PublishedContentFeed>,
        language: SupportedAppLanguage = .portugueseBrazil
    ) {
        cards = Array(state.presentation.value?.items.prefix(3) ?? [])
        showsStaleDisclosure = cards.isEmpty == false && state.presentation.showsStaleBanner
        showsRetry = showsStaleDisclosure || cards.isEmpty && state != .unavailable
        libraryAction = TodayRecommendationsLibraryAction(language: language)
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

    static func heading(for language: SupportedAppLanguage) -> String {
        TodayCopy.string("today.recommendations.heading", language: language)
    }

    static func emptyCopy(for language: SupportedAppLanguage) -> String {
        TodayCopy.string("today.recommendations.empty", language: language)
    }

    static func unavailableCopy(
        for language: SupportedAppLanguage
    ) -> String {
        TodayCopy.string(
            "today.recommendations.unavailable",
            language: language
        )
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
    @Environment(\.locale) private var locale

    var body: some View {
        let presentation = TodayRecommendationsPresentation(
            state: model.state,
            language: language
        )
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            BodyFlowSectionHeader(
                TodayRecommendationsPresentation.heading(for: language),
                symbol: .library
            )

            sectionContent(presentation)

            NavigationLink(value: AppRoute.content(presentation.libraryAction.route)) {
                HStack(spacing: BodyFlowSpacing.xs) {
                    Label(verbatim: presentation.libraryAction.title, symbol: .library)
                        .font(BodyFlowTypography.headline)
                    Image(symbol: .chevron)
                        .font(BodyFlowTypography.caption)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(BodyFlowColor.accent)
                .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.bodyFlowRow)
            .accessibilityIdentifier("today.recommendations.library")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.recommendations")
    }

    @ViewBuilder
    private func sectionContent(_ presentation: TodayRecommendationsPresentation) -> some View {
        switch presentation.sectionState {
        case .loading:
            // A card-shaped placeholder (no values, hidden from VoiceOver)
            // holds the space the first recommendation will take, so the
            // section does not jump when it arrives.
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                loadingPlaceholder
                    .accessibilityHidden(true)
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: BodyFlowSpacing.minimumTapTarget)
                    .accessibilityIdentifier("today.recommendations.loading")
            }
        case .empty:
            Text(TodayRecommendationsPresentation.emptyCopy(for: language))
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.secondaryText)
        case .cards:
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                if presentation.showsStaleDisclosure { StaleDataBanner() }
                recommendationCards(presentation.cards)
                if presentation.showsRetry { retryButton }
            }
        case .offline:
            recoverableState(copy("today.recommendations.offline"), kind: .warning)
        case .failed:
            recoverableState(copy("today.recommendations.error"), kind: .error)
        case .unavailable:
            BodyFlowStatusLine(
                TodayRecommendationsPresentation.unavailableCopy(for: language),
                kind: .unavailable,
                font: BodyFlowTypography.body
            )
            .accessibilityIdentifier("today.recommendations.unavailable")
        }
    }

    private var loadingPlaceholder: some View {
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

    private func recoverableState(
        _ message: String,
        kind: BodyFlowStatusLine.Kind
    ) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            BodyFlowStatusLine(message, kind: kind, font: BodyFlowTypography.body)
            retryButton
        }
    }

    private var retryButton: some View {
        Button {
            Task { await model.retry() }
        } label: {
            Text(copy("state.retry"))
        }
        .buttonStyle(BodyFlowButtonStyle(role: .secondary))
        .accessibilityIdentifier("today.recommendations.retry")
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        TodayCopy.string(key, language: language)
    }
}

@MainActor
private struct TodayRecommendationCard: View {
    let presentation: TodayRecommendationsCardPresentation
    let model: TodayRecommendationsViewModel
    let catalogRevision: Int

    @State private var isVisible = false
    @Environment(\.locale) private var locale

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
                        verbatim: readingTime(presentation.summary),
                        symbol: .clock
                    )
                    .font(BodyFlowTypography.callout)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.bodyFlowRow)
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

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        TodayCopy.string(key, language: language)
    }

    private func readingTime(_ summary: PublishedContentSummary) -> String {
        String(
            format: copy("library.reading-time-format"),
            locale: language.formattingLocale,
            summary.readingTimeMinutes
        )
    }
}
