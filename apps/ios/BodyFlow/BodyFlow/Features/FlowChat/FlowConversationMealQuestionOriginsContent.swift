import SwiftUI

/// Read-only origin labels. Each action observes a fresh current typed question;
/// the actual existing answer sheet remains the only answer interaction.
@MainActor
struct FlowConversationMealQuestionOriginsContent: View {
  let model: FlowConversationModel
  @Environment(\.locale) private var locale
  private var english: Bool { BodyFlowPresentationLanguage.resolve(locale) == .englishUnitedStates }
  var body: some View {
    if let origins = model.mealQuestionOrigins {
      let visibleQuestions = Set<UUID>(model.unifiedRows.compactMap { entry in
        guard entry.kind == .intake, entry.question != nil, let id = entry.intakeID,
          model.hasLinkedNeutralMealQuestion(intakeID: id)
        else { return nil }
        return id
      })
      VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
        ForEach(model.recoveredMealQuestionOrigins.filter { !visibleQuestions.contains($0.id) }) { origin in
          VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
            switch origin.source {
            case .text(let text): Text(verbatim: text)
            case .media(let caption):
              Text(english ? "Report with an attachment" : "Relato com anexo")
              if let caption { Text(verbatim: caption) }
            }
            Button(english ? "Resume this message" : "Retomar esta mensagem") {
              Task { await model.beginNeutralMealReply(intakeID: origin.id) }
            }
            .disabled(!model.canReadNeutralMealQuestion(intakeID: origin.id))
            .accessibilityIdentifier("conversation.origins.answer.\(origin.id.uuidString.lowercased())")
          }.padding(BodyFlowSpacing.sm)
        }
        if origins.unavailable {
          Text(english ? "Previous reports are unavailable right now." : "Não foi possível consultar os relatos anteriores agora.")
          Button(english ? "Try again" : "Tentar novamente") {
            Task { await model.loadMealQuestionOrigins() }
          }.accessibilityIdentifier("conversation.origins.retry")
        }
        if origins.hasMore {
          Button {
            Task { await model.loadMealQuestionOrigins(reset: false) }
          } label: {
            HStack(spacing: BodyFlowSpacing.sm) {
              Text(english ? "Check older reports" : "Consultar relatos mais antigos")
              if origins.isLoadingMore {
                ProgressView().controlSize(.mini)
                  .accessibilityLabel(english ? "Loading earlier reports" : "Carregando relatos anteriores")
                  .accessibilityIdentifier("conversation.origins.loading")
              }
            }
          }
          .disabled(origins.isLoading)
          .accessibilityIdentifier("conversation.origins.more")
        }
      }.accessibilityElement(children: .contain)
        .accessibilityIdentifier("conversation.origins")
    }
  }
}
