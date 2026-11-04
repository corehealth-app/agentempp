import SwiftUI

@MainActor
struct FlowConversationMealEditorView: View {
  let model: FlowConversationMealEditModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.locale) private var locale
  private var english: Bool { BodyFlowPresentationLanguage.resolve(locale) == .englishUnitedStates }
  var body: some View {
    NavigationStack {
      ScrollView { FlowConversationMealEditorContent(model: model).padding(BodyFlowSpacing.md) }
        .background(BodyFlowColor.color(.backgroundPrimary))
        .navigationTitle(english ? "Meal edit" : "Editar refeição")
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

/// Same content is hosted directly by the native accessibility probes. The
/// wrapper owns only scrolling/navigation; every action uses the real model.
@MainActor
struct FlowConversationMealEditorContent: View {
  let model: FlowConversationMealEditModel
  @Environment(\.locale) private var locale
  @State private var discardID: ConversationMealEditOutboxID?
  private var language: SupportedAppLanguage { BodyFlowPresentationLanguage.resolve(locale) }
  private var english: Bool { language == .englishUnitedStates }
  var body: some View {
    VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
      if model.presentation != nil {
        if model.isLocked || !model.isItemForm {
          Text(
            model.hasPreparedIntent
              ? (english ? "Original edit preserved" : "Edição original preservada")
              : (english ? "Selected change" : "Alteração selecionada")
          )
          .font(BodyFlowTypography.cardTitle)
          if !model.foodName.isEmpty {
            Text(verbatim: model.foodName).accessibilityIdentifier("conversation.edit.locked-name")
            Text(verbatim: "\(model.quantityText(language: language)) \(model.quantityUnit)")
              .accessibilityIdentifier("conversation.edit.locked-quantity")
          }
          if model.pendingItems.count > 1 {
            ForEach(model.pendingItems.dropFirst()) { item in
              Text(
                verbatim: "\(item.foodName) · \(NSDecimalNumber(decimal: item.grams).stringValue) g"
              )
            }
          }
          if let action = model.formAction {
            switch action {
            case .save: EmptyView()
            case .undoSave: Text(english ? "Undo the original edit" : "Desfazer a edição original")
            case .undoRegistration:
              Text(english ? "Undo the original registration" : "Desfazer o registro original")
            }
          }
          Text(
            english
              ? "The original content is preserved. Check the edit's status to continue."
              : "O conteúdo original está preservado. Consulte o status da edição para continuar."
          )
          .foregroundStyle(BodyFlowColor.secondaryText)
        } else {
          Text(english ? "Food" : "Alimento").font(BodyFlowTypography.headline)
          TextField(
            english ? "Food name" : "Nome do alimento",
            text: Binding(get: { model.foodName }, set: { model.foodName = $0 })
          )
          .textFieldStyle(.roundedBorder).accessibilityIdentifier("conversation.edit.name")
          Text(english ? "Quantity" : "Quantidade").font(BodyFlowTypography.headline)
          HStack {
            TextField(
              english ? "Quantity" : "Quantidade",
              text: Binding(
                get: { model.quantityText(language: language) },
                set: { model.setQuantityText($0, language: language) })
            )
            .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("conversation.edit.quantity")
            Text(verbatim: model.quantityUnit).accessibilityIdentifier("conversation.edit.unit")
          }
          if model.canToggleQuantityUnit(language: language) {
            Button(
              model.quantityUnit == "g"
                ? (english ? "Use original unit" : "Usar unidade original")
                : (english ? "Enter grams" : "Informar gramas")
            ) { model.toggleQuantityUnit(language: language) }
            .accessibilityIdentifier("conversation.edit.toggle-unit")
          }
          if model.referenceChanged {
            Text(
              english
                ? "Quantity kept in grams using the original food reference."
                : "Quantidade preservada em gramas pela referência do alimento original."
            )
            .foregroundStyle(BodyFlowColor.secondaryText)
          } else if model.usesEstimatedReference {
            Text(
              english
                ? "Conversion uses this food's saved portion reference."
                : "A conversão usa a referência de porção salva deste alimento."
            )
            .foregroundStyle(BodyFlowColor.secondaryText)
          }
        }
        if model.isWorking {
          ProgressView(english ? "Waiting for confirmation…" : "Aguardando confirmação…")
        }
        if let failure = model.failure {
          Text(failureText(failure)).foregroundStyle(BodyFlowColor.secondaryText)
            .accessibilityIdentifier("conversation.edit.failure")
        }
        if model.canSave(language: language) || (!model.isLocked && model.isItemForm) {
          Button(
            model.hasPreparedIntent
              ? (english ? "Continue the original edit" : "Continuar edição original")
              : (english ? "Save edit" : "Salvar edição")
          ) { Task { await model.save(language: language) } }
          .buttonStyle(.borderedProminent).disabled(!model.canSave(language: language))
          .accessibilityIdentifier("conversation.edit.save")
        }
        if model.canCheckStatus {
          Button(english ? "Check status" : "Consultar status") { Task { await model.reconcile() } }
            .accessibilityIdentifier("conversation.edit.reconcile")
        }
        if model.canResubmit {
          Button(english ? "Resend the same edit" : "Reenviar a mesma edição") {
            Task { await model.resubmit() }
          }
          .accessibilityIdentifier("conversation.edit.resubmit")
        }
        if model.canDiscardUnsent, let operation = model.pendingOperation {
          Button(
            english ? "Discard unsent edit" : "Descartar edição não enviada", role: .destructive
          ) {
            discardID = .init(operation: operation)
          }.accessibilityIdentifier("conversation.edit.discard")
        }
      } else {
        Text(english ? "This editor is unavailable." : "Este editor está indisponível.")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("conversation.edit.content")
    .alert(
      english ? "Discard unsent edit?" : "Descartar edição não enviada?",
      isPresented: Binding(
        get: { discardID != nil }, set: { if !$0 { discardID = nil } }), presenting: discardID
    ) { id in
      Button(english ? "Discard" : "Descartar", role: .destructive) {
        Task { await model.discardUnsent(id: id) }
      }
      Button(english ? "Cancel" : "Cancelar", role: .cancel) {}
    } message: { _ in
      Text(
        english
          ? "Only an edit that was never dispatched can be discarded."
          : "Somente uma edição que nunca foi enviada pode ser descartada.")
    }
  }
  private func failureText(_ value: FlowConversationFailure) -> String {
    switch value {
    case .offline:
      english
        ? "Connection unavailable. The original edit is preserved."
        : "Sem conexão. A edição original está preservada."
    case .storage:
      english
        ? "Could not save the edit on this device. Its original intent is preserved here."
        : "Não foi possível guardar a edição neste dispositivo. A intenção original está preservada aqui."
    case .changed:
      english
        ? "The meal or account changed. The original edit is preserved for review."
        : "A refeição ou a conta mudou. A edição original está preservada para revisão."
    case .rateLimited:
      english
        ? "Please wait before checking again. The edit is preserved."
        : "Aguarde antes de consultar novamente. A edição está preservada."
    case .reconciliationRequired:
      english
        ? "Check the original edit's status before continuing."
        : "Consulte o status da edição original antes de continuar."
    case .unavailable, .invalidInput:
      english
        ? "The edit is unavailable right now. No success was assumed."
        : "A edição está indisponível no momento. A confirmação continua pendente."
    }
  }
}
