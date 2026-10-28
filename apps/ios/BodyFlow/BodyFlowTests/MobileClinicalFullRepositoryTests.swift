import Foundation
import Testing
@testable import BodyFlow

@Suite("Clinical FULL network — strict public input and original session")
struct MobileClinicalFullRepositoryTests {
    static let scope = ClinicalFullScope(kind:.regular,cycleID:ClinicalFullFormTests.cycle)
    static let key = try! IdempotencyKey(validating:"b3b01000-0000-4000-8000-000000004920")
    static func object(_ data:Data?) throws -> [String:Any] {
        let bytes = try #require(data)
        let decoded = try JSONSerialization.jsonObject(with:bytes)
        return try #require(decoded as? [String:Any])
    }
    @Test(arguments:[ClinicalFullKind.regular,.transition,.routine]) func publicRequestsContainOnlyAnswersAndExplicitNullableScope(kind:ClinicalFullKind) async throws {
        let scope = ClinicalFullScope(kind:kind,cycleID:kind.requiresCycle ? Self.scope.cycleID : nil)
        let transport = FullRecordingTransport(scope:scope), lifecycle = FullNetworkLifecycle()
        let bound = try await MobileClinicalFullRepository(transport:transport,lifecycle:lifecycle).scoped(for:"auth-A")
        let form = try await bound.describe(scope:scope,purpose:.normal)
        var draft = ClinicalFullDraft(questionnaire:form)
        if kind.requiresNewPhotos { draft.acceptBodyFat(from:form) }
        _ = try await bound.assess(scope:scope,draft:draft)
        let choice = ClinicalFullChoice(kind:.keep)
        let preview = try await bound.prepare(scope:scope,draft:draft,choice:choice,key:Self.key)
        _ = try await bound.confirm(scope:scope,draft:draft,choice:choice,preview:preview,key:Self.key)
        let calls = await transport.calls
        #expect(calls.map(\.path) == ["/api/mobile/v1/reevaluation/form","/api/mobile/v1/reevaluation/assess","/api/mobile/v1/reevaluation/preview","/api/mobile/v1/reevaluation/confirm"])
        for call in calls {
            let object = try Self.object(call.body)
            #expect(object["kind"] as? String == kind.rawValue)
            if kind == .routine { #expect(object["cycleId"] is NSNull) }
            else { #expect(object["cycleId"] as? String == scope.cycleID) }
            for forbidden in ["userId","phase","sourceHash","meanHundredths","targets","context_hash","noPlanOrigin"] { #expect(object[forbidden] == nil) }
        }
        let assess = try Self.object(calls[1].body)
        let answers = try #require(assess["input"] as? [String:Any])
        #expect(answers["choice"] == nil)
        if kind == .routine { #expect(answers["bodyFat"] is NSNull) }
        let prepared = try Self.object(calls[2].body)
        #expect(((prepared["input"] as? [String:Any])?["choice"] as? [String:String]) == ["kind":"keep"])
        #expect(calls[2].idempotency == .required(Self.key) && calls[3].idempotency == .required(Self.key))
        #expect(await lifecycle.finished == 4)
    }
    @Test func anOriginalRepositoryCannotSendAfterBOrAfterANewSessionForA() async throws {
        let transport = FullRecordingTransport(scope:Self.scope), lifecycle = FullNetworkLifecycle()
        let old = try await MobileClinicalFullRepository(transport:transport,lifecycle:lifecycle).scoped(for:"auth-A")
        await lifecycle.replace(user:"auth-B")
        await #expect(throws:(any Error).self) { try await old.entry() }
        await #expect(throws:(any Error).self) { try await old.scoped(for:"auth-B") }
        await lifecycle.replace(user:"auth-A")
        await #expect(throws:(any Error).self) { try await old.entry() }
        #expect(await transport.calls.isEmpty)
    }
    @Test func aLateResponseCannotEscapeTheOriginalLease() async throws {
        let transport = FullRecordingTransport(scope:Self.scope), lifecycle = FullNetworkLifecycle()
        let bound = try await MobileClinicalFullRepository(transport:transport,lifecycle:lifecycle).scoped(for:"auth-A")
        await transport.holdNext()
        let task = Task { try await bound.entry() }
        await transport.waitForRequest(); await lifecycle.replace(user:"auth-B"); await transport.release()
        await #expect(throws:(any Error).self) { try await task.value }
        #expect(await lifecycle.finished == 1)
        #expect(await lifecycle.leaseReads == 1)
    }
    @Test func historicDisplayCannotSendANewConfirmationAndHealthCodesAreCanonical() async throws {
        let transport = FullRecordingTransport(scope:Self.scope), lifecycle = FullNetworkLifecycle()
        let bound = try await MobileClinicalFullRepository(transport:transport,lifecycle:lifecycle).scoped(for:"auth-A")
        let historic:ClinicalFullPreview = try ClinicalFullWorkflowTests.decode(ClinicalFullPreview.self,["version":1,"status":"historical_display_unavailable","preview_id":ClinicalFullWorkflowTests.previewID,"kind":"REGULAR","cycle_id":Self.scope.cycleID!,"expires_at":"2026-11-03T12:15:00Z"]).validated()
        let draft = ClinicalFullDraft(questionnaire:try ClinicalFullWorkflowTests.form(Self.scope))
        await #expect(throws:ClinicalFullFailure.invalidResponse) { try await bound.confirm(scope:Self.scope,draft:draft,choice:.init(kind:.keep),preview:historic,key:Self.key) }
        await #expect(throws:ClinicalFullFailure.invalidResponse) { try await bound.declareHealth(items:[],key:Self.key) }
        #expect(await transport.calls.isEmpty)
        _ = try await bound.declareHealth(items:[.professionalDiet,.reducedIntake],key:Self.key)
        let call = try #require(await transport.calls.first)
        let body = try Self.object(call.body)
        #expect(body.count == 1 && body["items"] as? [String] == ["reduced_intake","professional_diet"])
        #expect(call.idempotency == .required(Self.key))
    }
}
private actor FullRecordingTransport: MobileAPIExecuting {
    struct Call: Sendable { let path:String; let body:Data?; let idempotency:MobileAPIIdempotency }
    let scope:ClinicalFullScope
    private(set) var calls:[Call] = []
    private var hold = false
    private var held:CheckedContinuation<Void,Never>?
    private var started:CheckedContinuation<Void,Never>?
    init(scope:ClinicalFullScope) { self.scope = scope }
    func execute<Response:Decodable & Sendable>(_ request:MobileAPIRequest<Response>) async throws -> Response {
        calls.append(Call(path:request.path,body:request.body,idempotency:request.idempotency)); started?.resume(); started = nil
        if hold { await withCheckedContinuation { held = $0 } }
        let data:Data
        if request.path.hasSuffix("/form") { data = try JSONEncoder().encode(ClinicalFullWorkflowTests.form(scope)) }
        else {
            let object:[String:Any]
            if request.path.hasSuffix("/assess") { object = ["version":1,"status":"no_change_available","actions":[],"preference":NSNull()] }
            else if request.path.hasSuffix("/preview") { object = ["version":1,"status":"ready","preview_id":ClinicalFullWorkflowTests.previewID,"kind":scope.kind.rawValue,"cycle_id":scope.cycleID.map { $0 as Any } ?? NSNull(),"expires_at":"2026-11-03T12:15:00Z","choice":["kind":"keep"],"phase":"recomposicao","targets":["calories_kcal":1599,"protein_g":126],"professional_assessment_recommended":false,"pause_weight_loss_guidance":false] }
            else if request.path.hasSuffix("/confirm") { object = ["version":1,"review_id":ClinicalFullWorkflowTests.previewID,"kind":scope.kind.rawValue,"cycle_id":scope.cycleID.map { $0 as Any } ?? NSNull(),"completed_at":"2026-10-26T12:01:00Z","next_due_date":"2026-11-09"] }
            else if request.path.hasSuffix("/health") { object = ["version":1,"receipt_id":ClinicalFullWorkflowTests.previewID,"declared_at":"2026-10-26T12:01:00Z"] }
            else { object = ["version":1,"availability":"available","unavailable_reason":NSNull(),"clock":["base_date":"2026-10-20","due_date":"2026-11-03","timezone":"America/Sao_Paulo"],"cycle":["id":ClinicalFullFormTests.cycle,"kind":"REGULAR","status":"open","revision":"1"]] }
            data = try JSONSerialization.data(withJSONObject:object)
        }
        return try JSONDecoder().decode(Response.self,from:data)
    }
    func holdNext() { hold = true }
    func waitForRequest() async { if calls.isEmpty { await withCheckedContinuation { started = $0 } } }
    func release() { hold = false; held?.resume(); held = nil }
}
private actor FullNetworkLifecycle: SessionLifecycleProviding {
    private var user = "auth-A"
    private var generation:UInt64 = 1
    private(set) var finished = 0
    private(set) var leaseReads = 0
    func currentBearerToken() async -> String? { "synthetic-only" }
    func leaseForRequest() async throws -> SessionLease { leaseReads += 1; return SessionLease(userID:user,generation:generation,bearer:"synthetic-only") }
    func validate(_ lease:SessionLease) async throws { guard lease.userID == user, lease.generation == generation else { throw SessionLifecycleError.sessionSuperseded } }
    func refreshAfterUnauthorized(lease:SessionLease) async throws -> SessionLease { try await validate(lease); return lease }
    func signOut() async -> RemoteRevocationOutcome { generation += 1; return .confirmed }
    func beginPatientWork(lease:SessionLease,cancel:@escaping @Sendable () -> Void) async throws -> UUID { try await validate(lease); return UUID() }
    func finishPatientWork(_ id:UUID) async { finished += 1 }
    func replace(user:String) { self.user = user; generation += 1 }
}
