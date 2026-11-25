import SwiftUI

@MainActor
struct FlowNeutralIntakeComposerContent: View {
  let model: FlowNeutralIntakeModel
  var capture: FlowConversationCaptureCapability? = nil
  var captureAction: @MainActor (FlowConversationCapturePresentation.Choice) -> Void = { _ in }
  @Environment(\.locale) private var locale
  @FocusState private var focused: Bool
  @State private var attachmentPreview: (UUID, FlowChatMediaPreview)?
  private var english: Bool { BodyFlowPresentationLanguage.resolve(locale) == .englishUnitedStates }
  var body: some View {
    @Bindable var model = model
    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
      if let held = model.heldOriginalIntakeID {
        Label(english ? "Attachment preserved" : "Anexo preservado", systemImage: "lock")
        Text(
          english
            ? "This attachment is preserved and will not be sent now. You can continue by text or discard it."
            : "Este anexo foi preservado e não será enviado agora. Você pode continuar por texto ou descartá-lo."
        )
        Button(
          english ? "Discard preserved attachment" : "Descartar anexo preservado",
          role: .destructive
        ) {
          Task { await model.discardUnsent(intakeID: held) }
        }.disabled(model.isWorking)
      }
      if let original = model.activePreparedIntakeID {
        Label(
          english ? "Original message preserved" : "Mensagem original preservada",
          systemImage: "lock")
        Text(
          english
            ? "This original message is locked until its local delivery is resolved."
            : "Esta mensagem original fica travada até resolver sua entrega local.")
        HStack {
          if model.preparedInput != nil {
            Button(english ? "Check original" : "Consultar original") {
              Task { await model.reconcile(intakeID: original) }
            }
          }
          Button(english ? "Discard unsent" : "Descartar não enviado", role: .destructive) {
            Task { await model.discardUnsent(intakeID: original) }
          }
        }
      }
      if let attachment = model.attachment {
        HStack {
          if let preview = attachmentPreview, preview.0 == attachment.id,
            let image = preview.1.thumbnail
          {
            Image(decorative: image, scale: 1).resizable().scaledToFill()
              .frame(width: 48, height: 38)
              .clipShape(RoundedRectangle(cornerRadius: 6))
              .accessibilityHidden(true)
          }
          if attachment.staged.kind == .audioNote && !model.isWorking {
            FlowChatAudioDraftButton(url: attachment.staged.fileURL, english: english)
              .id(attachment.id)
          }
          Label(
            attachment.staged.kind == .audioNote
              ? (english ? "Audio attached" : "Áudio anexado")
              : (english ? "Photo attached" : "Foto anexada"),
            systemImage: attachment.staged.kind == .audioNote ? "waveform" : "photo")
          Spacer()
          Button(english ? "Remove" : "Remover") { Task { await model.removeAttachment() } }
            .disabled(model.isWorking || model.isComposerLocked)
        }
        .task(id: attachment.id) {
          let preview = await FlowChatMediaPreview.load(attachment.staged)
          guard !Task.isCancelled, model.attachment?.id == attachment.id else { return }
          attachmentPreview = (attachment.id, preview)
        }
        .onDisappear { attachmentPreview = nil }
        .accessibilityIdentifier("conversation.neutral.attachment")
      }
      if let phase = model.mediaPhase {
        ProgressView(
          phase == .uploading
            ? (english ? "Uploading attachment…" : "Enviando anexo…")
            : (english ? "Reading attachment…" : "Lendo anexo…")
        )
        .accessibilityIdentifier("conversation.neutral.media-progress")
      }
      HStack(alignment: .bottom, spacing: BodyFlowSpacing.xs) {
        if let capture, model.captureContext != nil {
          Menu {
            if capture.camera.isAvailable() {
              Button(english ? "Take photo" : "Tirar foto", systemImage: "camera") {
                choose(.camera)
              }
            }
            Button(english ? "Photo library" : "Galeria", systemImage: "photo") { choose(.gallery) }
            Button(english ? "Record audio" : "Gravar áudio", systemImage: "mic") {
              choose(.recording)
            }
            Button(english ? "Choose audio" : "Selecionar áudio", systemImage: "waveform") {
              choose(.audioFile)
            }
            mealContextPicker
          } label: {
            Image(systemName: "plus").frame(width: 44, height: 44)
          }
          .disabled(model.isWorking || model.isComposerLocked)
          .accessibilityLabel(english ? "Attach photo or audio" : "Anexar foto ou áudio")
          .accessibilityIdentifier("conversation.neutral.attach")
        }
        if model.isComposerLocked {
          Text(verbatim: model.composer).frame(maxWidth: .infinity, alignment: .leading)
        } else {
          TextField(
            english ? "Message to Flow" : "Mensagem ao Flow", text: $model.composer,
            axis: .vertical
          )
          .lineLimit(1...5).focused($focused)
          .padding(BodyFlowSpacing.sm)
          .frame(minHeight: 44)
          .background(BodyFlowColor.background, in: RoundedRectangle(cornerRadius: 16))
          .accessibilityLabel(english ? "Message to Flow" : "Mensagem ao Flow")
          .accessibilityIdentifier(
            "conversation.neutral.composer")
        }
        if capture != nil, model.captureContext != nil {
          Button { choose(.recording) } label: {
            Image(systemName: "mic").frame(width: 44, height: 44)
          }
          .buttonStyle(.plain)
          .foregroundStyle(BodyFlowColor.accent)
          .disabled(model.isWorking || model.isComposerLocked)
          .accessibilityLabel(english ? "Record audio" : "Gravar áudio")
          .accessibilityIdentifier("conversation.neutral.record-audio")
        }
        Button {
          focused = false
          Task { await model.submit() }
        } label: {
          Image(systemName: "paperplane.fill")
        }
        .buttonStyle(BodyFlowButtonStyle(role: .primary, isCompact: true)).disabled(!model.canSubmit)
        .accessibilityLabel(
          model.isComposerLocked
            ? (english ? "Retry original message" : "Retomar mensagem original")
            : (english ? "Send report" : "Enviar relato")
        )
        .accessibilityIdentifier("conversation.neutral.send")
      }
      if capture == nil || model.captureContext == nil {
        mealContextPicker.pickerStyle(.menu)
      } else if let hint = model.mealTypeHint {
        Text(mealName(hint)).font(BodyFlowTypography.caption)
          .foregroundStyle(BodyFlowColor.accent)
      }
      if capture == nil {
        Text(
          english
            ? "Text reports. Photos, audio and linked activity replies are not available in this preview."
            : "Relatos por texto. Fotos, áudio e respostas vinculadas de atividade ainda não estão disponíveis nesta prévia."
        )
        .font(BodyFlowTypography.caption).foregroundStyle(BodyFlowColor.secondaryText)
      }
    }.padding(BodyFlowSpacing.md)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("conversation.neutral.composer-content")
  }
  private var mealContextPicker: some View {
    @Bindable var model = model
    return Picker(english ? "Meal" : "Refeição", selection: $model.mealTypeHint) {
      Text(english ? "No meal hint" : "Sem indicação de refeição")
        .tag(nil as ConversationMealCommand.MealType?)
      ForEach(ConversationMealCommand.MealType.allCases, id: \.self) {
        Text(mealName($0)).tag(Optional($0))
      }
    }.disabled(model.isWorking || model.isComposerLocked)
  }
  private func choose(_ choice: FlowConversationCapturePresentation.Choice) {
    focused = false
    captureAction(choice)
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
      ForEach(
        model.savedRows.filter {
          !historicalMealIDs.contains($0.childID) && !historicalSavedIntakeIDs.contains($0.id)
        }
      ) { row in
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
          FlowNeutralIntakeSavedContent(
            row: row, english: english, compact: true, media: model.mediaPreview(for: row.id))
          if case .meal = row.acknowledgement, let conversation {
            FlowConversationMealControlsContent(model: conversation, commandID: row.childID)
          }
        }.id(FlowTranscriptPositioning.intakeAnchor(row.id))
      }
      ForEach(
        model.terminalRows.filter {
          !historicalTerminalIntakeIDs.contains($0.id)
            || model.mealQuestionChild(intakeID: $0.id) != nil
        }
      ) { row in
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
          if !historicalTerminalIntakeIDs.contains(row.id) {
            source(row.input)
            Text(status(row.response)).accessibilityIdentifier("conversation.neutral.closed")
          }
          if model.mealQuestionChild(intakeID: row.id) != nil, let conversation,
            !conversation.isMealQuestionClosed(intakeID: row.id)
          {
            if let question = conversation.neutralMealQuestion(intakeID: row.id) {
              Text(
                verbatim: FlowConversationThreadEventPresentation.question(
                  question, english: english))
            }
            Button(english ? "Answer Flow" : "Responder ao Flow") {
              Task { await conversation.beginNeutralMealReply(intakeID: row.id) }
            }
            .disabled(!conversation.canReadNeutralMealQuestion(intakeID: row.id))
            .accessibilityIdentifier("conversation.neutral.answer-meal")
          }
        }.padding(BodyFlowSpacing.md).accessibilityElement(children: .contain)
          .id(
            historicalTerminalIntakeIDs.contains(row.id)
              ? "local-terminal/" + row.id.uuidString.lowercased()
              : FlowTranscriptPositioning.intakeAnchor(row.id))
      }
      ForEach(model.pendingRows, id: \.input.intakeID) { row in
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
          if !historicalOriginalIntakeIDs.contains(row.input.intakeID) {
            source(row.input, sent: false)
          }
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
            Button(reviewButtonLabel(row)) {
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
  private func source(_ input: FlowNeutralIntakeInput, sent: Bool = true) -> some View {
    FlowChatBubble(outgoing: true) {
      switch input.source {
      case .text(let text): Text(verbatim: text)
      case .media(_, let caption):
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
          FlowChatAttachmentView(
            preview: model.mediaPreview(for: input.intakeID), english: english, sent: sent)
          if let caption { Text(verbatim: caption) }
        }
      }
    }
  }
  private func questionContent(_ text: String) -> some View {
    VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
      Text(verbatim: text).font(BodyFlowTypography.headline)
      Text(
        english
          ? "Send a new report with this information."
          : "Envie um novo relato com essa informação."
      )
      .font(BodyFlowTypography.caption)
    }
  }
  private func status(_ row: ConversationNeutralIntakeOutboxEntry) -> String {
    if let value = model.state(intakeID: row.input.intakeID) { return status(value) }
    if row.hold == .notRecorded { return clarificationStatus }
    return row.state == .queued
      ? (english ? "Stored and not dispatched." : "Guardado e ainda não enviado.")
      : (english
        ? "Delivery is uncertain. Check its original status."
        : "A entrega está incerta. Consulte o status original.")
  }
  private var clarificationStatus: String {
    english
      ? "Flow needs clarification. No registration was confirmed."
      : "O Flow precisa de um esclarecimento. Nenhum registro foi confirmado."
  }
  private func reviewButtonLabel(_ row: ConversationNeutralIntakeOutboxEntry) -> String {
    if row.hold == .notRecorded { return english ? "See what is missing" : "Ver o que faltou" }
    return english ? "Check original status" : "Consultar status original"
  }
  private func status(_ value: FlowNeutralIntakeResponseSnapshot) -> String {
    switch value.deliveryState {
    case .notRecorded:
      var reason = value.reason
      if case .some(.meal(.state(let state))) = value.result { reason = state.reason }
      if let explanation = FlowConversationJournalV3Presentation.notRecordedReason(
        reason, english: english)
      { return explanation }
      return english
        ? "This message did not record a meal or activity."
        : "Esta mensagem não registrou refeição nem atividade."
    case .clarificationRequired:
      return clarificationStatus
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
  var compact = false
  var media: FlowChatMediaPreview? = nil
  var body: some View {
    if compact {
      VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
        FlowChatBubble(outgoing: true) {
          switch row.input.source {
          case .text(let text): Text(verbatim: text)
          case .media(_, let caption):
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
              FlowChatAttachmentView(preview: media, english: english)
              if let caption { Text(verbatim: caption) }
            }
          }
        }
        FlowChatBubble {
          if let feedback = row.feedback {
            ConversationFeedbackPresentationView(feedback: feedback, compact: true)
          } else {
            savedFacts
          }
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("conversation.neutral.saved.\(row.id.uuidString.lowercased())")
    } else {
      savedFacts
    }
  }

  private var savedFacts: some View {
    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
      if !compact, case .text(let text) = row.input.source { Text(verbatim: text) }
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
