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
        mealType.map { RegistrationCopy.mealTypeTitle(code: $0, language: language) } ?? TodayCopy.string(
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
                Label(verbatim: copy("today.attention.title"), symbol: .attention)
                    .font(BodyFlowTypography.cardTitle)
                    .foregroundStyle(BodyFlowColor.primaryText)
                    .accessibilityAddTraits(.isHeader)

                pendingContent
                    .accessibilityIdentifier("today.pending")

                ForEach(descriptor.routineActions) { action in
                    attentionRow(
                        title: action.title,
                        detail: RoutineCopy.status(action.status, language: language)
                    )
                }

                if descriptor.pending.isEmpty,
                   descriptor.routineActions.isEmpty {
                    BodyFlowStatusLine(
                        copy("today.attention.empty"),
                        kind: .success,
                        font: BodyFlowTypography.body
                    )
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
            attentionRow(
                title: pending.title(for: language),
                detail: pending.detail(for: language)
            )
        }
    }

    /// A waiting item: the vocabulary "waiting" glyph in the warning color,
    /// title and received detail, read as one element.
    private func attentionRow(title: String, detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                Text(title)
                    .font(BodyFlowTypography.body)
                Text(detail)
                    .font(BodyFlowTypography.callout)
                    .foregroundStyle(BodyFlowColor.secondaryText)
            }
        } icon: {
            Image(symbol: .clock)
                .foregroundStyle(BodyFlowColor.warning)
        }
        .accessibilityElement(children: .combine)
    }
}
