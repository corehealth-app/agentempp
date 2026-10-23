import Foundation
import Testing
@testable import BodyFlow

@Suite("Roberto23/10 household measures")
struct MealHouseholdQuantityTests {
    private let pt = SupportedAppLanguage.portugueseBrazil
    private let en = SupportedAppLanguage.englishUnitedStates
    private let bread = #"{"unit":"unit","grams_per_unit":30,"reference_id":"app-household-cheese-bread-unit-v1","estimated":true}"#
    private let whey = #"{"unit":"scoop","grams_per_unit":30,"reference_id":"app-household-whey-scoop-v1","estimated":true}"#

    private func candidate(name: String, grams: String, metadata: String) throws -> MealDraftCandidate {
        try JSONDecoder().decode(MealDraftCandidate.self, from: Data("""
        {"candidate_id":"c1-12345678","name":"\(name)","quantity_g":\(grams),"quantity_basis":"portion_reference","count":\(name == "whey" ? 1 : 8),"unit_label":"\(name == "whey" ? "medida" : "unidade")","confidence":null,"needs_review":true,"review_reason":"estimated_quantity","quantity_display":\(metadata)}
        """.utf8))
    }

    @Test("Exact screenshot pão de queijo com requeijão240g/8units: edit3units sends90g")
    func breadUnits() throws {
        var item = MealDraftReview.Item(candidate: try candidate(name: "pão de queijo com requeijão", grams: "240", metadata: bread))
        #expect(item.quantityDisplay(language: pt) == "8")
        #expect(item.quantity(language: pt) == 240)
        item.setQuantityText("3", language: pt)
        #expect(item.quantity(language: pt) == 90)
        #expect(item.basis == .portionReference)
        item.name = "arroz"
        #expect(item.quantity(language: pt) == nil)
    }

    @Test("Exact whey screenshot:1measure instead of demanding the weight;2measures sends60g")
    func wheyMeasures() throws {
        var item = MealDraftReview.Item(candidate: try candidate(name: "whey", grams: "30", metadata: whey))
        #expect(item.quantityDisplay(language: pt) == "1")
        #expect(item.hasApproximateQuantity)
        item.setQuantityText("2", language: en)
        #expect(item.quantity(language: en) == 60)
        #expect(item.basis == .portionReference)
    }

    @Test("Only changing display mode preserves precise original grams and approximate provenance")
    func untouchedModeRoundTrip() throws {
        var item = MealDraftReview.Item(candidate: try candidate(name: "whey", grams: "25.123456789", metadata: whey))
        for _ in 0..<8 { item.toggleQuantityUnit(language: pt) }
        #expect(item.quantity(language: pt) == Decimal(string: "25.123456789"))
        #expect(!item.hasTypedQuantity)
        #expect(item.hasApproximateQuantity)
        #expect(item.basis == .portionReference)
    }

    @Test("25g of whey stays25g and stated after returning to estimated measures; invalid input remains blocked")
    func realScoopWeight() throws {
        var item = MealDraftReview.Item(candidate: try candidate(name: "whey", grams: "30", metadata: whey))
        item.toggleQuantityUnit(language: pt)
        item.setQuantityText("25", language: pt)
        item.toggleQuantityUnit(language: pt)
        #expect(item.quantity(language: pt) == 25)
        #expect(item.basis == .stated)
        #expect(item.quantityDisplay(language: pt).hasPrefix("0,833"))
        item.setQuantityText("", language: pt)
        item.toggleQuantityUnit(language: pt)
        #expect(item.quantity(language: pt) == nil)
    }

    private func proposal() throws -> MealProposalEditorDraft {
        let item = try JSONDecoder().decode(MealProposalItemSnapshot.self, from: Data("""
        {"name":"whey","quantity_g":25.123456789,"kcal":100,"user_kcal":null,"nutrition_source":"canonical_exact","quantity_basis":"portion_reference","quantity_display":\(whey)}
        """.utf8))
        let snapshot = RegistrationSnapshot(id: "household", status: "pending", createdAt: APITimestamp(value: Date()), expiresAt: APITimestamp(value: Date().addingTimeInterval(3600)), resolvedAt: nil, proposal: .meal(MealProposalSnapshot(mealType: "cafe_da_manha", items: [item], totals: nil, warnings: [])))
        return MealProposalEditorDraft(seed: MealProposalEditorSeed(registration: snapshot, initialConsumedAt: Date()))
    }

    @Test("Pending proposal display mode never rewrites untouched or typed grams")
    func pendingProposalModeRoundTrip() throws {
        var draft = try proposal()
        draft.toggleQuantityUnit(language: en)
        #expect(draft.quantityText == nil)
        #expect(draft.request(language: en)?.items[0].quantityG == Decimal(string: "25.123456789"))
        draft.quantityText = "25"
        draft.toggleQuantityUnit(language: en)
        #expect(draft.request(language: en)?.items[0].quantityG == 25)
        #expect(draft.request(language: en)?.items[0].quantityBasis == .stated)
        draft.quantityText = "2"
        draft.toggleQuantityUnit(language: en)
        #expect(draft.request(language: en)?.items[0].quantityG == 60)
        #expect(draft.request(language: en)?.items[0].quantityBasis == .portionReference)
        draft.foodName = "arroz"
        #expect(draft.request(language: en) == nil)
    }

