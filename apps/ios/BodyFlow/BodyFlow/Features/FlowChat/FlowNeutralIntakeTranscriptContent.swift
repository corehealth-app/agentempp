import SwiftUI

@MainActor
struct FlowNeutralIntakeComposerContent: View {
  let model: FlowNeutralIntakeModel
  var capture: FlowConversationCaptureCapability? = nil
  var captureAction: @MainActor (FlowConversationCapturePresentation.Choice) -> Void = { _ in }
  @Environment(\.locale) private var locale
  @FocusState private var focused: Bool
  @State private var attachmentPreview: (UUID, FlowChatMediaPreview)?
  @State private var recordingCaption: String?
  private var english: Bool { BodyFlowPresentationLanguage.resolve(locale) == .englishUnitedStates }
  private var hasMessage: Bool {
    model.attachment != nil || model.isComposerLocked
      || !model.composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
  var body: some View {
    @Bindable var model = model
    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
      if !model.isWorking, let held = model.heldOriginalIntakeID {
        Text(english ? "This attachment will not be sent." : "Este anexo não será enviado.")
        Button(
          english ? "Discard preserved attachment" : "Descartar anexo preservado",
          role: .destructive
        ) {
          Task { await model.discardUnsent(intakeID: held) }
        }.disabled(model.isWorking)
      }
      if !model.isWorking, let original = model.activePreparedIntakeID {
        HStack {
          if model.preparedInput != nil {
            Button(english ? "Check message" : "Ver mensagem") {
              Task { await model.reconcile(intakeID: original) }
            }
          }
          Button(english ? "Discard unsent" : "Descartar não enviado", role: .destructive) {
            Task { await model.discardUnsent(intakeID: original) }
          }
        }
      }
      if !model.isWorking, let attachment = model.attachment {
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
      HStack(alignment: .bottom, spacing: BodyFlowSpacing.xs) {
        if let capture {
          Menu {
            if model.captureContext != nil {
              if capture.camera.isAvailable() {
                Button(english ? "Take photo" : "Tirar foto", systemImage: "camera") {
                  choose(.camera)
                }
              }
              Button(english ? "Photo library" : "Galeria", systemImage: "photo") { choose(.gallery) }
              Button(english ? "Choose audio" : "Selecionar áudio", systemImage: "waveform") {
                choose(.audioFile)
              }
            }
          } label: {
            Image(systemName: "plus").frame(width: 44, height: 44)
          }
          .disabled(
            model.captureContext == nil || model.isWorking || model.isComposerLocked
              || recordingCaption != nil)
          .accessibilityLabel(attachmentMenuLabel)
          .accessibilityIdentifier("conversation.neutral.attach")
        }
        if let recordingCaption {
          HStack {
            Label(recordingCaption, systemImage: "waveform")
              .monospacedDigit()
              .foregroundStyle(BodyFlowColor.accent)
            Spacer(minLength: 0)
            Text(english ? "Swipe left to cancel" : "Deslize para cancelar")
              .font(BodyFlowTypography.caption)
          }
          .frame(maxWidth: .infinity, minHeight: 44)
          .accessibilityIdentifier("conversation.neutral.voice-recording")
        } else if model.isComposerLocked {
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
        if let capture, !hasMessage || recordingCaption != nil {
          FlowChatVoiceButton(
            model: model, stager: capture.stager, english: english,
            recordingCaption: $recordingCaption, dismissKeyboard: { focused = false })
        } else {
          Button {
            focused = false
            Task { await model.submit() }
          } label: {
            Image(systemName: "paperplane.fill")
          }
          .buttonStyle(BodyFlowButtonStyle(role: .primary, isCompact: true)).disabled(!model.canSubmit)
          .accessibilityLabel(english ? "Send message" : "Enviar mensagem")
          .accessibilityIdentifier("conversation.neutral.send")
        }
      }
      if capture == nil {
        mealContextPicker.pickerStyle(.menu)
      } else if let hint = model.mealTypeHint {
        Text(mealName(hint)).font(BodyFlowTypography.caption)
          .foregroundStyle(BodyFlowColor.accent)
      }
    }.padding(BodyFlowSpacing.md)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("conversation.neutral.composer-content")
  }
  private var attachmentMenuLabel: String {
    if model.captureContext != nil { return english ? "Attach photo or audio" : "Anexar foto ou áudio" }
    return english ? "Attachments unavailable" : "Anexos indisponíveis"
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
  var historicalQuestionIntakeIDs: Set<UUID> = []
  var oldestVisibleHistoryAt: String? = nil
  @State var restoredQuestionsExpanded = false
  @Environment(\.locale) private var locale
  private var english: Bool { BodyFlowPresentationLanguage.resolve(locale) == .englishUnitedStates }
  var body: some View {
    VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
      ForEach(
        model.savedRows.filter {
          !historicalMealIDs.contains($0.childID) && !historicalSavedIntakeIDs.contains($0.id)
        }
      ) { row in
        let review = row.feedback.map { FlowFeedbackPreview($0.presentation, english: english).pending != nil } ?? false
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
          FlowNeutralIntakeSavedContent(
            row: row, english: english, compact: true, media: model.mediaPreview(for: row.id),
            showsPhotoQuestion: conversation?.currentGroup(commandID: row.childID)?.photoReview == nil)
          if case .meal = row.acknowledgement, let conversation {
            FlowConversationMealControlsContent(
              model: conversation, commandID: row.childID, needsPhotoReview: review)
          }
        }.id(FlowTranscriptPositioning.intakeAnchor(row.id))
      }
      ForEach(
        model.terminalRows.filter {
          FlowTranscriptPositioning.canAppendTerminal(
            admittedAt: $0.response.intake?.admittedAt, oldestVisibleAt: oldestVisibleHistoryAt)
            && (!historicalTerminalIntakeIDs.contains($0.id)
              || (model.mealQuestionChild(intakeID: $0.id) != nil
                && !historicalQuestionIntakeIDs.contains($0.id)))
        }
      ) { row in
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
          if !historicalTerminalIntakeIDs.contains(row.id) {
            source(row.input)
            if let reply = model.turnReply(intakeID: row.id) {
              FlowChatBubble {
                Text(FlowChatPresentation.turnReplyText(reply))
                  .accessibilityIdentifier("conversation.turn.reply")
              }
            } else if row.response.turnReply == nil {
              Text(status(row.response)).accessibilityIdentifier("conversation.neutral.closed")
            }
          }
          if !historicalQuestionIntakeIDs.contains(row.id),
            model.mealQuestionChild(intakeID: row.id) != nil, let conversation,
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
          .id(historicalTerminalIntakeIDs.contains(row.id)
            ? "local-terminal/" + row.id.uuidString.lowercased()
            : FlowTranscriptPositioning.intakeAnchor(row.id))
      }
      let restored = model.pendingRows.filter(isRestoredQuestion)
      if !restored.isEmpty {
        DisclosureGroup(
          english ? "Earlier messages to review" : "Mensagens anteriores para revisar",
          isExpanded: $restoredQuestionsExpanded
        ) {
          ForEach(restored, id: \.input.intakeID) { pendingRow($0) }
        }
        .accessibilityIdentifier("conversation.neutral.restored-questions")
      }
      ForEach(model.pendingRows.filter {
        !isRestoredQuestion($0)
          && ($0.hold != .notRecorded || !historicalQuestionIntakeIDs.contains($0.input.intakeID))
      }, id: \.input.intakeID) {
        pendingRow($0)
      }
      if model.isWorking, let id = model.activePreparedIntakeID,
        let attachment = model.attachment,
        !model.pendingRows.contains(where: { $0.input.intakeID == id }),
        !model.savedRows.contains(where: { $0.id == id }),
        !historicalOriginalIntakeIDs.contains(id)
      {
        FlowChatBubble(outgoing: true) {
          FlowChatAttachmentView(
            preview: model.mediaPreview(for: id) ?? .init(
              kind: attachment.staged.kind, duration: attachment.staged.duration, thumbnail: nil),
            english: english, sent: false)
        }
        .id(FlowTranscriptPositioning.intakeAnchor(id))
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
      if let failure = model.failure {
        Text(failureText(failure)).foregroundStyle(BodyFlowColor.secondaryText)
          .accessibilityIdentifier("conversation.neutral.failure")
      }
      if model.respondingIntakeID != nil {
        FlowWaitingBubble(label: responseWaitLabel)
      }
    }.accessibilityIdentifier("conversation.neutral.transcript")
  }

  private func isRestoredQuestion(_ row: ConversationNeutralIntakeOutboxEntry) -> Bool {
    let id = row.input.intakeID
    return row.hold == .notRecorded && !historicalQuestionIntakeIDs.contains(id)
      && model.respondingIntakeID != id && model.state(intakeID: id) == nil
  }

  private func pendingRow(_ row: ConversationNeutralIntakeOutboxEntry) -> some View {
    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
      if !historicalOriginalIntakeIDs.contains(row.input.intakeID) {
        source(row.input, sent: false)
      }
      if model.respondingIntakeID != row.input.intakeID {
        if let question = pendingQuestion(for: row) {
          FlowChatBubble { Text(verbatim: question) }
        } else if !isRestoredQuestion(row) {
          Text(status(row)).accessibilityIdentifier("conversation.neutral.state")
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
      }
    }.disabled(model.isWorking).padding(BodyFlowSpacing.md)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier(
        "conversation.neutral.pending.\(row.input.intakeID.uuidString.lowercased())")
  }

  private var responseWaitLabel: String {
    if model.mediaPhase == .uploading || (model.mediaPhase == nil && model.attachment != nil) {
      return english ? "Sending…" : "Enviando…"
    }
    return english ? "Waiting for Flow…" : "Aguardando o Flow…"
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
  private func pendingQuestion(for row: ConversationNeutralIntakeOutboxEntry) -> String? {
    guard let response = model.state(intakeID: row.input.intakeID) else { return nil }
    if let question = response.question { return question.text }
    if case .workout(.state(let state)) = response.result { return state.question?.text }
    return nil
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
      ? "Tell me a little more about this message."
      : "Pode me contar um pouco mais sobre essa mensagem?"
  }
  private func reviewButtonLabel(_ row: ConversationNeutralIntakeOutboxEntry) -> String {
    if row.hold == .notRecorded { return english ? "Resume message" : "Retomar mensagem" }
    return english ? "Check original status" : "Consultar status original"
  }
  private func status(_ value: FlowNeutralIntakeResponseSnapshot) -> String {
    if value.reason == "conversation_reply_pending" {
      return english ? "Flow is preparing a reply." : "O Flow está preparando uma resposta."
    }
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
  var showsPhotoQuestion = true
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
            ConversationFeedbackPresentationView(
              feedback: feedback, compact: true, showsPhotoQuestion: showsPhotoQuestion)
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
        // This is a factual estimate on the receipt, independent of guidance
        // and the food budget. A missing estimate has no numerical value.
        if compact, let energy = saved.activity.estimatedKcal {
          Text(english ? "Estimated expenditure: \(energy) kcal" : "Gasto estimado: \(energy) kcal")
        } else if saved.activity.estimatedKcal == nil {
          Text(english ? "Estimated expenditure unavailable" : "Gasto estimado indisponível")
        }
        Text(verbatim: saved.registration.localDate)
      }
      if let feedback = row.feedback {
        ConversationFeedbackPresentationView(feedback: feedback)
      }
    }.padding(BodyFlowSpacing.md)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(BodyFlowColor.color(.backgroundSecondary), in: RoundedRectangle(cornerRadius: 20))
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("conversation.neutral.saved.\(row.id.uuidString.lowercased())")
  }
}
