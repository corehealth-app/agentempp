import Foundation
import Testing

@testable import BodyFlow

@Suite("Onboarding models")
struct OnboardingModelsTests {
    @Test("only public coach personas are selectable")
    func selectablePersonas() {
        #expect(CoachPersona.allCases == [.focus, .impulse, .zen])
        #expect(CoachPersona.allCases.map(\.displayName) == [
            "Focus", "Impulse", "Zen",
        ])
    }

    @Test("onboarding follows the approved seven-step order")
    func onboardingOrder() {
        #expect(OnboardingStep.allCases == [
            .welcome, .bodyData, .objective, .routine,
            .persona, .consent, .completion,
        ])
    }

    @Test("objectives mirror the backend domain vocabulary")
    func objectiveCodes() {
        #expect(BodyFlowObjective.allCases.map(\.rawValue) == [
            "recomposicao", "ganho_massa", "manutencao",
        ])
    }

    @Test("official document actions preserve exact immutable identity")
    func officialDocumentActionIdentity() {
        let document = OnboardingLegalDocument(
            documentKey: "terms_of_service",
            version: "2026-09-15.1",
            locale: "pt-BR",
            body: "Synthetic terms for tests only",
            contentURL: nil,
            contentHash: String(repeating: "a", count: 64),
            purpose: "synthetic_terms_test",
            action: .acceptance,
            required: true,
            effectiveAt: "2026-09-15T00:00:00.000Z"
        )

        #expect(document.explicitAction == OnboardingDocumentAction(
            documentKey: "terms_of_service",
            version: "2026-09-15.1",
            locale: "pt-BR",
            contentHash: String(repeating: "a", count: 64),
            action: .acceptance
        ))
        #expect(!document.explicitAction.documentKey.hasPrefix("dev."))
    }

    @Test("server state requires its authoritative locale")
    func decodesAuthoritativeLocale() throws {
        let payload = Data(
            """
            {
              "locale": "en-US",
              "completion": { "completed": false, "completed_at": null },
              "requirements": {
                "available": false,
                "blocking_reason": "documents_unavailable",
                "documents": []
              },
              "accepted_actions": []
            }
            """.utf8
        )

        let state = try JSONDecoder().decode(OnboardingServerState.self, from: payload)

        #expect(state.locale == "en-US")
        #expect(state.draft == nil)
    }

    @Test("server state decodes an authoritative completed profile for legal reconsent")
    func decodesAuthoritativeReconsentDraft() throws {
        let payload = Data(
            """
            {
              "locale": "pt-BR",
              "completion": {
                "completed": false,
                "completed_at": "2026-09-15T15:00:00.000Z"
              },
              "requirements": {
                "available": true,
                "blocking_reason": null,
                "documents": []
              },
              "accepted_actions": [],
              "draft": {
                "name": "Synthetic User",
                "locale": "pt-BR",
                "country": "BR",
                "timezone": "America/Sao_Paulo",
                "sex": "masculino",
                "birth_date": "1990-01-01",
                "height_cm": 180,
                "weight_kg": 80,
                "body_fat_percent": null,
                "objective": "recomposicao",
                "activity_level": "moderado",
                "training_frequency": 4,
                "water_intake": "moderado",
                "hunger_level": "moderada",
                "wake_time": "07:00",
                "bedtime": "23:00",
                "food_organization": "sim",
                "persona": "focus",
                "current_step": "consent"
              }
            }
            """.utf8
        )

        let state = try JSONDecoder().decode(OnboardingServerState.self, from: payload)

        #expect(state.draft?.displayName == "Synthetic User")
        #expect(state.draft?.objective == .bodyRecomposition)
        #expect(state.draft?.persona == .focus)
        #expect(state.draft?.wakeTime == LocalTime(hour: 7, minute: 0))
        #expect(state.draft?.currentStep == .consent)
    }

    @Test(arguments: ["Pacific/Kiritimati", "Etc/GMT+12"])
    func decodesAuthoritativeBirthDateAsCivilDateInExtremeTimeZones(
        timeZoneIdentifier: String
    ) throws {
        let payload = Data(
            """
            {
              "locale": "pt-BR",
              "completion": {
                "completed": false,
                "completed_at": "2026-09-15T15:00:00.000Z"
              },
              "requirements": {
                "available": true,
                "blocking_reason": null,
                "documents": []
              },
              "accepted_actions": [],
              "draft": {
                "name": "Synthetic User",
                "locale": "pt-BR",
                "country": "BR",
                "timezone": "\(timeZoneIdentifier)",
                "sex": "masculino",
                "birth_date": "1990-01-01",
                "height_cm": 180,
                "weight_kg": 80,
                "body_fat_percent": null,
                "objective": "recomposicao",
                "activity_level": "moderado",
                "training_frequency": 4,
                "water_intake": "moderado",
                "hunger_level": "moderada",
                "wake_time": "07:00",
                "bedtime": "23:00",
                "food_organization": "sim",
                "persona": "focus",
                "current_step": "consent"
              }
            }
            """.utf8
        )

        let state = try JSONDecoder().decode(OnboardingServerState.self, from: payload)
        let draft = try #require(state.draft)
        let birthDate = try #require(draft.birthDate)

        #expect(OnboardingCivilDate.string(
            from: birthDate,
            timeZoneIdentifier: timeZoneIdentifier
        ) == "1990-01-01")
    }
}
