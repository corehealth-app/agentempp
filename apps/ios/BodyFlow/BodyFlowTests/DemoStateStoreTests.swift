import Foundation
import Testing

@testable import BodyFlow

@Suite("Demo state persistence")
struct DemoStateStoreTests {
    @Test("round trips an auth session exactly")
    func authSessionRoundTrip() async throws {
        let store = DemoStateStore(secureStore: InMemorySecureStore())
        let expected = AuthSession(
            userID: "fixture-user",
            email: "demo-user@fixture.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: false
        )

        try await store.saveSession(expected)

        #expect(try await store.loadSession() == expected)
    }

    @Test("round trips an onboarding draft exactly")
    func onboardingDraftRoundTrip() async throws {
        let store = DemoStateStore(secureStore: InMemorySecureStore())
        let expected = OnboardingDraft(
            displayName: "Demo User",
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
                documentIDs: ["development-privacy", "development-terms"],
                acceptedAt: Date(timeIntervalSince1970: 946_684_800)
            ),
            currentStep: .persona
        )

        try await store.saveOnboardingDraft(expected)

        #expect(try await store.loadOnboardingDraft() == expected)
    }

    @Test("round trips a coach persona exactly")
    func coachPersonaRoundTrip() async throws {
        let store = DemoStateStore(secureStore: InMemorySecureStore())

        try await store.saveCoachPersona(.zen, for: "demo-user-v1")

        #expect(try await store.loadCoachPersona(for: "demo-user-v1") == .zen)
    }

    @Test("reports corrupted session JSON as an invalid payload")
    func corruptedSessionJSON() async {
        let secureStore = InMemorySecureStore()
        let store = DemoStateStore(secureStore: secureStore)

        await #expect(throws: DemoStateStoreError.invalidPayload) {
            try await secureStore.store(
                Data("not-json".utf8),
                forKey: "bodyflow.demo.session.v1"
            )
            _ = try await store.loadSession()
        }
    }

    @Test("clear all removes every persisted demo value")
    func clearAll() async throws {
        let store = DemoStateStore(secureStore: InMemorySecureStore())
        let session = AuthSession(
            userID: "fixture-user",
            email: "demo-user@fixture.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: true
        )
        let draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .completion)

        try await store.saveSession(session)
        try await store.saveOnboardingDraft(draft)
        try await store.saveCoachPersona(.impulse, for: "demo-user-v1")

        try await store.clearAll(for: "demo-user-v1")

        #expect(try await store.loadSession() == nil)
        #expect(try await store.loadOnboardingDraft() == nil)
        #expect(try await store.loadCoachPersona(for: "demo-user-v1") == nil)
    }

    @Test("maps secure storage errors to demo state availability")
    func secureStorageFailure() async {
        let store = DemoStateStore(secureStore: FailingDemoSecureStore())
        let session = AuthSession(
            userID: "fixture-user",
            email: "demo-user@fixture.invalid",
            isEmailConfirmed: false,
            isOnboardingCompleted: false
        )

        await #expect(throws: DemoStateStoreError.secureStorageUnavailable) {
            try await store.saveSession(session)
        }
    }
}

private enum DemoStorageFixtureError: Error, Equatable, Sendable {
    case unavailable
}

private actor FailingDemoSecureStore: SecureStoring {
    func data(forKey key: String) async throws -> Data? {
        throw DemoStorageFixtureError.unavailable
    }

    func store(_ data: Data, forKey key: String) async throws {
        throw DemoStorageFixtureError.unavailable
    }

    func removeData(forKey key: String) async throws {
        throw DemoStorageFixtureError.unavailable
    }
}
