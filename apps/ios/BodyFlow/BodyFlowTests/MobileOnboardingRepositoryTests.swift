import Foundation
import Testing

@testable import BodyFlow

@Suite("Mobile onboarding repository")
struct MobileOnboardingRepositoryTests {
    @Test("Release dependency graph installs only real or fail-closed onboarding")
    func releaseDependencyGraphExcludesDemoOnboarding() throws {
        let mobileConfiguration = try MobileAPIConfiguration(
            originString: "https://staging.example.test"
        )
        let real = AppDependencies.make(
            configuration: .resolve(arguments: [], buildFlavor: .release),
            mobileAPIConfigurationProvider: StaticMobileAPIConfigurationProvider(
                configuration: mobileConfiguration
            ),
            sessionTokenProvider: OnboardingSessionTokenProvider()
        )
        let unavailable = AppDependencies.make(
            configuration: .resolve(arguments: [], buildFlavor: .release)
        )

        #expect(real.onboarding is MobileOnboardingRepository)
        #expect(unavailable.onboarding is UnavailableOnboardingRepository)
        #expect(!(real.onboarding is DemoOnboardingRepository))
        #expect(!(unavailable.onboarding is DemoOnboardingRepository))
    }

    @Test("loads exact server-owned requirements without preselecting actions")
    func loadsOfficialRequirements() async throws {
        let transport = OnboardingTransportSpy(
            state: OnboardingServerState(
                completion: OnboardingCompletionState(completed: false, completedAt: nil),
                requirements: OnboardingRequirements(
                    available: true,
                    blockingReason: nil,
                    documents: [termsDocument]
                ),
                acceptedActions: []
            ),
            completion: completionAcknowledgement
        )
        let repository = MobileOnboardingRepository(transport: transport)

        let state = try await repository.loadState(for: "fixture-user")

        #expect(state.requirements.documents == [termsDocument])
        #expect(state.acceptedActions.isEmpty)
        #expect(state.draft == nil)
        let request = try #require(await transport.requests.first)
        #expect(request.method == .get)
        #expect(request.path == "/api/mobile/v1/onboarding")
        #expect(request.body == nil)
        #expect(request.idempotency == .notRequired)
    }

    @Test("encodes all supported fields and exact actions without caller-owned authority")
    func completesWithExactServerContract() async throws {
        let transport = OnboardingTransportSpy(
            state: emptyState,
            completion: completionAcknowledgement
        )
        let repository = MobileOnboardingRepository(transport: transport)
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .completion)
        draft.documentActions = [termsDocument.explicitAction]
        let key = try IdempotencyKey(validating: "onboarding-fixture-key")

        let result = try await repository.completeOfficial(
            draft,
            for: "fixture-user",
            idempotencyKey: key
        )

