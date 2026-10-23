import Foundation
import Testing
@testable import BodyFlow

@Suite("Roberto milk volume and whey quantity")
struct MealLiquidQuantityTests {
    private let pt = SupportedAppLanguage.portugueseBrazil
    private let en = SupportedAppLanguage.englishUnitedStates
    private let metadata = #"{"unit":"mL","grams_per_unit":1.03,"reference_id":"fao-infoods-v2-whole-milk-tb","estimated":true}"#

    private func proposal(_ grams: String = "206", metadata: String? = nil, name: String = "leite integral") throws -> MealProposalEditorDraft {
        let item = try JSONDecoder().decode(MealProposalItemSnapshot.self, from: Data("""
        {"name":"\(name)","quantity_g":\(grams),"kcal":125.66,"protein_g":6.49,"carbs_g":9.89,"fat_g":6.7,"user_kcal":null,"nutrition_source":"canonical_exact","quantity_basis":"portion_reference","quantity_display":\(metadata ?? self.metadata)}
        """.utf8))
        let snapshot = RegistrationSnapshot(id: "qa-volume",status: "pending",createdAt: APITimestamp(value:Date()),expiresAt:APITimestamp(value:Date().addingTimeInterval(3600)),resolvedAt:nil,proposal:.meal(MealProposalSnapshot(mealType:"almoco",items:[item],totals:nil,warnings:[])))
        return MealProposalEditorDraft(seed:MealProposalEditorSeed(registration:snapshot,initialConsumedAt:Date()))
    }

    @Test("200mL milk keeps206g for calculation; editing250mL sends257.5g")
    func proposalUsesVolumeWithoutLosingCanonicalGrams() throws {
        var draft = try proposal()
        #expect(draft.quantityDisplay(language:pt) == "200")
        #expect(draft.request(language:pt)?.items[0].quantityG == 206)
        draft.quantityText = "250"
        #expect(draft.request(language:pt)?.items[0].quantityG == Decimal(string:"257.5"))
        #expect(draft.request(language:pt)?.items[0].quantityBasis == .portionReference)
    }

    @Test("Volume formatting never rewrites an untouched historical200g value")
    func historicalWeightIsPreserved() throws {
        let draft = try proposal("200.123456789")
        #expect(draft.quantityDisplay(language:pt).hasPrefix("194,"))
        #expect(draft.quantityDisplay(language:en).hasPrefix("194."))
        #expect(draft.request(language:pt)?.items[0].quantityG == Decimal(string:"200.123456789"))
    }

    @Test("Changing food after typing volume blocks reinterpretation ofmL asg")
    func nameChangeInvalidatesTypedVolume() throws {
        var draft = try proposal()
        draft.quantityText = "250"
        draft.foodName = "whey protein em pó"
        #expect(draft.request(language:pt) == nil)
        draft.quantityText = "30"
        #expect(draft.request(language:pt)?.items[0].quantityG == 30)
    }

    @Test("Upper bound is checked in grams after conversion")
    func convertedMaximumIsChecked() throws {
        var draft = try proposal()
        draft.quantityText = "9990"
        #expect(draft.request(language:pt) == nil)
    }

