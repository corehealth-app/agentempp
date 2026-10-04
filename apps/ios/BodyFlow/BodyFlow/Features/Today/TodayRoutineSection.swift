import SwiftUI

struct TodayRoutineCollectionDescriptor: Equatable, Sendable, Identifiable {
    enum Kind: String, Equatable, Sendable {
        case supplement = "Suplemento"
        case medication = "Medicamento"

        var title: String {
            switch self {
            case .supplement:
                "Suplementos"
            case .medication:
                "Medicamentos"
            }
        }

        var emptyMessage: String {
            switch self {
            case .supplement:
                "Nenhum suplemento registrado."
            case .medication:
                "Nenhum medicamento registrado."
            }
        }

        var routineKind: RoutineItemKind {
            switch self {
            case .supplement: .supplement
            case .medication: .medication
            }
        }
    }

    enum State: Equatable, Sendable {
        case unavailable
        case empty
        case populated
    }

    var id: Kind { kind }

    let kind: Kind
    let state: State
    let items: [TodayRoutineDescriptor]
}

struct TodayRoutineDescriptor: Equatable, Sendable, Identifiable {
    let id: String
    let kind: RoutineItemKind
    let name: String
    let doseText: String?
    let occurrenceStatuses: [String]
}

@MainActor
struct TodayRoutineSectionView: View {
    let collections: [TodayRoutineCollectionDescriptor]
    @Environment(\.locale) private var locale

    // One section heading, then one card per collection whose heading row
    // carries the "view list" link; the rows are the tappable routine items.
    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            BodyFlowSectionHeader(copy("today.routine.title"), symbol: .routine)

            ForEach(collections) { collection in
                BodyFlowCard {
                    collectionContent(collection)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.routines")
    }

    @ViewBuilder
    private func collectionContent(
        _ collection: TodayRoutineCollectionDescriptor
    ) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            // Title and list link share the row while both fit; the link
            // drops below the title at accessibility sizes.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: BodyFlowSpacing.sm) {
                    collectionTitleLabel(collection.kind)
                    Spacer(minLength: BodyFlowSpacing.sm)
                    viewListLink(collection.kind)
                }
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    collectionTitleLabel(collection.kind)
                    viewListLink(collection.kind)
                }
            }

            switch collection.state {
            case .unavailable:
                BodyFlowStatusLine(
                    copy("common.not-available"),
                    kind: .unavailable,
                    font: BodyFlowTypography.body
                )
            case .empty:
                BodyFlowStatusLine(
                    emptyMessage(collection.kind),
                    kind: .empty,
                    font: BodyFlowTypography.body
                )
            case .populated:
                ForEach(collection.items) { routine in
                    routineContent(routine)
                }
            }
        }
    }

    private func collectionTitleLabel(
        _ kind: TodayRoutineCollectionDescriptor.Kind
    ) -> some View {
        Text(collectionTitle(kind))
            .font(BodyFlowTypography.cardTitle)
            .foregroundStyle(BodyFlowColor.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("today.routine.header.\(kind.routineKind.rawValue)")
    }

    private func viewListLink(
        _ kind: TodayRoutineCollectionDescriptor.Kind
    ) -> some View {
        NavigationLink(value: AppRoute.routine(RoutineRoute(
            kind: kind.routineKind,
            destination: .list
        ))) {
            HStack(spacing: BodyFlowSpacing.xs) {
                Label(verbatim: copy("today.routine.view-list"), symbol: .list)
                    .font(BodyFlowTypography.callout)
                Image(symbol: .chevron)
                    .font(BodyFlowTypography.caption)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(BodyFlowColor.accent)
            // +1: a fractional layout offset must never round the target under 44 pt.
            .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bodyFlowRow)
        .accessibilityIdentifier("routine.list.\(kind.routineKind.rawValue)")
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        TodayCopy.string(key, language: language)
    }

    private func collectionTitle(
        _ kind: TodayRoutineCollectionDescriptor.Kind
    ) -> String {
        switch kind {
        case .supplement: copy("today.routine.supplements")
        case .medication: copy("today.routine.medications")
        }
    }

    private func emptyMessage(
        _ kind: TodayRoutineCollectionDescriptor.Kind
    ) -> String {
        switch kind {
        case .supplement: copy("today.routine.supplements.empty")
        case .medication: copy("today.routine.medications.empty")
        }
    }

    private func routineContent(_ routine: TodayRoutineDescriptor) -> some View {
        NavigationLink(value: AppRoute.routine(RoutineRoute(
            kind: routine.kind,
            itemID: routine.id,
            destination: .detail
        ))) {
            HStack(alignment: .center, spacing: BodyFlowSpacing.sm) {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                    Text(routine.name)
                        .font(BodyFlowTypography.body)
                        .foregroundStyle(BodyFlowColor.primaryText)
                    if let doseText = routine.doseText,
                       !doseText.isEmpty {
                        Text(doseText)
                            .font(BodyFlowTypography.callout)
                            .foregroundStyle(BodyFlowColor.secondaryText)
                    }
                    ForEach(
                        Array(routine.occurrenceStatuses.enumerated()),
                        id: \.offset
                    ) { _, status in
                        Label(
                            verbatim: RoutineCopy.status(status, language: language),
                            symbol: statusSymbol(status)
                        )
                            .font(BodyFlowTypography.callout)
                            .foregroundStyle(BodyFlowColor.secondaryText)
                    }
                }
                Spacer(minLength: BodyFlowSpacing.xs)
                Image(symbol: .chevron)
                    .font(BodyFlowTypography.caption)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: BodyFlowSpacing.minimumTapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bodyFlowRow)
        .accessibilityIdentifier("routine.\(routine.id)")
    }

    private func statusSymbol(_ status: String) -> BodyFlowSymbol {
        switch status {
        case "taken":
            .success
        case "skipped":
            .skipped
        case "snoozed":
            .snoozed
        default:
            .clock
        }
    }
}
