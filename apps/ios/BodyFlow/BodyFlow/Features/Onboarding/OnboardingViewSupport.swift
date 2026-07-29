import Foundation
import SwiftUI

@MainActor
struct OnboardingStepHeader: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
            Text(title)
                .font(BodyFlowTypography.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(BodyFlowColor.primaryText)
            Text(message)
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.secondaryText)
        }
    }
}

@MainActor
struct OnboardingFieldIssue: View {
    let model: OnboardingFlowModel
    let candidates: [OnboardingValidationIssue]

    var body: some View {
        if let issue = candidates.first(where: model.validationIssues.contains) {
            Label(issue.message, systemImage: "exclamationmark.circle.fill")
                .font(BodyFlowTypography.callout)
                .foregroundStyle(BodyFlowColor.warning)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
        }
    }
}

extension OnboardingFlowModel {
    func accessibilityHint(
        for candidates: [OnboardingValidationIssue]
    ) -> String {
        FormAccessibilityText.hint(
            for: candidates.first(where: validationIssues.contains)?.message
        )
    }
}

extension BiologicalSex {
    var onboardingLabel: String {
        switch self {
        case .masculine: "Masculino"
        case .feminine: "Feminino"
        }
    }
}

extension BodyFlowObjective {
    var onboardingLabel: String {
        switch self {
        case .bodyRecomposition: "Recomposição corporal"
        case .muscleGain: "Ganho de massa"
        case .maintenance: "Manutenção"
        }
    }

    var onboardingDescription: String {
        switch self {
        case .bodyRecomposition: "Apoiar mudanças graduais na composição corporal."
        case .muscleGain: "Organizar a rotina com foco em ganho de massa."
        case .maintenance: "Manter hábitos e medidas com consistência."
        }
    }
}

extension ActivityLevel {
    var onboardingLabel: String {
        switch self {
        case .sedentary: "Sedentário"
        case .light: "Leve"
        case .moderate: "Moderado"
        case .high: "Alto"
        case .athlete: "Atleta"
        }
    }
}

extension WaterIntake {
    var onboardingLabel: String {
        switch self {
        case .low: "Pouco"
        case .moderate: "Moderado"
        case .high: "Bastante"
        }
    }
}

extension HungerLevel {
    var onboardingLabel: String {
        switch self {
        case .low: "Pouca"
        case .moderate: "Moderada"
        case .high: "Muita"
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
