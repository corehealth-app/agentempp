import Foundation
import Testing
@testable import BodyFlow

@Suite("Legacy onboarding — documents without another signup")
struct OnboardingLegacyDocumentsTests {
    static func stateObject(marker:String? = nil,draft:OnboardingDraft? = nil) throws -> [String:Any] {
        let state=OnboardingServerState(completion:.init(completed:false,completedAt:marker),requirements:E3Fixtures.requirements,
            acceptedActions:[],draft:draft,signupCompletion:.osc1,clinicalSignup:.current,clinicalPolicy:try OnboardingCurrentPresentationTests.policy())
        var object=try #require(JSONSerialization.jsonObject(with:JSONEncoder().encode(state)) as? [String:Any])
        object["legacy_reconsent"]=["protocol":"documents_only_v1"]
        if draft == nil {object["draft"]=NSNull()}
        return object
    }
    static func decode(_ object:[String:Any]) throws -> OnboardingServerState {
        try JSONDecoder().decode(OnboardingServerState.self,from:JSONSerialization.data(withJSONObject:object))
    }
    @Test(arguments:[Optional<String>.none,"2026-10-01T12:00:00.123456Z"])
    func closedCapabilityRoundTripsWithoutInventingADraftOrSignupDate(marker:String?) throws {
        let state=try Self.decode(Self.stateObject(marker:marker))
        #expect(state.draft == nil && !state.completion.completed && state.completion.completedAt == marker)
        let wire=try #require(JSONSerialization.jsonObject(with:JSONEncoder().encode(state)) as? [String:Any])
        #expect((wire["legacy_reconsent"] as? [String:Any])?["protocol"] as? String == "documents_only_v1")
    }
    @Test func aPresentNullUnknownOrMalformedCapabilityCannotBecomeAnOrdinarySignup() throws {
        for bad:Any in [NSNull(),["protocol":"unknown"],[:],"documents_only_v1"] {
            var object=try Self.stateObject();object["legacy_reconsent"]=bad
            #expect(throws:(any Error).self) {try Self.decode(object)}
        }
    }
    @Test func documentsOnlyRejectsAQuestionnaireAndPreservesOrdinaryDraftValidation() throws {
        let object=try Self.stateObject(marker:"2026-10-01T12:00:00.123456Z",draft:E3Fixtures.draft())
        #expect(throws:(any Error).self) {try Self.decode(object)}
        var ordinary=object;ordinary.removeValue(forKey:"legacy_reconsent")
        #expect(try Self.decode(ordinary).draft != nil)
    }
    static let key = try! IdempotencyKey(validating:"b3b01000-0000-4000-8000-000000007301")
    static func input() throws -> OnboardingLegacyDocumentInput {
        try .init(locale:"pt-BR",actions:E3Fixtures.requirements.documents.map(\.explicitAction))
    }
    static func acknowledgementObject() throws -> [String:Any] {
        let actions=try Self.input().documentActions.map { action -> [String:Any] in
            var wire=try #require(JSONSerialization.jsonObject(with:JSONEncoder().encode(action)) as? [String:Any])
            wire["purpose"]="synthetic_notice";wire["acted_at"]="2026-10-27T12:00:00.000001Z";return wire
        }
        return ["version":1,"operation_key":key.value,"receipt":["id":"b3b01000-0000-4000-8000-000000007302",
            "locale":"pt-BR","accepted_at":"2026-10-28T01:00:00.000001Z","document_actions":actions]]
    }
    @Test func separateCommandHasOnlyThreeFieldsAndRejectsForeignOrDevelopmentActions() throws {
        let input=try Self.input()
        let wire=try #require(JSONSerialization.jsonObject(with:JSONEncoder().encode(input)) as? [String:Any])
        #expect(Set(wire.keys) == ["version","locale","document_actions"])
        #expect(throws:OnboardingRepositoryError.invalidDraft) {try OnboardingLegacyDocumentInput(locale:"pt-BR",actions:[])}
        let action=try #require(input.documentActions.first)
        #expect(throws:OnboardingRepositoryError.invalidDraft) {try OnboardingLegacyDocumentInput(locale:"en-US",actions:[action])}
        #expect(throws:OnboardingRepositoryError.invalidDraft) {try OnboardingLegacyDocumentInput(locale:"pt-BR",actions:[action,action])}
        let dev=OnboardingDocumentAction(documentKey:"dev_fixture",version:action.version,locale:action.locale,contentHash:action.contentHash,action:action.action)
        #expect(throws:OnboardingRepositoryError.invalidDraft) {try OnboardingLegacyDocumentInput(locale:"pt-BR",actions:[dev])}
    }
    @Test(arguments:["version","operation","locale","hash","action","future_action"])
    func originalAcknowledgementMustMatchTheExactCommandWithoutGrantingSignup(change:String) throws {
        let input=try Self.input()
        var wire=try Self.acknowledgementObject()
        let valid=try JSONDecoder().decode(OnboardingLegacyDocumentAcknowledgement.self,from:JSONSerialization.data(withJSONObject:wire))
        #expect(valid.matches(input,key:Self.key))
        var receipt=try #require(wire["receipt"] as? [String:Any])
        var actions=try #require(receipt["document_actions"] as? [[String:Any]])
        switch change {
        case "version":wire["version"]=2
        case "operation":wire["operation_key"]="b3b01000-0000-4000-8000-000000007399"
        case "locale":receipt["locale"]="en-US"
        case "hash":actions[0]["content_hash"]=String(repeating:"b",count:64)
        case "action":actions[0]["action"]="consent"
        default:actions[0]["acted_at"]="2026-10-29T01:00:00.000001Z"
        }
        receipt["document_actions"]=actions;wire["receipt"]=receipt
        let invalid=try JSONDecoder().decode(OnboardingLegacyDocumentAcknowledgement.self,from:JSONSerialization.data(withJSONObject:wire))
        #expect(!invalid.matches(input,key:Self.key))
    }
    @Test func scopedTransportUsesTheSeparateEndpointWithoutQueriesOrSignupIntent() async throws {
        let peer=LegacyDocumentPeer(response:try JSONSerialization.data(withJSONObject:Self.acknowledgementObject()))
        let repo=try await MobileOnboardingRepository(transport:peer,sessionLifecycle:LegacyDocumentLifecycle(),clinicalRepresentation:.currentV1).scoped(for:"auth-A")
        let ack=try await repo.acceptLegacyDocuments(Self.input(),for:"auth-A",key:Self.key)
        #expect(ack.matches(try Self.input(),key:Self.key))
        let requests=await peer.requests;#expect(requests.count == 1)
        let request=try #require(requests.first)
        #expect(request.method == .post && request.path == "/api/mobile/v1/onboarding/reconsent" && request.queryItems.isEmpty)
        #expect(request.idempotency == .required(Self.key))
        let bytes=try #require(request.body)
        let wire=try #require(JSONSerialization.jsonObject(with:bytes) as? [String:Any])
        #expect(Set(wire.keys) == ["version","locale","document_actions"])
    }
    @Test func pendingLegacyDocumentsNeverRestoreADeviceQuestionnaire() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("legacy-documents-\(UUID().uuidString)")
        defer {try? FileManager.default.removeItem(at:folder)}
        let store=OnboardingDeviceDraftStore(directory:folder);store.save(E3Fixtures.draft(),for:"auth-A")
        let peer=LegacyDocumentPeer(response:try JSONSerialization.data(withJSONObject:Self.stateObject()))
        let repo=try await MobileOnboardingRepository(transport:peer,deviceDraft:store,sessionLifecycle:LegacyDocumentLifecycle(),clinicalRepresentation:.currentV1).scoped(for:"auth-A")
        let state=try await repo.loadState(for:"auth-A")
        #expect(state.draft == nil && state.legacyReconsent == .documentsOnly && store.load(for:"auth-A") == nil)
    }
    @Test(arguments:[Optional<String>.none,"2026-10-01T12:00:00.123456Z"]) @MainActor
    func rootRestoresOnlyDocumentsWithoutRequiringOrCreatingAQuestionnaire(marker:String?) async throws {
        let repository=LegacyDocumentStateRepository(state:try Self.decode(Self.stateObject(marker:marker)))
        let session=AuthSession(userID:"auth-A",email:"legacy@example.invalid",isEmailConfirmed:true,isOnboardingCompleted:true)
        let app=AppFlowModel(authentication:CleanupModelAuthentication(session:session),onboarding:repository,
            persona:E3Persona(),telemetry:DisabledTelemetryClient())
        await app.start()
        #expect(app.state == .onboarding(userID:"auth-A",step:.consent))
        #expect(app.restoredOnboardingDraft == nil)
        #expect(app.restoredOnboardingRequirements == E3Fixtures.requirements)
        #expect(app.restoredHistoricalCompletedAt == marker)
        #expect(app.onboardingLoadFailure == nil && app.onboardingOwnerToken != nil)
    }
    @Test(arguments:[false,true],[false,true])
    func originalSessionOwnsBothLateSuccessAndLateFailure(returnToA:Bool,failure:Bool) async throws {
        let life=LegacyDocumentLifecycle()
        let peer=LegacyDocumentPeer(response:try JSONSerialization.data(withJSONObject:Self.acknowledgementObject()),failure:failure ? .network:nil,effect:{
            await life.replace("auth-B");if returnToA {await life.replace("auth-A")}
        })
        let repo=try await MobileOnboardingRepository(transport:peer,sessionLifecycle:life,clinicalRepresentation:.currentV1).scoped(for:"auth-A")
        await #expect(throws:SessionLifecycleError.sessionSuperseded) {try await repo.acceptLegacyDocuments(Self.input(),for:"auth-A",key:Self.key)}
        await #expect(throws:SessionLifecycleError.sessionSuperseded) {try await repo.acceptLegacyDocuments(Self.input(),for:"auth-A",key:Self.key)}
        #expect(await peer.requests.count == 1)
    }
}

