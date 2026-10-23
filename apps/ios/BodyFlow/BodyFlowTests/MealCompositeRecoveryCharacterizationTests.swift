import Foundation
import Testing

@testable import BodyFlow

@Suite("Composite meal correction — reported recovery path")
struct MealCompositeRecoveryCharacterizationTests {
    // Food descriptions, quantities and visible nutrition match the report.
    // IDs, timestamps and canonical_exact are synthetic, not account evidence.
    // The partially shown parmesan has no known quantity and is not invented here.
    static let responseJSON = Data("""
    {
      "data": {
        "id": "46bc1afb-f547-4073-8049-446cfbb69f1d", "status": "pending",
        "created_at": "2026-10-23T16:33:00Z", "expires_at": "2026-10-24T16:33:00Z",
        "resolved_at": null,
        "proposal": {
          "kind": "meal", "meal_type": "almoco",
          "items": [
            {"name": "macarrão espaguete cozido", "quantity_g": 200,
             "kcal": 260, "protein_g": 10, "carbs_g": 50, "fat_g": 3,
             "user_kcal": null, "nutrition_source": "canonical_exact",
             "resolution": "resolved", "quantity_basis": "visual_estimate"},
            {"name": "carne desfiada com molho e milho", "quantity_g": 180,
             "kcal": 0, "protein_g": 0, "carbs_g": 0, "fat_g": 0,
             "user_kcal": null, "nutrition_source": "composite_rejected",
             "resolution": "needs_clarification", "quantity_basis": "visual_estimate"}
          ],
          "totals": null,
          "warnings": ["Não consegui identificar \\\"carne desfiada com molho e milho\\\" porque veio com vários alimentos juntos. Peça pro paciente descrever cada item separado com a quantidade (ex: \\\"leite 250ml\\\" e \\\"whey 30g\\\"). Não foi possível calcular as calorias desse item ainda."],
          "source": {"channel": "gallery", "media_asset_id": "394518b6-289b-4189-9297-e16637058e8e"}
        }
      },
      "meta": {"api_version": "v1", "request_id": "synthetic-composite-recovery"}
    }
    """.utf8)

    private static let consumedAt = Date(timeIntervalSince1970: 1_792_773_000)

    @Test("a complete rejected-composite response permits correction without manual calories",
          arguments: SupportedAppLanguage.allCases)
    func completeResponseAllowsCorrection(language: SupportedAppLanguage) throws {
        // Decode the actual wire envelope: a convenience initializer would hide
        // the distinction between absent provenance keys and explicit nulls.
        let response = try JSONDecoder().decode(RegistrationProposalResponse.self, from: Self.responseJSON)
        let seed = MealProposalEditorSeed(
            registration: response.data, initialConsumedAt: Self.consumedAt, editedIndex: 1
        )
        var draft = MealProposalEditorDraft(seed: seed)

        #expect(!seed.hasUnknownKcalOrigin)
        #expect(seed.officialKcal == nil)
        #expect(draft.foodName == "carne desfiada com molho e milho")
        #expect(draft.quantityValue(language: language) == 180)
        #expect(draft.blocker(language: language) == nil)
        #expect(!MealProposalPresentation(registration: response.data).allowsConfirm)

        // This replacement is a synthetic user correction, not an inference
        // about which meat or sauce the patient actually ate.
        draft.foodName = "carne bovina desfiada cozida"
        let request = try #require(draft.request(language: language))
        #expect(request.items.map(\.foodName) == [
            "macarrão espaguete cozido", "carne bovina desfiada cozida",
        ])
        #expect(request.items.map(\.quantityG) == [200, 180])
        #expect(request.items.map(\.quantityBasis) == [.visualEstimate, .visualEstimate])
        #expect(request.items.map(\.userKcal) == [nil, nil])
        #expect(request.mealType == .lunch)
        #expect(request.consumedAt?.value == Self.consumedAt)
        #expect(request.source?.channel == .gallery)
        #expect(request.source?.mediaAssetID == "394518b6-289b-4189-9297-e16637058e8e")

        let encoded = try JSONEncoder().encode(request)
        let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let items = try #require(object["items"] as? [[String: Any]])
        #expect(items.allSatisfy { $0["user_kcal"] == nil })
        // The 260 official kcal must never become a patient override. The BFF
        // remains responsible for recalculating the edited proposal.
    }

    @Test("missing provenance on another item prevents a lossy correction request",
          arguments: SupportedAppLanguage.allCases)
    func anotherItemWithoutProvenanceBlocksCorrection(language: SupportedAppLanguage) throws {
        // Deliberately incomplete synthetic DTO; not a claim about the report.
        var envelope = try #require(try JSONSerialization.jsonObject(with: Self.responseJSON) as? [String: Any])
        var data = try #require(envelope["data"] as? [String: Any])
        var proposal = try #require(data["proposal"] as? [String: Any])
        var items = try #require(proposal["items"] as? [[String: Any]])
        items[0].removeValue(forKey: "user_kcal")
        proposal["items"] = items
        data["proposal"] = proposal
        envelope["data"] = data
        let response = try JSONDecoder().decode(
            RegistrationProposalResponse.self, from: JSONSerialization.data(withJSONObject: envelope)
        )
        var draft = MealProposalEditorDraft(seed: MealProposalEditorSeed(
            registration: response.data, initialConsumedAt: Self.consumedAt, editedIndex: 1
        ))
        draft.foodName = "carne bovina desfiada cozida"

        #expect(draft.blocker(language: language) == .unknownKcalOrigin)
        #expect(draft.request(language: language) == nil)
        draft.manualKcalText = "300"
        #expect(draft.request(language: language) == nil)
    }
}
