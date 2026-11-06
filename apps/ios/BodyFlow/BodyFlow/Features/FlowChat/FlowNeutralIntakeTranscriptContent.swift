import SwiftUI

@MainActor
struct FlowNeutralIntakeComposerContent: View {
  let model: FlowNeutralIntakeModel
  @Environment(\.locale) private var locale
  @FocusState private var focused: Bool
  private var english: Bool { BodyFlowPresentationLanguage.resolve(locale) == .englishUnitedStates }
  var body: some View {
    @Bindable var model = model
    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
      if let original = model.preparedInput {
        Label(
          english ? "Original message preserved" : "Mensagem original preservada",
          systemImage: "lock")
        Text(
          english
            ? "This original message is locked until its local delivery is resolved."
            : "Esta mensagem original fica travada até resolver sua entrega local.")
        HStack {
          Button(english ? "Check original" : "Consultar original") {
            Task { await model.reconcile(intakeID: original.intakeID) }
          }
          Button(english ? "Discard unsent" : "Descartar não enviado", role: .destructive) {
            Task { await model.discardUnsent(intakeID: original.intakeID) }
          }
        }
      }
      HStack(alignment: .bottom) {
        if model.isComposerLocked {
          Text(verbatim: model.composer).frame(maxWidth: .infinity, alignment: .leading)
        } else {
          TextField(
            english
              ? "Tell Flow what you ate or which activity you performed…"
              : "Conte ao Flow o que comeu ou qual atividade realizou…", text: $model.composer,
            axis: .vertical
          )
          .lineLimit(1...6).focused($focused)
          .accessibilityLabel(english ? "Message to Flow" : "Mensagem ao Flow")
          .accessibilityIdentifier(
            "conversation.neutral.composer")
        }
        Button {
          focused = false
          Task { await model.submit() }
        } label: {
          Image(systemName: "paperplane.fill").frame(width: 44, height: 44)
        }
        .buttonStyle(BodyFlowButtonStyle(role: .primary)).disabled(!model.canSubmit)
        .accessibilityLabel(english ? "Send report" : "Enviar relato")
        .accessibilityIdentifier("conversation.neutral.send")
      }
      Picker(
        english ? "Meal context (optional)" : "Refeição como contexto (opcional)",
        selection: $model.mealTypeHint
      ) {
        Text(english ? "No meal hint" : "Sem indicação de refeição").tag(
          nil as ConversationMealCommand.MealType?)
        ForEach(ConversationMealCommand.MealType.allCases, id: \.self) { value in
          Text(mealName(value)).tag(Optional(value))
        }
      }.pickerStyle(.menu).disabled(model.isWorking || model.isComposerLocked)
      Text(
        english
          ? "Text reports. Photos, audio and linked activity replies are not available in this preview."
          : "Relatos por texto. Fotos, áudio e respostas vinculadas de atividade ainda não estão disponíveis nesta prévia."
      )
      .font(BodyFlowTypography.caption).foregroundStyle(BodyFlowColor.secondaryText)
    }.padding(BodyFlowSpacing.md)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("conversation.neutral.composer-content")
  }
  private func mealName(_ value: ConversationMealCommand.MealType) -> String {
    switch value {
    case .cafe: english ? "Breakfast" : "Café da manhã"
    case .almoco: english ? "Lunch" : "Almoço"
    case .lanche: english ? "Snack" : "Lanche"
    case .jantar: english ? "Dinner" : "Jantar"
    case .ceia: english ? "Supper" : "Ceia"
    case .outro: english ? "Other" : "Outra"
    }
  }
}

