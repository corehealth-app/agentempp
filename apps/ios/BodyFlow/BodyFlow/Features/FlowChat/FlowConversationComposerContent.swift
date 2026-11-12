import SwiftUI

/// The actual composer content, also hosted independently for native control
/// verification. Its parent retains the existing persistent viewport/focus
/// behavior; all actions still use the original authenticated model.
@MainActor
struct FlowConversationComposerContent: View {
  let model: FlowConversationModel
  let capture: FlowConversationCaptureCapability?
  let captureAction: @MainActor (FlowConversationCapturePresentation.Choice) -> Void
  let discardAction: @MainActor (UUID, Bool) -> Void
  @FocusState private var composerFocused: Bool
  @Environment(\.locale) private var locale
  private var english: Bool { BodyFlowPresentationLanguage.resolve(locale) == .englishUnitedStates }
  var body: some View {
    if let neutral = model.neutralIntake {
      FlowNeutralIntakeComposerContent(
        model: neutral, capture: capture, captureAction: captureAction)
    } else {
      legacyContent
    }
  }
  @ViewBuilder private var legacyContent: some View {
    @Bindable var model = model
    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
      if let prepared = model.preparedIntent, !model.isWorking {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
          Label(
            english ? "Original report preserved" : "Relato original preservado",
            systemImage: "lock"
          )
          .font(BodyFlowTypography.headline)
          Text(
            english
              ? "The meal and message stay locked for this same report. To change them, discard only a report that was never sent."
              : "A refeição e a mensagem ficam travadas para este mesmo relato. Para alterá-las, descarte somente um relato que nunca foi enviado."
          )
          .font(BodyFlowTypography.caption)
          Button(english ? "Check original status" : "Consultar status do original") {
            Task { await model.reconcile(commandID: prepared.commandID) }
          }
          Button(
            english ? "Discard unsent report" : "Descartar relato não enviado", role: .destructive
          ) {
            discardAction(prepared.commandID, true)
          }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conversation.prepared.locked")
      }
      if let attached = model.attachment {
        HStack {
          Label(
            attached.staged.kind == .audioNote
              ? (english ? "Audio attached" : "Áudio anexado")
              : (english ? "Photo attached" : "Foto anexada"),
            systemImage: attached.staged.kind == .audioNote ? "waveform" : "photo")
          Spacer()
          Button(english ? "Remove" : "Remover") { Task { await model.removeAttachment() } }
            .disabled(model.isWorking || model.isComposerLocked)
        }
        .accessibilityIdentifier("conversation.attachment")
      }
      HStack(alignment: .bottom, spacing: BodyFlowSpacing.sm) {
        if let capture, model.captureContext != nil {
          Menu {
            if capture.camera.isAvailable() {
              Button(english ? "Take photo" : "Tirar foto", systemImage: "camera") {
                captureChoice(.camera)
              }
            }
            Button(english ? "Photo library" : "Galeria", systemImage: "photo") {
              captureChoice(.gallery)
            }
            Button(english ? "Record audio" : "Gravar áudio", systemImage: "mic") {
              captureChoice(.recording)
            }
            Button(english ? "Choose audio" : "Selecionar áudio", systemImage: "waveform") {
              captureChoice(.audioFile)
            }
          } label: {
            Image(systemName: "plus").frame(width: 44, height: 44)
          }
          .disabled(model.isWorking || model.isComposerLocked || model.terminalQuestion != nil)
          .accessibilityLabel(english ? "Attach photo or audio" : "Anexar foto ou áudio")
          .accessibilityIdentifier("conversation.attach")
        }
        if model.isComposerLocked {
          Text(
            model.composer.isEmpty
              ? (english ? "Attachment without a caption" : "Anexo sem legenda") : model.composer
          )
          .font(BodyFlowTypography.body)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityIdentifier("conversation.composer.locked")
        } else {
          TextField(
            english ? "Tell Flow what you ate…" : "Conte ao Flow o que você comeu…",
            text: $model.composer, axis: .vertical
          )
          .lineLimit(1...6)
          .focused($composerFocused)
          .font(BodyFlowTypography.body)
          .accessibilityIdentifier("conversation.composer")
        }
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
        .accessibilityLabel(
          model.isComposerLocked
            ? (english ? "Continue with the original report" : "Continuar com o relato original")
            : (english ? "Send meal report" : "Enviar relato de refeição")
        )
        .accessibilityIdentifier("conversation.send")
      }
      if model.isComposerLocked {
        Text(
          model.mealType.map(mealName)
            ?? (english ? "Meal not selected" : "Refeição não selecionada")
        )
        .font(BodyFlowTypography.caption)
        .accessibilityIdentifier("conversation.meal-selector.locked")
      } else {
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
        .disabled(model.isWorking || model.isComposerLocked || model.terminalQuestion != nil)
        .accessibilityIdentifier("conversation.meal-selector")
      }
    }
    .padding(BodyFlowSpacing.md)
  }
  private func captureChoice(_ choice: FlowConversationCapturePresentation.Choice) {
    composerFocused = false
    captureAction(choice)
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
}
