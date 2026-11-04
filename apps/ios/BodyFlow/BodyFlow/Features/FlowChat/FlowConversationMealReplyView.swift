import SwiftUI

@MainActor struct FlowConversationMealReplyView: View {
  let model: FlowConversationMealReplyModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.locale) private var locale
  private var english: Bool { BodyFlowPresentationLanguage.resolve(locale) == .englishUnitedStates }
  var body: some View {
    NavigationStack {
      ScrollView { FlowConversationMealReplyContent(model: model).padding(BodyFlowSpacing.md) }
        .background(BodyFlowColor.color(.backgroundPrimary))
        .navigationTitle(english ? "Answer Flow" : "Responder ao Flow")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(english ? "Close" : "Fechar") {
              model.dismiss()
              dismiss()
            }
          }
        }
    }
  }
}

@MainActor struct FlowConversationMealReplyContent: View {
  let model: FlowConversationMealReplyModel
  @Environment(\.locale) private var locale
  @State private var confirmDiscard = false
  @State private var showsUnitChoices = false
  @State private var showsMealChoices = false
  private var language: SupportedAppLanguage { BodyFlowPresentationLanguage.resolve(locale) }
  private var english: Bool { language == .englishUnitedStates }
  var body: some View {
    VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
      if let question = model.question {
        Text(verbatim: FlowConversationThreadEventPresentation.question(question, english: english))
          .font(BodyFlowTypography.headline).accessibilityIdentifier("conversation.reply.question")
        if model.isLocked {
          Text(english ? "Original answer preserved" : "Resposta original preservada")
            .font(BodyFlowTypography.cardTitle)
          if question.kind == "quantity" {
            Text(verbatim: "\(model.amountText) \(model.quantityUnit)")
              .accessibilityIdentifier("conversation.reply.locked-quantity")
          } else if let meal = model.mealType {
            Text(verbatim: mealLabel(meal)).accessibilityIdentifier(
              "conversation.reply.locked-meal")
          }
          Text(
            english
              ? "Check this answer's status before making another attempt."
              : "Consulte o status desta resposta antes de tentar novamente.")
        } else if question.kind == "quantity" {
          TextField(
            english ? "Quantity" : "Quantidade",
            text: Binding(get: { model.amountText }, set: { model.amountText = $0 })
          )
          .keyboardType(.decimalPad).textFieldStyle(.roundedBorder).accessibilityIdentifier(
            "conversation.reply.quantity")
          Button(unitLabel(model.quantityUnit)) { showsUnitChoices = true }
            .buttonStyle(.bordered).disabled(model.isWorking)
            .accessibilityLabel(english ? "Unit" : "Unidade")
            .accessibilityValue(unitLabel(model.quantityUnit))
            .accessibilityIdentifier("conversation.reply.unit")
            .confirmationDialog(
              english ? "Unit" : "Unidade", isPresented: $showsUnitChoices,
              titleVisibility: .visible
            ) {
              ForEach(question.allowedUnits, id: \.self) { value in
                Button(unitLabel(value)) {
                  guard !model.isLocked && !model.isWorking else { return }
                  model.quantityUnit = value
                }
              }
              Button(english ? "Cancel" : "Cancelar", role: .cancel) {}
            }
          if question.quantityReference != nil {
            Text(
              english
                ? "Flow will use the original food's portion reference."
                : "O Flow usará a referência de porção do alimento original."
            )
            .foregroundStyle(BodyFlowColor.secondaryText)
          }
        } else {
          Button(
            model.mealType.map(mealLabel) ?? (english ? "Select the meal" : "Selecione a refeição")
          ) {
            showsMealChoices = true
          }
          .buttonStyle(.bordered).disabled(model.isWorking)
          .accessibilityLabel(english ? "Meal" : "Refeição")
          .accessibilityValue(
            model.mealType.map(mealLabel) ?? (english ? "Not selected" : "Não selecionada")
          )
          .accessibilityIdentifier("conversation.reply.meal")
          .confirmationDialog(
            english ? "Meal" : "Refeição", isPresented: $showsMealChoices,
            titleVisibility: .visible
          ) {
            ForEach(ConversationMealCommand.MealType.allCases, id: \.self) { value in
              Button(mealLabel(value)) {
                guard !model.isLocked && !model.isWorking else { return }
                model.mealType = value
              }
            }
            Button(english ? "Cancel" : "Cancelar", role: .cancel) {}
          }
        }
        if model.isWorking {
          ProgressView(english ? "Waiting for confirmation…" : "Aguardando confirmação…")
        }
        if let failure = model.failure {
          Text(verbatim: failureText(failure)).foregroundStyle(BodyFlowColor.secondaryText)
            .accessibilityIdentifier("conversation.reply.failure")
        }
        if !model.isLocked || model.canSubmit {
          Button(
            model.isLocked
              ? (english ? "Continue the original answer" : "Continuar resposta original")
              : (english ? "Send answer" : "Enviar resposta")
          ) { Task { await model.submit(language: language) } }
          .disabled(!model.canSubmit).buttonStyle(.borderedProminent).accessibilityIdentifier(
            "conversation.reply.submit")
        }
        if model.canCheckStatus {
          Button(english ? "Check answer status" : "Consultar status da resposta") {
            Task { await model.checkStatus() }
          }.accessibilityIdentifier("conversation.reply.reconcile")
        }
        if model.canResume {
          Button(english ? "Resume the original answer" : "Retomar resposta original") {
            Task { await model.resume() }
          }.accessibilityIdentifier("conversation.reply.resume")
        }
        if model.canDiscardUnsent {
          Button(
            english ? "Discard unsent answer" : "Descartar resposta não enviada", role: .destructive
          ) { confirmDiscard = true }.accessibilityIdentifier("conversation.reply.discard")
        }
        Text(
          english
            ? "Your original report stays preserved. This answer is linked to its question."
            : "Seu relato original permanece preservado. Esta resposta está vinculada à pergunta."
        )
        .foregroundStyle(BodyFlowColor.secondaryText)
      }
    }
    .accessibilityElement(children: .contain).accessibilityIdentifier("conversation.reply.form")
    .confirmationDialog(
      english ? "Discard unsent answer?" : "Descartar resposta não enviada?",
      isPresented: $confirmDiscard
    ) {
      Button(english ? "Discard" : "Descartar", role: .destructive) {
        Task { await model.discardUnsent() }
      }
    }
  }
  private func unitLabel(_ value: String) -> String {
    switch value {
    case "caneca": english ? "cup" : "caneca"
    case "scoop": english ? "scoop" : "medida"
    case "unit": english ? "unit" : "unidade"
    default: value
    }
  }
  private func mealLabel(_ value: ConversationMealCommand.MealType) -> String {
    switch value {
    case .cafe: english ? "Breakfast" : "Café da manhã"
    case .almoco: english ? "Lunch" : "Almoço"
    case .lanche: english ? "Snack" : "Lanche"
    case .jantar: english ? "Dinner" : "Jantar"
    case .ceia: english ? "Late meal" : "Ceia"
    case .outro: english ? "Other meal" : "Outra refeição"
    }
  }
  private func failureText(_ value: FlowConversationFailure) -> String {
    switch value {
    case .storage:
      english
        ? "The protected answer could not be stored. Its original content is preserved."
        : "Não foi possível guardar a resposta protegida. O conteúdo original está preservado."
    case .offline:
      english
        ? "Connection unavailable. Check the original answer's status when connected."
        : "Sem conexão. Consulte o status da resposta original quando estiver conectado."
    case .rateLimited:
      english
        ? "Please wait before checking the answer again."
        : "Aguarde antes de consultar a resposta novamente."
    case .changed:
      english
        ? "The meal context changed. Your original answer remains protected."
        : "O contexto da refeição mudou. Sua resposta original permanece protegida."
    case .invalidInput:
      english
        ? "Enter a valid quantity or select the meal."
        : "Informe uma quantidade válida ou selecione a refeição."
    case .reconciliationRequired, .unavailable:
      english
        ? "Confirmation is unavailable. Your original answer is preserved; check its status."
        : "A confirmação está indisponível. Sua resposta original está preservada; consulte o status."
    }
  }
}

