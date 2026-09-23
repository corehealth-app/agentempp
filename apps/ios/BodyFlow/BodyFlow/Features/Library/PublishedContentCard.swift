import SwiftUI

extension ContentCategory {
    var libraryDisplayName: String {
        libraryDisplayName(for: .portugueseBrazil)
    }

    func libraryDisplayName(for language: SupportedAppLanguage) -> String {
        let key: String.LocalizationValue = switch self {
        case .weightLoss: "library.category.weight-loss"
        case .hypertrophy: "library.category.hypertrophy"
        case .nutrition: "library.category.nutrition"
        case .training: "library.category.training"
        case .neuroscience: "library.category.neuroscience"
        case .habitFormation: "library.category.habit-formation"
        case .cardiovascularHealth: "library.category.cardiovascular-health"
        case .hydration: "library.category.hydration"
        case .supplementation: "library.category.supplementation"
        case .sleep: "library.category.sleep"
        case .usingBodyFlow: "library.category.using-performe-ai"
        }
        return LibraryCopy.string(key, language: language)
    }

}

extension LibrarySelection {
    var title: String {
        title(for: .portugueseBrazil)
    }

    func title(for language: SupportedAppLanguage) -> String {
        switch self {
        case .all:
            LibraryCopy.string("library.filter.all", language: language)
        case .saved:
            LibraryCopy.string("library.filter.saved", language: language)
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .all:
            "library.selection.all"
        case .saved:
            "library.selection.saved"
        }
    }
}

enum LibraryEmptyMessage {
    static func message(
        selection: LibrarySelection,
        category: ContentCategory?,
        language: SupportedAppLanguage = .portugueseBrazil
    ) -> String {
        if category != nil {
            return LibraryCopy.string(
                "library.empty.category",
                language: language
            )
        }

        return switch selection {
        case .all:
            LibraryCopy.string("library.empty.all", language: language)
        case .saved:
            LibraryCopy.string("library.empty.saved", language: language)
        }
    }
}

struct LibraryCardPresentation: Equatable, Sendable, Identifiable {
    let publicationID: String
    let cover: PublishedContentCover?
    let title: String
    let excerpt: String
    let categoryLabel: String
    let readingTimeLabel: String
    let saved: Bool
    let completed: Bool

    init(
        summary: PublishedContentSummary,
        language: SupportedAppLanguage = .portugueseBrazil
    ) {
        publicationID = summary.publicationID
        cover = summary.cover
        title = summary.title
        excerpt = summary.excerpt
        categoryLabel = summary.category.libraryDisplayName(for: language)
        readingTimeLabel = String(
            format: LibraryCopy.string(
                "library.reading-time-format",
                language: language
            ),
            locale: language.formattingLocale,
            summary.readingTimeMinutes
        )
        saved = summary.saved
        completed = summary.completed
    }

    var id: String { publicationID }

    var route: ContentRoute {
        .detail(publicationID: publicationID, origin: .library)
    }

    var accessibilityIdentifier: String {
        "library.card.\(publicationID)"
    }
}

struct LibraryPresentation: Equatable, Sendable {
    let cards: [LibraryCardPresentation]
    let nextCursor: String?

    init(
        feed: PublishedContentFeed,
        language: SupportedAppLanguage = .portugueseBrazil
    ) {
        cards = feed.items.map {
            LibraryCardPresentation(summary: $0, language: language)
        }
        nextCursor = feed.nextCursor
    }
}

struct LibraryCardCoverInput: Equatable, Sendable {
    let publicationID: String
    let version: Int
    let cover: PublishedContentCover?

    init(
        summary: PublishedContentSummary,
        authorizedCover: PublishedContentCover?
    ) {
        publicationID = summary.publicationID
        version = summary.version
        cover = authorizedCover
    }
}

enum LibraryPagingAction: Equatable, Sendable {
    case none
    case loadMore
    case retryNextPage
    case reloadFirstPage
}

struct LibraryPagingPresentation: Equatable, Sendable {
    let action: LibraryPagingAction
    let showsProgress: Bool
    let accessibilityIdentifier: String?

    init(
        feed: PublishedContentFeed,
        state: PublishedContentNextPageState
    ) {
        switch state {
        case .idle:
            action = feed.nextCursor == nil ? .none : .loadMore
            showsProgress = false
            accessibilityIdentifier = feed.nextCursor == nil
                ? nil
                : "library.load-more"
        case .loading:
            action = .none
            showsProgress = true
            accessibilityIdentifier = nil
        case .failed:
            action = .retryNextPage
            showsProgress = false
            accessibilityIdentifier = "state.retry-next-page"
        case .reloadFirstPageRequired:
            action = .reloadFirstPage
            showsProgress = false
            accessibilityIdentifier = "state.reload-first-page"
        }
    }
}

