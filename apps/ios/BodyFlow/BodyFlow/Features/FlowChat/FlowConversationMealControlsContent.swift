#if canImport(UIKit)
  import SwiftUI

  /// Existing current-group/editor ports. Neither this view nor its caller
  /// reconstructs an original command, dispatch receipt or session authority.
  @MainActor
  struct FlowConversationMealControlsContent: View {
    let model: FlowConversationModel
    let commandID: UUID
    @State private var userExpansion: Bool?
    @Environment(\.locale) private var locale
    private var english: Bool {
      BodyFlowPresentationLanguage.resolve(locale) == .englishUnitedStates
    }
    private var expanded: Bool {
      userExpansion ?? (model.currentGroup(commandID: commandID) != nil
        || model.groupUnavailable(commandID: commandID))
    }
    var body: some View {
      if model.canLoadMealDetails(commandID: commandID) {
        DisclosureGroup(isExpanded: Binding(
          get: { expanded }, set: { userExpansion = $0 }
        )) {
          if expanded {
            currentMeal
              .task(id: model.knownEditRevision(commandID: commandID)) {
                if !model.groupUnavailable(commandID: commandID) {
                  await model.loadCurrentGroup(commandID: commandID)
                }
              }
          }
        } label: {
          Label(english ? "Edit item" : "Editar item", systemImage: "pencil")
            .font(BodyFlowTypography.body)
        }
        .tint(BodyFlowColor.accent)
        .padding(.horizontal, BodyFlowSpacing.sm)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conversation.meal.controls.\(commandID.uuidString.lowercased())")
      }
    }

    private var currentMeal: some View {
      VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
        if let group = model.currentGroup(commandID: commandID) {
          FlowConversationMealGroupView(
            group: group, editing: model.mealEditActions(commandID: commandID),
            showsFacts: group.revision > 0,
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
      .padding(.vertical, BodyFlowSpacing.sm)
    }
  }
#endif
