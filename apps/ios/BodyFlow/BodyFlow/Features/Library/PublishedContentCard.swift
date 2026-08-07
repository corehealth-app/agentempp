import SwiftUI

extension ContentCategory {
    var libraryDisplayName: String {
        switch self {
        case .weightLoss:
            "Emagrecimento"
        case .hypertrophy:
            "Hipertrofia"
        case .nutrition:
            "Nutrição"
        case .training:
            "Treino"
        case .neuroscience:
            "Neurociência"
        case .habitFormation:
            "Formação de hábitos"
        case .cardiovascularHealth:
            "Saúde cardiovascular"
        case .hydration:
            "Hidratação"
        case .supplementation:
            "Suplementação"
        case .sleep:
            "Sono"
        case .usingBodyFlow:
            "Uso do BodyFlow"
        }
    }
}

extension LibrarySelection {
    var title: String {
        switch self {
        case .all:
            "Todos"
        case .saved:
            "Salvos"
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
        category: ContentCategory?
    ) -> String {
        if category != nil {
            return "Nenhum conteúdo disponível nesta categoria."
        }

        return switch selection {
        case .all:
            "Nenhum conteúdo publicado está disponível para você agora."
        case .saved:
            "Você ainda não tem conteúdos salvos disponíveis."
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

    init(summary: PublishedContentSummary) {
        publicationID = summary.publicationID
        cover = summary.cover
        title = summary.title
        excerpt = summary.excerpt
        categoryLabel = summary.category.libraryDisplayName
        readingTimeLabel = "\(summary.readingTimeMinutes) min de leitura"
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

    init(feed: PublishedContentFeed) {
        cards = feed.items.map(LibraryCardPresentation.init)
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
            BodyFlowCard {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                    cardContent
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(presentation.accessibilityIdentifier)
    }

    private var accessibilityCard: some View {
        BodyFlowCard {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                NavigationLink(value: AppRoute.content(presentation.route)) {
                    HStack(spacing: BodyFlowSpacing.xs) {
                        Text("Abrir conteúdo")
                            .font(BodyFlowTypography.headline)
                        Spacer(minLength: BodyFlowSpacing.sm)
                        Image(systemName: "chevron.right")
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
                .buttonStyle(.plain)
                .accessibilityLabel("Abrir \(presentation.title)")
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
        Label(presentation.categoryLabel, systemImage: "books.vertical")
            .font(BodyFlowTypography.callout)
            .foregroundStyle(BodyFlowColor.secondaryText)
    }

    private var readingTimeMetadata: some View {
        Label(presentation.readingTimeLabel, systemImage: "clock")
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

    @ViewBuilder
    private var statusLabels: some View {
        if presentation.saved {
            Label("Salvo", systemImage: "bookmark.fill")
        }
        if presentation.completed {
            Label("Concluído", systemImage: "checkmark.circle.fill")
        }
    }
}
