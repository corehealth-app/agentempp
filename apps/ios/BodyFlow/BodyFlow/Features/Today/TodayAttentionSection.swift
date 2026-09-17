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
    let kind: String
    let mealType: String?

    var title: String {
        title(for: .portugueseBrazil)
    }

    var detail: String {
        detail(for: .portugueseBrazil)
    }

    func title(for language: SupportedAppLanguage) -> String {
        TodayCopy.string(
            kind == "meal" ? "today.pending.meal" : "today.pending.workout",
            language: language
        )
    }

    func detail(for language: SupportedAppLanguage) -> String {
        mealType ?? TodayCopy.string(
            "today.pending.confirmation",
            language: language
        )
    }
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
    @Environment(\.locale) private var locale

    var body: some View {
        BodyFlowCard {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                Label(copy("today.attention.title"), systemImage: "bell.badge")
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
                    Label(copy("today.attention.empty"), systemImage: "checkmark.circle")
                        .font(BodyFlowTypography.body)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.attention")
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        TodayCopy.string(key, language: language)
    }

    @ViewBuilder
    private var pendingContent: some View {
        ForEach(descriptor.pending) { pending in
            Label {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                    Text(pending.title(for: language))
                        .font(BodyFlowTypography.body)
                    Text(pending.detail(for: language))
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