/// Mounted directly in the real Flow transcript. Historical meal descriptors
/// can replace the same proven child ID; text/time guesses never deduplicate.
@MainActor
struct FlowNeutralIntakeTranscriptContent: View {
  let model: FlowNeutralIntakeModel
  var conversation: FlowConversationModel? = nil
  var historicalMealIDs: Set<UUID> = []
  var historicalSavedIntakeIDs: Set<UUID> = []
  var historicalOriginalIntakeIDs: Set<UUID> = []
  var historicalTerminalIntakeIDs: Set<UUID> = []
  @Environment(\.locale) private var locale
  private var english: Bool { BodyFlowPresentationLanguage.resolve(locale) == .englishUnitedStates }
  var body: some View {
    VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
      ForEach(model.savedRows.filter { !historicalMealIDs.contains($0.childID) && !historicalSavedIntakeIDs.contains($0.id) }) { row in
        FlowNeutralIntakeSavedContent(row: row, english: english)
        if case .meal = row.acknowledgement, let conversation {
          FlowConversationMealControlsContent(model: conversation, commandID: row.childID)
        }
      }
      ForEach(model.terminalRows.filter {
        !historicalTerminalIntakeIDs.contains($0.id)
          || model.mealQuestionChild(intakeID: $0.id) != nil
      }) { row in
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
          if !historicalTerminalIntakeIDs.contains(row.id) {
            source(row.input)
            Text(status(row.response)).accessibilityIdentifier("conversation.neutral.closed")
          }
          if model.mealQuestionChild(intakeID: row.id) != nil, let conversation {
            if let question = conversation.neutralMealQuestion(intakeID: row.id) {
              Text(verbatim: FlowConversationThreadEventPresentation.question(question, english: english))
            }
            Button(english ? "Answer Flow" : "Responder ao Flow") {
              Task { await conversation.beginNeutralMealReply(intakeID: row.id) }
            }
            .disabled(!conversation.canReadNeutralMealQuestion(intakeID: row.id))
            .accessibilityIdentifier("conversation.neutral.answer-meal")
          }
        }.padding(BodyFlowSpacing.md).accessibilityElement(children: .contain)
      }
      ForEach(model.pendingRows, id: \.input.intakeID) { row in
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
          if !historicalOriginalIntakeIDs.contains(row.input.intakeID) { source(row.input) }
          Text(status(row)).accessibilityIdentifier("conversation.neutral.state")
          if let response = model.state(intakeID: row.input.intakeID) {
            if let question = response.question { questionContent(question.text) }
            if case .workout(.state(let state)) = response.result, let question = state.question {
              questionContent(question.text)
            }
          }
          if row.state == .queued && row.hold == nil {
            Button(english ? "Send original" : "Enviar original") {
              Task { await model.sendQueued(intakeID: row.input.intakeID) }
            }
            Button(english ? "Discard unsent" : "Descartar não enviado", role: .destructive) {
              Task { await model.discardUnsent(intakeID: row.input.intakeID) }
            }
          } else {
            Button(english ? "Check original status" : "Consultar status original") {
              Task { await model.reconcile(intakeID: row.input.intakeID) }
            }
            if model.canContinue(intakeID: row.input.intakeID) {
              Button(english ? "Continue the same original" : "Continuar o mesmo original") {
                Task { await model.continueOriginal(intakeID: row.input.intakeID) }
              }
              .accessibilityIdentifier("conversation.neutral.continue")
            }
          }
        }.disabled(model.isWorking).padding(BodyFlowSpacing.md)
          .accessibilityElement(children: .contain)
          .accessibilityIdentifier(
            "conversation.neutral.pending.\(row.input.intakeID.uuidString.lowercased())")
      }
      if model.heldCount > 0 {
        Text(
          english
            ? "Protected messages remain stored for their original account and period."
            : "Mensagens protegidas continuam guardadas para a conta e o período originais."
        )
        .accessibilityIdentifier("conversation.neutral.held")
      }
      if model.offlineQueuedCount > 0 {
        Text(
          english
            ? "Original message stored on this device. Reconnect to verify its status."
            : "Mensagem original guardada neste dispositivo. Conecte para consultar seu status."
        )
        .accessibilityIdentifier("conversation.neutral.offline-queued")
      }
      if model.isWorking {
        ProgressView(
          english ? "Checking the original delivery…" : "Verificando a entrega original…")
      }
      if let failure = model.failure {
        Text(failureText(failure)).foregroundStyle(BodyFlowColor.secondaryText)
          .accessibilityIdentifier("conversation.neutral.failure")
      }
    }.accessibilityIdentifier("conversation.neutral.transcript")
  }
  @ViewBuilder private func source(_ input: FlowNeutralIntakeInput) -> some View {
    switch input.source {
    case .text(let text): Text(verbatim: text).font(BodyFlowTypography.body)
    case .media: Text(english ? "Original attachment" : "Anexo original")
    }
  }
  private func questionContent(_ text: String) -> some View {
    VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
      Text(verbatim: text).font(BodyFlowTypography.headline)
      Text(
        english
          ? "Linked answers are not available here yet. A new complete report is independent from this original."
          : "Respostas vinculadas ainda não estão disponíveis aqui. Um novo relato completo é independente deste original."
      )
      .font(BodyFlowTypography.caption)
    }
  }
  private func status(_ row: ConversationNeutralIntakeOutboxEntry) -> String {
    if let value = model.state(intakeID: row.input.intakeID) { return status(value) }
    return row.state == .queued
      ? (english ? "Stored and not dispatched." : "Guardado e ainda não enviado.")
      : (english
        ? "Delivery is uncertain. Check its original status."
        : "A entrega está incerta. Consulte o status original.")
  }
  private func status(_ value: FlowNeutralIntakeResponseSnapshot) -> String {
    switch value.deliveryState {
    case .notRecorded:
      return english
        ? "This message did not record a meal or activity."
        : "Esta mensagem não registrou refeição nem atividade."
    case .clarificationRequired:
      return english
        ? "Flow needs clarification. No registration was confirmed."
        : "O Flow precisa de um esclarecimento. Nenhum registro foi confirmado."
    case .needsReply:
      return english
        ? "Flow needs an answer. No registration was confirmed."
        : "O Flow precisa de uma resposta. Nenhum registro foi confirmado."
    case .held:
      return english
        ? "Original preserved. Registration is not confirmed."
        : "Original preservado. O registro não está confirmado."
    case .absent:
      return english
        ? "No registration was found for this original."
        : "Nenhum registro foi encontrado para este original."
    case .pending, .unconfirmed:
      return english
        ? "Waiting for the original factual confirmation."
        : "Aguardando a confirmação factual do original."
    }
  }
  private func failureText(_ failure: ConversationNeutralIntakeFailure) -> String {
    switch failure {
    case .offline:
      english
        ? "Connection interrupted. The original message is preserved."
        : "Conexão interrompida. A mensagem original está preservada."
    case .storage:
      english
        ? "Protected storage is unavailable or full. The original text is preserved."
        : "O armazenamento protegido está indisponível ou cheio. O texto original está preservado."
    case .changed:
      english
        ? "The original account or period changed. No new delivery is authorized."
        : "A conta ou o período original mudou. Nenhum novo envio está autorizado."
    case .rateLimited:
      english
        ? "Please wait before checking this original again."
        : "Aguarde antes de consultar este original novamente."
    case .invalidInput:
      english
        ? "Write a valid report of up to 2,000 characters."
        : "Escreva um relato válido de até 2.000 caracteres."
    case .reconciliationRequired:
      english
        ? "Check the original status before continuing."
        : "Consulte o status original antes de continuar."
    case .unavailable:
      english
        ? "Confirmation is unavailable. The original delivery is preserved."
        : "A confirmação está indisponível. A entrega original está preservada."
    }
  }
}

