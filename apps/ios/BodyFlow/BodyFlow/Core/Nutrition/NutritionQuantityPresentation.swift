import Foundation

struct NutritionQuantityPresentation {
  let text: String
  let reference: String?
  static func consumed(_ meal: NutritionWindowMeal, locale: Locale, english: Bool) -> Self {
    guard let display = meal.displayQuantity else {
      return .init(text: "\(number(meal.quantityG,locale:locale)) g", reference: nil)
    }
    let text =
      "\(display.estimated ? "≈" : "")\(number(display.value,locale:locale)) \(unit(display.unit,english:english))"
    let reference =
      display.estimated
      ? "\(english ? "Original reference" : "Referência original"): \(number(display.reference.value,locale:locale)) \(unit(display.reference.unit,english:english)) / \(number(display.reference.quantityG,locale:locale)) g"
      : nil
    return .init(text: text, reference: reference)
  }
  static func planned(_ item: NutritionWindowPlannedItem, locale: Locale, english: Bool) -> Self {
    if let value = item.displayQty, let name = item.displayUnit {
      return .init(
        text: "\(number(value,locale:locale)) \(unit(name,english:english))", reference: nil)
    }
    return .init(text: "\(number(item.quantityG,locale:locale)) g", reference: nil)
  }
  private static func number(_ value: Decimal?, locale: Locale) -> String {
    value.map { $0.formatted(.number.locale(locale).precision(.fractionLength(0...2))) } ?? "—"
  }
  private static func unit(_ raw: String, english: Bool) -> String {
    switch raw {
    case "scoop": english ? "scoop" : "medida"
    case "unit": english ? "unit" : "un."
    default: raw
    }
  }
}
