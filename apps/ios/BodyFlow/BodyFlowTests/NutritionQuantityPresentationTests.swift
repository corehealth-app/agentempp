import Foundation
import Testing

@testable import BodyFlow

@Suite("Actual SQL unit pieces preserve sealed units through the native presentation")
struct NutritionQuantityPresentationTests {
  @Test(arguments: ["milk", "whey"])
  func originalSavedReopenedAndUndoneUseTheProvedCurrentIdentity(_ food: String) throws {
    let fixture = try NutritionActualUnitFixture()
    let original = try fixture.meal(food: food, stage: "original")
    let saved = try fixture.meal(food: food, stage: "saved")
    let undone = try fixture.meal(food: food, stage: "undone")
    let locale = Locale(identifier: "pt_BR")
    let a = NutritionQuantityPresentation.consumed(original, locale: locale, english: false)
    let b = NutritionQuantityPresentation.consumed(saved, locale: locale, english: false)
    let c = NutritionQuantityPresentation.consumed(undone, locale: locale, english: false)
    #expect(a.text == (food == "milk" ? "200 mL" : "1 medida") && a.reference == nil)
    #expect(b.text == (food == "milk" ? "≈400 mL" : "≈1,33 medida"))
    #expect(b.reference?.contains(food == "milk" ? "206 g" : "30 g") == true)
    #expect(c.text == a.text && c.reference == nil)
    #expect(saved.id != original.id && undone.id != original.id && undone.id != saved.id)
    #expect(saved.displayQuantity?.provenance == .auditedSameFoodScale)
    #expect(undone.displayQuantity?.provenance == .auditedRestore)
  }
  @Test func legacyMassAndAnUnprovedMilkNameNeverAcquireAnInventedUnit() throws {
    let fixture = try NutritionActualUnitFixture()
    let legacy = try fixture.meal(food: "legacy", stage: "original")
    #expect(
      NutritionQuantityPresentation.consumed(
        legacy, locale: Locale(identifier: "pt_BR"), english: false
      ).text == "100 g")
    var raw = try fixture.raw(food: "milk", stage: "original")
    raw["display_quantity"] = NSNull()
    let milk = try JSONDecoder().decode(
      NutritionWindowMeal.self, from: JSONSerialization.data(withJSONObject: raw))
    #expect(
      NutritionQuantityPresentation.consumed(
        milk, locale: Locale(identifier: "pt_BR"), english: false
      ).text == "206 g")
  }
  @Test func prescribedExplicitUnitIsPrimaryWithoutReplacingItWithGrams() throws {
    let raw: [String: Any] = [
      "food_name": "whey", "quantity_g": 30, "display_qty": 1, "display_unit": "scoop",
    ]
    let item = try JSONDecoder().decode(
      NutritionWindowPlannedItem.self, from: JSONSerialization.data(withJSONObject: raw))
    #expect(
      NutritionQuantityPresentation.planned(
        item, locale: Locale(identifier: "pt_BR"), english: false
      ).text == "1 medida")
  }
}
struct NutritionActualUnitFixture {
  private let records: [[String: Any]]
  init() throws {
    #if SWIFT_PACKAGE
      let url = try #require(
        Bundle.module.url(forResource: "NutritionWindowUnitsProjectedFacts", withExtension: "json"))
    #else
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
        "Fixtures/NutritionWindowUnitsProjectedFacts.json")
    #endif
    let root = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    records = try #require(root["records"] as? [[String: Any]])
  }
  func raw(food: String, stage: String) throws -> [String: Any] {
    let record = try #require(
      records.first { $0["food"] as? String == food && $0["stage"] as? String == stage })
    return try #require(record["meal"] as? [String: Any])
  }
  func meal(food: String, stage: String) throws -> NutritionWindowMeal {
    try JSONDecoder().decode(
      NutritionWindowMeal.self,
      from: JSONSerialization.data(withJSONObject: raw(food: food, stage: stage)))
  }
}
