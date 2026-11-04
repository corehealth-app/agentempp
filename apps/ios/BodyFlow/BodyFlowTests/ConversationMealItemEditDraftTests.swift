import Foundation
import Testing

@testable import BodyFlow

@Suite("Conversation item editor preserves quantity authorship")
struct ConversationMealItemEditDraftTests {
  @Test func milkStartsInMillilitersAndKeepsExactOfficialMass() throws {
    let original = try item("milk")
    let draft = ConversationMealItemEditDraft(original)
    #expect(draft.quantityUnit == "mL")
    #expect(draft.quantityText(language: .portugueseBrazil) == "200")
    #expect(draft.usesEstimatedReference)
    #expect(try #require(draft.request(language: .portugueseBrazil)).quantityG == 206)
    #expect(!draft.hasChanges(language: .portugueseBrazil))
    #expect(draft.request(language: .portugueseBrazil)?.quantityBasis == nil)
  }
  @Test func milkDecimalVolumeAndWheyScoopUseOnlyQualifiedReferences() throws {
    var milk = ConversationMealItemEditDraft(try item("milk"))
    milk.setQuantityText("250,5", language: .portugueseBrazil)
    let milkRequest = try #require(milk.request(language: .portugueseBrazil))
    #expect(milkRequest.quantityG == Decimal(string: "258.015"))
    #expect(milkRequest.quantityBasis == .portionReference)
    #expect(milkRequest.userKcal == nil && milkRequest.candidateID == nil)
    var whey = ConversationMealItemEditDraft(try item("whey"))
    #expect(whey.quantityUnit == "scoop")
    whey.setQuantityText("1,5", language: .portugueseBrazil)
    #expect(whey.request(language: .portugueseBrazil)?.quantityG == 45)
    #expect(whey.request(language: .portugueseBrazil)?.quantityBasis == .portionReference)
    #expect(whey.hasChanges(language: .portugueseBrazil))
  }
  @Test func unitToggleAndFormattedEchoNeverRoundOriginalOrAuthoredMass() throws {
    var raw = try payload("milk")
    try change(&raw, "quantity_g", 206.123456789)
    let original = try decodeItem(raw)
    var draft = ConversationMealItemEditDraft(original)
    let exact = try #require(draft.request(language: .portugueseBrazil)).quantityG
    let visible = draft.quantityText(language: .portugueseBrazil)
    draft.setQuantityText(visible, language: .portugueseBrazil)
    draft.toggleQuantityUnit(language: .portugueseBrazil)
    #expect(draft.quantityUnit == "g")
    #expect(draft.request(language: .portugueseBrazil)?.quantityG == exact)
    #expect(draft.request(language: .portugueseBrazil)?.quantityBasis == nil)
    draft.toggleQuantityUnit(language: .portugueseBrazil)
    draft.setQuantityText("1,123456789", language: .portugueseBrazil)
    let typed = draft.request(language: .portugueseBrazil)?.quantityG
    draft.toggleQuantityUnit(language: .portugueseBrazil)
    draft.setQuantityText(
      draft.quantityText(language: .portugueseBrazil), language: .portugueseBrazil)
    draft.toggleQuantityUnit(language: .portugueseBrazil)
    #expect(draft.request(language: .portugueseBrazil)?.quantityG == typed)
  }
  @Test func renamingNeverReinterpretsAnAuthoredScoopAsGrams() throws {
    var draft = ConversationMealItemEditDraft(try item("whey"))
    draft.setQuantityText("1,5", language: .portugueseBrazil)
    draft.foodName = "Arroz cozido"
    #expect(draft.quantityUnit == "g" && draft.referenceChanged)
    #expect(draft.quantityText(language: .portugueseBrazil) == "45")
    #expect(draft.request(language: .portugueseBrazil)?.quantityG == 45)
    #expect(!draft.canToggleQuantityUnit(language: .portugueseBrazil))
    draft.setQuantityText("20", language: .portugueseBrazil)
    #expect(draft.request(language: .portugueseBrazil)?.quantityG == 20)
    #expect(draft.request(language: .portugueseBrazil)?.quantityBasis == .stated)
    draft.foodName = "whey"
    #expect(draft.quantityUnit == "scoop")
    #expect(draft.request(language: .portugueseBrazil)?.quantityG == 20)
    draft.toggleQuantityUnit(language: .portugueseBrazil)
    #expect(draft.quantityText(language: .portugueseBrazil) == "20")
  }
  @Test func explicitGramInputNeverUsesTheVolumeFactor() throws {
    var draft = ConversationMealItemEditDraft(try item("milk"))
    draft.toggleQuantityUnit(language: .englishUnitedStates)
    draft.setQuantityText("200.5", language: .englishUnitedStates)
    #expect(draft.request(language: .englishUnitedStates)?.quantityG == Decimal(string: "200.5"))
    #expect(draft.request(language: .englishUnitedStates)?.quantityBasis == .stated)
    #expect(draft.request(language: .englishUnitedStates)?.foodName == draft.foodName)
  }
  @Test(arguments: ["", "0", "-1", "1e3", "1.234", "1,2,3", "1 000", "nan", "99999", "1 g"])
  func invalidInputNeverBecomesZeroOrARequest(_ text: String) throws {
    var draft = ConversationMealItemEditDraft(try item("milk"))
    draft.setQuantityText(text, language: .portugueseBrazil)
    #expect(draft.request(language: .portugueseBrazil) == nil)
    #expect(!draft.canToggleQuantityUnit(language: .portugueseBrazil))
  }
  @Test func missingMassAndNamesAreNotFabricatedOrTruncated() throws {
    var raw = try payload("group")
    try change(&raw, "quantity_g", NSNull())
    var draft = ConversationMealItemEditDraft(try decodeItem(raw))
    #expect(draft.quantityText(language: .portugueseBrazil).isEmpty)
    #expect(draft.request(language: .portugueseBrazil) == nil)
    draft.setQuantityText("120", language: .portugueseBrazil)
    #expect(draft.request(language: .portugueseBrazil)?.quantityG == 120)
    draft.foodName = String(repeating: "x", count: 161)
    #expect(draft.request(language: .portugueseBrazil) == nil)
    draft.foodName = "  "
    #expect(draft.request(language: .portugueseBrazil) == nil)
  }
  @Test func quantityOnlyEditDoesNotChangeTheOriginalPublicItem() throws {
    let original = try item("milk")
    var draft = ConversationMealItemEditDraft(original)
    draft.setQuantityText("300", language: .portugueseBrazil)
    #expect(original.quantityG == 206 && original.quantityDisplay?.unit == "mL")
    let request = try #require(draft.request(language: .portugueseBrazil))
    #expect(request.foodName == original.foodName && request.quantityG == 309)
    #expect(request.userKcal == nil && request.candidateID == nil)
    #expect(draft.recordID == original.id)
  }
  private func payload(_ key: String) throws -> [String: Any] {
    #if SWIFT_PACKAGE
      let url = try #require(
        Bundle.module.url(forResource: "ConversationMealEditPublicFixtures", withExtension: "json"))
    #else
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
        "Fixtures/ConversationMealEditPublicFixtures.json")
    #endif
    let root = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let envelope = try #require(root[key] as? [String: Any])
    return try #require(envelope["data"] as? [String: Any])
  }
  private func item(_ key: String) throws -> ConversationMealGroupSnapshot.Item {
    try decodeItem(payload(key))
  }
  private func decodeItem(_ payload: [String: Any]) throws -> ConversationMealGroupSnapshot.Item {
    let group = try ConversationMealGroupSnapshot(
      data: JSONSerialization.data(withJSONObject: payload))
    return try #require(group.current?.items.first)
  }
  private func change(_ payload: inout [String: Any], _ key: String, _ value: Any) throws {
    var current = try #require(payload["current"] as? [String: Any])
    var items = try #require(current["items"] as? [[String: Any]])
    items[0][key] = value
    current["items"] = items
    payload["current"] = current
  }
}