private struct LegacyDocumentWireRequest:Sendable {
    let method:HTTPMethod;let path:String;let queryItems:[URLQueryItem];let body:Data?;let idempotency:MobileAPIIdempotency
}
private actor LegacyDocumentPeer:MobileAPIExecuting {
    let response:Data;let failure:MobileAPITransportError?;let effect:@Sendable () async -> Void
    private(set) var requests:[LegacyDocumentWireRequest]=[]
    init(response:Data,failure:MobileAPITransportError?=nil,effect:@escaping @Sendable () async -> Void={}) {self.response=response;self.failure=failure;self.effect=effect}
    func execute<Response:Decodable & Sendable>(_ request:MobileAPIRequest<Response>) async throws -> Response {
        requests.append(.init(method:request.method,path:request.path,queryItems:request.queryItems,body:request.body,idempotency:request.idempotency))
        await effect();if let failure {throw failure};return try JSONDecoder().decode(Response.self,from:response)
    }
}
private actor LegacyDocumentLifecycle:SessionLifecycleProviding {
    private var user="auth-A",generation:UInt64=1
    func replace(_ user:String) {self.user=user;generation += 1}
    func currentBearerToken() async -> String? {"synthetic"}
    func leaseForRequest() async throws -> SessionLease {.init(userID:user,generation:generation,bearer:"synthetic")}
    func validate(_ lease:SessionLease) async throws {guard lease.userID == user && lease.generation == generation else {throw SessionLifecycleError.sessionSuperseded}}
    func refreshAfterUnauthorized(lease:SessionLease) async throws -> SessionLease {try await validate(lease);return lease}
    func signOut() async -> RemoteRevocationOutcome {generation += 1;return .confirmed}
    func beginPatientWork(lease:SessionLease,cancel:@escaping @Sendable () -> Void) async throws -> UUID {try await validate(lease);return UUID()}
    func finishPatientWork(_ id:UUID) async {}
    func performPatientStateOperation<Value:Sendable>(lease:SessionLease,operation:@Sendable () throws -> Value) throws -> Value {
        guard lease.userID == user && lease.generation == generation else {throw SessionLifecycleError.sessionSuperseded}
        return try operation()
    }
}

private actor LegacyDocumentStateRepository:OnboardingRepository {
    let state:OnboardingServerState
    init(state:OnboardingServerState){self.state=state}
    func loadState(for userID:String) async throws -> OnboardingServerState {state}
    func loadDraft(for userID:String) async throws -> OnboardingDraft? {throw OnboardingRepositoryError.serviceUnavailable}
    func saveDraft(_ draft:OnboardingDraft,for userID:String) async throws {throw OnboardingRepositoryError.serviceUnavailable}
    func complete(_ draft:OnboardingDraft,for userID:String) async throws {throw OnboardingRepositoryError.serviceUnavailable}
    func clear(for userID:String) async throws {throw OnboardingRepositoryError.serviceUnavailable}
}
