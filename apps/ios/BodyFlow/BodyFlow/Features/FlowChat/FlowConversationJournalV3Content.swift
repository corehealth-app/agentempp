import Foundation

/// Display of observed public fields only. No command/question/editor metadata
/// is recreated from history, and unknown expenditure remains unknown.
struct FlowConversationJournalV3Presentation {
  let title: String
  let source: String?
  let lines: [String]
  init(entry: ConversationJournalV3PageSnapshot.Entry, english: Bool) {
    switch entry.status {
    case .pending: title = english ? "Awaiting confirmation" : "Aguardando confirmação"
    case .notRecorded: title = english ? "Report not recorded" : "Relato não registrado"
    case .needsReply, .clarificationRequired:
      title = english ? "Historical question" : "Pergunta histórica"
    case .registered:
      switch entry.record {
      case .workout: title = english ? "Activity registered" : "Atividade registrada"
      case .meal: title = english ? "Meal registered" : "Refeição registrada"
      case .edit(let edit):
        switch edit.change {
        case .saved: title = english ? "Meal updated" : "Refeição atualizada"
        case .saveUndone: title = english ? "Meal change undone" : "Alteração de refeição desfeita"
        case .registrationUndone:
          title = english ? "Meal registration undone" : "Registro de refeição desfeito"
        }
      case nil: title = english ? "Historical record" : "Registro histórico"
      }
    }
    switch entry.input {
    case .text(let text): source = text
    case .media(let caption):
      source = caption ?? (english ? "Original report attachment" : "Anexo do relato original")
    case .quantity(_, let amount, let unit):
      source = "\(amount.formatted(.number.precision(.fractionLength(0...6)))) \(unit)"
    case .mealType(let type): source = Self.meal(type, english: english)
    case nil: source = nil
    }
    var facts: [String] = []
    if case .media = entry.input {
      facts.append(
        english
          ? "This history includes the caption. The original attachment is unavailable here."
          : "Este histórico inclui a legenda. O anexo original está indisponível aqui.")
    }
    switch entry.record {
    case .workout(let workout):
      facts.append(
        "\(workout.workoutType) · \(workout.durationMin) min"
          + (workout.intensity.map { " · " + $0 } ?? ""))
      facts.append(
        (english ? "Historical registration: " : "Registro histórico: ") + workout.localDate)
      facts.append(
        workout.estimatedKcal.map {
          (english ? "Estimated expenditure: " : "Gasto estimado: ") + "\($0) kcal."
        } ?? (english ? "Energy expenditure unavailable." : "Gasto energético indisponível."))
    case .meal(let meal):
      facts.append(Self.meal(meal.mealType, english: english) + " · " + meal.localDate)
    case .edit(let edit):
      facts.append(
        (english ? "Historical revision " : "Revisão histórica ") + String(edit.revision))
    case nil: break
    }
    if let question = entry.question {
      switch question {
      case .observed(_, let text): facts.append(text)
      case .meal(let kind, _, let foodName, let units, _):
        if kind == "meal_type" {
          facts.append(english ? "Which meal was it?" : "Qual foi a refeição?")
        } else {
          let name = foodName ?? (english ? "that food" : "esse alimento")
          facts.append(
            english
              ? "What quantity of \(name) did you consume?"
              : "Qual quantidade de \(name) você consumiu?")
          if !units.isEmpty { facts.append(units.joined(separator: " · ")) }
        }
      }
      facts.append(
        english
          ? "Observed question, for reference only." : "Pergunta observada, apenas para consulta.")
    }
    if entry.kind == .reply {
      facts.append(english ? "Historical linked reply." : "Resposta vinculada histórica.")
    }
    if entry.kind == .replyResult {
      facts.append(
        english
          ? "Historical reply observation. This event alone is not a registration."
          : "Observação histórica da resposta. Este evento isolado não é um registro.")
    }
    lines = facts
  }
  private static func meal(_ type: String, english: Bool) -> String {
    switch type {
    case "cafe": english ? "Breakfast" : "Café da manhã"
    case "almoco": english ? "Lunch" : "Almoço"
    case "lanche": english ? "Snack" : "Lanche"
    case "jantar": english ? "Dinner" : "Jantar"
    case "ceia": english ? "Late meal" : "Ceia"
    default: english ? "Other meal" : "Outra refeição"
    }
  }
}

#if canImport(UIKit)
  import SwiftUI

  struct FlowConversationJournalV3Content: View {
    let entry: ConversationJournalV3PageSnapshot.Entry
    let feedback: ConversationFeedbackPresentationSnapshot.Bound?
    let english: Bool
    var body: some View {
      let text = FlowConversationJournalV3Presentation(entry: entry, english: english)
      VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
        if let source = text.source {
          Text(verbatim: source).accessibilityIdentifier("conversation.journal3.source")
        }
        Text(verbatim: text.title).font(BodyFlowTypography.headline)
          .accessibilityIdentifier("conversation.journal3.status")
        ForEach(Array(text.lines.enumerated()), id: \.offset) { _, line in Text(verbatim: line) }
        if let feedback { ConversationFeedbackPresentationView(feedback: feedback) }
      }
      .font(BodyFlowTypography.body).padding(BodyFlowSpacing.md)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("conversation.journal3.\(entry.eventID)")
    }
  }
#endif
