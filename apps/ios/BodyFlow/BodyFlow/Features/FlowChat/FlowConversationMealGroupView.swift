import SwiftUI

/// Current consumed facts from a fresh owned read. Historical feedback remains
/// a separate immutable disclosure in the parent; nothing here recalculates
/// macros, targets, remaining budget or educational guidance.
struct FlowConversationMealGroupView: View {
  let group: ConversationMealGroupSnapshot
  var editing: FlowConversationMealEditActions? = nil
  var showsFacts = true
  var showsCurrentQuantity = false
  @State private var undoRequest: UndoRequest?
  private struct UndoRequest {
    let group: ConversationMealGroupSnapshot
    let save: Bool
  }
  @Environment(\.locale) private var locale
  private var language: SupportedAppLanguage { BodyFlowPresentationLanguage.resolve(locale) }
  private var english: Bool { language == .englishUnitedStates }

  var body: some View {
    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
      Text(
        showsFacts || showsCurrentQuantity
          ? (english ? "Current meal" : "Refeição atual")
          : (english ? "Recorded foods" : "Alimentos registrados")
      )
      .font(BodyFlowTypography.cardTitle).accessibilityAddTraits(.isHeader)
      .accessibilityIdentifier("conversation.meal.current-title")
      if (showsFacts || showsCurrentQuantity) && group.revision > 0 {
        Label(
          english
            ? "Updated after the original registration" : "Atualizada após o registro original",
          systemImage: "pencil"
        )
        .font(BodyFlowTypography.caption).foregroundStyle(BodyFlowColor.secondaryText)
      }
      if let current = group.current {
        ForEach(current.items, id: \.id) { item in
          HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
              Text(verbatim: item.foodName).font(BodyFlowTypography.headline)
              if showsFacts || showsCurrentQuantity {
                Text(quantity(item)).accessibilityIdentifier("conversation.meal.current-quantity")
              }
              if showsFacts {
                Text(
                  verbatim:
                    "\(amount(item.kcal)) kcal · P \(amount(item.proteinG)) g · C \(amount(item.carbsG)) g · \(english ? "F" : "G") \(amount(item.fatG)) g"
                )
                .foregroundStyle(BodyFlowColor.secondaryText)
              }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(
              "conversation.meal.current-item.\(item.id.uuidString.lowercased())")
            Spacer(minLength: BodyFlowSpacing.sm)
            if let editing, group.actions.save.allowed {
              Button {
                editing.editItem(item)
              } label: {
                Image(systemName: "pencil")
              }
              .buttonStyle(.bordered).disabled(editing.isWorking)
              .accessibilityLabel(english ? "Edit \(item.foodName)" : "Editar \(item.foodName)")
              .accessibilityIdentifier("conversation.meal.edit.\(item.id.uuidString.lowercased())")
            }
          }
        }
      } else if group.lastOperation?.kind == .registrationUndone {
        Text(english ? "Registration undone" : "Registro desfeito")
          .accessibilityIdentifier("conversation.meal.registration-undone")
      } else {
        Text(
          english
            ? "Current meal details are unavailable. This does not mean zero consumption."
            : "Os dados atuais da refeição estão indisponíveis. Isso não significa consumo zero.")
      }
      if let editing {
        if group.actions.undoSave.allowed {
          Button(english ? "Undo last edit" : "Desfazer última edição") {
            undoRequest = .init(group: group, save: true)
          }.disabled(editing.isWorking).accessibilityIdentifier("conversation.meal.undo-save")
        }
        if group.actions.undoRegistration.allowed {
          Button(english ? "Undo registration" : "Desfazer registro", role: .destructive) {
            undoRequest = .init(group: group, save: false)
          }.disabled(editing.isWorking).accessibilityIdentifier(
            "conversation.meal.undo-registration")
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("conversation.meal.current")
    .alert(
      english ? "Undo this change?" : "Desfazer esta alteração?",
      isPresented: Binding(
        get: { undoRequest != nil }, set: { if !$0 { undoRequest = nil } }), presenting: undoRequest
    ) { request in
      Button(english ? "Undo" : "Desfazer", role: .destructive) {
        if request.save {
          editing?.undoSave(request.group)
        } else {
          editing?.undoRegistration(request.group)
        }
      }
      Button(english ? "Cancel" : "Cancelar", role: .cancel) {}
    } message: { request in
      Text(
        request.save
          ? (english ? "Undo the selected saved edit." : "Desfazer a edição salva selecionada.")
          : (english ? "Undo this meal registration." : "Desfazer o registro desta refeição."))
    }
  }
  private func quantity(_ item: ConversationMealGroupSnapshot.Item) -> String {
    let grams = item.quantityG.flatMap {
      Decimal(string: String($0), locale: Locale(identifier: "en_US_POSIX"))
    }
    let value = MealQuantityValue(grams: grams, metadata: item.quantityDisplay, name: item.foodName)
    guard let label = value.label(language: language) else {
      return english ? "Quantity unavailable" : "Quantidade indisponível"
    }
    return value.usesReference ? "\(label) (\(amount(item.quantityG)) g)" : label
  }
  private func amount(_ value: Double?) -> String {
    guard let value else { return "—" }
    return value.formatted(
      .number.locale(language.formattingLocale).precision(.fractionLength(0...2)))
  }
}
