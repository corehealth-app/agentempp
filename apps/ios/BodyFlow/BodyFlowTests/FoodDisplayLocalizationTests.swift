import Foundation
import Testing

@testable import BodyFlow

@Suite("Reviewed catalogue names are localized only at presentation")
struct FoodDisplayLocalizationTests {
  @Test(arguments: ["Oil, olive, salad or cooking", "Oil olive salad or cooking"])
  func oilNameAndReceiptCopyArePortugueseWithoutChangingNumbers(_ original: String) {
    #expect(FoodDisplayLocalization.name(original, english: false) == "azeite de oliva")
    let receipt = "\(original) · 5 g\n44,2 kcal | Proteína: 0 g"
    #expect(
      FoodDisplayLocalization.message(receipt, english: false)
        == "azeite de oliva · 5 g\n44,2 kcal | Proteína: 0 g")
    #expect(receipt.contains(original))
    #expect(FoodDisplayLocalization.message(receipt, english: true) == receipt)
  }
  @Test func knownEggPreparationIsPreservedAndUnknownQualifiersAreNotStripped() {
    #expect(
      FoodDisplayLocalization.name("Egg, whole, cooked, scrambled", english: false) == "ovo mexido")
    #expect(
      FoodDisplayLocalization.name("Egg, whole, cooked, fried", english: false) == "ovo frito")
    for value in ["pão francês com ovo", "Brand Egg whole cooked fried", "leite", "whey"] {
      #expect(FoodDisplayLocalization.name(value, english: false) == value)
    }
  }
  @Test func wireUnitsAreTranslatedWithoutChangingTheirProtocolValues() {
    #expect(NutritionQuantityPresentation.unit("unit", english: false) == "unidade")
    #expect(NutritionQuantityPresentation.unit("scoop", english: false) == "medida")
    #expect(NutritionQuantityPresentation.unit("unit", english: true) == "unit")
    for value in ["g", "kg", "mL", "L", "caneca"] {
      #expect(NutritionQuantityPresentation.unit(value, english: false) == value)
    }
  }

  @Test(arguments: ["whey", "Oil olive salad or cooking"])
  func coldJournalQuestionUsesPortugueseNamesAndUnits(_ food: String) throws {
    var page = try publicJournalV3Pages()[7]
    var rows = try #require(page["items"] as? [[String: Any]])
    var outcome = try #require(rows[0]["outcome"] as? [String: Any])
    let reference = MealQuantityDisplay.reference(for: food)
    let rawReference: Any =
      try reference.map {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode($0))
      } ?? NSNull()
    outcome["observed_question"] = [
      "kind": "quantity", "food_index": 0, "food_name": food,
      "allowed_units": ["g", "kg"] + (reference.map { [$0.unit] } ?? []),
      "quantity_reference": rawReference,
    ]
    rows[0]["outcome"] = outcome
    page["items"] = rows
    let entry = try #require(decodePublicJournalV3(page).items.first)
    let portuguese = FlowConversationJournalV3Presentation(entry: entry, english: false)
    let text = portuguese.lines.joined(separator: "\n")
    #expect(portuguese.source == "Comi leite")
    if food == "whey" {
      #expect(text.contains("g · kg · medida"))
      #expect(!text.contains("scoop"))
      let english = FlowConversationJournalV3Presentation(entry: entry, english: true)
      #expect(english.lines.contains("g · kg · scoop"))
    } else {
      #expect(text.contains("azeite de oliva"))
      #expect(!text.contains("salad or cooking"))
    }
  }
}
