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
    let name: String
    let doseText: String?
    let occurrenceStatuses: [String]
}

@MainActor
struct TodayRoutineSectionView: View {
    let collections: [TodayRoutineCollectionDescriptor]

    var body: some View {
        BodyFlowCard {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                Label("Rotina", systemImage: "checklist")
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
            Text(collection.kind.title)
                .font(BodyFlowTypography.body)
                .fontWeight(.semibold)
                .foregroundStyle(BodyFlowColor.primaryText)

            switch collection.state {
            case .unavailable:
                Label("Indisponível", systemImage: "nosign")
                    .font(BodyFlowTypography.body)
                    .foregroundStyle(BodyFlowColor.secondaryText)
            case .empty:
                Label(collection.kind.emptyMessage, systemImage: "tray")
                    .font(BodyFlowTypography.body)
                    .foregroundStyle(BodyFlowColor.secondaryText)
            case .populated:
                ForEach(collection.items) { routine in
                    routineContent(routine)
                }
            }
        }
    }

    private func routineContent(_ routine: TodayRoutineDescriptor) -> some View {
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
                Label(status, systemImage: statusIcon(status))
                    .font(BodyFlowTypography.callout)
                    .foregroundStyle(BodyFlowColor.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
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
