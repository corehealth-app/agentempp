import Foundation

#if DEBUG
/// UI-test scenario for the meal capture (Debug builds only): free text
/// becomes synthetic candidates, with no server and no media.
enum DemoMealCaptureScenario {
    static let argument = "--ui-testing-meal-capture"
    /// Text that the synthetic reader does not recognize.
    static let unrecognizedText = "xyz"

    static func isEnabled(arguments: [String]) -> Bool {
        arguments.contains(argument)
    }
}

/// Synthetic candidates; no real account data and nothing calculated.
struct DemoMealDraftProvider: MealDraftProviding {
    func draft(
        _ attempt: MutationAttempt<MealDraftRequest>
    ) async throws -> MealDraftSnapshot {
        guard case let .text(text) = attempt.payload,
              text != DemoMealCaptureScenario.unrecognizedText
        else {
            throw MealCaptureFailure.nothingRecognized
        }
        return MealDraftSnapshot(
            source: "text",
            mediaAssetID: nil,
            transcript: nil,
            contextNote: nil,
            items: [
                MealDraftCandidate(
                    candidateID: "c1-0a1b2c3d", name: "ovos mexidos", quantityG: 100,
                    quantityBasis: "portion_reference", count: 2, unitLabel: "unidade",
                    confidence: nil, needsReview: true, reviewReason: "estimated_quantity"
                ),
                MealDraftCandidate(
                    candidateID: "c2-1b2c3d4e", name: "granola", quantityG: nil,
                    quantityBasis: "missing", count: nil, unitLabel: nil,
                    confidence: nil, needsReview: true, reviewReason: "missing_quantity"
                ),
            ],
            nutritionLabel: nil
        )
    }
}
#endif
