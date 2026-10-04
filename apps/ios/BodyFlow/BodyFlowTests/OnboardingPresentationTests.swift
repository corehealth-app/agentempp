import Foundation
import SwiftUI
import Testing

@testable import BodyFlow

@Suite("Onboarding presentation policies")
struct OnboardingPresentationTests {
    @Test("release resolves synthetic consent presentation as unavailable")
    func releaseHidesSyntheticConsentPresentation() {
        let configuration = AppLaunchConfiguration.resolve(
            arguments: ["--ui-testing"],
            buildFlavor: .release
        )

        #expect(configuration.developmentConsentAvailability == .unavailable)
    }

    @Test("development and official consent identifiers remain stable")
    func developmentConsentAccessibilityIdentifiers() {
        #expect(OnboardingConsentAccessibilityID.developmentGroup == "onboarding.development-consent")
        #expect(OnboardingConsentAccessibilityID.developmentTerms == "consent.terms")
        #expect(OnboardingConsentAccessibilityID.developmentPrivacy == "consent.privacy")
        #expect(OnboardingConsentAccessibilityID.officialGroup == "onboarding.legal-documents")
        #expect(
            OnboardingConsentAccessibilityID.officialAction("terms_of_service")
                == "onboarding.legal-action.terms_of_service"
        )
    }

    @Test("the root renders a flow model only for the active onboarding user")
    func rootRenderRequiresMatchingUser() {
        #expect(OnboardingRootLoadState.canRender(
            modelUserID: "user-a",
            activeUserID: "user-a"
        ))
        #expect(!OnboardingRootLoadState.canRender(
            modelUserID: "user-a",
            activeUserID: "user-b"
        ))
    }

    @Test("a newer load attempt supersedes an older attempt for the same user")
    func newerLoadSupersedesOlderAttempt() {
        var state = OnboardingRootLoadState()
        let attemptA = state.begin(for: "fixture-user")
        let attemptB = state.begin(for: "fixture-user")

        #expect(!state.canPublish(
            attemptA,
            activeUserID: "fixture-user",
            isCancelled: false
        ))
        #expect(state.canPublish(
            attemptB,
            activeUserID: "fixture-user",
            isCancelled: false
        ))
    }

    @Test("a cancelled or identity-mismatched load cannot publish")
    func cancelledLoadCannotPublish() {
        var state = OnboardingRootLoadState()
        let attempt = state.begin(for: "fixture-user")

        #expect(!state.canPublish(
            attempt,
            activeUserID: "fixture-user",
            isCancelled: true
        ))
        #expect(!state.canPublish(
            attempt,
            activeUserID: "other-user",
            isCancelled: false
        ))
    }

    @Test("body fat is optional and exposes its name and unit to accessibility")
    func bodyFatDescriptorIsExplicitlyOptional() {
        let descriptor = OnboardingDecimalFieldDescriptor.bodyFat

        #expect(descriptor.prompt == "Opcional")
        #expect(descriptor.accessibilityLabel == "Gordura corporal")
        #expect(descriptor.unit == "%")
        #expect(descriptor.accessibilityValue(for: nil) == "Não informado, %")
        #expect(descriptor.accessibilityValue(for: 25.5) == "25,5 %")
    }

    @Test("height and weight retain coherent prompts, labels and units")
    func requiredBodyDescriptorsRemainCoherent() {
        #expect(OnboardingDecimalFieldDescriptor.height.prompt == "0")
        #expect(OnboardingDecimalFieldDescriptor.height.accessibilityLabel == "Altura")
        #expect(OnboardingDecimalFieldDescriptor.height.unit == "cm")
        #expect(OnboardingDecimalFieldDescriptor.height.accessibilityValue(for: 170) == "170 cm")

        #expect(OnboardingDecimalFieldDescriptor.weight.prompt == "0")
        #expect(OnboardingDecimalFieldDescriptor.weight.accessibilityLabel == "Peso")
        #expect(OnboardingDecimalFieldDescriptor.weight.unit == "kg")
        #expect(OnboardingDecimalFieldDescriptor.weight.accessibilityValue(for: nil) == "Não informado, kg")
    }

    @MainActor
    @Test("onboarding validation exposes the matching hint and announcement")
    func onboardingValidationAccessibilityText() {
        let model = OnboardingFlowModel(
            userID: "fixture-user",
            initialDraft: BodyFlowTestFixtures.onboardingDraft(currentStep: .welcome),
            repository: PresentationOnboardingRepository(),
            personaRepository: PresentationPersonaRepository(),
            developmentConsentAvailability: .unavailable,
            onStepChanged: { _ in },
            onCompleted: {},
            initialValidationIssues: [.displayNameRequired, .countryInvalid]
        )

        #expect(
            model.accessibilityHint(for: [.displayNameRequired])
                == "Erro: Informe como você quer ser chamado."
        )
        #expect(
            FormAccessibilityText.validationAnnouncement(
                messages: model.validationIssues.map(\.message)
            )
                == "Erros no formulário: Informe como você quer ser chamado. Confirme um país válido."
        )
    }

    /// Client request C2-17 (16/01/2026 audio, 17/01/2026 21:39:38 text):
    /// "trocar treinar por musculação" in the weekly frequency question.
    @Test("the weekly frequency question asks about strength training, not workouts in general")
    func frequencyQuestionSaysStrengthTraining() throws {
        let expected: [(key: String.LocalizationValue, portuguese: String, english: String)] = [
            ("onboarding.routine.training-frequency.title",
             "Musculação por semana", "Strength training per week"),
            ("onboarding.validation.training-frequency-out-of-range",
             "Informe de 0 a 7 treinos de musculação por semana.",
             "Enter between 0 and 7 strength training sessions per week."),
            ("onboarding.completion.training", "Musculação", "Strength training"),
        ]
        for entry in expected {
            let portuguese = try AppLocalization.string(entry.key, for: .portugueseBrazil)
            let english = try AppLocalization.string(entry.key, for: .englishUnitedStates)
            #expect(portuguese == entry.portuguese)
            #expect(english == entry.english)
            #expect(portuguese.contains("usculação"))
            #expect(!portuguese.contains("treinos por semana"))
            #expect(!english.localizedCaseInsensitiveContains("workout"))
        }
        // The two labels that used to say "Treinos" carry no trace of it. The
        // validation sentence keeps the approved "treinos de musculação".
        for key: String.LocalizationValue in [
            "onboarding.routine.training-frequency.title",
            "onboarding.completion.training",
        ] {
            #expect(!(try AppLocalization.string(key, for: .portugueseBrazil)).contains("rein"))
        }
        // The hard-coded Portuguese copy matches the catalog.
        #expect(OnboardingValidationIssue.trainingFrequencyOutOfRange.message
            == "Informe de 0 a 7 treinos de musculação por semana.")
        #expect(OnboardingValidationIssue.trainingFrequencyOutOfRange.message(for: .portugueseBrazil)
            == OnboardingValidationIssue.trainingFrequencyOutOfRange.message)
        #expect(OnboardingValidationIssue.trainingFrequencyOutOfRange.message(for: .englishUnitedStates)
            == "Enter between 0 and 7 strength training sessions per week.")
    }

    @Test("premium onboarding copy is complete in Portuguese and English")
    func premiumOnboardingCopyIsBilingual() throws {
        #expect(
            try AppLocalization.string(
                "onboarding.persona.title",
                for: .portugueseBrazil
            ) == "Estilo do Flow"
        )
        #expect(
            try AppLocalization.string(
                "onboarding.persona.title",
                for: .englishUnitedStates
            ) == "Flow’s style"
        )
        #expect(
            try AppLocalization.string(
                "onboarding.progress.format",
                for: .englishUnitedStates
            ) == "Step %lld of %lld"
        )
        #expect(
            try AppLocalization.string(
                "onboarding.consent.development.message",
                for: .englishUnitedStates
            ) == "QA validation environment. These documents are synthetic and do not represent real legal acceptance."
        )
        #expect(
            try AppLocalization.string(
                "onboarding.validation.display-name-required",
                for: .englishUnitedStates
            ) == "Enter what you would like to be called."
        )
        #expect(
            try AppLocalization.string(
                "onboarding.validation.consent-required",
                for: .portugueseBrazil
            ) == "Confirme as ações exigidas para todos os documentos atuais."
        )
    }

}

private actor PresentationOnboardingRepository: OnboardingRepository {
    func loadDraft(for userID: String) async throws -> OnboardingDraft? { nil }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {}
    func complete(_ draft: OnboardingDraft, for userID: String) async throws {}
    func clear(for userID: String) async throws {}
}

private actor PresentationPersonaRepository: CoachPersonaRepository {
    func selectedPersona(for userID: String) async throws -> CoachPersona? { nil }
    func setPersona(_ persona: CoachPersona, for userID: String) async throws {}
}
