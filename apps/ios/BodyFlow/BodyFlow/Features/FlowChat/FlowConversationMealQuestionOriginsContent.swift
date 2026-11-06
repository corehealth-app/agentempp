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
      VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
        ForEach(model.recoveredMealQuestionOrigins) { origin in
          VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
            switch origin.source {
            case .text(let text): Text(verbatim: text)
            case .media(let caption):
              Text(english ? "Report with an attachment" : "Relato com anexo")
              if let caption { Text(verbatim: caption) }
            }
            Button(english ? "Check the current question" : "Consultar pergunta atual") {
              Task { await model.beginNeutralMealReply(intakeID: origin.id) }
            }
            .disabled(!model.canReadNeutralMealQuestion(intakeID: origin.id))
            .accessibilityIdentifier("conversation.origins.answer.\(origin.id.uuidString.lowercased())")
          }.padding(BodyFlowSpacing.sm)
        }
        if origins.isLoading {
          ProgressView(english ? "Checking previous reports…" : "Consultando relatos anteriores…")
            .accessibilityIdentifier("conversation.origins.loading")
        }
        if origins.unavailable {
          Text(english ? "Previous reports are unavailable right now." : "Não foi possível consultar os relatos anteriores agora.")
          Button(english ? "Try again" : "Tentar novamente") {
            Task { await model.loadMealQuestionOrigins() }
          }.accessibilityIdentifier("conversation.origins.retry")
        }
        if origins.hasMore {
          Button(english ? "Check older reports" : "Consultar relatos mais antigos") {
            Task { await model.loadMealQuestionOrigins(reset: false) }
          }
          .disabled(origins.isLoading)
          .accessibilityIdentifier("conversation.origins.more")
        }
      }.accessibilityElement(children: .contain)
        .accessibilityIdentifier("conversation.origins")
    }
  }
}
