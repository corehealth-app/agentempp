import SwiftUI

/// Candidate component. No release/root factory installs this view yet.
/// Every saved card comes from the controller's factual acknowledgement;
/// historical clinical sections are the bound server-rendered presentation.
@MainActor
struct FlowConversationView: View {
  let model: FlowConversationModel
  var capture: FlowConversationCaptureCapability? = nil
  @State private var capturePresentation: FlowConversationCapturePresentation?
  @Environment(\.locale) private var locale
  @Environment(\.scenePhase) private var scenePhase
  @FocusState private var composerFocused: Bool
  @State private var keyboardClearance: CGFloat = 0
  @State private var discardID: UUID?
  private var english: Bool { BodyFlowPresentationLanguage.resolve(locale) == .englishUnitedStates }

  var body: some View {
    @Bindable var model = model
    GeometryReader { geometry in
      ZStack {
        FlowKeyboardClearanceObserver(owner: ObjectIdentifier(model)) { keyboardClearance = $0 }
          .frame(width: geometry.size.width, height: geometry.size.height)
          .allowsHitTesting(false).accessibilityHidden(true)
        VStack(spacing: 0) {
          transcript
          Divider()
          FlowComposerViewport(
            viewportHeight: geometry.size.height, keyboardClearance: keyboardClearance
          ) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
              if let attached = model.attachment {
                HStack {
                  Label(
                    attached.staged.kind == .audioNote
                      ? (english ? "Audio attached" : "Áudio anexado")
                      : (english ? "Photo attached" : "Foto anexada"),
                    systemImage: attached.staged.kind == .audioNote ? "waveform" : "photo")
                  Spacer()
                  Button(english ? "Remove" : "Remover") { Task { await model.removeAttachment() } }
                    .disabled(model.isWorking)
                }
                .accessibilityIdentifier("conversation.attachment")
              }
              HStack(alignment: .bottom, spacing: BodyFlowSpacing.sm) {
                if let capture, model.captureContext != nil {
                  Menu {
                    if capture.camera.isAvailable() {
                      Button(english ? "Take photo" : "Tirar foto", systemImage: "camera") {
                        openCapture(.camera)
                      }
                    }
                    Button(english ? "Photo library" : "Galeria", systemImage: "photo") {
                      openCapture(.gallery)
                    }
                    Button(english ? "Record audio" : "Gravar áudio", systemImage: "mic") {
                      openCapture(.recording)
                    }
                    Button(english ? "Choose audio" : "Selecionar áudio", systemImage: "waveform") {
                      openCapture(.audioFile)
                    }
                  } label: {
                    Image(systemName: "plus").frame(width: 44, height: 44)
                  }
                  .disabled(model.isWorking || model.terminalQuestion != nil)
                  .accessibilityLabel(english ? "Attach photo or audio" : "Anexar foto ou áudio")
                  .accessibilityIdentifier("conversation.attach")
                }
                TextField(
                  english ? "Tell Flow what you ate…" : "Conte ao Flow o que você comeu…",
                  text: $model.composer, axis: .vertical
                )
                .lineLimit(1...6)
                .focused($composerFocused)
                .font(BodyFlowTypography.body)
                .accessibilityIdentifier("conversation.composer")
                Button {
                  composerFocused = false
                  Task { await model.submit() }
                } label: {
                  Image(systemName: "paperplane.fill")
                    .frame(
                      width: BodyFlowSpacing.minimumTapTarget,
                      height: BodyFlowSpacing.minimumTapTarget)
                }
                .buttonStyle(BodyFlowButtonStyle(role: .primary))
                .disabled(!model.canSubmit)
                .accessibilityLabel(english ? "Send meal report" : "Enviar relato de refeição")
                .accessibilityIdentifier("conversation.send")
              }
              Picker(
                english ? "Meal (optional)" : "Refeição (opcional)", selection: $model.mealType
              ) {
                Text(english ? "Meal (optional)" : "Refeição (opcional)").tag(
                  nil as ConversationMealCommand.MealType?)
                ForEach(ConversationMealCommand.MealType.allCases, id: \.self) { type in
                  Text(mealName(type)).tag(Optional(type))
                }
              }
              .pickerStyle(.menu)
              .disabled(model.isWorking || model.terminalQuestion != nil)
            }
            .padding(BodyFlowSpacing.md)
          }
        }
        .padding(.bottom, keyboardClearance)
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
    }
    .background(BodyFlowColor.color(.backgroundPrimary))
    .navigationTitle("Flow")
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityIdentifier("screen.flow-conversation")
    .sheet(item: $capturePresentation) { presentation in
      if let capture {
        FlowConversationCaptureView(capability: capture, presentation: presentation, model: model)
      }
    }
    .task { await model.refreshConversation() }
    .onDisappear { model.cancelTransientWork() }
    .onChange(of: model.isWorking) { _, busy in if !busy { Task { await model.loadHistory() } } }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await model.refreshConversation() } }
    }
    .alert(
      english ? "Discard unsent report?" : "Descartar relato não enviado?",
      isPresented: Binding(get: { discardID != nil }, set: { if !$0 { discardID = nil } })
    ) {
      Button(english ? "Discard" : "Descartar", role: .destructive) {
        if let id = discardID {
          discardID = nil
          Task { await model.discardUnsent(commandID: id) }
        }
      }
      Button(english ? "Cancel" : "Cancelar", role: .cancel) { discardID = nil }
    } message: {
      Text(
        english
          ? "Only a report that was never dispatched can be discarded."
          : "Somente um relato que nunca foi enviado pode ser descartado.")
    }
  }

  private var transcript: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
          Text(verbatim: "Flow AI").font(BodyFlowTypography.headline).accessibilityAddTraits(
            .isHeader)
          Text(english ? "Your day in conversation" : "Seu dia em conversa")
            .foregroundStyle(BodyFlowColor.secondaryText)
        }
        if model.isRefreshing {
          ProgressView(english ? "Updating…" : "Atualizando…").accessibilityIdentifier(
            "conversation.refreshing")
        }
        if let question = model.terminalQuestion {
          VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Text(questionText(question.reason)).font(BodyFlowTypography.headline)
            Text(
              english
                ? "A linked reply is not available yet. Your original report is preserved and has not recorded a meal."
                : "A resposta vinculada ainda não está disponível. Seu relato original está preservado e não registrou uma refeição."
            )
            Button(english ? "Write an independent report" : "Escrever relato independente") {
              model.beginIndependentReport()
            }
          }
          .padding(BodyFlowSpacing.md)
          .accessibilityIdentifier("conversation.terminal-question")
        }
        if model.hasMoreHistory {
          Button(english ? "Load earlier reports" : "Carregar relatos anteriores") {
            Task { await model.loadHistory(reset: false) }
          }
          .disabled(model.isLoadingHistory)
        }
        ForEach(Array(model.journalRows.reversed()), id: \.eventID) { entry in journalEntry(entry) }
        if model.isLoadingHistory {
          ProgressView(english ? "Loading history…" : "Carregando histórico…")
        }
        if model.historyUnavailable {
          Text(
            english
              ? "History is unavailable right now. Your pending reports are preserved."
              : "O histórico está indisponível no momento. Seus relatos pendentes estão preservados."
          )
          .foregroundStyle(BodyFlowColor.secondaryText)
        }
        ForEach(model.savedRows) { row in savedCard(row) }
        ForEach(model.pendingRows) { row in
          source(row.command.source)
          VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Text(pendingText(row)).font(BodyFlowTypography.body)
            if row.state == .queued && row.hold == nil {
              Button(english ? "Send report" : "Enviar relato") {
                Task { await model.sendQueued(commandID: row.id) }
              }
            } else if row.hold != .notRecorded && row.hold != .reset && row.hold != .staleEpoch
              && row.hold != .serverChanged
            {
              Button(english ? "Check status" : "Consultar status") {
                Task { await model.reconcile(commandID: row.id) }
              }
              if model.canResubmit(commandID: row.id) {
                Button(english ? "Resend the same report" : "Reenviar o mesmo relato") {
                  Task { await model.resubmit(commandID: row.id) }
                }
              }
            }
            if row.state == .queued {
              Button(english ? "Discard" : "Descartar", role: .destructive) { discardID = row.id }
            }
          }
          .disabled(model.isWorking)
          .padding(BodyFlowSpacing.md)
          .accessibilityIdentifier("conversation.pending.\(row.id.uuidString.lowercased())")
        }
        ForEach(model.heldRows, id: \.commandID) { held in
          VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Text(
              english
                ? "A protected report needs your review."
                : "Um relato protegido precisa da sua revisão.")
            if held.canDiscardUnsent {
              Button(
                english ? "Discard unsent report" : "Descartar relato não enviado",
                role: .destructive
              ) { discardID = held.commandID }
            }
          }
          .accessibilityIdentifier("conversation.held")
        }
        ForEach(model.queuedMetadata, id: \.self) { _ in
          Text(
            english
              ? "Report stored on this device. Connection is required to continue."
              : "Relato guardado neste dispositivo. É necessária conexão para continuar."
          )
          .accessibilityIdentifier("conversation.queued-offline")
        }
        if model.isWorking {
          ProgressView(
            model.mediaPhase == .uploading
              ? (english ? "Sending attachment…" : "Enviando anexo…")
              : model.mediaPhase == .processing
                ? (english ? "Reading attachment…" : "Lendo anexo…")
                : (english ? "Waiting for confirmation…" : "Aguardando confirmação…"))
        }
        if let failure = model.failure {
          Text(failureText(failure)).foregroundStyle(BodyFlowColor.secondaryText)
            .accessibilityIdentifier("conversation.failure")
        }
      }
      .padding(BodyFlowSpacing.md)
    }
    .refreshable { await model.refreshConversation() }
  }

  private func savedCard(_ row: FlowConversationSavedRow) -> some View {
    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
      source(row.command.source)
      VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
        if let group = model.currentGroup(commandID: row.id) {
          FlowConversationMealGroupView(group: group)
        } else {
          Text(
            english
              ? "Current meal details are unavailable."
              : "Os dados atuais da refeição estão indisponíveis."
          )
          .foregroundStyle(BodyFlowColor.secondaryText)
          Button(english ? "Update meal" : "Atualizar refeição") {
            Task { await model.loadCurrentGroup(commandID: row.id) }
          }
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
      .padding(BodyFlowSpacing.md)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(BodyFlowColor.color(.backgroundSecondary), in: RoundedRectangle(cornerRadius: 20))
      .accessibilityIdentifier("conversation.saved.\(row.id.uuidString.lowercased())")
      .task(id: row.id) { await model.loadCurrentGroup(commandID: row.id) }
    }
  }
  @ViewBuilder private func journalEntry(_ entry: ConversationJournalPageSnapshot.Entry)
    -> some View
  {
    switch entry {
    case .command(let value):
      if let row = model.journalSavedRow(value) {
        savedCard(row)
        if model.hasLocalUnresolved(commandID: row.id) {
          Button(english ? "Sync confirmation" : "Sincronizar confirmação") {
            Task { await model.reconcile(commandID: row.id) }
          }
          .disabled(model.isWorking)
        }
      } else if case .state(let state) = value.result {
        source(value.originalCommand.source)
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
          if state.status == .notRecorded {
            Text(english ? "Meal not recorded" : "Refeição não registrada").font(
              BodyFlowTypography.headline)
            Text(questionText(state.reason))
            Text(
              english
                ? "The original report is preserved. A linked reply is not available yet."
                : "O relato original está preservado. A resposta vinculada ainda não está disponível."
            )
          } else {
            Text(english ? "Awaiting confirmation" : "Aguardando confirmação")
            if model.hasLocalUnresolved(commandID: value.originalCommand.commandID) {
              Button(english ? "Check status" : "Consultar status") {
                Task { await model.reconcile(commandID: value.originalCommand.commandID) }
              }
            }
          }
        }
        .padding(BodyFlowSpacing.md)
        .accessibilityIdentifier("conversation.journal.decision")
      }
    case .edit(let value):
      Label(editNotice(value.result.receipt.kind), systemImage: "clock.arrow.circlepath")
        .font(BodyFlowTypography.caption).foregroundStyle(BodyFlowColor.secondaryText)
        .accessibilityIdentifier("conversation.journal.edit")
    }
  }
  private func editNotice(_ kind: ConversationMealEditEffectSnapshot.Kind) -> String {
    switch kind {
    case .saved:
      english
        ? "A meal edit was saved. See current meal details."
        : "Uma edição da refeição foi salva. Consulte os dados atuais."
    case .saveUndone: english ? "A meal edit was undone." : "Uma edição da refeição foi desfeita."
    case .registrationUndone:
      english ? "The meal registration was undone." : "O registro da refeição foi desfeito."
    }
  }

  private func openCapture(_ choice: FlowConversationCapturePresentation.Choice) {
    guard let context = model.captureContext, model.terminalQuestion == nil else { return }
    composerFocused = false
    capturePresentation = .init(choice: choice, context: context)
  }
  private func mealName(_ type: ConversationMealCommand.MealType) -> String {
    switch type {
    case .cafe: english ? "Breakfast" : "Café da manhã"
    case .almoco: english ? "Lunch" : "Almoço"
    case .lanche: english ? "Snack" : "Lanche"
    case .jantar: english ? "Dinner" : "Jantar"
    case .ceia: english ? "Supper" : "Ceia"
    case .outro: english ? "Other" : "Outra"
    }
  }
  private func questionText(_ reason: String?) -> String {
    switch reason {
    case "missing_quantity":
      english ? "What quantity did you consume?" : "Qual quantidade você consumiu?"
    case "meal_type_required": english ? "Which meal was this?" : "Qual foi a refeição?"
    case "nutrition_label_confirmation_required":
      english
        ? "The nutrition label needs your review." : "O rótulo nutricional precisa da sua revisão."
    default: english ? "This report needs your review." : "Este relato precisa da sua revisão."
    }
  }
  private func source(_ source: ConversationMealCommand.Source) -> some View {
    Group {
      switch source {
      case .text(let text): Text(verbatim: text)
      case .media(_, let caption):
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
          Label(
            english ? "Attached meal media" : "Mídia da refeição anexada", systemImage: "paperclip")
          if let caption { Text(verbatim: caption) }
        }
      }
    }
    .font(BodyFlowTypography.body)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(BodyFlowSpacing.md)
    .background(BodyFlowColor.color(.backgroundSecondary), in: RoundedRectangle(cornerRadius: 20))
    .accessibilityIdentifier("conversation.original-source")
  }
  private func pendingText(_ row: FlowConversationPendingRow) -> String {
    if row.hold == .notRecorded {
      return english
        ? "This report was not recorded. More information is needed."
        : "Este relato não foi registrado. São necessárias mais informações."
    }
    if row.hold == .reset || row.hold == .staleEpoch || row.hold == .serverChanged {
      return english
        ? "This report is protected and cannot be sent again."
        : "Este relato está protegido e não pode ser enviado novamente."
    }
    return row.state == .queued
      ? (english
        ? "Stored on this device; not sent yet." : "Guardado neste dispositivo; ainda não enviado.")
      : (english
        ? "The outcome is not confirmed. Check its status."
        : "O resultado ainda não foi confirmado. Consulte o status.")
  }
  private func failureText(_ failure: FlowConversationFailure) -> String {
    switch failure {
    case .offline:
      english ? "No connection. Update when you can." : "Sem conexão. Atualize quando for possível."
    case .storage:
      model.pendingDraftID != nil
        ? (english
          ? "Could not store the report. Your text is still in the message field."
          : "Não foi possível guardar o relato. Seu texto continua no campo de mensagem.")
        : (english
          ? "Could not update the report. Check its status."
          : "Não foi possível atualizar o relato. Consulte o status.")
    case .invalidInput:
      english ? "Review the report before sending." : "Revise o relato antes de enviar."
    case .reconciliationRequired:
      english
        ? "Check the original report's status before retrying."
        : "Consulte o status do relato original antes de tentar novamente."
    case .rateLimited:
      english
        ? "Please wait before sending another report." : "Aguarde antes de enviar outro relato."
    case .changed:
      english
        ? "The session changed. Update before continuing."
        : "A sessão foi alterada. Atualize antes de continuar."
    case .unavailable:
      english
        ? "Flow is unavailable right now. Try updating again."
        : "O Flow está indisponível no momento. Tente atualizar novamente."
    }
  }
}
