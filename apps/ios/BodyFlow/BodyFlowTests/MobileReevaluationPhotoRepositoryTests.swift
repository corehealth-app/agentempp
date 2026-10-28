import Foundation
import Testing
import UIKit
@testable import BodyFlow

@Suite("Recurring photos — original session and immutable HTTP intentions")
struct MobileReevaluationPhotoRepositoryTests {
    typealias Fixture = ReevaluationPhotoContractTests
    static let key = try! IdempotencyKey(validating:"b3b01000-0000-4000-8000-000000005650")
    static func data(_ raw:[String:Any]) throws -> Data { try JSONSerialization.data(withJSONObject:raw) }
    static func snapshot() -> [String:Any] {
        ["version":1,"cycle_id":Fixture.cycle,"cycle_revision":"2","acceptance_id":Fixture.acceptance,"photos":["front","side","back"].map { ["pose":$0,"asset":NSNull()] as [String:Any] },"quota":["max_new_photos":6,"window_seconds":86400]]
    }
    @Test func allRequestsStayOnTheBoundCycleAndContainOnlyPublicInputs() async throws {
        let ticket:[String:Any] = ["signed_url":"https://owned.supabase.co/storage/v1/object/upload/sign/body-checkin-photos/\(Fixture.document)/\(Fixture.asset).jpg?token=synthetic","method":"PUT","headers":["Content-Type":"image/jpeg","x-upsert":"false"],"expires_at":"2026-10-27T14:00:00.000Z"]
        let payloads = [Fixture.consent(),Fixture.consent(true),Self.snapshot(),
            ["version":1,"cycle_id":Fixture.cycle,"cycle_revision":"2","asset":Fixture.photo(),"quota":["max_new_photos":6,"window_seconds":86400]],
            ["version":1,"cycle_id":Fixture.cycle,"asset":Fixture.photo(),"upload":ticket],
            ["version":1,"cycle_id":Fixture.cycle,"cycle_revision":"3","source_revision":"2","asset":Fixture.photo(status:"uploaded")],
            ["version":1,"cycle_id":Fixture.cycle,"asset_id":Fixture.asset,"status":"processed"],
            ["version":1,"cycle_id":Fixture.cycle,"acceptance_id":Fixture.acceptance,"status":"discard_requested","deletion":"waiting"]]
        let transport = RecurringPhotoTransport(payloads:try payloads.map(Self.data)), lifecycle = RecurringPhotoLifecycle()
        let repo = try await MobileReevaluationPhotoRepository(transport:transport,lifecycle:lifecycle).scoped(for:"auth-A",cycleID:Fixture.cycle)
        let consent = try await repo.consent()
        _ = try await repo.accept(ReevaluationPhotoConsentInput(state:consent),key:Self.key)
        _ = try await repo.snapshot()
        _ = try await repo.allocate(.init(expectedRevision:"2",acceptanceId:Fixture.acceptance,pose:.front,mimeType:"image/jpeg",sizeBytes:1200),key:Self.key)
        _ = try await repo.issueUpload(assetID:Fixture.asset,acceptanceID:Fixture.acceptance,key:Self.key)
        _ = try await repo.complete(assetID:Fixture.asset,acceptanceID:Fixture.acceptance,key:Self.key)
        _ = try await repo.process(assetID:Fixture.asset,key:Self.key)
        _ = try await repo.discard(.init(acceptanceId:Fixture.acceptance,expectedRevision:"3"),key:Self.key)
        let calls = await transport.calls, base = "/api/mobile/v1/reevaluation/\(Fixture.cycle)/photos"
        #expect(calls.map(\.path) == [base+"/consent",base+"/consent",base,base,base+"/\(Fixture.asset)/upload",base+"/\(Fixture.asset)/complete",base+"/\(Fixture.asset)/process",base+"/discard"])
        for index in [1,3,4,5,6,7] {
            #expect(calls[index].idempotency == .required(Self.key))
            let body = try #require(calls[index].body)
            let object = try #require(JSONSerialization.jsonObject(with:body) as? [String:Any])
            for forbidden in ["userId","cycleId","signupGeneration","now","mean","sourceHash","bf_percent_estimate"] { #expect(object[forbidden] == nil) }
            if [4,5,6].contains(index) { #expect(object.isEmpty) }
        }
        #expect(await lifecycle.finished == 8)
        #expect(await lifecycle.leaseReads == 1)
    }
    @Test func oldScopeCannotRenewForBOrForANewSessionOfA() async throws {
        let transport = RecurringPhotoTransport(payloads:[try Self.data(Fixture.consent())]), lifecycle = RecurringPhotoLifecycle()
        let repo = try await MobileReevaluationPhotoRepository(transport:transport,lifecycle:lifecycle).scoped(for:"auth-A",cycleID:Fixture.cycle)
        await lifecycle.replace("auth-B")
        await #expect(throws:(any Error).self) { try await repo.consent() }
        await #expect(throws:(any Error).self) { try await repo.scoped(for:"auth-B",cycleID:Fixture.cycle) }
        await lifecycle.replace("auth-A")
        await #expect(throws:(any Error).self) { try await repo.consent() }
        #expect(await transport.calls.isEmpty)
    }
    @Test func neitherLateResponseNorFinishingRegistryCanReturnDataAcrossSessionChange() async throws {
        for finish in [false,true] {
            let transport = RecurringPhotoTransport(payloads:[try Self.data(Fixture.consent())],hold:!finish), lifecycle = RecurringPhotoLifecycle()
            let repo = try await MobileReevaluationPhotoRepository(transport:transport,lifecycle:lifecycle).scoped(for:"auth-A",cycleID:Fixture.cycle)
            if finish { await lifecycle.switchOnFinish() }
            let task = Task { try await repo.consent() }
            if !finish { await transport.waitStarted(); await lifecycle.replace("auth-B"); await transport.release() }
            await #expect(throws:(any Error).self) { try await task.value }
            #expect(await lifecycle.finished == 1)
        }
    }
    @Test func processingRetryPreservesTheSameKeyAfterAnUncertainNetworkOutcome() async throws {
        let result = try Self.data(["version":1,"cycle_id":Fixture.cycle,"asset_id":Fixture.asset,"status":"processed"])
        let transport = RecurringPhotoTransport(payloads:[result],failFirst:true), lifecycle = RecurringPhotoLifecycle()
        let repo = try await MobileReevaluationPhotoRepository(transport:transport,lifecycle:lifecycle).scoped(for:"auth-A",cycleID:Fixture.cycle)
        await #expect(throws:ReevaluationPhotoFailure.offline) { try await repo.process(assetID:Fixture.asset,key:Self.key) }
        #expect(try await repo.process(assetID:Fixture.asset,key:Self.key).status == .processed)
        #expect(await transport.calls.count == 2)
        #expect(await transport.calls.allSatisfy { $0.idempotency == .required(Self.key) })
    }
    @Test func malformedScopeAndMutationInputDoNotReachTransport() async throws {
        let transport = RecurringPhotoTransport(payloads:[]), lifecycle = RecurringPhotoLifecycle()
        let unbound = MobileReevaluationPhotoRepository(transport:transport,lifecycle:lifecycle)
        await #expect(throws:(any Error).self) { try await unbound.scoped(for:"auth-A",cycleID:"bad") }
        let repo = try await unbound.scoped(for:"auth-A",cycleID:Fixture.cycle)
        await #expect(throws:(any Error).self) { try await repo.allocate(.init(expectedRevision:"0",acceptanceId:Fixture.acceptance,pose:.front,mimeType:"image/jpeg",sizeBytes:1200),key:Self.key) }
        await #expect(throws:(any Error).self) { try await repo.process(assetID:"bad",key:Self.key) }
        #expect(await transport.calls.isEmpty)
    }
    @Test @MainActor func captureUsesOneOriginalLeaseForAPIAndProtectedFiles() async throws {
        let transport = RecurringPhotoTransport(payloads:[try Self.data(Fixture.consent())]), lifecycle = RecurringPhotoLifecycle()
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("recurring-photo-test-"+UUID().uuidString,isDirectory:true)
        defer { try? FileManager.default.removeItem(at:parent) }
        let staging = MediaStagingStore(temporaryDirectory:parent)
        let capability = ReevaluationPhotoCaptureCapability.live(transport:transport,lifecycle:lifecycle,uploader:RecurringNoUpload(),staging:staging,camera:.unavailable)
        let scope = try await capability.scoped("auth-A",Fixture.cycle)
        _ = try await scope.photos.consent()
        #expect(await lifecycle.leaseReads == 1)
        let bytes = UIGraphicsImageRenderer(size:CGSize(width:2,height:2)).jpegData(withCompressionQuality:1) { context in
            UIColor.red.setFill(); context.fill(CGRect(x:0,y:0,width:2,height:2))
        }
        let media = try await scope.stagePhoto(bytes,.gallery)
        #expect(media.kind == .signupBodyPhoto && media.mimeType == "image/jpeg" && media.sizeBytes > 0)
        #expect(FileManager.default.fileExists(atPath:media.fileURL.path))
        try await scope.discardStaged(media.fileURL)
        #expect(!FileManager.default.fileExists(atPath:media.fileURL.path))
        await lifecycle.replace("auth-B")
        await #expect(throws:(any Error).self) { try await scope.stagePhoto(bytes,.gallery) }
        #expect((try? FileManager.default.contentsOfDirectory(atPath:staging.root.path).isEmpty) == true)
    }
    @Test func onlyTheAuthoritativePhotoQuotaCodeCanBeTreatedAsAQuotaRefusal() async throws {
        let transport = RecurringPhotoTransport(payloads:[]), lifecycle = RecurringPhotoLifecycle()
        let repo = try await MobileReevaluationPhotoRepository(transport:transport,lifecycle:lifecycle).scoped(for:"auth-A",cycleID:Fixture.cycle)
        let input = ReevaluationPhotoAllocationInput(expectedRevision:"2",acceptanceId:Fixture.acceptance,pose:.front,mimeType:"image/jpeg",sizeBytes:1200)
        await transport.failNext(.rateLimited(code:"mobile_reevaluation_photo_quota",requestID:nil))
        await #expect(throws:ReevaluationPhotoFailure.quota) { try await repo.allocate(input,key:Self.key) }
        await transport.failNext(.rateLimited(code:"unrelated_limit",requestID:nil))
        await #expect(throws:ReevaluationPhotoFailure.unavailable) { try await repo.allocate(input,key:Self.key) }
    }
}
private struct RecurringNoUpload:StorageUploading {
    func upload(_ media:StagedMedia,with ticket:MediaUploadTicket) async throws { throw ReevaluationPhotoFailure.unavailable }
}
private actor RecurringPhotoTransport: MobileAPIExecuting {
    struct Call:Sendable { let path:String; let body:Data?; let idempotency:MobileAPIIdempotency }
    private var payloads:[Data]; private var hold:Bool; private var failFirst:Bool
    private var nextFailure:MobileAPITransportError?
    private(set) var calls:[Call] = []
    private var held:CheckedContinuation<Void,Never>?; private var started:CheckedContinuation<Void,Never>?
    init(payloads:[Data],hold:Bool = false,failFirst:Bool = false) { self.payloads = payloads; self.hold = hold; self.failFirst = failFirst }
    func execute<Response:Decodable & Sendable>(_ request:MobileAPIRequest<Response>) async throws -> Response {
        calls.append(.init(path:request.path,body:request.body,idempotency:request.idempotency)); started?.resume(); started = nil
        if hold { await withCheckedContinuation { held = $0 } }
        if failFirst { failFirst = false; throw MobileAPITransportError.network }
        if let failure = nextFailure { nextFailure = nil; throw failure }
        return try JSONDecoder().decode(Response.self,from:payloads.removeFirst())
    }
    func waitStarted() async { if calls.isEmpty { await withCheckedContinuation { started = $0 } } }
    func release() { hold = false; held?.resume(); held = nil }
    func failNext(_ failure:MobileAPITransportError) { nextFailure = failure }
}
private actor RecurringPhotoLifecycle: SessionLifecycleProviding {
    private var user = "auth-A", generation:UInt64 = 1, replaceAtFinish = false
    private(set) var finished = 0, leaseReads = 0
    func currentBearerToken() async -> String? { "synthetic-only" }
    func leaseForRequest() async throws -> SessionLease { leaseReads += 1; return SessionLease(userID:user,generation:generation,bearer:"synthetic-only") }
    func validate(_ lease:SessionLease) async throws { guard lease.userID == user, lease.generation == generation else { throw SessionLifecycleError.sessionSuperseded } }
    func refreshAfterUnauthorized(lease:SessionLease) async throws -> SessionLease { try await validate(lease); return lease }
    func signOut() async -> RemoteRevocationOutcome { generation += 1; return .confirmed }
    func beginPatientWork(lease:SessionLease,cancel:@escaping @Sendable () -> Void) async throws -> UUID { try await validate(lease); return UUID() }
    func finishPatientWork(_ id:UUID) async { finished += 1; if replaceAtFinish { replace("auth-B") } }
    func performPatientStateOperation<Value:Sendable>(lease:SessionLease,operation:@Sendable () throws -> Value) async throws -> Value {
        guard lease.userID == user, lease.generation == generation else { throw SessionLifecycleError.sessionSuperseded }
        try Task.checkCancellation(); return try operation()
    }
    func replace(_ user:String) { self.user = user; generation += 1 }
    func switchOnFinish() { replaceAtFinish = true }
}