@MainActor struct FlowConversationMealReplyDeliveryView: View {
  let result: ConversationMealReplyResultSnapshot
  let feedback: ConversationFeedbackPresentationSnapshot.Bound?
  let english: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
      if let receipt = result.receipt {
        Text(
          english
            ? "Meal registered after a linked reply" : "Refeição registrada após resposta vinculada"
        ).font(BodyFlowTypography.headline)
        Text(
          english
            ? "Historical registration (\(receipt.localDate))."
            : "Registro histórico (\(receipt.localDate)).")
        if let feedback { ConversationFeedbackPresentationView(feedback: feedback) }
        Text(
          english
            ? "Current details and editing for this linked meal are not available yet."
            : "Os dados atuais e a edição desta refeição vinculada ainda não estão disponíveis."
        )
        .foregroundStyle(BodyFlowColor.secondaryText)
      }
    }.accessibilityElement(children: .contain).accessibilityIdentifier(
      "conversation.reply.delivered")
  }
}

/// Only redacted prior-context metadata is visible; the old body stays sealed.
@MainActor struct FlowConversationMealReplyHeldActions: View {
  let model: FlowConversationMealReplyModel
  let english: Bool
  @State private var selectedID: UUID?
  var body: some View {
    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
      ForEach(model.heldEntries.filter(\.canDiscardUnsent), id: \.id) { entry in
        Button(
          english ? "Discard a previous unsent answer" : "Descartar resposta anterior não enviada",
          role: .destructive
        ) { selectedID = entry.id }
        .disabled(model.isWorking).accessibilityIdentifier("conversation.reply.discard-held")
      }
    }
    .confirmationDialog(
      english ? "Discard this unsent answer?" : "Descartar esta resposta não enviada?",
      isPresented: Binding(get: { selectedID != nil }, set: { if !$0 { selectedID = nil } })
    ) {
      Button(english ? "Discard" : "Descartar", role: .destructive) {
        if let id = selectedID {
          selectedID = nil
          Task { await model.discardProtectedUnsent(replyID: id) }
        }
      }
    } message: {
      Text(
        english
          ? "This answer was never sent. Its protected content will be removed from this device."
          : "Esta resposta nunca foi enviada. O conteúdo protegido será removido deste aparelho.")
    }
  }
}
