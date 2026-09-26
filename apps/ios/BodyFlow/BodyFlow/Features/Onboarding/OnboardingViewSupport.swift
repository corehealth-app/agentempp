import Foundation
import SwiftUI

enum OnboardingCopy {
    static func string(
        _ key: String.LocalizationValue,
        language: SupportedAppLanguage
    ) -> String {
        (try? AppLocalization.string(key, for: language)) ?? String(localized: key)
    }

    static func format(
        _ key: String.LocalizationValue,
        language: SupportedAppLanguage,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format: string(key, language: language),
            locale: language.formattingLocale,
            arguments: arguments
        )
    }
}

@MainActor
struct OnboardingStepHeader: View {
    let titleKey: String.LocalizationValue
    let titleFallback: String
    let messageKey: String.LocalizationValue
    let messageFallback: String
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
            Text(PremiumPresentationCopy.string(
                titleKey,
                locale: locale,
                fallback: titleFallback
            ))
                .font(BodyFlowTypography.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(BodyFlowColor.primaryText)
            Text(PremiumPresentationCopy.string(
                messageKey,
                locale: locale,
                fallback: messageFallback
            ))
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.step-header")
    }
}

@MainActor
struct OnboardingFieldIssue: View {
    let model: OnboardingFlowModel
    let candidates: [OnboardingValidationIssue]
    @Environment(\.locale) private var locale

    var body: some View {
        if let issue = candidates.first(where: model.validationIssues.contains) {
            BodyFlowStatusLine(
                issue.message(for: BodyFlowPresentationLanguage.resolve(locale)),
                kind: .error,
                font: BodyFlowTypography.callout
            )
        }
    }
}

extension OnboardingFlowModel {
    func accessibilityHint(
        for candidates: [OnboardingValidationIssue]
    ) -> String {
        let language = BodyFlowPresentationLanguage.resolve(.current)
        return FormAccessibilityText.hint(
            for: candidates.first(where: validationIssues.contains)?.message(
                for: language
            ),
            language: language
        )
    }
}

extension BiologicalSex {
    func onboardingLabel(for language: SupportedAppLanguage) -> String {
        switch self {
        case .masculine:
            OnboardingCopy.string("onboarding.biological-sex.masculine", language: language)
        case .feminine:
            OnboardingCopy.string("onboarding.biological-sex.feminine", language: language)
        }
    }
}

extension BodyFlowObjective {
    func onboardingLabel(for language: SupportedAppLanguage) -> String {
        switch self {
        case .bodyRecomposition:
            OnboardingCopy.string("onboarding.objective.body-recomposition.title", language: language)
        case .muscleGain:
            OnboardingCopy.string("onboarding.objective.muscle-gain.title", language: language)
        case .maintenance:
            OnboardingCopy.string("onboarding.objective.maintenance.title", language: language)
        }
    }

    func onboardingDescription(for language: SupportedAppLanguage) -> String {
        switch self {
        case .bodyRecomposition:
            OnboardingCopy.string("onboarding.objective.body-recomposition.detail", language: language)
        case .muscleGain:
            OnboardingCopy.string("onboarding.objective.muscle-gain.detail", language: language)
        case .maintenance:
            OnboardingCopy.string("onboarding.objective.maintenance.detail", language: language)
        }
    }
}

extension ActivityLevel {
    func onboardingLabel(for language: SupportedAppLanguage) -> String {
        switch self {
        case .sedentary:
            OnboardingCopy.string("onboarding.routine.activity-level.sedentary", language: language)
        case .light:
            OnboardingCopy.string("onboarding.routine.activity-level.light", language: language)
        case .moderate:
            OnboardingCopy.string("onboarding.routine.activity-level.moderate", language: language)
        case .high:
            OnboardingCopy.string("onboarding.routine.activity-level.high", language: language)
        case .athlete:
            OnboardingCopy.string("onboarding.routine.activity-level.athlete", language: language)
        }
    }
}

extension WaterIntake {
    func onboardingLabel(for language: SupportedAppLanguage) -> String {
        switch self {
        case .low:
            OnboardingCopy.string("onboarding.routine.water-intake.low", language: language)
        case .moderate:
            OnboardingCopy.string("onboarding.routine.water-intake.moderate", language: language)
        case .high:
            OnboardingCopy.string("onboarding.routine.water-intake.high", language: language)
        }
    }
}

extension HungerLevel {
    func onboardingLabel(for language: SupportedAppLanguage) -> String {
        switch self {
        case .low:
            OnboardingCopy.string("onboarding.routine.hunger-level.low", language: language)
        case .moderate:
            OnboardingCopy.string("onboarding.routine.hunger-level.moderate", language: language)
        case .high:
            OnboardingCopy.string("onboarding.routine.hunger-level.high", language: language)
        }
    }
}

#if DEBUG
private actor PreviewOnboardingRepository: OnboardingRepository {
    func loadDraft(for userID: String) async throws -> OnboardingDraft? { nil }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {}
    func complete(_ draft: OnboardingDraft, for userID: String) async throws {}
    func clear(for userID: String) async throws {}
}

private actor PreviewCoachPersonaRepository: CoachPersonaRepository {
    private var selected: CoachPersona?

    func selectedPersona(for userID: String) async throws -> CoachPersona? {
        selected
    }

    func setPersona(_ persona: CoachPersona, for userID: String) async throws {
        selected = persona
    }
}

extension OnboardingFlowModel {
    static func preview(
        step: OnboardingStep,
        operationState: OnboardingOperationState = .idle,
        validationIssues: [OnboardingValidationIssue] = []
    ) -> OnboardingFlowModel {
        OnboardingFlowModel(
            userID: "preview-user",
            initialDraft: OnboardingDraft(
                displayName: "Pessoa de exemplo",
                localeIdentifier: "pt-BR",
                countryCode: "BR",
                timeZoneIdentifier: "America/Sao_Paulo",
                biologicalSex: .feminine,
                birthDate: Date(timeIntervalSince1970: 946_684_800),
                heightCM: 170,
                weightKG: 65,
                bodyFatPercent: 25,
                objective: .bodyRecomposition,
                activityLevel: .moderate,
                trainingFrequency: 3,
                waterIntake: .moderate,
                hungerLevel: .moderate,
                wakeTime: LocalTime(hour: 7, minute: 0),
                bedtime: LocalTime(hour: 23, minute: 0),
                foodOrganization: .yes,
                persona: .focus,
                consent: DevelopmentConsentAcceptance(
                    documentIDs: [.terms, .privacy],
                    acceptedAt: Date(timeIntervalSince1970: 946_684_800)
                ),
                currentStep: step
            ),
            repository: PreviewOnboardingRepository(),
            personaRepository: PreviewCoachPersonaRepository(),
            developmentConsentAvailability: .syntheticDevelopment,
            onStepChanged: { _ in },
            onCompleted: {},
            initialOperationState: operationState,
            initialValidationIssues: validationIssues
        )
    }
}
#endif
