import Foundation
import Testing
@testable import BodyFlow

@Suite("Signup current representation and historical display")
struct OnboardingCurrentPresentationTests {
    @Test func explicitRepositoryKeepsNegotiationWhenScopedAndNeverAcceptsMissingCurrentFields() async throws {
        let transport=OnboardingCurrentStateTransport(state:try Self.state(current:true))
        let repo=MobileOnboardingRepository(transport:transport,sessionLifecycle:ClinicalOnboardingReadLifecycle(),clinicalRepresentation:.currentV1)
        let scoped=try await repo.scoped(for:"auth-A")
        let state=try await scoped.loadState(for:"auth-A")
        #expect(state.clinicalSignup == .current && state.clinicalPolicy?.pauseWeightLossGuidance == true)
        let request=try #require(await transport.queries.first)
        #expect(request.contains(URLQueryItem(name:"clinical_policy",value:"current_clinical_v1")))
        let old=OnboardingCurrentStateTransport(state:try Self.state(current:false))
        let required=try await MobileOnboardingRepository(transport:old,sessionLifecycle:ClinicalOnboardingReadLifecycle(),clinicalRepresentation:.currentV1).scoped(for:"auth-A")
        await #expect(throws:OnboardingRepositoryError.serviceUnavailable) {try await required.loadState(for:"auth-A")}
        let legacy=MobileOnboardingRepository(transport:old)
        _=try await legacy.loadState(for:"auth-A")
        #expect(await old.queries.last?.contains(where:{$0.name=="clinical_policy"}) == false)
    }
    @Test("Current onboarding requires an original Auth scope before any read")
    func unboundCurrentOnboardingRefusesBeforeIO() async throws {
        let transport = OnboardingCurrentStateTransport(state: try Self.state(current: true))
        let tokenOnly = MobileOnboardingRepository(transport: transport, clinicalRepresentation: .currentV1)
        await #expect(throws: SessionLifecycleError.sessionSuperseded) { _ = try await tokenOnly.scoped(for: "auth-A") }
        await #expect(throws: SessionLifecycleError.sessionSuperseded) { _ = try await tokenOnly.loadState(for: "auth-A") }
        let unbound = MobileOnboardingRepository(transport: transport,
            sessionLifecycle: ClinicalOnboardingReadLifecycle(), clinicalRepresentation: .currentV1)
        await #expect(throws: SessionLifecycleError.sessionSuperseded) { _ = try await unbound.loadState(for: "auth-A") }
        #expect(await transport.queries.isEmpty)
    }

    @Test("Late onboarding success and failure never cross into B or a replacement A", arguments: [false, true], [false, true])
    func lateCurrentReadRetainsOriginalScope(_ failure: Bool, _ returnToA: Bool) async throws {
        let transport = OnboardingCurrentStateTransport(state: try Self.state(current: true))
        let lifecycle = ClinicalOnboardingReadLifecycle()
        let scoped = try await MobileOnboardingRepository(transport: transport,
            sessionLifecycle: lifecycle, clinicalRepresentation: .currentV1).scoped(for: "auth-A")
        await transport.holdNext()
        let read = Task { try await scoped.loadState(for: "auth-A") }
        await transport.waitUntilStarted()
        await lifecycle.replace("auth-B")
        if returnToA { await lifecycle.replace("auth-A") }
        await transport.release(failure: failure)
        await #expect(throws: SessionLifecycleError.sessionSuperseded) { _ = try await read.value }
        await #expect(throws: SessionLifecycleError.sessionSuperseded) { _ = try await scoped.loadState(for: "auth-A") }
        #expect(await transport.queries.count == 1)
        #expect(await lifecycle.leaseCalls == 1)
    }

    @Test @MainActor func reacceptanceMasksHistoricalObjectiveUsingCurrentPolicyWithoutChangingItsSubmittedValue() throws {
        let state=try Self.state(current:true)
        let model=OnboardingFlowModel(userID:"auth-A",initialDraft:E3Fixtures.draft(),repository:E3Repository(),personaRepository:E3Persona(),developmentConsentAvailability:.unavailable,requirements:E3Fixtures.requirements,historicalCompletedAt:"2026-10-01T12:00:00Z",signupCompletion:.osc1,clinicalSignup:.current,clinicalPolicy:state.clinicalPolicy,onStepChanged:{_ in},onCompleted:{})
        #expect(model.hidesHistoricalObjective)
        #expect(model.draft.objective == E3Fixtures.draft().objective)
    }
    static func policy()throws->CurrentClinicalPolicy {
        try JSONDecoder().decode(CurrentClinicalPolicy.self,from:Data(#"{"version":1,"observed_at":"2026-10-27T12:00:00.000001Z","assessment":"complete","recording_allowed":true,"pause_weight_loss_guidance":true,"professional_assessment_recommended":true,"phase_selection_pending":false,"target_source":"unavailable","hide":{"objective":true,"calories":true,"protein":true,"balance":true,"block":true}}"#.utf8))
    }
    static func state(current:Bool)throws->OnboardingServerState {
        .init(completion:.init(completed:false,completedAt:nil),requirements:.unavailable,acceptedActions:[],signupCompletion:current ? .osc1:nil,clinicalSignup:current ? .current:nil,clinicalPolicy:current ? try policy():nil)
    }
}
private actor OnboardingCurrentStateTransport:MobileAPIExecuting {
    let state:OnboardingServerState
    var queries:[[URLQueryItem]]=[]
    private var holds = false
    private var failure = false
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    init(state:OnboardingServerState){self.state=state}
    func holdNext() { holds = true }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release(failure: Bool) { self.failure = failure; continuation?.resume(); continuation = nil }
    func execute<Response:Decodable & Sendable>(_ request:MobileAPIRequest<Response>) async throws->Response {
        queries.append(request.queryItems)
        if holds {
            holds = false; started = true
            await withCheckedContinuation { continuation = $0; waiter?.resume(); waiter = nil }
            if failure { throw MobileAPITransportError.network }
        }
        return try JSONDecoder().decode(Response.self,from:JSONEncoder().encode(state))
    }
}

private actor ClinicalOnboardingReadLifecycle: SessionLifecycleProviding {
    private var userID = "auth-A", generation: UInt64 = 1
    private(set) var leaseCalls = 0
    func currentBearerToken() async -> String? { "synthetic" }
    func leaseForRequest() async throws -> SessionLease {
        leaseCalls += 1
        return SessionLease(userID: userID, generation: generation, bearer: "synthetic")
    }
    func validate(_ lease: SessionLease) async throws {
        guard lease.userID == userID, lease.generation == generation else { throw SessionLifecycleError.sessionSuperseded }
    }
    func refreshAfterUnauthorized(lease: SessionLease) async throws -> SessionLease { try await validate(lease); return lease }
    func signOut() async -> RemoteRevocationOutcome { generation += 1; return .confirmed }
    func beginPatientWork(lease: SessionLease, cancel: @escaping @Sendable () -> Void) async throws -> UUID { try await validate(lease); return UUID() }
    func finishPatientWork(_ id: UUID) async {}
    func replace(_ value: String) { userID = value; generation += 1 }
}
