import Foundation
import Testing

@testable import BodyFlow

@Suite("Registration Presentation")
struct RegistrationPresentationTests {
    @Test("meal proposal preserves every provider item and total literally")
    func proposalValuesRemainLiteral() {
        let presentation = MealProposalPresentation(
            registration: Self.pendingRegistration
        )

        #expect(presentation.registrationID == "proposal-literal-1")
        #expect(presentation.status == "pending")
        #expect(presentation.mealType == "almoco")
        #expect(presentation.items == [
            MealProposalItemPresentation(
                name: "Item B",
                quantityG: 133.5,
                kcal: 417,
                proteinG: 29,
                carbsG: 41,
                fatG: 17
            ),
            MealProposalItemPresentation(
                name: "Item A",
                quantityG: 82,
                kcal: nil,
                proteinG: 7,
                carbsG: nil,
                fatG: 4
            ),
        ])
        #expect(presentation.totals == MealProposalTotalsPresentation(
            kcal: 731,
            proteinG: 44,
            carbsG: 73,
            fatG: 21
        ))
    }

    @Test("proposal warnings preserve provider order and expiry is not reconstructed")
    func warningsAndExpiryRemainLiteral() {
        let presentation = MealProposalPresentation(
            registration: Self.pendingRegistration
        )

        #expect(presentation.warnings == [
            "Segundo aviso do provedor",
            "Primeiro aviso do provedor",
        ])
        #expect(presentation.expiresAt == Self.expiresAt)
    }

    @Test("pending proposal never exposes confirmed estimated or patient reference labels")
    func pendingProposalHasNoProvenanceLabels() {
        let presentation = MealProposalPresentation(
            registration: Self.pendingRegistration
        )

        #expect(!presentation.visibleText.contains("Referência confirmada"))
        #expect(!presentation.visibleText.contains("Estimativa"))
        #expect(!presentation.visibleText.contains("Informado pelo paciente"))
        #expect(!presentation.visibleText.contains("Origem não informada"))
    }

    @Test("absence of a provider warning never implies confirmed provenance")
    func noWarningDoesNotInferProvenance() {
        let registration = RegistrationSnapshot(
            id: Self.pendingRegistration.id,
            status: "pending",
            createdAt: Self.pendingRegistration.createdAt,
            expiresAt: Self.pendingRegistration.expiresAt,
            resolvedAt: nil,
            proposal: .meal(
                MealProposalSnapshot(
                    mealType: "almoco",
                    items: Self.items,
                    totals: Self.totals,
                    warnings: []
                )
            )
        )
        let presentation = MealProposalPresentation(registration: registration)

        #expect(presentation.warnings.isEmpty)
        #expect(!presentation.visibleText.contains("Referência confirmada"))
        #expect(!presentation.visibleText.contains("Estimativa"))
        #expect(!presentation.visibleText.contains("Informado pelo paciente"))
    }

    @Test("only a pending proposal exposes edit confirm and cancel actions")
    func onlyPendingIsActionable() {
        let pending = MealProposalPresentation(
            registration: Self.pendingRegistration
        )
        let confirmed = MealProposalPresentation(
            registration: RegistrationSnapshot(
                id: Self.pendingRegistration.id,
                status: "confirmed",
                createdAt: Self.pendingRegistration.createdAt,
                expiresAt: Self.pendingRegistration.expiresAt,
                resolvedAt: APITimestamp(value: Self.expiresAt.value),
                proposal: Self.pendingRegistration.proposal
            )
        )

        #expect(pending.allowsEdit)
        #expect(pending.allowsConfirm)
        #expect(pending.allowsCancel)
        #expect(!confirmed.allowsEdit)
        #expect(!confirmed.allowsConfirm)
        #expect(!confirmed.allowsCancel)
    }

    @Test("meal editor seeds consumed time from the model time rather than the proposal creation timestamp")
    func editorSeedUsesModelInitialConsumedAt() {
        let modelInitialConsumedAt = Date(timeIntervalSince1970: 1_784_678_900)

        let seed = MealProposalEditorSeed(
            registration: Self.pendingRegistration,
            initialConsumedAt: modelInitialConsumedAt
        )

        #expect(seed.consumedAt == modelInitialConsumedAt)
        #expect(seed.consumedAt != Self.pendingRegistration.createdAt.value)
    }

    private static let createdAt = APITimestamp(
        value: Date(timeIntervalSince1970: 1_784_589_300)
    )
    private static let expiresAt = APITimestamp(
        value: Date(timeIntervalSince1970: 1_784_592_900)
    )
    private static let items = [
        MealProposalItemSnapshot(
            name: "Item B",
            quantityG: 133.5,
            kcal: 417,
            proteinG: 29,
            carbsG: 41,
            fatG: 17
        ),
        MealProposalItemSnapshot(
            name: "Item A",
            quantityG: 82,
            kcal: nil,
            proteinG: 7,
            carbsG: nil,
            fatG: 4
        ),
    ]
    private static let totals = MealProposalTotalsSnapshot(
        kcal: 731,
        proteinG: 44,
        carbsG: 73,
        fatG: 21
    )
    private static let pendingRegistration = RegistrationSnapshot(
        id: "proposal-literal-1",
        status: "pending",
        createdAt: createdAt,
        expiresAt: expiresAt,
        resolvedAt: nil,
        proposal: .meal(
            MealProposalSnapshot(
                mealType: "almoco",
                items: items,
                totals: totals,
                warnings: [
                    "Segundo aviso do provedor",
                    "Primeiro aviso do provedor",
                ]
            )
        )
    )
}