    @Test("The pending form echo after changing display mode is not a new quantity statement")
    func pendingFormattedEchoKeepsPrecision() throws {
        var draft = try proposal()
        draft.toggleQuantityUnit(language: en)
        draft.setQuantityText(draft.quantityDisplay(language: en), language: en)
        #expect(draft.quantityText == nil)
        #expect(draft.request(language: en)?.items[0].quantityG == Decimal(string: "25.123456789"))
        #expect(draft.request(language: en)?.items[0].quantityBasis == .portionReference)
        draft.quantityText = "25"
        draft.toggleQuantityUnit(language: en)
        draft.setQuantityText(draft.quantityDisplay(language: en), language: en)
        #expect(draft.request(language: en)?.items[0].quantityG == 25)
        #expect(draft.request(language: en)?.items[0].quantityBasis == .stated)
    }

    @Test("The confirmed form echo after changing display mode preserves precision and untouched state")
    func confirmedFormattedEchoKeepsPrecision() throws {
        let snapshot = try JSONDecoder().decode(MealRecordItemSnapshot.self, from: Data("""
        {"id":"whey","food_name":"whey","quantity_g":25.123456789,"kcal":100,"consumed_at":"2026-10-23T12:00:00Z","quantity_display":\(whey)}
        """.utf8))
        var item = MealRecordEditItem(snapshot)
        item.toggleQuantityUnit(language: en)
        item.setQuantityText(item.quantityDisplay(language: en), language: en)
        #expect(item.quantityText == nil)
        #expect(item.request(language: en)?.quantityG == Decimal(string: "25.123456789"))
        item.quantityText = "25"
        item.toggleQuantityUnit(language: en)
        item.setQuantityText(item.quantityDisplay(language: en), language: en)
        #expect(item.request(language: en)?.quantityG == 25)
    }

    @Test("Confirmed record mode preserves untouched mass and edited25g; rename invalidates typed measures")
    func confirmedRecordModeRoundTrip() throws {
        let snapshot = try JSONDecoder().decode(MealRecordItemSnapshot.self, from: Data("""
        {"id":"whey","food_name":"whey","quantity_g":25.123456789,"kcal":100,"consumed_at":"2026-10-23T12:00:00Z","quantity_display":\(whey)}
        """.utf8))
        var item = MealRecordEditItem(snapshot)
        item.toggleQuantityUnit(language: en)
        #expect(item.quantityText == nil)
        #expect(item.request(language: en)?.quantityG == Decimal(string: "25.123456789"))
        item.quantityText = "25"
        item.toggleQuantityUnit(language: en)
        #expect(item.request(language: en)?.quantityG == 25)
        item.foodName = "arroz"
        #expect(item.request(language: en) == nil)
    }

    @Test("Unknown/tampered references fall back to canonical grams", arguments: [
        #"{"unit":"scoop","grams_per_unit":0,"reference_id":"app-household-whey-scoop-v1","estimated":true}"#,
        #"{"unit":"scoop","grams_per_unit":25,"reference_id":"app-household-whey-scoop-v1","estimated":true}"#,
        #"{"unit":"mL","grams_per_unit":30,"reference_id":"app-household-whey-scoop-v1","estimated":true}"#,
        #"{"unit":"scoop","grams_per_unit":30,"reference_id":"unknown","estimated":true}"#,
    ])
    func rejectsTampering(_ metadata: String) throws {
        let item = MealDraftReview.Item(candidate: try candidate(name: "whey", grams: "30", metadata: metadata))
        #expect(item.quantityDisplay(language: pt) == "30")
        #expect(item.quantity(language: pt) == 30)
    }

    @Test("A valid reference for a different food never lends that food its factor")
    func mismatchedFood() throws {
        let item = MealDraftReview.Item(candidate: try candidate(name: "arroz", grams: "30", metadata: whey))
        #expect(item.quantityValue.unit == "g")
        #expect(item.quantityDisplay(language: pt) == "30")
        #expect(!item.canToggleQuantityUnit(language: pt))
    }

    @Test("Typing250.5mL then toggling to grams and echoing formatted text preserves258.015g", arguments: SupportedAppLanguage.allCases)
    func typedMilkVolumeRoundTrip(_ language: SupportedAppLanguage) throws {
        let metadata = #"{"unit":"mL","grams_per_unit":1.03,"reference_id":"fao-infoods-v2-whole-milk-tb","estimated":true}"#
        var item = MealDraftReview.Item(candidate: try candidate(name: "leite", grams: "206", metadata: metadata))
        item.setQuantityText(language == pt ? "250,5" : "250.5", language: language)
        item.toggleQuantityUnit(language: language)
        item.setQuantityText(item.quantityDisplay(language: language), language: language)
        #expect(item.quantity(language: language) == Decimal(string: "258.015"))
        #expect(item.basis == .portionReference)
    }
}
