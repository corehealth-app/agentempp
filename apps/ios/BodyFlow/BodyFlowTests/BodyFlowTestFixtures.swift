import Foundation

@testable import BodyFlow

enum BodyFlowTestFixtures {
    static func onboardingDraft(
        currentStep: OnboardingStep
    ) -> OnboardingDraft {
        OnboardingDraft(
            displayName: "Fixture User",
            localeIdentifier: "pt-BR",
            countryCode: "US",
            timeZoneIdentifier: "America/New_York",
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
                documentIDs: ["development-privacy", "development-terms"],
                acceptedAt: Date(timeIntervalSince1970: 946_684_800)
            ),
            currentStep: currentStep
        )
    }
}
