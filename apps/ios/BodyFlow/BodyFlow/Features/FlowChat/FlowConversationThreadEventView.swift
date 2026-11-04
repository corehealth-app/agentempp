import Foundation

/// Literal public history presentation only. No result is promoted to current
/// meal facts, a pending command ACK, or permission to submit a linked answer.
struct FlowConversationThreadEventPresentation {
  let title: String
  let sourceText: String?
  let lines: [String]
  let observedQuestionLines: [String]
  let linkedActionGate: String?
  init(
    entry: ConversationThreadPageSnapshot.Entry, parent: ConversationThreadPageSnapshot.Thread,
    observedQuestion: ConversationThreadPageSnapshot.Question?, english: Bool,
    linkedRepliesAvailable: Bool = false
  ) {
    switch entry.detail {
    case .report(let report):
      switch report.status {
      case .pending: title = english ? "Awaiting confirmation" : "Aguardando confirmação"
      case .registered: title = english ? "Meal registered" : "Refeição registrada"
      case .notRecorded:
        title = english ? "Original report not recorded" : "Relato original não registrado"
      }
      switch parent.originalCommand.source {
      case .text(let text): sourceText = text
      case .media(_, let caption):
        sourceText =
          caption ?? (english ? "Original report attachment" : "Anexo do relato original")
      }
      lines =
        report.status == .notRecorded
        ? [
          english
            ? "This original report did not record a meal. A linked confirmation appears separately."
            : "Este relato original não registrou uma refeição. Uma confirmação vinculada aparece separadamente."
        ] : []
      linkedActionGate = nil
    case .reply(let reply):
      title = english ? "Linked reply" : "Resposta vinculada"
      sourceText = nil
      var answer: String
      switch reply.body.answer {
      case .quantity(_, let amount, let unit):
        let raw = String(amount)
        answer = (raw.hasSuffix(".0") ? String(raw.dropLast(2)) : raw) + " " + unit
      case .mealType(let type):
        switch type {
        case .cafe: answer = english ? "Breakfast" : "Café da manhã"
        case .almoco: answer = english ? "Lunch" : "Almoço"
        case .lanche: answer = english ? "Snack" : "Lanche"
        case .jantar: answer = english ? "Dinner" : "Jantar"
        case .ceia: answer = english ? "Late meal" : "Ceia"
        case .outro: answer = english ? "Other meal" : "Outra refeição"
        }
      }
      lines = [
        (english ? "Question for that reply: " : "Pergunta daquela resposta: ")
          + Self.question(reply.question, english: english), answer,
      ]
      linkedActionGate = nil
    case .replyResult(let result):
      title =
        result.status == "prepared"
        ? (english ? "Historical preparation completed" : "Preparação histórica concluída")
        : (english ? "Another detail was requested" : "Outro detalhe foi solicitado")
      sourceText = nil
      lines =
        result.nextQuestion.map {
          [
            (english ? "Question at that moment: " : "Pergunta naquele momento: ")
              + Self.question($0, english: english)
          ]
        } ?? [
          english
            ? "This event alone is not a meal registration."
            : "Este evento isolado não é um registro de refeição."
        ]
      linkedActionGate = nil
    case .fulfillment(let result):
      title =
        english
        ? "Meal registered after a linked reply" : "Refeição registrada após resposta vinculada"
      sourceText = nil
      lines = [
        english
          ? "Historical registration (\(result.receipt.localDate))."
          : "Registro histórico (\(result.receipt.localDate))."
      ]
      linkedActionGate =
        english
        ? "Current details and editing for this linked meal are not available yet."
        : "Os dados atuais e a edição desta refeição vinculada ainda não estão disponíveis."
    case .edit(let edit):
      sourceText = nil
      switch edit.receipt.kind {
      case .saved: title = english ? "Edit saved" : "Edição salva"
      case .saveUndone: title = english ? "Edit undone" : "Edição desfeita"
      case .registrationUndone: title = english ? "Registration undone" : "Registro desfeito"
      }
      lines = [
        english
          ? "Earlier registration details remain historical."
          : "Os dados do registro anterior permanecem históricos."
      ]
      linkedActionGate =
        edit.binding.isChild
        ? (english
          ? "Current details and editing for this linked meal are not available yet."
          : "Os dados atuais e a edição desta refeição vinculada ainda não estão disponíveis.")
        : nil
    }
    let unavailableReply =
      english
      ? "Linked replies are not available yet. Your original report is preserved."
      : "A resposta vinculada ainda não está disponível. Seu relato original está preservado."
    observedQuestionLines =
      observedQuestion.map {
        [
          english ? "Question observed in history" : "Pergunta observada no histórico",
          Self.question($0, english: english),
        ] + (linkedRepliesAvailable ? [] : [unavailableReply])
      } ?? []
  }
  static func question(_ question: ConversationThreadPageSnapshot.Question, english: Bool) -> String
  {
    if let food = question.foodName {
      return english
        ? "What quantity of \(food) did you consume?" : "Qual quantidade de \(food) você consumiu?"
    }
    return english ? "Which meal was this?" : "Qual foi a refeição?"
  }
}

#if canImport(UIKit)
  import SwiftUI

  struct FlowConversationThreadEventView: View {
    let entry: ConversationThreadPageSnapshot.Entry
    let parent: ConversationThreadPageSnapshot.Thread
    let observedQuestion: ConversationThreadPageSnapshot.Question?
    let feedback: ConversationFeedbackPresentationSnapshot.Bound?
    let english: Bool
    var linkedRepliesAvailable = false
    var body: some View {
      let value = FlowConversationThreadEventPresentation(
        entry: entry, parent: parent, observedQuestion: observedQuestion, english: english,
        linkedRepliesAvailable: linkedRepliesAvailable)
      VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
        Text(verbatim: value.title).font(BodyFlowTypography.headline).accessibilityAddTraits(
          .isHeader)
        if let source = value.sourceText { Text(verbatim: source) }
        ForEach(Array(value.lines.enumerated()), id: \.offset) { _, line in Text(verbatim: line) }
        if let feedback {
          // Linked lineage/current group has not been qualified yet. Never label
          // the immutable original nutrition as current edited meal facts.
          DisclosureGroup(
            english ? "Historical registration details" : "Detalhes do registro histórico"
          ) {
            ConversationFeedbackPresentationView(feedback: feedback)
          }
          .accessibilityIdentifier("conversation.thread.historical-feedback")
        }
        ForEach(Array(value.observedQuestionLines.enumerated()), id: \.offset) { _, line in
          Text(verbatim: line)
        }
        if let gate = value.linkedActionGate {
          Text(verbatim: gate).foregroundStyle(BodyFlowColor.secondaryText)
            .accessibilityIdentifier("conversation.thread.linked-actions-unavailable")
        }
      }
      .padding(BodyFlowSpacing.md)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(BodyFlowColor.color(.backgroundSecondary), in: RoundedRectangle(cornerRadius: 20))
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("conversation.thread.event.\(entry.eventID)")
    }
  }
#endif
