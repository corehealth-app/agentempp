#if canImport(UIKit)
  import SwiftUI

  /// Existing current-group/editor ports. Neither this view nor its caller
  /// reconstructs an original command, dispatch receipt or session authority.
  @MainActor
  struct FlowConversationMealControlsContent: View {
    let model: FlowConversationModel
    let commandID: UUID
    @Environment(\.locale) private var locale
    private var english: Bool {
      BodyFlowPresentationLanguage.resolve(locale) == .englishUnitedStates
    }
    var body: some View {
      if model.canRequestMealDetails(commandID: commandID) {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
          if let group = model.currentGroup(commandID: commandID) {
            FlowConversationMealGroupView(
              group: group, editing: model.mealEditActions(commandID: commandID), showsFacts: false,
              showsCurrentQuantity: true)
          } else if model.isLoadingMealDetails(commandID: commandID) {
            ProgressView(english ? "Loading current meal…" : "Carregando refeição atual…")
          } else {
            if model.groupUnavailable(commandID: commandID) {
              Text(
                english
                  ? "Current meal details are unavailable. The registration remains saved."
                  : "Os dados atuais da refeição estão indisponíveis. O registro continua salvo."
              )
              .foregroundStyle(BodyFlowColor.secondaryText)
            }
            Button(
              model.groupUnavailable(commandID: commandID)
                ? (english ? "Try again" : "Tentar novamente")
                : (english ? "View current meal details" : "Ver dados atuais da refeição")
            ) {
              Task { await model.loadCurrentGroup(commandID: commandID) }
            }
          }
        }
        .padding(BodyFlowSpacing.md)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conversation.meal.controls.\(commandID.uuidString.lowercased())")
        .task(id: model.knownEditRevision(commandID: commandID)) {
          if !model.groupUnavailable(commandID: commandID) {
            await model.loadCurrentGroup(commandID: commandID)
          }
        }
      }
    }
  }
#endif
