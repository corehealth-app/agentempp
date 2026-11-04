import Foundation

/// Local name/quantity working copy for one current item. It creates no
/// operation UUID, version, lease, calories, registration or acknowledgement.
/// Conversion stays tied to the reference the person actually typed against.
struct ConversationMealItemEditDraft: Sendable {
  let recordID: UUID
  var foodName: String
  private let originalName: String
  private let originalReference: MealQuantityValue
  private var quantityEntry = MealQuantityEntry()

  init(_ item: ConversationMealGroupSnapshot.Item) {
    recordID = item.id
    foodName = item.foodName
    originalName = item.foodName
    let grams = item.quantityG.flatMap { try? editDecimal($0) }
    originalReference = MealQuantityValue(
      grams: grams, metadata: item.quantityDisplay, name: item.foodName)
  }

  /// A rename cannot carry a milk density or whey scoop to a different food.
  /// Existing authored input is converted with its ORIGINAL reference, then
  /// shown in grams; it is never re-read as a different unit or erased.
  var referenceChanged: Bool {
    guard let reference = originalReference.metadata else { return false }
    return reference.validated(for: foodName) == nil
  }
  private var displaysReference: Bool {
    originalReference.usesReference && !quantityEntry.displaysGrams && !referenceChanged
  }
  var quantityUnit: String { displaysReference ? originalReference.unit : "g" }
  var usesEstimatedReference: Bool { displaysReference }

  func quantityText(language: SupportedAppLanguage) -> String {
    let grams = quantityEntry.grams(originalReference, language: language)
    if let text = quantityEntry.text {
      if grams == nil || quantityEntry.typedUsingReference == displaysReference { return text }
    }
    return originalReference.presenting(grams: grams, inGrams: !displaysReference)
      .displayText(language: language)
  }
  mutating func setQuantityText(_ text: String, language: SupportedAppLanguage) {
    // SwiftUI may echo a formatted conversion. Preserve the unrounded source
    // and unit of authorship until the person actually changes that text.
    guard text != quantityText(language: language) else { return }
    quantityEntry.setText(text, usesReference: displaysReference)
  }
  func canToggleQuantityUnit(language: SupportedAppLanguage) -> Bool {
    !referenceChanged && quantityEntry.canToggle(originalReference, language: language)
  }
  mutating func toggleQuantityUnit(language: SupportedAppLanguage) {
    guard canToggleQuantityUnit(language: language) else { return }
    quantityEntry.toggle(originalReference, language: language)
  }
  func hasChanges(language: SupportedAppLanguage) -> Bool {
    editECMATrim(foodName) != originalName
      || quantityEntry.grams(originalReference, language: language)
        != originalReference.canonicalGrams
  }
  func request(language: SupportedAppLanguage) -> ConversationMealEditOperation.Item? {
    guard let grams = quantityEntry.grams(originalReference, language: language) else { return nil }
    let basis: ConversationMealEditOperation.Item.QuantityBasis? =
      quantityEntry.text == nil
      ? nil : (quantityEntry.typedUsingReference ? .portionReference : .stated)
    // Public current items contain no candidate attribution. Do not manufacture
    // one, infer a visual basis, copy calculated kcal, or require manual kcal.
    return try? ConversationMealEditOperation.Item(
      foodName: editECMATrim(foodName), quantityG: grams, quantityBasis: basis)
  }
}
