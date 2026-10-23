import Foundation
import Testing

@testable import BodyFlow

@Suite("Same-proposal ingredient recovery")
struct MealProposalListEditorTests {
    private let time = Date(timeIntervalSince1970: 1_792_773_000)

    private func registration(unknownFirst: Bool = false, unknownSecond: Bool = false,
                              reportedSentinel: Bool = false) throws -> RegistrationSnapshot {
        var envelope = try #require(JSONSerialization.jsonObject(
            with: MealCompositeRecoveryCharacterizationTests.responseJSON) as? [String: Any])
        var data = try #require(envelope["data"] as? [String: Any])
        var proposal = try #require(data["proposal"] as? [String: Any])
        var items = try #require(proposal["items"] as? [[String: Any]])
        if unknownFirst { items[0].removeValue(forKey: "user_kcal") }
        if unknownSecond { items[1].removeValue(forKey: "nutrition_source") }
        if reportedSentinel {
            // Declared synthetic third food, not the partially visible parmesan.
            items.append(["name": "Suco sentinela", "quantity_g": 250, "kcal": 55,
                "protein_g": 0, "carbs_g": 13, "fat_g": 0, "user_kcal": 55,
                "nutrition_source": "user_kcal", "resolution": "resolved", "quantity_basis": "stated"])
        }
        proposal["items"] = items; data["proposal"] = proposal; envelope["data"] = data
        return try JSONDecoder().decode(RegistrationProposalResponse.self,
            from: JSONSerialization.data(withJSONObject: envelope)).data
    }

    @Test("unchanged list preserves photo quantities, source, order and official provenance",
          arguments: SupportedAppLanguage.allCases)
    func unchanged(language: SupportedAppLanguage) throws {
        let list = MealProposalListEditorDraft(registration: try registration(), consumedAt: time, editedIndex: 1)
        #expect(list.initialEntryID == list.entries[1].id)
        #expect(list.blocker(language: language) == nil)
        let request = try #require(list.request(language: language))
        #expect(request.items.map(\.foodName) == ["macarrão espaguete cozido", "carne desfiada com molho e milho"])
        #expect(request.items.map(\.quantityG) == [200, 180])
        #expect(request.items.map(\.quantityBasis) == [.visualEstimate, .visualEstimate])
        #expect(request.items.map(\.userKcal) == [nil, nil])
        #expect(request.mealType == .lunch)
        #expect(request.consumedAt?.value == time)
        #expect(request.source?.channel == .gallery)
        #expect(request.source?.mediaAssetID == "394518b6-289b-4189-9297-e16637058e8e")
    }

    @Test("adding an ingredient never divides or copies the rejected total",
          arguments: SupportedAppLanguage.allCases)
    func addEmpty(language: SupportedAppLanguage) throws {
        var list = MealProposalListEditorDraft(registration: try registration(), consumedAt: time)
        let added = list.addIngredient()
        let id = try #require(added)
        let entry = try #require(list.entries.first { $0.id == id })
        #expect(entry.original == nil)
        #expect(entry.draft.foodName.isEmpty)
        #expect(entry.draft.quantityDisplay(language: language).isEmpty)
        #expect(list.entries[1].draft.quantityValue(language: language) == 180)
        #expect(list.blocker(language: language) == .invalidName(id))
        #expect(list.request(language: language) == nil)
    }

    @Test("explicit ingredient weights recover the list without changing the macaroni",
          arguments: SupportedAppLanguage.allCases)
    func explicitIngredients(language: SupportedAppLanguage) throws {
        var list = MealProposalListEditorDraft(registration: try registration(), consumedAt: time)
        list.remove(list.entries[1].id)
        // Synthetic user-entered ingredients/weights. They are not inferred
        // from the 180 g or offered as clinical facts about Roberto's plate.
        for (name, grams) in [("carne bovina desfiada cozida", "130"), ("molho de tomate", "30"), ("milho cozido", "20")] {
            let added = list.addIngredient()
            let id = try #require(added)
            list.updateEntry(id) {
                $0.foodName = name
                $0.setQuantityText(grams, language: language)
            }
        }
        let request = try #require(list.request(language: language))
        #expect(request.items.map(\.foodName) == ["macarrão espaguete cozido", "carne bovina desfiada cozida", "molho de tomate", "milho cozido"])
        #expect(request.items.map(\.quantityG) == [200, 130, 30, 20])
        #expect(request.items.map(\.quantityBasis) == [.visualEstimate, .stated, .stated, .stated])
        #expect(request.items.allSatisfy { $0.userKcal == nil })
        #expect(request.source?.channel == .gallery)
    }

    @Test("remove and undo restore identity, order and patient calorie overrides")
    func undoPreserves() throws {
        var list = MealProposalListEditorDraft(registration: try registration(reportedSentinel: true), consumedAt: time)
        let before = try #require(list.request(language: .portugueseBrazil))
        let entries = list.entries
        list.remove(entries[1].id)
        #expect(list.entries.map(\.id) == [entries[0].id, entries[2].id])
        #expect(list.canUndoRemoval)
        #expect(list.undoRemoval() == entries[1].id)
        #expect(list.entries == entries)
        #expect(list.request(language: .portugueseBrazil) == before)
        #expect(before.items.map(\.userKcal) == [nil, nil, 55])
    }

    @Test("unknown provenance needs an explicit server recalculation for that entry only")
    func unknownProvenance() throws {
        var list = MealProposalListEditorDraft(registration: try registration(unknownFirst: true, reportedSentinel: true), consumedAt: time)
        let id = list.entries[0].id
        #expect(list.blocker(language: .portugueseBrazil) == .item(id, .unknownKcalOrigin))
        list.updateEntry(id) { $0.manualKcalText = "500" }
        #expect(list.request(language: .portugueseBrazil) == nil)
        list.updateEntry(id) { $0.useServerCalculation() }
        let request = try #require(list.request(language: .portugueseBrazil))
        #expect(request.items.map(\.userKcal) == [nil, nil, 55])
        #expect(request.items.map(\.quantityG) == [200, 180, 250])
    }

    @Test("invalid names and quantities identify the affected entry")
    func invalidEntry() throws {
        var list = MealProposalListEditorDraft(registration: try registration(), consumedAt: time)
        let id = list.entries[1].id
        list.updateEntry(id) { $0.foodName = "   " }
        #expect(list.blocker(language: .portugueseBrazil) == .invalidName(id))
        list.updateEntry(id) { $0.foodName = String(repeating: "a", count: 161) }
        #expect(list.blocker(language: .portugueseBrazil) == .invalidName(id))
        list.updateEntry(id) { $0.foodName = "milho"; $0.quantityText = "0" }
        #expect(list.blocker(language: .portugueseBrazil) == .item(id, .invalidQuantity))
    }

    @Test("the 30 food contract and undo capacity are enforced without losing removed entries")
    func capacity() throws {
        var list = MealProposalListEditorDraft(registration: try registration(), consumedAt: time)
        let first = list.entries[0].id
        list.remove(first)
        while list.entries.count < 30 {
            let added = list.addIngredient()
            _ = try #require(added)
        }
        #expect(!list.canAdd)
        #expect(list.addIngredient() == nil)
        #expect(!list.canUndoRemoval)
        #expect(list.undoRemoval(first) == nil)
        #expect(list.removedEntries.map(\.id) == [first])
        let last = try #require(list.entries.last).id
        list.remove(last)
        #expect(list.undoRemoval(first) == first)
        #expect(list.entries.first?.id == first)
        #expect(list.entries.first?.draft.quantityValue(language: .portugueseBrazil) == 200)
        #expect(list.removedEntries.map(\.id) == [last])
        #expect(list.undoRemoval(last) == nil)
        #expect(list.entries.count == 30)
    }

    @Test("undoing removals in a different order preserves the original food order")
    func undoOutOfOrder() throws {
        var list = MealProposalListEditorDraft(registration: try registration(reportedSentinel: true), consumedAt: time)
        let original = list.entries
        list.remove(original[0].id); list.remove(original[1].id)
        #expect(list.undoRemoval(original[0].id) == original[0].id)
        #expect(list.undoRemoval(original[1].id) == original[1].id)
        #expect(list.entries == original)
    }

    @Test("recalculating one unknown food never authorizes another unknown food")
    func twoUnknownFoods() throws {
        var list = MealProposalListEditorDraft(registration: try registration(unknownFirst: true, unknownSecond: true), consumedAt: time)
        let first = list.entries[0].id, second = list.entries[1].id
        list.updateEntry(first) { $0.useServerCalculation() }
        #expect(list.entry(id: first)?.draft.hasUnknownKcalOrigin == true)
        #expect(list.blocker(language: .portugueseBrazil) == .item(second, .unknownKcalOrigin))
        #expect(list.request(language: .portugueseBrazil) == nil)
        list.updateEntry(second) { $0.useServerCalculation() }
        #expect(list.request(language: .portugueseBrazil)?.items.map(\.userKcal) == [nil, nil])
    }

    @Test("editing two foods before one save keeps both edits and the global meal context")
    func twoEdits() throws {
        var list = MealProposalListEditorDraft(registration: try registration(reportedSentinel: true), consumedAt: time)
        list.updateEntry(list.entries[0].id) { $0.foodName = "arroz cozido"; $0.quantityText = "100" }
        list.updateEntry(list.entries[1].id) { $0.foodName = "milho cozido"; $0.quantityText = "20" }
        list.mealType = .breakfast
        list.consumedAt = time.addingTimeInterval(-3600)
        let request = try #require(list.request(language: .portugueseBrazil))
        #expect(request.items.map(\.foodName) == ["arroz cozido", "milho cozido", "Suco sentinela"])
        #expect(request.items.map(\.quantityG) == [100, 20, 250])
        #expect(request.items.map(\.quantityBasis) == [.stated, .stated, .stated])
        #expect(request.items.map(\.userKcal) == [nil, nil, 55])
        #expect(request.mealType == .breakfast)
        #expect(request.consumedAt?.value == time.addingTimeInterval(-3600))
    }

    @Test("remove and undo keep exact grams, display mode, label provenance and edited calorie text")
    func preciseUndo() throws {
        let item = try JSONDecoder().decode(MealProposalItemSnapshot.self, from: Data(#"{"name":"whey","quantity_g":25.123456789,"kcal":100,"user_kcal":null,"nutrition_source":"product_label","quantity_basis":"portion_reference","quantity_display":{"unit":"scoop","grams_per_unit":30,"reference_id":"app-household-whey-scoop-v1","estimated":true}}"#.utf8))
        let snapshot = RegistrationSnapshot(id: "precise-synthetic", status: "pending", createdAt: APITimestamp(value: time), expiresAt: APITimestamp(value: time.addingTimeInterval(3600)), resolvedAt: nil, proposal: .meal(MealProposalSnapshot(mealType: "almoco", items: [item], totals: nil, warnings: [], source: MealProposalSourceSnapshot(channel: "gallery", mediaAssetID: "394518b6-289b-4189-9297-e16637058e8e"))))
        var list = MealProposalListEditorDraft(registration: snapshot, consumedAt: time)
        let id = list.entries[0].id
        list.updateEntry(id) { $0.toggleQuantityUnit(language: .portugueseBrazil) }
        let before = list.entries[0]
        list.remove(id); _ = list.undoRemoval(id)
        #expect(list.entries[0] == before)
        let request = try #require(list.request(language: .portugueseBrazil))
        #expect(request.items[0].quantityG == Decimal(string: "25.123456789"))
        #expect(request.items[0].quantityBasis == .portionReference)
        #expect(request.items[0].usesNutritionLabel)
        list.updateEntry(id) { $0.manualKcalText = "121,5" }
        let edited = list.entries[0]
        list.remove(id); _ = list.undoRemoval(id)
        #expect(list.entries[0] == edited)
        #expect(list.request(language: .portugueseBrazil)?.items[0].userKcal == Decimal(string: "121.5"))
        #expect(list.request(language: .portugueseBrazil)?.items[0].usesNutritionLabel == false)
    }

    @Test("removing every item blocks saving and undo recovers the original proposal")
    func emptyList() throws {
        var list = MealProposalListEditorDraft(registration: try registration(), consumedAt: time)
        let original = list.entries
        for entry in original { list.remove(entry.id) }
        #expect(list.blocker(language: .portugueseBrazil) == .noItems)
        #expect(list.request(language: .portugueseBrazil) == nil)
        _ = list.undoRemoval(); _ = list.undoRemoval()
        #expect(list.entries == original)
        #expect(list.request(language: .portugueseBrazil) != nil)
    }

    @Test("an oversized incoming proposal is kept intact and cannot be submitted")
    func oversizedSnapshot() throws {
        let base = try registration()
        guard case let .meal(meal) = base.proposal else { Issue.record("Expected meal fixture"); return }
        let items = Array(repeating: meal.items[0], count: 31)
        let snapshot = RegistrationSnapshot(id: base.id, status: base.status,
            createdAt: base.createdAt, expiresAt: base.expiresAt, resolvedAt: nil,
            proposal: .meal(.init(mealType: meal.mealType, items: items, totals: nil, warnings: [])))
        let list = MealProposalListEditorDraft(registration: snapshot, consumedAt: time)
        #expect(list.entries.count == 31)
        #expect(list.blocker(language: .portugueseBrazil) == .tooManyItems)
        #expect(list.request(language: .portugueseBrazil) == nil)
    }

    @Test("a stale field binding cannot modify a different food after removal")
    func staleIdentity() throws {
        var list = MealProposalListEditorDraft(registration: try registration(), consumedAt: time)
        let staleID = list.entries[0].id
        let survivor = list.entries[1]
        list.remove(staleID)
        list.updateEntry(staleID) { $0.foodName = "must not replace the survivor" }
        #expect(list.entries == [survivor])
        _ = list.undoRemoval(staleID)
        #expect(list.entries[0].draft.foodName == "macarrão espaguete cozido")
    }
}
