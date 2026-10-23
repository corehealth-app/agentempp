import Foundation
import Testing

@testable import BodyFlow

@Suite("Meal review without repeated acknowledgments")
struct MealSimplifiedReviewTests {
    // Literal food names/quantities from the report. Candidate IDs and the
    // photo identifier are synthetic. Identification does not imply that
    // the later nutrition calculation has resolved the compound item.
    private let data = Data(#"{"source":"photo","items":[{"candidate_id":"c1-12345678","name":"macarrão espaguete cozido","quantity_g":200,"quantity_basis":"visual_estimate","needs_review":true,"review_reason":"estimated_quantity"},{"candidate_id":"c2-23456789","name":"carne desfiada com molho e milho","quantity_g":180,"quantity_basis":"visual_estimate","needs_review":true,"review_reason":"estimated_quantity"}]}"#.utf8)

    @Test("accepting identified foods unchanged needs no per-item switches and preserves estimates",
          arguments: SupportedAppLanguage.allCases)
    func unchangedPhotoReview(language: SupportedAppLanguage) throws {
        let review = MealDraftReview(draft: try JSONDecoder().decode(MealDraftSnapshot.self, from: data),
            source: try #require(MealProposalSource(channel: .gallery,
                mediaAssetID: "394518b6-289b-4189-9297-e16637058e8e")), mealType: .lunch)
        // Roberto explicitly reported no edits. No toggles or field writes.
        #expect(review.blocker(language: language) == nil)
        let request = try #require(review.request(language: language))
        #expect(request.items.map(\.foodName) == ["macarrão espaguete cozido", "carne desfiada com molho e milho"])
        #expect(request.items.map(\.quantityG) == [200, 180])
        #expect(request.items.map(\.quantityBasis) == [.visualEstimate, .visualEstimate])
        #expect(request.items.allSatisfy { $0.userKcal == nil && !$0.usesNutritionLabel })
        #expect(request.source?.mediaAssetID == "394518b6-289b-4189-9297-e16637058e8e")
    }

    @Test("the reported unchanged AI result stays pending but never shows an internal operator instruction")
    func rejectedNutritionIsExplainedToThePerson() throws {
        let response = try JSONDecoder().decode(RegistrationProposalResponse.self,
            from: MealCompositeRecoveryCharacterizationTests.responseJSON)
        let presentation = MealProposalPresentation(registration: response.data)
        #expect(presentation.hasUnresolvedItems)
        #expect(!presentation.allowsConfirm)
        #expect(presentation.allowsEdit)
        #expect(presentation.items[0].kcal == 260)
        #expect(presentation.items[1].needsClarification)
        #expect(!presentation.warnings.contains { $0.contains("Peça pro paciente") })
    }
}
