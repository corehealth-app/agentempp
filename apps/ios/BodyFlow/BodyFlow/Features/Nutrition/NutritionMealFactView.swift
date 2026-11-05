import SwiftUI

/// A confirmed fact row supplied by the owned window, without read/write authority.
struct NutritionMealFactView: View {
  let meal: NutritionWindowMeal
  let english: Bool
  @Environment(\.locale) private var locale
  var body: some View {
    let quantity = NutritionQuantityPresentation.consumed(meal, locale: locale, english: english)
    VStack(alignment: .leading, spacing: 3) {
      Text(meal.foodName).font(.body)
      Text(
        "\(quantity.text) · \(amount(meal.kcal)) kcal · \(english ? "Protein" : "Proteína") \(amount(meal.proteinG)) g"
      )
      .font(.caption).foregroundStyle(.secondary)
      if let reference = quantity.reference {
        Text(reference).font(.caption2).foregroundStyle(.secondary)
      }
    }.accessibilityElement(children: .combine)
      .accessibilityIdentifier("nutrition.consumed.\(meal.id.uuidString.lowercased())")
  }
  private func amount(_ value: Decimal?) -> String {
    value.map { $0.formatted(.number.locale(locale).precision(.fractionLength(0...2))) } ?? "—"
  }
}
