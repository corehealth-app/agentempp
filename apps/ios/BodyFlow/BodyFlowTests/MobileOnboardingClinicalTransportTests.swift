import Foundation
import Testing
@testable import BodyFlow

@Suite("Clinical signup wire and original session")
struct MobileOnboardingClinicalTransportTests {
    @Test func clinicalCompletionUsesLiteralNullWhileLegacyRemainsClosed() async throws {
        let transport=ClinicalSignupTransport(),repo=try await MobileOnboardingRepository(transport:transport,sessionLifecycle:ClinicalSignupLifecycle()).scoped(for:"auth-A")
        var draft=E3Fixtures.draft();draft.objective=nil
        let intent=try Self.intent()
        await #expect(throws:OnboardingRepositoryError.invalidDraft) {try await repo.completeOfficial(draft,for:"auth-A",completionIntent:intent)}
        #expect(await transport.calls.isEmpty)
        let ack=try await repo.completeOfficial(draft,for:"auth-A",completionIntent:intent,clinicalSignup:.current)
        #expect(ack.objective == nil && ack.matches(draft))
        let call=try #require(await transport.calls.first),raw=try #require(call.body)
        let object=try #require(JSONSerialization.jsonObject(with:raw) as? [String:Any])
        #expect(object["objective"] is NSNull)
        #expect(object["signup_strength_protocol"] as? String == "osc1")
        #expect(object["completion_intent_id"] as? String == intent.intentID.uuidString.lowercased())
        #expect(call.idempotency == .required(intent.requestKey))
        #expect(call.query.contains(URLQueryItem(name:"clinical_policy",value:"current_clinical_v1")))
        for key in ["no_plan","health_state","epoch","calories","targets"] {#expect(object[key] == nil)}
    }
    @Test func healthWireContainsOnlyExplicitTupleAndKeepsSameHeaderKey() async throws {
        let transport=ClinicalSignupTransport(),repo=try await MobileOnboardingRepository(transport:transport,sessionLifecycle:ClinicalSignupLifecycle()).scoped(for:"auth-A")
        let input=try OnboardingSignupHealthDeclaration(intent:Self.intent(),locale:"pt-BR",actions:E3Fixtures.draft().documentActions ?? [],risks:[.reducedIntake])
        let key=try IdempotencyKey(validating:"b3b01000-0000-4000-8000-000000005905")
        for _ in 0..<2 {_=try await repo.admitSignupHealth(input,for:"auth-A",key:key)}
        let calls=await transport.calls
        #expect(calls.count == 2 && calls[0].body == calls[1].body)
        for call in calls {
            #expect(call.path == "/api/mobile/v1/onboarding/health" && call.idempotency == .required(key))
            let bytes=try #require(call.body)
            let object=try #require(JSONSerialization.jsonObject(with:bytes) as? [String:Any])
            #expect(Set(object.keys)==["version","intent_id","request_key","locale","document_actions","risks"])
        }
    }
    @Test func retiredRepositoryCannotDeclareAsBOrReplacementA() async throws {
        let transport=ClinicalSignupTransport(),life=ClinicalSignupLifecycle()
        let root=MobileOnboardingRepository(transport:transport,sessionLifecycle:life)
        let old=try await root.scoped(for:"auth-A")
        let input=try OnboardingSignupHealthDeclaration(intent:Self.intent(),locale:"pt-BR",actions:E3Fixtures.draft().documentActions ?? [],risks:[.reducedIntake])
        let key=try IdempotencyKey(validating:"b3b01000-0000-4000-8000-000000005905")
        for user in ["auth-B","auth-A"] {
            await life.replace(user)
            await #expect(throws:(any Error).self) {try await old.admitSignupHealth(input,for:"auth-A",key:key)}
        }
        #expect(await transport.calls.isEmpty)
    }
    @Test("Explicit clinical commands also refuse token-only legacy constructors before dispatch")
    func clinicalCommandsRequireOriginalScope() async throws {
        let transport = ClinicalSignupTransport(), repo = MobileOnboardingRepository(transport: transport)
        let input = try OnboardingSignupHealthDeclaration(intent: Self.intent(), locale: "pt-BR",
            actions: E3Fixtures.draft().documentActions ?? [], risks: [.reducedIntake])
        let key = try IdempotencyKey(validating: "b3b01000-0000-4000-8000-000000005905")
        await #expect(throws: SessionLifecycleError.sessionSuperseded) { _ = try await repo.admitSignupHealth(input, for: "auth-A", key: key) }
        var draft = E3Fixtures.draft(); draft.objective = nil
        let intent = try Self.intent()
        await #expect(throws: SessionLifecycleError.sessionSuperseded) { _ = try await repo.completeOfficial(draft, for: "auth-A", completionIntent: intent, clinicalSignup: .current) }
        #expect(await transport.calls.isEmpty)
    }

    static func intent()throws->OnboardingCompletionIntent {
        try JSONDecoder().decode(OnboardingCompletionIntent.self,from:Data(#"{"protocol":"osc1","preparation_id":"b3b01000-0000-4000-8000-000000005900","intent_id":"b3b01000-0000-4000-8000-000000005901","request_key":"osc1:b3b01000-0000-4000-8000-000000005902"}"#.utf8))
    }
}
private actor ClinicalSignupTransport:MobileAPIExecuting {
    struct Call:Sendable {let path:String;let body:Data?;let idempotency:MobileAPIIdempotency;let query:[URLQueryItem]}
    var calls:[Call]=[]
    func execute<Response:Decodable & Sendable>(_ request:MobileAPIRequest<Response>) async throws->Response {
        calls.append(.init(path:request.path,body:request.body,idempotency:request.idempotency,query:request.queryItems))
        let bytes=try #require(request.body)
        var input=try #require(JSONSerialization.jsonObject(with:bytes) as? [String:Any])
        let at="2026-10-27T12:00:00.000001Z", output:[String:Any]
        if request.path.hasSuffix("/health") {
            guard case .required(let key)=request.idempotency else {throw OnboardingRepositoryError.invalidDraft}
            input["id"]="b3b01000-0000-4000-8000-000000005903";input["requirement_set_id"]="b3b01000-0000-4000-8000-000000005904";input["admitted_at"]=at
            output=["version":1,"availability":"available","operation_key":key.value,"receipt":input]
        } else {
            let actions=(input["document_actions"] as? [[String:Any]] ?? []).map {item in var a=item;a["purpose"]="synthetic";a["acted_at"]=at;return a}
            output=["onboarding_completed":true,"completed_at":at,"objective":input["objective"] ?? NSNull(),"persona":input["persona"] ?? "focus","document_actions":actions,"clinical_policy":try JSONSerialization.jsonObject(with:JSONEncoder().encode(OnboardingCurrentPresentationTests.policy())),
                    "clinical_safety":["version":1,"no_plan":true,"hold_active":false,"loss_guard":false,"hide_protein":true,"recording_allowed":true,"date":"2026-10-27","timezone":"America/Sao_Paulo","observed_at":at]]
        }
        return try JSONDecoder().decode(Response.self,from:JSONSerialization.data(withJSONObject:output))
    }
}
private actor ClinicalSignupLifecycle:SessionLifecycleProviding {
    var user="auth-A",generation:UInt64=1
    func currentBearerToken() async->String? {"synthetic"}
    func leaseForRequest() async throws->SessionLease {.init(userID:user,generation:generation,bearer:"synthetic")}
    func validate(_ lease:SessionLease) async throws {guard lease.userID==user && lease.generation==generation else {throw SessionLifecycleError.sessionSuperseded}}
    func refreshAfterUnauthorized(lease:SessionLease) async throws->SessionLease {try await validate(lease);return lease}
    func signOut() async->RemoteRevocationOutcome {generation+=1;return .confirmed}
    func beginPatientWork(lease:SessionLease,cancel:@escaping @Sendable ()->Void) async throws->UUID {try await validate(lease);return UUID()}
    func finishPatientWork(_ id:UUID) async {}
    func replace(_ value:String) {user=value;generation+=1}
}
