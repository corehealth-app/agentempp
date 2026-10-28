import Foundation

/// Bound once to the original Auth lease and actual REGULAR cycle. This is
/// separate from signup and generic meal media authority.
struct MobileReevaluationPhotoRepository: ReevaluationPhotosProviding {
    let transport:any MobileAPIExecuting
    let lifecycle:any SessionLifecycleProviding
    private var lease:SessionLease?
    private var cycleID:String?
    init(transport:any MobileAPIExecuting,lifecycle:any SessionLifecycleProviding) {
        self.transport = transport; self.lifecycle = lifecycle; lease = nil; cycleID = nil
    }
    func scoped(for userID:String,cycleID:String) async throws -> Self {
        guard ReevaluationPhotoValidation.id(cycleID) else { throw ReevaluationPhotoFailure.invalidInput }
        if let lease {
            guard lease.userID == userID, self.cycleID == cycleID.lowercased() else { throw ReevaluationPhotoFailure.sessionEnded }
            try await lifecycle.validate(lease); return self
        }
        let original = try await lifecycle.leaseForRequest()
        guard original.userID == userID else { throw ReevaluationPhotoFailure.sessionEnded }
        return try await scoped(to:original,cycleID:cycleID)
    }
    /// A capture must retain the very same lease for filesystem, PUT and API;
    /// asking for a second lease could silently bind a new session of A.
    func scoped(to original:SessionLease,cycleID:String) async throws -> Self {
        guard ReevaluationPhotoValidation.id(cycleID) else { throw ReevaluationPhotoFailure.invalidInput }
        if let lease { guard lease.userID == original.userID, lease.generation == original.generation, self.cycleID == cycleID.lowercased() else { throw ReevaluationPhotoFailure.sessionEnded } }
        try await lifecycle.validate(original)
        var result = self
        if let mobile = transport as? MobileAPITransport { result = .init(transport:mobile.scoped(to:original),lifecycle:lifecycle) }
        result.lease = original; result.cycleID = cycleID.lowercased(); return result
    }
    private var scope:String {
        get throws { guard lease != nil, let cycleID else { throw ReevaluationPhotoFailure.sessionEnded }; return cycleID }
    }
    private var base:String { get throws { "/api/mobile/v1/reevaluation/\(try scope)/photos" } }
    private func key(_ key:IdempotencyKey) throws { guard ReevaluationPhotoValidation.id(key.value) else { throw ReevaluationPhotoFailure.invalidInput } }
    private func asset(_ id:String,_ acceptanceID:String? = nil) throws -> String {
        guard ReevaluationPhotoValidation.id(id), acceptanceID == nil || ReevaluationPhotoValidation.id(acceptanceID!) else { throw ReevaluationPhotoFailure.invalidInput }
        return id.lowercased()
    }
    func consent() async throws -> ReevaluationPhotoConsent {
        let value:ReevaluationPhotoConsent = try await request(.init(method:.get,path:base+"/consent"))
        return try value.validated(cycleID:scope)
    }
    func accept(_ input:ReevaluationPhotoConsentInput,key:IdempotencyKey) async throws -> ReevaluationPhotoConsent {
        try self.key(key)
        let value:ReevaluationPhotoConsent = try await request(.init(method:.post,path:base+"/consent",body:JSONEncoder().encode(input),idempotencyKey:key))
        let checked = try value.validated(cycleID:scope)
        guard checked.availability == .available, let shown = checked.document,
              ReevaluationPhotoValidation.same(shown.id,input.document.id), shown.documentKey == input.document.documentKey,
              shown.version == input.document.version, shown.locale == input.document.locale, shown.bodyHash == input.document.bodyHash,
              UInt64(checked.cycleRevision)! >= UInt64(input.expectedRevision)! else { throw ReevaluationPhotoFailure.invalidResponse }
        return checked
    }
    func snapshot() async throws -> ReevaluationPhotoSnapshot {
        let value:ReevaluationPhotoSnapshot = try await request(.init(method:.get,path:base))
        return try value.validated(cycleID:scope)
    }
    func allocate(_ input:ReevaluationPhotoAllocationInput,key:IdempotencyKey) async throws -> ReevaluationPhotoAllocation {
        try self.key(key); try input.validate()
        let value:ReevaluationPhotoAllocation = try await request(.init(method:.post,path:base,body:JSONEncoder().encode(input),idempotencyKey:key))
        return try value.validated(cycleID:scope,input:input)
    }
    private struct Empty:Encodable,Sendable {}
    private func assetRequest<T:Decodable & Sendable>(_ id:String,_ action:String,_ key:IdempotencyKey) throws -> MobileAPIRequest<T> {
        try self.key(key)
        return try .init(method:.post,path:base+"/\(asset(id))/\(action)",body:JSONEncoder().encode(Empty()),idempotencyKey:key)
    }
    func issueUpload(assetID:String,acceptanceID:String,key:IdempotencyKey) async throws -> ReevaluationPhotoUpload {
        _ = try asset(assetID,acceptanceID)
        let value:ReevaluationPhotoUpload = try await request(assetRequest(assetID,"upload",key))
        return try value.validated(cycleID:scope,assetID:assetID,acceptanceID:acceptanceID)
    }
    func complete(assetID:String,acceptanceID:String,key:IdempotencyKey) async throws -> ReevaluationPhotoCompletion {
        _ = try asset(assetID,acceptanceID)
        let value:ReevaluationPhotoCompletion = try await request(assetRequest(assetID,"complete",key))
        return try value.validated(cycleID:scope,assetID:assetID,acceptanceID:acceptanceID)
    }
    func process(assetID:String,key:IdempotencyKey) async throws -> ReevaluationPhotoProcessing {
        let value:ReevaluationPhotoProcessing = try await request(assetRequest(assetID,"process",key))
        return try value.validated(cycleID:scope,assetID:assetID)
    }
    func discard(_ input:ReevaluationPhotoDiscardInput,key:IdempotencyKey) async throws -> ReevaluationPhotoDiscard {
        try self.key(key)
        guard ReevaluationPhotoValidation.id(input.acceptanceId), ReevaluationPhotoValidation.revision(input.expectedRevision) else { throw ReevaluationPhotoFailure.invalidInput }
        let value:ReevaluationPhotoDiscard = try await request(.init(method:.post,path:base+"/discard",body:JSONEncoder().encode(input),idempotencyKey:key))
        return try value.validated(cycleID:scope,acceptanceID:input.acceptanceId)
    }
    func publish(_ operation:@MainActor @Sendable () throws -> Void) async throws {
        guard let lease else { throw ReevaluationPhotoFailure.sessionEnded }
        try await lifecycle.performVisiblePatientStateOperation(lease:lease,operation:operation)
    }
    private func request<T:Decodable & Sendable>(_ request:MobileAPIRequest<T>) async throws -> T {
        guard let lease else { throw ReevaluationPhotoFailure.sessionEnded }
        do { return try await ReevaluationPhotoSessionWork(lifecycle:lifecycle,lease:lease).run { try await transport.execute(request) } }
        catch {
            if error is CancellationError { throw CancellationError() }
            do { try await lifecycle.validate(lease) } catch { throw ReevaluationPhotoFailure.sessionEnded }
            if let failure = error as? ReevaluationPhotoFailure { throw failure }
            if let failure = error as? MobileAPITransportError {
                switch failure {
                case .network,.timeout: throw ReevaluationPhotoFailure.offline
                case .missingSession,.sessionSuperseded: throw ReevaluationPhotoFailure.sessionEnded
                case .validation: throw ReevaluationPhotoFailure.invalidInput
                case .conflict(let code,_): throw code.hasSuffix("_busy") ? ReevaluationPhotoFailure.busy : ReevaluationPhotoFailure.changed
                case .rateLimited(let code,_) where code == "mobile_reevaluation_photo_quota": throw ReevaluationPhotoFailure.quota
                case .http(let status,_,_) where [400,413,415].contains(status): throw ReevaluationPhotoFailure.invalidInput
                default: throw ReevaluationPhotoFailure.unavailable
                }
            }
            throw ReevaluationPhotoFailure.unavailable
        }
    }
}

