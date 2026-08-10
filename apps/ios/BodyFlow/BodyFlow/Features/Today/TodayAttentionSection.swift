import SwiftUI

enum TodaySectionKind: Equatable, Sendable {
    case attention
    case pending
    case energy
    case protein
    case meals
    case workouts
    case hydration
    case routines
    case block
    case history
}

struct TodayPendingDescriptor: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let detail: String
}

struct TodayRoutineAttentionID: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case supplement
        case medication
    }

    let kind: Kind
    let itemID: String
    let reminderRuleID: String
    let scheduledFor: APITimestamp
}

struct TodayRoutineAttentionDescriptor: Equatable, Sendable, Identifiable {
    let id: TodayRoutineAttentionID
    let title: String
    let status: String
}

struct TodayAttentionDescriptor: Equatable, Sendable {
    let pending: [TodayPendingDescriptor]
    let routineActions: [TodayRoutineAttentionDescriptor]

    var pendingRegistrationIDs: [String] {
        pending.map(\.id)
    }

    var routineActionIDs: [TodayRoutineAttentionID] {
        routineActions.map(\.id)
    }
}

@MainActor
struct TodayAttentionSection: View {
    let descriptor: TodayAttentionDescriptor

    var body: some View {
        BodyFlowCard {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                Label("Precisa da sua atenção", systemImage: "bell.badge")
                    .font(BodyFlowTypography.headline)
                    .foregroundStyle(BodyFlowColor.primaryText)

                pendingContent
                    .accessibilityIdentifier("today.pending")

                ForEach(descriptor.routineActions) { action in
                    Label {
                        VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                            Text(action.title)
                                .font(BodyFlowTypography.body)
                            Text(action.status)
                                .font(BodyFlowTypography.callout)
                                .foregroundStyle(BodyFlowColor.secondaryText)
                        }
                    } icon: {
                        Image(systemName: "clock.badge.exclamationmark")
                            .foregroundStyle(BodyFlowColor.warning)
                    }
                    .accessibilityElement(children: .combine)
                }

                if descriptor.pending.isEmpty,
                   descriptor.routineActions.isEmpty {
                    Label("Nenhuma ação pendente", systemImage: "checkmark.circle")
                        .font(BodyFlowTypography.body)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.attention")
    }

    @ViewBuilder
    private var pendingContent: some View {
        ForEach(descriptor.pending) { pending in
            Label {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                    Text(pending.title)
                        .font(BodyFlowTypography.body)
                    Text(pending.detail)
                        .font(BodyFlowTypography.callout)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                }
            } icon: {
                Image(systemName: "hourglass")
                    .foregroundStyle(BodyFlowColor.warning)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
