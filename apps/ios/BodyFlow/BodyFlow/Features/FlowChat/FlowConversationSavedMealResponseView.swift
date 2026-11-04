import SwiftUI

/// The owning model supplies only current-session facts and a bound historical
/// presentation. This view never establishes transport, clinical or write authority.
struct FlowConversationSavedMealResponseView: View {
  let row: FlowConversationSavedRow
  let group: ConversationMealGroupSnapshot?
  let scope: ConversationFeedbackPresentationSnapshot.Scope
  var editing: FlowConversationMealEditActions? = nil
  let refresh: @MainActor () -> Void
  @Environment(\.locale) private var locale
  private var english: Bool { BodyFlowPresentationLanguage.resolve(locale) == .englishUnitedStates }

  var body: some View {
    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
      if let feedback = row.feedback,
        ConversationMealPrimaryFeedbackPolicy.showsPrimary(
          receipt: row.receipt, feedback: feedback, group: group, scope: scope)
      {
        ConversationFeedbackPresentationView(feedback: feedback)
          .accessibilityElement(children: .contain)
          .accessibilityIdentifier("conversation.meal.primary")
        if let group, editing != nil {
          FlowConversationMealGroupView(group: group, editing: editing, showsFacts: false)
        }
      } else {
        if let group {
          FlowConversationMealGroupView(group: group, editing: editing)
        } else {
          Text(
            english
              ? "Current meal details are unavailable."
              : "Os dados atuais da refeição estão indisponíveis."
          )
          .foregroundStyle(BodyFlowColor.secondaryText)
          Button(english ? "Update meal" : "Atualizar refeição", action: refresh)
        }
        DisclosureGroup(
          english ? "Original historical registration" : "Registro original histórico"
        ) {
          if let feedback = row.feedback {
            ConversationFeedbackPresentationView(feedback: feedback)
          } else {
            Label(
              english ? "Meal recorded" : "Refeição registrada",
              systemImage: "checkmark.circle.fill"
            )
            .font(BodyFlowTypography.cardTitle)
            Text(
              english
                ? "Historical registration (\(row.receipt.localDate))"
                : "Registro histórico (\(row.receipt.localDate))")
            Text(
              english
                ? "Historical details are unavailable right now."
                : "Os detalhes históricos estão indisponíveis no momento."
            )
            .foregroundStyle(BodyFlowColor.secondaryText)
          }
        }
        .accessibilityIdentifier("conversation.meal.original-history")
      }
    }
  }
}