/// Registers the actual work before it can start and validates again after
/// finishing the registry (which can itself suspend and switch accounts).
struct ReevaluationPhotoSessionWork: Sendable {
    let lifecycle:any SessionLifecycleProviding
    let lease:SessionLease
    func run<T:Sendable>(_ operation:@escaping @Sendable () async throws -> T) async throws -> T {
        try Task.checkCancellation(); try await lifecycle.validate(lease)
        let cancellation = ReevaluationPhotoWorkCancellation()
        let id = try await lifecycle.beginPatientWork(lease:lease,cancel:{ cancellation.cancel() })
        let task = Task {
            try cancellation.check(); try Task.checkCancellation(); try await lifecycle.validate(lease)
            let value = try await operation()
            try cancellation.check(); try Task.checkCancellation(); try await lifecycle.validate(lease)
            return value
        }
        cancellation.install { task.cancel() }
        var finished = false
        do {
            let value = try await withTaskCancellationHandler { try await task.value } onCancel: { cancellation.cancel() }
            finished = true; await lifecycle.finishPatientWork(id)
            try cancellation.check(); try Task.checkCancellation(); try await lifecycle.validate(lease)
            cancellation.clear(); return value
        } catch {
            cancellation.cancel(); cancellation.clear()
            if !finished { await lifecycle.finishPatientWork(id) }
            throw error
        }
    }
}
private final class ReevaluationPhotoWorkCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var operation:(@Sendable () -> Void)?
    func install(_ value:@escaping @Sendable () -> Void) {
        let cancelNow = lock.withLock { operation = value; return cancelled }
        if cancelNow { value() }
    }
    func cancel() { let value = lock.withLock { cancelled = true; return operation }; value?() }
    func clear() { lock.withLock { operation = nil } }
    func check() throws { if lock.withLock({ cancelled }) { throw CancellationError() } }
}
