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

    var body: some View {
        BodyFlowCard {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                Label(copy("today.routine.title"), systemImage: "checklist")
                    .font(BodyFlowTypography.headline)
                    .foregroundStyle(BodyFlowColor.primaryText)

                ForEach(collections) { collection in
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
            Text(collectionTitle(collection.kind))
                .font(BodyFlowTypography.body)
                .fontWeight(.semibold)
                .foregroundStyle(BodyFlowColor.primaryText)

            NavigationLink(value: AppRoute.routine(RoutineRoute(
                kind: collection.kind.routineKind,
                destination: .list
            ))) {
                Label(copy("today.routine.view-list"), systemImage: "list.bullet")
                    .font(BodyFlowTypography.callout)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("routine.list.\(collection.kind.routineKind.rawValue)")
            .frame(minHeight: BodyFlowSpacing.minimumTapTarget)

            switch collection.state {
            case .unavailable:
                Label(copy("common.not-available"), systemImage: "nosign")
                    .font(BodyFlowTypography.body)
                    .foregroundStyle(BodyFlowColor.secondaryText)
            case .empty:
                Label(emptyMessage(collection.kind), systemImage: "tray")
                    .font(BodyFlowTypography.body)
                    .foregroundStyle(BodyFlowColor.secondaryText)
            case .populated:
                ForEach(collection.items) { routine in
                    routineContent(routine)
                }
            }
        }
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
                    RoutineCopy.status(status, language: language),
                    systemImage: statusIcon(status)
                )
                    .font(BodyFlowTypography.callout)
                    .foregroundStyle(BodyFlowColor.secondaryText)
            }
        }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("routine.\(routine.id)")
    }

    private func statusIcon(_ status: String) -> String {
        switch status {
        case "taken":
            "checkmark.circle"
        case "skipped":
            "forward.circle"
        case "snoozed":
            "clock.badge"
        default:
            "clock"
        }
    }
}