struct FlowNeutralIntakeSavedContent: View {
  let row: FlowNeutralIntakeSavedRow
  let english: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
      if case .text(let text) = row.input.source { Text(verbatim: text) }
      switch row.acknowledgement {
      case .meal(let saved):
        Label(
          english ? "Meal recorded" : "Refeição registrada", systemImage: "checkmark.circle.fill"
        ).font(BodyFlowTypography.headline)
        Text(verbatim: saved.receipt.localDate)
      case .workout(let saved):
        Label(
          english ? "Activity recorded" : "Atividade registrada",
          systemImage: "checkmark.circle.fill"
        ).font(BodyFlowTypography.headline)
        Text(verbatim: saved.activity.workoutType)
        Text("\(saved.activity.durationMin) min")
        // Energy commentary comes only from the current-policy sections below.
        // A factual ACK never grants permission to reconstruct masked guidance.
        if saved.activity.estimatedKcal == nil {
          Text(english ? "Estimated expenditure unavailable" : "Gasto estimado indisponível")
        }
        Text(verbatim: saved.registration.localDate)
      }
      if let feedback = row.feedback {
        ConversationFeedbackPresentationView(feedback: feedback)
      } else {
        Text(
          english
            ? "The current commentary is unavailable; the factual registration remains saved."
            : "O comentário atual está indisponível; o registro factual continua salvo."
        ).foregroundStyle(BodyFlowColor.secondaryText)
      }
    }.padding(BodyFlowSpacing.md)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(BodyFlowColor.color(.backgroundSecondary), in: RoundedRectangle(cornerRadius: 20))
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("conversation.neutral.saved.\(row.id.uuidString.lowercased())")
  }
}