        #expect(result == completionAcknowledgement)
        let request = try #require(await transport.requests.first)
        #expect(request.method == .post)
        #expect(request.path == "/api/mobile/v1/onboarding")
        #expect(request.idempotency == .required(key))
        let body = try #require(request.body)
        let object = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(object["user_id"] == nil)
        #expect(object["onboarding_completed"] == nil)
        #expect(object["accepted_at"] == nil)
        #expect(object["persona"] as? String == "focus")
        #expect(object["document_actions"] as? [[String: String]] == [[
            "document_key": "terms_of_service",
            "version": "2026-09-15.1",
            "locale": "pt-BR",
            "content_hash": String(repeating: "a", count: 64),
            "action": "acceptance",
        ]])
    }

    @Test(arguments: ["Pacific/Kiritimati", "Etc/GMT+12"])
    func preservesCivilBirthDateWhenSubmittingFromExtremeTimeZones(
        timeZoneIdentifier: String
    ) async throws {
        let transport = OnboardingTransportSpy(
            state: emptyState,
            completion: completionAcknowledgement
        )
        let repository = MobileOnboardingRepository(transport: transport)
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .completion)
        draft.timeZoneIdentifier = timeZoneIdentifier
        draft.birthDate = try #require(OnboardingCivilDate.date(
            from: "1990-01-01",
            timeZoneIdentifier: timeZoneIdentifier
        ))
        draft.documentActions = [termsDocument.explicitAction]

        _ = try await repository.completeOfficial(
            draft,
            for: "fixture-user",
            idempotencyKey: IdempotencyKey(validating: "onboarding-extreme-timezone-key")
        )

        let request = try #require(await transport.requests.first)
        let body = try #require(request.body)
        let object = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(object["birth_date"] as? String == "1990-01-01")
        #expect(object["timezone"] as? String == timeZoneIdentifier)
    }

    @Test("maps a changed document to a reloadable onboarding failure")
    func mapsChangedRequirements() async throws {
        let transport = OnboardingTransportSpy(
            state: emptyState,
            completion: completionAcknowledgement,
            completionError: .conflict(
                code: "onboarding_requirements_changed",
                requestID: "request-onboarding-test"
            )
        )
        let repository = MobileOnboardingRepository(transport: transport)
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .completion)
        draft.documentActions = [termsDocument.explicitAction]

        await #expect(throws: OnboardingRepositoryError.requirementsChanged) {
            try await repository.completeOfficial(
                draft,
                for: "fixture-user",
                idempotencyKey: IdempotencyKey(validating: "onboarding-fixture-key")
            )
        }
    }

    @Test("maps a different post-completion submission to an immutable-state failure")
    func mapsAlreadyCompleted() async throws {
        let transport = OnboardingTransportSpy(
            state: emptyState,
            completion: completionAcknowledgement,
            completionError: .conflict(
                code: "onboarding_already_completed",
                requestID: "request-onboarding-test"
            )
        )
        let repository = MobileOnboardingRepository(transport: transport)
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .completion)
        draft.documentActions = [termsDocument.explicitAction]

        await #expect(throws: OnboardingRepositoryError.alreadyCompleted) {
            try await repository.completeOfficial(
                draft,
                for: "fixture-user",
                idempotencyKey: IdempotencyKey(validating: "onboarding-fixture-key")
            )
        }
    }

    @Test("rejects an acknowledgement whose objective does not match the submitted draft")
    func rejectsMismatchedObjectiveAcknowledgement() async throws {
        let invalid = OnboardingCompletionAcknowledgement(
            onboardingCompleted: true,
            completedAt: "2026-09-15T15:00:00.000Z",
            objective: .muscleGain,
            persona: .focus,
            documentActions: completionAcknowledgement.documentActions
        )
        let repository = MobileOnboardingRepository(
            transport: OnboardingTransportSpy(state: emptyState, completion: invalid)
        )
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .completion)
        draft.documentActions = [termsDocument.explicitAction]

        await #expect(throws: OnboardingRepositoryError.serviceUnavailable) {
            try await repository.completeOfficial(
                draft,
                for: "auth-subject-different-from-domain-id",
                idempotencyKey: IdempotencyKey(validating: "onboarding-fixture-key")
            )
        }
    }

    @Test("rejects an acknowledgement without a valid server timestamp")
    func rejectsInvalidTimestampAcknowledgement() async throws {
        let invalid = OnboardingCompletionAcknowledgement(
            onboardingCompleted: true,
            completedAt: "not-a-server-timestamp",
            objective: .bodyRecomposition,
            persona: .focus,
            documentActions: completionAcknowledgement.documentActions
        )
        let repository = MobileOnboardingRepository(
            transport: OnboardingTransportSpy(state: emptyState, completion: invalid)
        )
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .completion)
        draft.documentActions = [termsDocument.explicitAction]

        await #expect(throws: OnboardingRepositoryError.serviceUnavailable) {
            try await repository.completeOfficial(
                draft,
                for: "fixture-auth-subject",
                idempotencyKey: IdempotencyKey(validating: "onboarding-fixture-key")
            )
        }
    }

    @Test("rejects an acknowledgement missing an exact submitted legal action")
    func rejectsMissingAcknowledgedAction() async throws {
        let invalid = OnboardingCompletionAcknowledgement(
            onboardingCompleted: true,
            completedAt: "2026-09-15T15:00:00.000Z",
            objective: .bodyRecomposition,
            persona: .focus,
            documentActions: []
        )
        let repository = MobileOnboardingRepository(
            transport: OnboardingTransportSpy(state: emptyState, completion: invalid)
        )
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .completion)
        draft.documentActions = [termsDocument.explicitAction]

        await #expect(throws: OnboardingRepositoryError.serviceUnavailable) {
            try await repository.completeOfficial(
                draft,
                for: "fixture-auth-subject",
                idempotencyKey: IdempotencyKey(validating: "onboarding-fixture-key")
            )
        }
    }

    private var termsDocument: OnboardingLegalDocument {
        OnboardingLegalDocument(
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
    }

    private var emptyState: OnboardingServerState {
        OnboardingServerState(
            completion: OnboardingCompletionState(completed: false, completedAt: nil),
            requirements: .unavailable,
            acceptedActions: []
        )
    }

    private var completionAcknowledgement: OnboardingCompletionAcknowledgement {
        OnboardingCompletionAcknowledgement(
            onboardingCompleted: true,
            completedAt: "2026-09-15T15:00:00.000Z",
            objective: .bodyRecomposition,
            persona: .focus,
            documentActions: [
                OnboardingAcceptedAction(
                    documentKey: "terms_of_service",
                    version: "2026-09-15.1",
                    locale: "pt-BR",
                    contentHash: String(repeating: "a", count: 64),
                    purpose: "synthetic_terms_test",
                    action: .acceptance,
                    actedAt: "2026-09-15T15:00:00.000Z"
                ),
            ]
        )
    }
}

private struct OnboardingSessionTokenProvider: SessionTokenProviding {
    func currentBearerToken() async -> String? {
        "synthetic-session-token"
    }
}

private struct RecordedOnboardingRequest: Sendable {
    let method: HTTPMethod
    let path: String
    let body: Data?
    let idempotency: MobileAPIIdempotency
}

private actor OnboardingTransportSpy: MobileAPIExecuting {
    private let state: OnboardingServerState
    private let completion: OnboardingCompletionAcknowledgement
    private let completionError: MobileAPITransportError?
    private(set) var requests: [RecordedOnboardingRequest] = []

    init(
        state: OnboardingServerState,
        completion: OnboardingCompletionAcknowledgement,
        completionError: MobileAPITransportError? = nil
    ) {
        self.state = state
        self.completion = completion
        self.completionError = completionError
    }

    func execute<Response: Decodable & Sendable>(
        _ request: MobileAPIRequest<Response>
    ) async throws -> Response {
        requests.append(RecordedOnboardingRequest(
            method: request.method,
            path: request.path,
            body: request.body,
            idempotency: request.idempotency
        ))
        if request.method == .get {
            return state as! Response
        }
        if let completionError { throw completionError }
        return completion as! Response
    }
}