    @Test("Missing malformed or unknown metadata falls back to grams without breaking a row",
          arguments:["null","true","[]",#"{"unit":"L","grams_per_unit":1.03}"#,#"{"unit":"mL","grams_per_unit":0,"reference_id":"bad","estimated":true}"#])
    func metadataIsOptionalAndUntrusted(_ bad: String) throws {
        let draft = try proposal(metadata:bad)
        #expect(draft.quantityDisplay(language:pt) == "206")
        #expect(draft.request(language:pt)?.items[0].quantityG == 206)
    }

    @Test("Draft candidate volume is editable; powder never inherits milk metadata")
    func draftReviewUsesVolume() throws {
        let candidate = try JSONDecoder().decode(MealDraftCandidate.self,from:Data("""
        {"candidate_id":"c1-12345678","name":"leite integral","quantity_g":206,"quantity_basis":"portion_reference","count":null,"unit_label":null,"confidence":null,"needs_review":true,"review_reason":"estimated_quantity","quantity_display":\(metadata)}
        """.utf8))
        var item = MealDraftReview.Item(candidate:candidate)
        #expect(item.quantityDisplay(language:pt) == "200")
        item.setQuantityText("250,5",language:pt)
        #expect(item.quantity(language:pt) == Decimal(string:"258.015"))
        #expect(item.basis == .portionReference)
        item.name = "whey protein em pó"
        #expect(item.quantity(language:pt) == nil)
    }

    @Test("Confirmed record edit converts typed volume once and keeps untouched mass")
    func confirmedEditUsesVolume() throws {
        let snapshot = try JSONDecoder().decode(MealRecordItemSnapshot.self,from:Data("""
        {"id":"qa-volume","food_name":"leite integral","quantity_g":206,"kcal":125.66,"protein_g":6.49,"carbs_g":9.89,"fat_g":6.7,"source":"canonical_exact","consumed_at":"2026-10-22T12:00:00Z","meal_type":"almoco","quantity_display":\(metadata)}
        """.utf8))
        var item = MealRecordEditItem(snapshot)
        #expect(item.quantityDisplay(language:pt) == "200")
        #expect(item.request(language:pt)?.quantityG == 206)
        item.quantityText = "250.5"
        #expect(item.request(language:en)?.quantityG == Decimal(string:"258.015"))
        item.foodName = "whey protein em pó"
        #expect(item.request(language:en) == nil)
    }

    @Test("Returning from grams to volume also invalidates a previously typed number")
    func quantityContextRoundTrip() throws {
        var editor = try proposal()
        editor.foodName = "whey protein em pó"
        editor.quantityText = "30"
        editor.foodName = "leite integral"
        #expect(editor.request(language:pt) == nil)

        let candidate = try JSONDecoder().decode(MealDraftCandidate.self,from:Data("""
        {"candidate_id":"c1-12345678","name":"leite integral","quantity_g":206,"quantity_basis":"portion_reference","count":null,"unit_label":null,"confidence":null,"needs_review":true,"review_reason":"estimated_quantity","quantity_display":\(metadata)}
        """.utf8))
        var draft = MealDraftReview.Item(candidate:candidate)
        draft.name = "whey protein em pó"
        draft.quantityText = "30"
        draft.name = "leite integral"
        #expect(draft.quantity(language:pt) == nil)

        let snapshot = try JSONDecoder().decode(MealRecordItemSnapshot.self,from:Data("""
        {"id":"qa-volume","food_name":"leite integral","quantity_g":206,"kcal":125.66,"protein_g":6.49,"carbs_g":9.89,"fat_g":6.7,"source":"canonical_exact","consumed_at":"2026-10-22T12:00:00Z","meal_type":"almoco","quantity_display":\(metadata)}
        """.utf8))
        var record = MealRecordEditItem(snapshot)
        record.foodName = "whey protein em pó"
        record.quantityText = "30"
        record.foodName = "leite integral"
        #expect(record.request(language:pt) == nil)
    }

    @Test("Known liquid references displaymL without applying milk density to other drinks",
          arguments:["café coado","chá preparado","água","suco de laranja"])
    func otherDocumentedLiquids(_ name: String) throws {
        let refs:[String:(String,String)] = [
            "café coado":("fao-infoods-v2-coffee-fndds4-1","1"),
            "chá preparado":("fao-infoods-v2-tea-fndds4-1","1"),
            "água":("fao-infoods-v2-water-cg","1"),
            "suco de laranja":("fao-infoods-v2-orange-juice-sw","1.038"),
        ]
        let reference = try #require(refs[name])
        let factor = try #require(Decimal(string:reference.1))
        let data = "{\"unit\":\"mL\",\"grams_per_unit\":\(reference.1),\"reference_id\":\"\(reference.0)\",\"estimated\":true}"
        var draft = try proposal(NSDecimalNumber(decimal:200*factor).stringValue,metadata:data,name:name)
        #expect(draft.quantityPresentation.isVolume)
        #expect(draft.quantityDisplay(language:pt) == "200")
        draft.quantityText = "250"
        #expect(draft.request(language:pt)?.items[0].quantityG == 250*factor)
    }
}
