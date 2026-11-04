import SwiftUI

/// Current consumed facts from a fresh owned read. Historical feedback remains
/// a separate immutable disclosure in the parent; nothing here recalculates
/// macros, targets, remaining budget or educational guidance.
struct FlowConversationMealGroupView: View {
  let group: ConversationMealGroupSnapshot
  @Environment(\.locale) private var locale
  private var language: SupportedAppLanguage { BodyFlowPresentationLanguage.resolve(locale) }
  private var english: Bool { language == .englishUnitedStates }

  var body: some View {
    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
      Text(english ? "Current meal" : "Refeição atual")
        .font(BodyFlowTypography.cardTitle).accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("conversation.meal.current-title")
      if group.revision > 0 {
        Label(
          english
            ? "Updated after the original registration" : "Atualizada após o registro original",
          systemImage: "pencil"
        )
        .font(BodyFlowTypography.caption).foregroundStyle(BodyFlowColor.secondaryText)
      }
      if let current = group.current {
        ForEach(current.items, id: \.id) { item in
          VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
            Text(verbatim: item.foodName).font(BodyFlowTypography.headline)
            Text(quantity(item)).accessibilityIdentifier("conversation.meal.current-quantity")
            Text(
              verbatim:
                "\(amount(item.kcal)) kcal · P \(amount(item.proteinG)) g · C \(amount(item.carbsG)) g · \(english ? "F" : "G") \(amount(item.fatG)) g"
            )
            .foregroundStyle(BodyFlowColor.secondaryText)
          }
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier(
            "conversation.meal.current-item.\(item.id.uuidString.lowercased())")
        }
      } else {
        Text(
          english
            ? "Current meal details are unavailable. This does not mean zero consumption."
            : "Os dados atuais da refeição estão indisponíveis. Isso não significa consumo zero.")
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("conversation.meal.current")
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