@MainActor
struct PublishedContentCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.refresh) private var refresh

    let presentation: LibraryCardPresentation
    let coverInput: LibraryCardCoverInput
    let requestedCoverRevision: Int
    let authorizedCoverRevision: Int?
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityCard
            } else {
                standardCard
            }
        }
    }

    private var standardCard: some View {
        NavigationLink(value: AppRoute.content(presentation.route)) {
            BodyFlowCard(surface: .card) {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                    cardContent
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.bodyFlowRow)
        .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(presentation.accessibilityIdentifier)
    }

    private var accessibilityCard: some View {
        BodyFlowCard(surface: .card) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                NavigationLink(value: AppRoute.content(presentation.route)) {
                    HStack(spacing: BodyFlowSpacing.xs) {
                        Text(copy("library.card.open"))
                            .font(BodyFlowTypography.headline)
                        Spacer(minLength: BodyFlowSpacing.sm)
                        Image(symbol: .chevron)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(BodyFlowColor.accent)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: BodyFlowSpacing.minimumTapTarget,
                        alignment: .leading
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.bodyFlowRow)
                .accessibilityLabel(String(
                    format: copy("library.card.open-format"),
                    locale: language.formattingLocale,
                    presentation.title
                ))
                .accessibilityIdentifier(presentation.accessibilityIdentifier)

                cardContent
            }
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        decorativeCover

        Text(presentation.title)
            .font(BodyFlowTypography.headline)
            .foregroundStyle(BodyFlowColor.primaryText)
            .fixedSize(horizontal: false, vertical: true)

        Text(presentation.excerpt)
            .font(BodyFlowTypography.body)
            .foregroundStyle(BodyFlowColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                categoryMetadata
                Spacer(minLength: BodyFlowSpacing.sm)
                readingTimeMetadata
            }
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                categoryMetadata
                readingTimeMetadata
            }
        }

        if presentation.saved || presentation.completed {
            statusRow
        }
    }

    private var decorativeCover: some View {
        ContentCoverView(
            publicationID: coverInput.publicationID,
            version: coverInput.version,
            cover: coverInput.cover,
            parentRevision: requestedCoverRevision,
            authorizedParentRevision: authorizedCoverRevision,
            onParentRevisionChanged: {},
            onCapabilityInvalidated: {
                await refreshParent()
            }
        )
    }

    private func refreshParent() async {
        if let refresh {
            await refresh()
        }
    }

    private var categoryMetadata: some View {
        Label(verbatim: presentation.categoryLabel, symbol: .library)
            .font(BodyFlowTypography.callout)
            .foregroundStyle(BodyFlowColor.secondaryText)
    }

    private var readingTimeMetadata: some View {
        Label(verbatim: presentation.readingTimeLabel, symbol: .clock)
            .font(BodyFlowTypography.callout)
            .foregroundStyle(BodyFlowColor.secondaryText)
    }

    private var statusRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: BodyFlowSpacing.md) {
                statusLabels
            }
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                statusLabels
            }
        }
        .font(BodyFlowTypography.callout)
        .foregroundStyle(BodyFlowColor.primaryText)
    }

    // Saved carries the brand color, completed the positive one; the text
    // names the state so the color is never the only channel.
    @ViewBuilder
    private var statusLabels: some View {
        if presentation.saved {
            LibraryStatusLabel(
                copy("library.status.saved"),
                symbol: .saved,
                tint: BodyFlowColor.accent
            )
        }
        if presentation.completed {
            LibraryStatusLabel(
                copy("library.status.completed"),
                symbol: .success,
                tint: BodyFlowColor.color(.feedbackPositive)
            )
        }
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        LibraryCopy.string(key, language: language)
    }
}

/// Saved / completed marker shared by the library card and the article:
/// resolved text with a tinted vocabulary glyph.
struct LibraryStatusLabel: View {
    private let title: String
    private let symbol: BodyFlowSymbol
    private let tint: Color

    init(_ title: String, symbol: BodyFlowSymbol, tint: Color) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        Label {
            Text(verbatim: title)
        } icon: {
            Image(symbol: symbol)
                .foregroundStyle(tint)
        }
    }
}
